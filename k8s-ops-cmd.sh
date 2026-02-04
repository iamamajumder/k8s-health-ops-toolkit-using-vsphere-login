#!/bin/bash
#===============================================================================
# Kubernetes Multi-Cluster Ops Command Script v3.5
# Purpose: Execute the same command across all clusters in clusters.conf
#          or dynamically discover clusters from TMC management cluster
#          with proper TMC context/kubeconfig setup and parallel execution
# v3.5: Added management cluster discovery via -m flag
#===============================================================================

set +e          # Disable exit-on-error
set -o pipefail # Fail on pipe errors

# Preserve PATH from parent shell
export PATH="${PATH}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/tmc-context.sh"
source "${SCRIPT_DIR}/lib/tmc.sh"

#===============================================================================
# Script Configuration
#===============================================================================

DEFAULT_TIMEOUT=30          # Default command timeout in seconds
DEFAULT_CONFIG="./clusters.conf"
OUTPUT_DIR="${SCRIPT_DIR}/ops-results"
BATCH_SIZE=6                # Default batch size for parallel execution
MANAGEMENT_ENV=""           # Environment parameter for -m flag

#===============================================================================
# Usage Function
#===============================================================================

show_usage() {
    cat << EOF
Kubernetes Multi-Cluster Ops Command Script v3.5

Usage:
  $0 [OPTIONS] "<command>" [clusters.conf]
  $0 -m <environment> [OPTIONS] "<command>"

Description:
  Execute the same command across all clusters defined in clusters.conf.
  Or dynamically discover clusters from a TMC management cluster.
  Commands run in parallel batches of 6 by default for faster execution.

Arguments:
  <command>         The command to execute on each cluster (required)
                    The command runs with KUBECONFIG set for each cluster
  clusters.conf     Path to configuration file with cluster names (one per line)
                    Default: ./clusters.conf

Options:
  -h, --help                       Show this help message
  -m, --management-cluster <env>   Discover clusters from management cluster
                                   Environment: prod-1, prod-2, uat-2, system-3
                                   Mutually exclusive with clusters.conf
  --timeout <sec>                  Command timeout in seconds (default: ${DEFAULT_TIMEOUT})
  --sequential                     Run commands sequentially instead of parallel
  --batch-size N                   Number of clusters to process in parallel (default: 6)
  --output-only                    Minimal terminal output, save full results to file

Examples (File-based mode):
  # Get Contour version on all clusters (parallel by default)
  $0 "kubectl get deploy -n projectcontour contour -o jsonpath='{.spec.template.spec.containers[0].image}'"

  # Check cert-manager version
  $0 "helm list -n cert-manager -o json | jq -r '.[0].chart'"

  # Get node count per cluster
  $0 "kubectl get nodes --no-headers | wc -l"

  # Check Kubernetes version
  $0 "kubectl version --short 2>/dev/null | grep Server"

  # With custom config and timeout
  $0 --timeout 60 "kubectl get pods -A" ./my-clusters.conf

  # Custom batch size (10 clusters at a time)
  $0 --batch-size 10 "kubectl get nodes"

  # Sequential execution (one cluster at a time)
  $0 --sequential "kubectl get nodes"

Examples (Management Discovery mode):
  # Execute command on all clusters in prod-1 management cluster
  $0 -m prod-1 "kubectl get nodes"

  # Dry run with management discovery
  $0 -m uat-2 "kubectl get pods -A"

  # Management discovery with custom batch size
  $0 -m prod-1 --batch-size 10 "kubectl get nodes"

  # Management discovery with sequential execution
  $0 -m system-3 --sequential "kubectl version --short"

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output

EOF
    exit 0
}

#===============================================================================
# Prerequisite Checks
#===============================================================================

check_prerequisites() {
    if ! command_exists kubectl; then
        error "kubectl command not found in PATH"
        exit 1
    fi

    if ! command_exists tanzu; then
        error "tanzu CLI not found in PATH"
        exit 1
    fi
}

#===============================================================================
# Execute Command on Single Cluster
#===============================================================================

