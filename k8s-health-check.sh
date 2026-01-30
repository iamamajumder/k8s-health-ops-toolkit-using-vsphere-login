#!/bin/bash
#===============================================================================
# Kubernetes Cluster Health Check - Unified Script v3.4
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Capture cluster state before/after upgrades/changes
#          Auto-discovers cluster metadata from TMC
#          Auto-creates TMC contexts based on cluster naming patterns
#          Supports parallel execution for multiple clusters
#===============================================================================

set +e          # Disable exit-on-error (may be inherited from user's .bashrc)
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
source "${SCRIPT_DIR}/lib/health.sh"
source "${SCRIPT_DIR}/lib/comparison.sh"

# Source all health check sections
for section in "${SCRIPT_DIR}"/lib/sections/*.sh; do
    source "${section}"
done

#===============================================================================
# Script Configuration
#===============================================================================

# Default mode
CHECK_MODE=""
PRE_RESULTS_DIR=""
PARALLEL_MODE="true"       # Parallel execution enabled by default
BATCH_SIZE=6               # Default batch size for parallel execution

#===============================================================================
# Prerequisite Checks
#===============================================================================

check_prerequisites() {
    # Check if kubectl is available
    if ! command_exists kubectl; then
        error "kubectl command not found in PATH"
        error "Please ensure kubectl is installed and available in your PATH"
        error "Current PATH: ${PATH}"
        exit 1
    fi

    # Check if tanzu CLI is available
    if ! command_exists tanzu; then
        error "tanzu CLI not found in PATH"
        error "Please ensure tanzu CLI is installed and available in your PATH"
        exit 1
    fi

    # Check if jq is available
    if ! command_exists jq; then
        error "jq command not found in PATH"
        error "Please install jq for JSON parsing"
        error "Install: https://jqlang.github.io/jq/download/ or 'choco install jq'"
        exit 1
    fi
}

#===============================================================================
# Usage Function
#===============================================================================

show_usage() {
    cat << EOF
Kubernetes Cluster Health Check (Unified Script v3.4)

Usage:
  PRE-change:   $0 --mode pre [options] [clusters.conf]
  POST-change:  $0 --mode post [options] [clusters.conf] [pre-results-dir]

Modes:
  --mode pre    Run PRE-change health check (capture baseline before changes)
  --mode post   Run POST-change health check (compare with PRE results)

Arguments:
  clusters.conf     Path to configuration file with cluster names (one per line)
                    Default: ./clusters.conf
  pre-results-dir   (POST mode only) Path to PRE-change results directory
                    Default: ./health-check-results/latest/

Example clusters.conf:
  prod-workload-01
  prod-workload-02
  uat-system-01

Features:
  - Auto-discovers cluster metadata from TMC
  - Auto-creates TMC contexts based on naming patterns
  - Caches cluster metadata for performance
  - Enhanced health summary with HEALTHY/WARNINGS/CRITICAL status
  - PRE vs POST comparison with deltas (POST mode)
  - Batch parallel execution (6 clusters at a time by default)

Cluster Naming Pattern:
  *-prod-[1-4]         → Production TMC context
  *-uat-[1-4]          → Non-production TMC context
  *-system-[1-4]       → Non-production TMC context

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output

Options:
  -h, --help           Show this help message
  --mode pre|post      Specify check mode (required)
  --sequential         Run health checks one at a time (default: parallel)
  --batch-size N       Number of clusters to process in parallel (default: 6)
  --cache-status       Show cache status
  --clear-cache        Clear all cached data

Examples:
  # PRE-change health check (parallel by default, 6 clusters at a time)
  $0 --mode pre
  $0 --mode pre ./clusters.conf

  # POST-change health check (parallel by default)
  $0 --mode post
  $0 --mode post ./clusters.conf ./health-check-results/pre-20250122_143000

  # Sequential execution (one cluster at a time)
  $0 --mode pre --sequential
  $0 --mode post --sequential

  # Custom batch size (10 clusters at a time)
  $0 --mode pre --batch-size 10

  # With debug output
  DEBUG=on $0 --mode pre

  # With TMC credentials
  TMC_SELF_MANAGED_USERNAME=myuser TMC_SELF_MANAGED_PASSWORD=mypass $0 --mode pre

  # Cache management
  $0 --cache-status
  $0 --clear-cache

EOF
    exit 0
}

#===============================================================================
# Run Health Check Sections
#===============================================================================

run_all_health_sections() {
    local mode="$1"
    local cluster_name="$2"

    print_header "KUBERNETES CLUSTER HEALTH CHECK - ${mode}-CHANGE"
    echo "Cluster: ${cluster_name}"
    echo "Check Started: $(get_formatted_timestamp)"
    echo ""

    # Run all 18 sections
    run_section_01_cluster_overview
    run_section_02_node_status
    run_section_03_pod_status
    run_section_04_workload_status
    run_section_05_storage_status
    run_section_06_networking
    run_section_07_antrea_cni
    run_section_08_tanzu_vmware
    run_section_09_security_rbac
    run_section_10_component_status
    run_section_11_helm_releases
    run_section_12_namespaces
    run_section_13_resource_quotas
    run_section_14_events
    run_section_15_connectivity
    run_section_16_images_audit
    run_section_17_certificates
    run_section_18_cluster_summary
}

#===============================================================================
# Process Single Cluster
#===============================================================================

process_cluster() {
    local cluster_name="$1"
    local output_base_dir="$2"
    local mode="$3"
    local pre_results_dir="$4"

    # Ensure TMC context exists for this cluster
    if ! ensure_tmc_context "${cluster_name}"; then
        error "Failed to create/verify TMC context for ${cluster_name}, skipping"
        return 1
    fi

    # Create cluster output directory
    local cluster_output_dir="${output_base_dir}/${cluster_name}"
    mkdir -p "${cluster_output_dir}"

    # Fetch kubeconfig with auto-discovery
    local kubeconfig_file="${cluster_output_dir}/kubeconfig"
    if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}"; then
        error "Failed to fetch kubeconfig for ${cluster_name}, skipping"
        return 1
    fi

    # Set kubeconfig for health checks
    export KUBECONFIG="${kubeconfig_file}"

    # Test connectivity
    progress "Verifying connectivity to ${cluster_name}..."
    if ! test_kubeconfig_connectivity "${kubeconfig_file}"; then
        error "Cannot connect to cluster ${cluster_name}. Skipping health check."
        return 1
    fi

    success "Connected to cluster ${cluster_name}"

    # Run health check
    progress "Running ${mode}-change health check for ${cluster_name}..."

    local report_file="${cluster_output_dir}/health-check-report.txt"

    # Run health check with error handling
    local hc_exit_code=0
    {
        run_all_health_sections "${mode^^}" "${cluster_name}"
    } > "${report_file}" 2>&1 || hc_exit_code=$?

    if [ "${hc_exit_code}" -ne 0 ]; then
        warning "Health check completed with exit code ${hc_exit_code} (some commands may have failed)"
    fi

    # Collect health metrics using centralized module
    collect_health_metrics
    calculate_health_status

    # Generate cluster summary
    local cluster_summary=$(generate_health_summary "${cluster_name}")

    success "Health check completed for ${cluster_name}"
    success "Report saved: ${report_file}"

    # POST mode: Generate comparison report
    if [[ "${mode}" == "post" ]] && [[ -n "${pre_results_dir}" ]]; then
        local pre_cluster_dir="${pre_results_dir}/${cluster_name}"
        if [[ -d "${pre_cluster_dir}" ]]; then
            local pre_report="${pre_cluster_dir}/health-check-report.txt"
            if [[ -f "${pre_report}" ]]; then
                progress "Generating comparison report..."
                local comparison_file="${cluster_output_dir}/comparison-report.txt"

                generate_comparison_report "${cluster_name}" "${pre_report}" "${report_file}" "${comparison_file}"

                success "Comparison report generated: ${comparison_file}"

                # Display beautified summary on CLI
                display_comparison_summary "${comparison_file}" "${cluster_name}"
            else
                warning "PRE-change report not found for ${cluster_name}, skipping comparison"
            fi
        else
            warning "No PRE-change results found for ${cluster_name}, skipping comparison"
        fi
    fi

    # Return summary via global variable
    CLUSTER_SUMMARY="${cluster_summary}"
    return 0
}

#===============================================================================
# Process Single Cluster (For Parallel Execution)
#===============================================================================

process_cluster_parallel() {
    local cluster_name="$1"
    local output_base_dir="$2"
    local mode="$3"
    local pre_results_dir="$4"
    local results_file="$5"

    local status="SUCCESS"

    # Create cluster output directory
    local cluster_output_dir="${output_base_dir}/${cluster_name}"
    mkdir -p "${cluster_output_dir}"

    # Fetch kubeconfig with auto-discovery (TMC context already prepared)
    local kubeconfig_file="${cluster_output_dir}/kubeconfig"
    if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}" >/dev/null 2>&1; then
        {
            echo "===CLUSTER_START==="
            echo "CLUSTER_NAME:${cluster_name}"
            echo "STATUS:FAILED"
            echo "ERROR:Failed to fetch kubeconfig"
            echo "===CLUSTER_END==="
        } >> "${results_file}"
        return 1
    fi

    # Set kubeconfig for health checks
    export KUBECONFIG="${kubeconfig_file}"

    # Test connectivity
    if ! test_kubeconfig_connectivity "${kubeconfig_file}" >/dev/null 2>&1; then
        {
            echo "===CLUSTER_START==="
            echo "CLUSTER_NAME:${cluster_name}"
            echo "STATUS:FAILED"
            echo "ERROR:Cannot connect to cluster"
            echo "===CLUSTER_END==="
        } >> "${results_file}"
        return 1
    fi

    # Run health check
    local report_file="${cluster_output_dir}/health-check-report.txt"

    # Run health check with error handling
    local hc_exit_code=0
    {
        run_all_health_sections "${mode^^}" "${cluster_name}"
    } > "${report_file}" 2>&1 || hc_exit_code=$?

    # Collect health metrics using centralized module
    collect_health_metrics
    calculate_health_status

    # POST mode: Generate comparison report
    if [[ "${mode}" == "post" ]] && [[ -n "${pre_results_dir}" ]]; then
        local pre_cluster_dir="${pre_results_dir}/${cluster_name}"
        if [[ -d "${pre_cluster_dir}" ]]; then
            local pre_report="${pre_cluster_dir}/health-check-report.txt"
            if [[ -f "${pre_report}" ]]; then
                local comparison_file="${cluster_output_dir}/comparison-report.txt"
                generate_comparison_report "${cluster_name}" "${pre_report}" "${report_file}" "${comparison_file}" >/dev/null 2>&1
            fi
        fi
    fi

    # Write result to results file using marker-based format (avoids multiline summary issues)
    {
        echo "===CLUSTER_START==="
        echo "CLUSTER_NAME:${cluster_name}"
        echo "STATUS:${status}"
        echo "HEALTH_STATUS:${HEALTH_STATUS}"
        echo "CRITICAL_COUNT:${HEALTH_CRITICAL_COUNT:-0}"
        echo "WARNING_COUNT:${HEALTH_WARNING_COUNT:-0}"
        echo "NODES_TOTAL:${HEALTH_NODES_TOTAL:-0}"
        echo "NODES_READY:${HEALTH_NODES_READY:-0}"
        echo "NODES_NOTREADY:${HEALTH_NODES_NOTREADY:-0}"
        echo "PODS_TOTAL:${HEALTH_PODS_TOTAL:-0}"
        echo "PODS_RUNNING:${HEALTH_PODS_RUNNING:-0}"
        echo "PODS_NOTRUNNING:$((HEALTH_PODS_TOTAL - HEALTH_PODS_RUNNING))"
        echo "PODS_CRASHLOOP:${HEALTH_PODS_CRASHLOOP:-0}"
        echo "PODS_PENDING:${HEALTH_PODS_PENDING:-0}"
        echo "PODS_COMPLETED:${HEALTH_PODS_COMPLETED:-0}"
        echo "PODS_UNACCOUNTED:${HEALTH_PODS_UNACCOUNTED:-0}"
        echo "DEPLOYS_TOTAL:${HEALTH_DEPLOYS_TOTAL:-0}"
        echo "DEPLOYS_READY:${HEALTH_DEPLOYS_READY:-0}"
        echo "DEPLOYS_NOTREADY:${HEALTH_DEPLOYS_NOTREADY:-0}"
        echo "DS_TOTAL:${HEALTH_DS_TOTAL:-0}"
        echo "DS_READY:${HEALTH_DS_READY:-0}"
        echo "DS_NOTREADY:${HEALTH_DS_NOTREADY:-0}"
        echo "STS_TOTAL:${HEALTH_STS_TOTAL:-0}"
        echo "STS_READY:${HEALTH_STS_READY:-0}"
        echo "STS_NOTREADY:${HEALTH_STS_NOTREADY:-0}"
        echo "PVC_TOTAL:${HEALTH_PVC_TOTAL:-0}"
        echo "PVC_BOUND:${HEALTH_PVC_BOUND:-0}"
        echo "PVC_NOTBOUND:${HEALTH_PVC_NOTBOUND:-0}"
        echo "HELM_TOTAL:${HEALTH_HELM_TOTAL:-0}"
        echo "HELM_DEPLOYED:${HEALTH_HELM_DEPLOYED:-0}"
        echo "HELM_FAILED:${HEALTH_HELM_FAILED:-0}"
        echo "NAMESPACES:$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' ')"
        echo "SERVICES:$(kubectl get svc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
        echo "===CLUSTER_END==="
    } >> "${results_file}"
    return 0
}

#===============================================================================
# Prepare TMC Contexts (Sequential - to avoid race conditions)
#===============================================================================

prepare_tmc_contexts() {
    local config_file="$1"

    # Prompt for TMC credentials if not set (only prompts once)
    if ! prompt_tmc_credentials; then
        error "TMC credentials are required"
        return 1
    fi

    progress "Preparing TMC contexts for all clusters..."

    local cluster_list=$(get_cluster_list "${config_file}")
    local cluster_count=$(count_clusters "${config_file}")
    local current=0
    local failed_clusters=()

    while IFS= read -r cluster_name; do
        current=$((current + 1))
        debug "[${current}/${cluster_count}] Preparing TMC context for ${cluster_name}..."

        if ! ensure_tmc_context "${cluster_name}" >/dev/null 2>&1; then
            warning "Failed to prepare TMC context for ${cluster_name}"
            failed_clusters+=("${cluster_name}")
        fi
    done < <(echo "${cluster_list}")

    if [ ${#failed_clusters[@]} -gt 0 ]; then
        warning "TMC context preparation failed for ${#failed_clusters[@]} cluster(s)"
        for fc in "${failed_clusters[@]}"; do
            debug "  - ${fc}"
        done
    fi

    success "TMC contexts prepared"
}

#===============================================================================
# Run Health Checks in Parallel (Batch-based)
#===============================================================================

run_health_checks_parallel() {
    local config_file="$1"
    local mode="$2"
    local pre_results_dir="$3"
    local output_base_dir="$4"
    local batch_size="$5"

    local cluster_list=$(get_cluster_list "${config_file}")
    local cluster_count=$(count_clusters "${config_file}")

    # Create temp file for collecting results
    local results_file=$(mktemp)
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

            process_cluster_parallel "${cluster_name}" "${output_base_dir}" "${mode}" "${pre_results_dir}" "${results_file}" &
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

    success "All ${cluster_count} health checks completed"
    echo ""

    # Parse results using marker-based format
    local success_count=0
    local failed_count=0
    local failed_clusters=()
    declare -a processed_clusters=()
    declare -a cluster_summaries=()

    print_section "Results Summary"

    # Read the results file and parse blocks
    local in_block=false
    local current_cluster=""
    local current_status=""
    local current_health_status=""
    local current_critical=0
    local current_warnings=0
    declare -A current_metrics

    while IFS= read -r line; do
        if [[ "${line}" == "===CLUSTER_START===" ]]; then
            in_block=true
            current_metrics=()
            continue
        fi

        if [[ "${line}" == "===CLUSTER_END===" ]]; then
            in_block=false
            # Process the collected cluster data
            current_cluster="${current_metrics[CLUSTER_NAME]}"
            current_status="${current_metrics[STATUS]}"
            current_health_status="${current_metrics[HEALTH_STATUS]}"
            current_critical="${current_metrics[CRITICAL_COUNT]:-0}"
            current_warnings="${current_metrics[WARNING_COUNT]:-0}"

            if [[ "${current_status}" == "SUCCESS" ]]; then
                success_count=$((success_count + 1))
                processed_clusters+=("${current_cluster}")

                # Display formatted summary for this cluster
                echo ""
                echo -e "${GREEN}[SUCCESS]${NC} ${YELLOW}${current_cluster}${NC}"
                echo ""
                echo "--- Resource Counts ---"
                echo ""
                echo "Nodes Total: ${current_metrics[NODES_TOTAL]:-0}"
                echo "Nodes Ready: ${current_metrics[NODES_READY]:-0}"
                echo "Pods Total: ${current_metrics[PODS_TOTAL]:-0}"
                echo "Pods Running: ${current_metrics[PODS_RUNNING]:-0}"
                echo "Pods Not Running: ${current_metrics[PODS_NOTRUNNING]:-0}"
                echo "Deployments Total: ${current_metrics[DEPLOYS_TOTAL]:-0}"
                echo "DaemonSets Total: ${current_metrics[DS_TOTAL]:-0}"
                echo "StatefulSets Total: ${current_metrics[STS_TOTAL]:-0}"
                echo "Services Total: ${current_metrics[SERVICES]:-0}"
                echo "PVCs Total: ${current_metrics[PVC_TOTAL]:-0}"
                echo "Namespaces: ${current_metrics[NAMESPACES]:-0}"
                echo "Helm Releases: ${current_metrics[HELM_TOTAL]:-0}"
                echo ""
                echo "--- Health Indicators ---"
                echo ""

                # Display health indicators with status
                local nodes_notready="${current_metrics[NODES_NOTREADY]:-0}"
                local pods_crashloop="${current_metrics[PODS_CRASHLOOP]:-0}"
                local pods_pending="${current_metrics[PODS_PENDING]:-0}"
                local deploys_notready="${current_metrics[DEPLOYS_NOTREADY]:-0}"
                local ds_notready="${current_metrics[DS_NOTREADY]:-0}"
                local sts_notready="${current_metrics[STS_NOTREADY]:-0}"
                local pvc_notbound="${current_metrics[PVC_NOTBOUND]:-0}"
                local helm_failed="${current_metrics[HELM_FAILED]:-0}"
                local pods_completed="${current_metrics[PODS_COMPLETED]:-0}"
                local pods_unaccounted="${current_metrics[PODS_UNACCOUNTED]:-0}"

                # Nodes NotReady - CRITICAL if > 0
                if [[ "${nodes_notready}" -gt 0 ]]; then
                    printf "Nodes NotReady: %-6s ${RED}[CRITICAL]${NC}\n" "${nodes_notready}"
                else
                    printf "Nodes NotReady: %-6s ${GREEN}[OK]${NC}\n" "${nodes_notready}"
                fi

                # Pods CrashLoop - CRITICAL if > 0
                if [[ "${pods_crashloop}" -gt 0 ]]; then
                    printf "Pods CrashLoop: %-6s ${RED}[CRITICAL]${NC}\n" "${pods_crashloop}"
                else
                    printf "Pods CrashLoop: %-6s ${GREEN}[OK]${NC}\n" "${pods_crashloop}"
                fi

                # Pods Pending - WARNING if > 0
                if [[ "${pods_pending}" -gt 0 ]]; then
                    printf "Pods Pending: %-6s ${YELLOW}[WARNING]${NC}\n" "${pods_pending}"
                else
                    printf "Pods Pending: %-6s ${GREEN}[OK]${NC}\n" "${pods_pending}"
                fi

                # Deployments NotReady - WARNING if > 0
                if [[ "${deploys_notready}" -gt 0 ]]; then
                    printf "Deploys NotReady: %-6s ${YELLOW}[WARNING]${NC}\n" "${deploys_notready}"
                else
                    printf "Deploys NotReady: %-6s ${GREEN}[OK]${NC}\n" "${deploys_notready}"
                fi

                # DaemonSets NotReady - WARNING if > 0
                if [[ "${ds_notready}" -gt 0 ]]; then
                    printf "DS NotReady: %-6s ${YELLOW}[WARNING]${NC}\n" "${ds_notready}"
                else
                    printf "DS NotReady: %-6s ${GREEN}[OK]${NC}\n" "${ds_notready}"
                fi

                # StatefulSets NotReady - WARNING if > 0
                if [[ "${sts_notready}" -gt 0 ]]; then
                    printf "STS NotReady: %-6s ${YELLOW}[WARNING]${NC}\n" "${sts_notready}"
                else
                    printf "STS NotReady: %-6s ${GREEN}[OK]${NC}\n" "${sts_notready}"
                fi

                # PVCs NotBound - WARNING if > 0
                if [[ "${pvc_notbound}" -gt 0 ]]; then
                    printf "PVCs NotBound: %-6s ${YELLOW}[WARNING]${NC}\n" "${pvc_notbound}"
                else
                    printf "PVCs NotBound: %-6s ${GREEN}[OK]${NC}\n" "${pvc_notbound}"
                fi

                # Helm Failed - WARNING if > 0
                if [[ "${helm_failed}" -gt 0 ]]; then
                    printf "Helm Failed: %-6s ${YELLOW}[WARNING]${NC}\n" "${helm_failed}"
                else
                    printf "Helm Failed: %-6s ${GREEN}[OK]${NC}\n" "${helm_failed}"
                fi

                # Pods Completed - INFO (not a problem)
                printf "Pods Completed: %-6s ${CYAN}[INFO]${NC}\n" "${pods_completed}"

                # Pods Unaccounted - WARNING if > 0
                if [[ "${pods_unaccounted}" -gt 0 ]]; then
                    printf "Pods Unaccounted: %-6s ${YELLOW}[WARNING]${NC}\n" "${pods_unaccounted}"
                else
                    printf "Pods Unaccounted: %-6s ${GREEN}[OK]${NC}\n" "${pods_unaccounted}"
                fi

                echo ""
                echo "=================================================================================="
                if [[ "${current_health_status}" == "CRITICAL" ]]; then
                    echo -e "CLUSTER HEALTH: ${RED}${current_health_status}${NC}"
                elif [[ "${current_health_status}" == "WARNINGS" ]]; then
                    echo -e "CLUSTER HEALTH: ${YELLOW}${current_health_status}${NC}"
                else
                    echo -e "CLUSTER HEALTH: ${GREEN}${current_health_status}${NC}"
                fi
                echo "  Critical Issues: ${current_critical}"
                echo "  Warnings: ${current_warnings}"
                echo "=================================================================================="
                echo ""

                # Store summary for later use
                cluster_summaries+=("CLUSTER: ${current_cluster}")
            else
                failed_count=$((failed_count + 1))
                failed_clusters+=("${current_cluster}")
                local error_msg="${current_metrics[ERROR]:-Unknown error}"
                echo -e "${RED}[FAILED]${NC} ${current_cluster}: ${error_msg}"
            fi
            continue
        fi

        if [[ "${in_block}" == "true" ]]; then
            local key="${line%%:*}"
            local value="${line#*:}"
            current_metrics["${key}"]="${value}"
        fi
    done < "${results_file}"

    # Cleanup temp file
    rm -f "${results_file}"

    # Store processed clusters for POST mode comparison display
    PARALLEL_PROCESSED_CLUSTERS=("${processed_clusters[@]}")

    # Return values via global variables
    PARALLEL_SUCCESS_COUNT=${success_count}
    PARALLEL_FAILED_COUNT=${failed_count}
    PARALLEL_FAILED_CLUSTERS=("${failed_clusters[@]}")
    PARALLEL_CLUSTER_SUMMARIES=("${cluster_summaries[@]}")
}

#===============================================================================
# Main Health Check Function
#===============================================================================

run_health_checks() {
    local config_file="$1"
    local mode="$2"
    local pre_results_dir="$3"
    local parallel="$4"
    local batch_size="$5"

    # POST mode: Validate PRE-results directory
    if [[ "${mode}" == "post" ]]; then
        if [[ ! -d "${pre_results_dir}" ]]; then
            error "PRE-results directory not found: ${pre_results_dir}"
            exit 1
        fi
    fi

    # Validate and load configuration
    if ! load_configuration "${config_file}"; then
        exit 1
    fi

    # Display banner
    local mode_upper="${mode^^}"
    print_section "Kubernetes ${mode_upper}-Change Health Check"

    display_info "Configuration File" "${config_file}"
    [[ "${mode}" == "post" ]] && display_info "PRE Results Directory" "${pre_results_dir}"
    if [[ "${parallel}" == "true" ]]; then
        display_info "Execution Mode" "Parallel (batch size: ${batch_size})"
    else
        display_info "Execution Mode" "Sequential"
    fi
    display_info "Started" "$(get_formatted_timestamp)"
    echo ""

    # Verify TMC CLI is available
    if ! command_exists tanzu; then
        error "Tanzu CLI not found. Please install tanzu CLI."
        exit 1
    fi

    # Create output directory
    local timestamp=$(get_timestamp)
    local output_base_dir="${SCRIPT_DIR}/health-check-results/${mode}-${timestamp}"
    mkdir -p "${output_base_dir}"

    # Get cluster list
    local cluster_list=$(get_cluster_list "${config_file}")
    if [ -z "${cluster_list}" ]; then
        error "No clusters found in configuration file"
        exit 1
    fi

    local cluster_count=$(count_clusters "${config_file}")

    # Display cluster list
    display_cluster_list "${config_file}" || exit 1

    # Initialize counters
    local success_count=0
    local failed_count=0
    local failed_clusters=()
    declare -a cluster_summaries=()

    if [[ "${parallel}" == "true" ]]; then
        # Parallel execution (batch-based)
        echo ""

        # Prepare TMC contexts sequentially first (to avoid race conditions)
        prepare_tmc_contexts "${config_file}"
        echo ""

        # Run health checks in parallel batches
        run_health_checks_parallel "${config_file}" "${mode}" "${pre_results_dir}" "${output_base_dir}" "${batch_size}"

        # Get results from global variables
        success_count=${PARALLEL_SUCCESS_COUNT}
        failed_count=${PARALLEL_FAILED_COUNT}
        failed_clusters=("${PARALLEL_FAILED_CLUSTERS[@]}")
        cluster_summaries=("${PARALLEL_CLUSTER_SUMMARIES[@]}")

        # POST mode: Display comparison reports for each cluster
        if [[ "${mode}" == "post" ]] && [[ -n "${pre_results_dir}" ]]; then
            echo ""
            print_section "PRE vs POST Comparison"

            for cluster_name in "${PARALLEL_PROCESSED_CLUSTERS[@]}"; do
                local comparison_file="${output_base_dir}/${cluster_name}/comparison-report.txt"
                if [[ -f "${comparison_file}" ]]; then
                    display_comparison_summary "${comparison_file}" "${cluster_name}"
                fi
            done
        fi
    else
        # Sequential execution (original behavior)
        local current=0

        # Process each cluster
        while IFS= read -r cluster_name; do
            current=$((current + 1))

            echo ""
            echo -e "${MAGENTA}[${current}/${cluster_count}]${NC} Processing: ${YELLOW}${cluster_name}${NC}"

            print_section "Processing Cluster: ${cluster_name}"

            if process_cluster "${cluster_name}" "${output_base_dir}" "${mode}" "${pre_results_dir}"; then
                cluster_summaries+=("${CLUSTER_SUMMARY}")
                success_count=$((success_count + 1))
            else
                failed_clusters+=("${cluster_name}")
                failed_count=$((failed_count + 1))
            fi

        done < <(get_cluster_list "${config_file}")
    fi

    # Cleanup cache
    cleanup_cluster_cache

    # For parallel mode, detailed summaries are already displayed per cluster above
    # For sequential mode, show detailed execution summary
    if [[ "${parallel}" != "true" ]]; then
        # Display detailed summary for sequential mode
        echo ""
        print_section "Execution Summary"
        echo -e "${CYAN}Total clusters processed: ${NC}${cluster_count}"
        echo -e "${GREEN}Successful: ${NC}${success_count}"

        if [ ${failed_count} -gt 0 ]; then
            echo -e "${RED}Failed: ${NC}${failed_count}"
            echo ""
            echo -e "${RED}Failed clusters:${NC}"
            for failed_cluster in "${failed_clusters[@]}"; do
                echo "  - ${failed_cluster}"
            done
        fi

        # Display all cluster summaries
        if [ ${#cluster_summaries[@]} -gt 0 ]; then
            echo ""
            print_section "Cluster Health Summaries"
            for summary in "${cluster_summaries[@]}"; do
                echo -e "${CYAN}${summary}${NC}"
            done
        fi
    else
        # Simplified summary for parallel mode (detailed output already shown)
        if [ ${failed_count} -gt 0 ]; then
            echo ""
            echo -e "${RED}Failed clusters (${failed_count}):${NC}"
            for failed_cluster in "${failed_clusters[@]}"; do
                echo "  - ${failed_cluster}"
            done
        fi
    fi

    echo ""
    echo -e "${CYAN}Results directory: ${NC}${output_base_dir}"

    # PRE mode: Update "latest" directory
    if [[ "${mode}" == "pre" ]]; then
        local latest_dir="${SCRIPT_DIR}/health-check-results/latest"

        # Remove existing latest directory/symlink if exists
        if [[ -L "${latest_dir}" ]]; then
            rm -f "${latest_dir}"
        elif [[ -d "${latest_dir}" ]]; then
            rm -rf "${latest_dir}"
        fi

        # Create symlink to the new results
        if ln -s "${output_base_dir}" "${latest_dir}" 2>/dev/null; then
            success "Created symlink: latest -> $(basename "${output_base_dir}")"
        else
            # Fallback: copy directory for Windows compatibility
            cp -r "${output_base_dir}" "${latest_dir}"
            success "Created 'latest' directory copy"
        fi

        echo ""
        echo -e "${CYAN}Quick access: ${NC}${latest_dir}"
    fi

    echo ""
    display_banner "${mode_upper}-Change Health Check Complete!"
    echo ""
}

#===============================================================================
# Argument Parsing
#===============================================================================

parse_arguments() {
    local config_file="./clusters.conf"
    local pre_results_dir=""
    local default_latest_dir="./health-check-results/latest"

    # Parse named arguments first
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                ;;
            --cache-status)
                get_cache_status
                exit 0
                ;;
            --clear-cache)
                clear_cache
                exit 0
                ;;
            --mode)
                shift
                if [[ "$1" == "pre" ]] || [[ "$1" == "post" ]]; then
                    CHECK_MODE="$1"
                else
                    error "Invalid mode: $1 (must be 'pre' or 'post')"
                    exit 1
                fi
                shift
                ;;
            --sequential)
                PARALLEL_MODE="false"
                shift
                ;;
            --parallel)
                # Keep for backward compatibility (parallel is now default)
                PARALLEL_MODE="true"
                shift
                ;;
            --batch-size)
                shift
                if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]; then
                    BATCH_SIZE="$1"
                else
                    error "Invalid batch size: $1 (must be a positive integer)"
                    exit 1
                fi
                shift
                ;;
            *)
                # Positional arguments
                break
                ;;
        esac
    done

    # Validate mode is specified
    if [[ -z "${CHECK_MODE}" ]]; then
        error "Mode not specified. Use --mode pre or --mode post"
        echo ""
        show_usage
    fi

    # Parse remaining positional arguments based on mode
    if [[ "${CHECK_MODE}" == "pre" ]]; then
        # PRE mode: only config_file argument
        [[ -n "$1" ]] && config_file="$1"
    else
        # POST mode: config_file and/or pre_results_dir
        if [[ $# -eq 0 ]]; then
            # No arguments - use defaults
            pre_results_dir="${default_latest_dir}"
            if [[ ! -d "${pre_results_dir}" ]]; then
                error "No PRE-change results found in 'latest' directory"
                error "Run the PRE-change health check first: $0 --mode pre"
                error "Or specify a PRE-results directory: $0 --mode post [clusters.conf] <pre-results-dir>"
                exit 1
            fi
            progress "Using latest PRE-change results from: ${pre_results_dir}"
        elif [[ $# -eq 1 ]]; then
            # Single argument - detect if it's a directory or file
            if [[ -d "$1" ]]; then
                pre_results_dir="$1"
            else
                config_file="$1"
                pre_results_dir="${default_latest_dir}"
            fi
        else
            # Two arguments - detect which is which
            if [[ -d "$1" ]]; then
                pre_results_dir="$1"
                config_file="${2:-./clusters.conf}"
            elif [[ -d "$2" ]]; then
                config_file="$1"
                pre_results_dir="$2"
            else
                config_file="$1"
                pre_results_dir="$2"
            fi
        fi

        # Resolve symlinks for display
        if [[ -L "${pre_results_dir}" ]]; then
            local actual_pre_dir=$(readlink -f "${pre_results_dir}" 2>/dev/null || readlink "${pre_results_dir}" 2>/dev/null || echo "${pre_results_dir}")
            progress "Resolved 'latest' symlink to: ${actual_pre_dir}"
        fi
    fi

    # Validate config file exists
    if [[ ! -f "${config_file}" ]]; then
        error "Configuration file not found: ${config_file}"
        if [[ "$config_file" == "./clusters.conf" ]]; then
            error "Create a clusters.conf file with cluster names (one per line)"
            error "Or specify a config file: $0 --mode ${CHECK_MODE} <clusters.conf>"
        fi
        exit 1
    fi

    # Store parsed values
    CONFIG_FILE="${config_file}"
    PRE_RESULTS_DIR="${pre_results_dir}"
}

#===============================================================================
# Main Entry Point
#===============================================================================

main() {
    # Check prerequisites
    check_prerequisites

    # Parse arguments
    parse_arguments "$@"

    # Run health checks
    run_health_checks "${CONFIG_FILE}" "${CHECK_MODE}" "${PRE_RESULTS_DIR}" "${PARALLEL_MODE}" "${BATCH_SIZE}"
}

main "$@"
