#!/bin/bash
#===============================================================================
# Kubernetes Cluster Health Check - Unified Script v3.3
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Capture cluster state before/after upgrades/changes
#          Auto-discovers cluster metadata from TMC
#          Auto-creates TMC contexts based on cluster naming patterns
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
source "${SCRIPT_DIR}/lib/scp.sh"
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
Kubernetes Cluster Health Check (Unified Script v3.3)

Usage:
  PRE-change:   $0 --mode pre [clusters.conf]
  POST-change:  $0 --mode post [clusters.conf] [pre-results-dir]

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

Cluster Naming Pattern:
  *-prod-[1-4]         → Production TMC context
  *-uat-[1-4]          → Non-production TMC context
  *-system-[1-4]       → Non-production TMC context

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output
  WINDOWS_SCP_ENABLED          Set to 'true' to enable Windows SCP transfer
  WINDOWS_SCP_USER             Windows username for SCP
  WINDOWS_SCP_HOST             Windows hostname for SCP
  WINDOWS_PRE_PATH             Windows destination path for PRE reports
  WINDOWS_POST_PATH            Windows destination path for POST reports

Options:
  -h, --help           Show this help message
  --mode pre|post      Specify check mode (required)
  --cache-status       Show cache status
  --clear-cache        Clear all cached data

Examples:
  # PRE-change health check (run before making changes)
  $0 --mode pre
  $0 --mode pre ./clusters.conf

  # POST-change health check (run after making changes)
  $0 --mode post
  $0 --mode post ./clusters.conf ./health-check-results/pre-20250122_143000

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
# Main Health Check Function
#===============================================================================

run_health_checks() {
    local config_file="$1"
    local mode="$2"
    local pre_results_dir="$3"

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
    local current=0
    local failed_clusters=()

    # Array to store cluster summaries for console display
    declare -a cluster_summaries=()

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

    # Cleanup cache
    cleanup_cluster_cache

    # Display summary
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

    echo ""
    echo -e "${CYAN}Results directory: ${NC}${output_base_dir}"

    # Display all cluster summaries
    if [ ${#cluster_summaries[@]} -gt 0 ]; then
        echo ""
        print_section "Cluster Health Summaries"
        for summary in "${cluster_summaries[@]}"; do
            echo -e "${CYAN}${summary}${NC}"
        done
    fi

    # Optional: Copy to Windows
    if [[ -n "${WINDOWS_SCP_ENABLED:-}" ]] && [[ "${WINDOWS_SCP_ENABLED}" == "true" ]]; then
        echo ""
        progress "Copying results to Windows machine..."
        if [[ "${mode}" == "pre" ]]; then
            copy_pre_to_windows "${output_base_dir}"
        else
            copy_post_to_windows "${output_base_dir}"
        fi
    fi

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
    run_health_checks "${CONFIG_FILE}" "${CHECK_MODE}" "${PRE_RESULTS_DIR}"
}

main "$@"