execute_on_cluster() {
    local cluster_name="$1"
    local command="$2"
    local timeout_sec="$3"
    local output_file="$4"

    local status="SUCCESS"
    local output=""
    local exit_code=0

    # Create temp directory for this cluster's kubeconfig
    local temp_dir=$(mktemp -d)
    local kubeconfig_file="${temp_dir}/kubeconfig"

    # Setup TMC context and fetch kubeconfig
    if ! ensure_tmc_context "${cluster_name}" >/dev/null 2>&1; then
        status="FAILED"
        output="Failed to create/verify TMC context"
        exit_code=1
    else
        if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}" >/dev/null 2>&1; then
            status="FAILED"
            output="Failed to fetch kubeconfig"
            exit_code=1
        else
            # Execute the command with timeout
            export KUBECONFIG="${kubeconfig_file}"

            if command_exists timeout; then
                output=$(timeout "${timeout_sec}" bash -c "${command}" 2>&1) || exit_code=$?
            else
                # Fallback for systems without timeout command (e.g., some macOS)
                output=$(bash -c "${command}" 2>&1) || exit_code=$?
            fi

            if [ ${exit_code} -ne 0 ]; then
                status="FAILED"
            fi
        fi
    fi

    # Write results to output file (atomic write)
    {
        echo "CLUSTER: ${cluster_name}"
        echo "STATUS: ${status}"
        echo "EXIT_CODE: ${exit_code}"
        echo "OUTPUT:"
        echo "${output}"
        echo "---END---"
    } >> "${output_file}"

    # Cleanup
    rm -rf "${temp_dir}"

    return ${exit_code}
}

#===============================================================================
# Execution Functions for Discovery Mode
#===============================================================================

run_parallel_with_list() {
    local command="$1"
    local cluster_list="$2"
    local timeout_sec="$3"
    local results_dir="$4"
    local batch_size="$5"

    # Convert cluster list to array
    local clusters=()
    while IFS= read -r cluster; do
        clusters+=("${cluster}")
    done <<< "${cluster_list}"

    local results_file="${results_dir}/raw_results.txt"
    > "${results_file}"

    local total_clusters=${#clusters[@]}
    local num_batches=$(( (total_clusters + batch_size - 1) / batch_size ))
    local global_idx=0

    progress "Processing ${total_clusters} clusters in batches of ${batch_size} (${num_batches} batch(es))..."
    echo ""

    for ((batch_num=1; batch_num<=num_batches; batch_num++)); do
        local batch_start=$global_idx
        local batch_end=$((batch_start + batch_size))
        if [ $batch_end -gt $total_clusters ]; then
            batch_end=$total_clusters
        fi
        local batch_count=$((batch_end - batch_start))

        echo -e "${CYAN}━━━ Batch ${batch_num}/${num_batches} (${batch_count} clusters) ━━━${NC}"

        declare -a pids=()

        for ((i=batch_start; i<batch_end; i++)); do
            local cluster="${clusters[$i]}"
            local display_idx=$((i + 1))
            echo -e "${MAGENTA}[${display_idx}/${total_clusters}]${NC} Launching: ${YELLOW}${cluster}${NC}"
            execute_on_cluster "${cluster}" "${command}" "${timeout_sec}" "${results_file}" &
            pids+=($!)
        done

        # Wait for all processes in this batch
        echo ""
        progress "Waiting for batch ${batch_num} to complete..."
        for pid in "${pids[@]}"; do
            wait $pid 2>/dev/null
        done

        success "Batch ${batch_num} completed"
        echo ""

        global_idx=$batch_end
    done
}

run_sequential_with_list() {
    local command="$1"
    local cluster_list="$2"
    local timeout_sec="$3"
    local results_dir="$4"

    local results_file="${results_dir}/raw_results.txt"
    > "${results_file}"

    local total_clusters
    total_clusters=$(count_clusters_from_list "${cluster_list}")

    progress "Running commands on ${total_clusters} clusters sequentially..."

    local idx=0
    while IFS= read -r cluster; do
        [[ -z "${cluster}" ]] && continue
        idx=$((idx + 1))
        echo -e "${MAGENTA}[${idx}/${total_clusters}]${NC} ${cluster}..."
        execute_on_cluster "${cluster}" "${command}" "${timeout_sec}" "${results_file}"
    done <<< "${cluster_list}"
}

#===============================================================================
# Run Commands in Parallel (Batch-based)
#===============================================================================

run_parallel() {
    local command="$1"
    local config_file="$2"
    local timeout_sec="$3"
    local results_dir="$4"
    local batch_size="$5"

    local cluster_list=$(get_cluster_list "${config_file}")
    local cluster_count=$(count_clusters "${config_file}")

    # Create temp file for collecting results
    local results_file="${results_dir}/raw_results.txt"
    > "${results_file}"

    # Calculate number of batches
    local num_batches=$(( (cluster_count + batch_size - 1) / batch_size ))

    progress "Processing ${cluster_count} clusters in batches of ${batch_size} (${num_batches} batch(es))..."
    echo ""

    # Convert cluster list to array
    local -a clusters=()
    while IFS= read -r cluster_name; do
        clusters+=("${cluster_name}")
    done < <(echo "${cluster_list}")

    local global_idx=0
    local batch_num=0

    # Process clusters in batches
    while [ ${global_idx} -lt ${cluster_count} ]; do
        batch_num=$((batch_num + 1))
        local batch_start=${global_idx}
        local batch_end=$((global_idx + batch_size))
        [ ${batch_end} -gt ${cluster_count} ] && batch_end=${cluster_count}
        local batch_count=$((batch_end - batch_start))

        echo -e "${CYAN}━━━ Batch ${batch_num}/${num_batches} (${batch_count} clusters) ━━━${NC}"

        # Array to store PIDs for this batch
        declare -A pids=()

        # Launch batch
        for ((i=batch_start; i<batch_end; i++)); do
            local cluster_name="${clusters[$i]}"
            local display_idx=$((i + 1))
            echo -e "${MAGENTA}[${display_idx}/${cluster_count}]${NC} Launching: ${YELLOW}${cluster_name}${NC}"

            execute_on_cluster "${cluster_name}" "${command}" "${timeout_sec}" "${results_file}" &
            pids["${cluster_name}"]=$!
        done

        # Wait for this batch to complete
        echo ""
        progress "Waiting for batch ${batch_num} to complete..."

        for cluster_name in "${!pids[@]}"; do
            wait ${pids[$cluster_name]} 2>/dev/null
        done

        success "Batch ${batch_num} completed"
        echo ""

        global_idx=${batch_end}
    done
}

#===============================================================================
# Run Commands Sequentially
#===============================================================================

run_sequential() {
    local command="$1"
    local config_file="$2"
    local timeout_sec="$3"
    local results_dir="$4"

    local cluster_list=$(get_cluster_list "${config_file}")
    local cluster_count=$(count_clusters "${config_file}")

    # Create temp file for collecting results
    local results_file="${results_dir}/raw_results.txt"
    > "${results_file}"

    progress "Running commands on ${cluster_count} clusters sequentially..."

    local idx=0
    while IFS= read -r cluster_name; do
        idx=$((idx + 1))
        echo -e "${MAGENTA}[${idx}/${cluster_count}]${NC} ${cluster_name}..."

        execute_on_cluster "${cluster_name}" "${command}" "${timeout_sec}" "${results_file}"
    done < <(echo "${cluster_list}")
}

#===============================================================================
# Parse and Display Results
#===============================================================================

display_results() {
    local results_file="$1"
    local output_file="$2"
    local command="$3"
    local output_only="$4"

    local success_count=0
    local failed_count=0
    local current_cluster=""
    local current_status=""
    local current_output=""
    local in_output=false

    # Parse results and display
    if [[ "${output_only}" != "true" ]]; then
        echo ""
        print_section "Command Results"
    fi

    # Write header to output file
    {
        echo "================================================================================"
        echo "MULTI-CLUSTER OPS COMMAND RESULTS"
        echo "================================================================================"
        echo "Timestamp: $(get_formatted_timestamp)"
        echo "Command: ${command}"
        echo "================================================================================"
        echo ""
    } > "${output_file}"

    # Parse the raw results file
    while IFS= read -r line; do
        if [[ "${line}" == "CLUSTER: "* ]]; then
            # Save previous cluster if exists
            if [[ -n "${current_cluster}" ]]; then
                # Write to file
                {
                    echo "CLUSTER: ${current_cluster}"
                    echo "STATUS: ${current_status}"
                    echo "OUTPUT:"
                    echo "${current_output}"
                    echo ""
                    echo "---"
                    echo ""
                } >> "${output_file}"

                # Display to terminal if not output-only
                if [[ "${output_only}" != "true" ]]; then
                    if [[ "${current_status}" == "SUCCESS" ]]; then
                        echo -e "${GREEN}[SUCCESS]${NC} ${YELLOW}${current_cluster}${NC}"
                    else
                        echo -e "${RED}[FAILED]${NC} ${YELLOW}${current_cluster}${NC}"
                    fi
                    echo "────────────────────────────────────────"
                    echo "${current_output}"
                    echo ""
                fi
            fi

            current_cluster="${line#CLUSTER: }"
            current_status=""
            current_output=""
            in_output=false
        elif [[ "${line}" == "STATUS: "* ]]; then
            current_status="${line#STATUS: }"
            if [[ "${current_status}" == "SUCCESS" ]]; then
                success_count=$((success_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        elif [[ "${line}" == "OUTPUT:" ]]; then
            in_output=true
        elif [[ "${line}" == "---END---" ]]; then
            in_output=false
        elif [[ "${in_output}" == "true" ]]; then
            if [[ -n "${current_output}" ]]; then
                current_output="${current_output}
${line}"
            else
                current_output="${line}"
            fi
        fi
    done < "${results_file}"

    # Process last cluster
    if [[ -n "${current_cluster}" ]]; then
        {
            echo "CLUSTER: ${current_cluster}"
            echo "STATUS: ${current_status}"
            echo "OUTPUT:"
            echo "${current_output}"
            echo ""
            echo "---"
            echo ""
        } >> "${output_file}"

        if [[ "${output_only}" != "true" ]]; then
            if [[ "${current_status}" == "SUCCESS" ]]; then
                echo -e "${GREEN}[SUCCESS]${NC} ${YELLOW}${current_cluster}${NC}"
            else
                echo -e "${RED}[FAILED]${NC} ${YELLOW}${current_cluster}${NC}"
            fi
            echo "────────────────────────────────────────"
            echo "${current_output}"
            echo ""
        fi
    fi

    # Write summary to file
    {
        echo "================================================================================"
        echo "SUMMARY"
        echo "================================================================================"
        echo "Total: $((success_count + failed_count))"
        echo "Success: ${success_count}"
        echo "Failed: ${failed_count}"
    } >> "${output_file}"

    # Display summary
    echo ""
    print_section "Summary"
    echo -e "${CYAN}Total Clusters:${NC} $((success_count + failed_count))"
    echo -e "${GREEN}Successful:${NC} ${success_count}"
    if [ ${failed_count} -gt 0 ]; then
        echo -e "${RED}Failed:${NC} ${failed_count}"
    else
        echo -e "Failed: ${failed_count}"
    fi
    echo ""
    echo -e "${CYAN}Results saved to:${NC} ${output_file}"
}

#===============================================================================
# Main Function
#===============================================================================

run_ops_command() {
    local command="$1"
    local config_file="$2"
    local timeout_sec="$3"
    local parallel="$4"
    local output_only="$5"
    local batch_size="$6"
    local mgmt_env="$7"

    local cluster_list=""
    local cluster_count=0
    local source_description=""

    # Management cluster discovery mode
    if [[ -n "${mgmt_env}" ]]; then
        # Validate environment format
        if ! validate_management_environment "${mgmt_env}"; then
            exit 1
        fi

        # Ensure TMC context for environment
        if ! ensure_tmc_context_for_environment "${mgmt_env}"; then
            error "Failed to create TMC context for environment: ${mgmt_env}"
            exit 1
        fi

        # Discover clusters
        progress "Discovering clusters from management cluster..."
        cluster_list=$(get_cluster_list_from_management "${mgmt_env}")

        if [[ -z "${cluster_list}" ]]; then
            warning "No clusters found in management cluster for environment: ${mgmt_env}"
            exit 0
        fi

        cluster_count=$(count_clusters_from_list "${cluster_list}")
        source_description="Management Cluster (${mgmt_env})"

    else
        # File-based mode (existing logic)
        # Validate config file
        if [[ ! -f "${config_file}" ]]; then
            error "Configuration file not found: ${config_file}"
            exit 1
        fi

        # Load and validate configuration
        if ! load_configuration "${config_file}"; then
            exit 1
        fi

        cluster_list=$(get_cluster_list "${config_file}")
        cluster_count=$(count_clusters "${config_file}")

        if [ "${cluster_count}" -eq 0 ]; then
            error "No clusters found in configuration file"
            exit 1
        fi

        source_description="Config File (${config_file})"
    fi

    # Create output directory
    local timestamp=$(get_timestamp)
    local results_dir="${OUTPUT_DIR}/ops-${timestamp}"
    mkdir -p "${results_dir}"

    local output_file="${results_dir}/output.txt"

    # Display banner
    echo ""
    print_section "Multi-Cluster Ops Command"
    display_info "Command" "${command}"
    display_info "Source" "${source_description}"
    display_info "Clusters" "${cluster_count}"
    display_info "Timeout" "${timeout_sec}s"
    if [[ "${parallel}" == "true" ]]; then
        display_info "Execution" "Parallel (batch size: ${batch_size})"
    else
        display_info "Execution" "Sequential"
    fi
    echo ""

    # Note: Credentials will be prompted inside ensure_tmc_context() only if
    # a new context needs to be created (existing valid contexts are reused)

    # Define results file path (used by both modes)
    local results_file="${results_dir}/raw_results.txt"

    # Execute commands
    if [[ -n "${mgmt_env}" ]]; then
        # Use list-based execution for management discovery mode
        if [[ "${parallel}" == "true" ]]; then
            run_parallel_with_list "${command}" "${cluster_list}" "${timeout_sec}" "${results_dir}" "${batch_size}"
        else
            run_sequential_with_list "${command}" "${cluster_list}" "${timeout_sec}" "${results_dir}"
        fi
    else
        # Use file-based execution for config file mode
        if [[ "${parallel}" == "true" ]]; then
            run_parallel "${command}" "${config_file}" "${timeout_sec}" "${results_dir}" "${batch_size}"
        else
            run_sequential "${command}" "${config_file}" "${timeout_sec}" "${results_dir}"
        fi
    fi

    # Display and save results
    display_results "${results_file}" "${output_file}" "${command}" "${output_only}"

    # Cleanup temp results file
    rm -f "${results_file}"

    echo ""
    display_banner "Ops Command Complete!"
    echo ""
}

#===============================================================================
# Argument Parsing
#===============================================================================

parse_arguments() {
    local command=""
    local config_file="${DEFAULT_CONFIG}"
    local timeout_sec="${DEFAULT_TIMEOUT}"
    local parallel="true"
    local output_only="false"
    local batch_size="${BATCH_SIZE}"

    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                ;;
            --timeout)
                shift
                if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                    timeout_sec="$1"
                else
                    error "Invalid timeout value: $1"
                    exit 1
                fi
                shift
                ;;
            -m|--management-cluster)
                shift
                if [[ -n "$1" ]] && [[ ! "$1" =~ ^- ]]; then
                    MANAGEMENT_ENV="$1"
                else
                    error "Environment required for -m/--management-cluster option"
                    error "Format: prod-1, prod-2, uat-2, system-3"
                    exit 1
                fi
                shift
                ;;
            --sequential)
                parallel="false"
                shift
                ;;
            --parallel)
                # Keep for backward compatibility (parallel is now default)
                parallel="true"
                shift
                ;;
            --batch-size)
                shift
                if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]; then
                    batch_size="$1"
                else
                    error "Invalid batch size: $1 (must be a positive integer)"
                    exit 1
                fi
                shift
                ;;
            --output-only)
                output_only="true"
                shift
                ;;
            -*)
                error "Unknown option: $1"
                show_usage
                ;;
            *)
                # Positional arguments
                if [[ -z "${command}" ]]; then
                    command="$1"
                else
                    # Only accept config file if not using management discovery
                    if [[ -z "${MANAGEMENT_ENV}" ]]; then
                        config_file="$1"
                    else
                        warning "Ignoring config file argument when using -m flag: $1"
                    fi
                fi
                shift
                ;;
        esac
    done

    # Validate command is provided
    if [[ -z "${command}" ]]; then
        error "No command specified"
        echo ""
        show_usage
    fi

    # Run the ops command
    run_ops_command "${command}" "${config_file}" "${timeout_sec}" "${parallel}" "${output_only}" "${batch_size}" "${MANAGEMENT_ENV}"
}

#===============================================================================
# Main Entry Point
#===============================================================================

main() {
    check_prerequisites
    parse_arguments "$@"
}

main "$@"
