#!/bin/bash
#===============================================================================
# Kubernetes Cluster Health Check - POST-CHANGE Script v3.1
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Capture cluster state after upgrades/changes and compare with PRE
#          Auto-discovers cluster metadata from TMC
#          Auto-creates TMC contexts based on cluster naming patterns
#===============================================================================

set -o pipefail

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
source "${SCRIPT_DIR}/lib/comparison.sh"

# Source all health check sections
for section in "${SCRIPT_DIR}"/lib/sections/*.sh; do
    source "${section}"
done

#===============================================================================
# Prerequisite Checks
#===============================================================================

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

#===============================================================================
# Usage Function
#===============================================================================

show_usage() {
    cat << EOF
Kubernetes Post-Change Health Check

Usage: $0                              # Uses ./clusters.conf and latest PRE results
       $0 <pre-results-dir>            # Uses ./clusters.conf with specific PRE results
       $0 [clusters.conf] <pre-results-dir>

Arguments:
  pre-results-dir   Path to PRE-change results directory for comparison
                    Default: ./health-check-results/latest/ (if not specified)
  clusters.conf     Path to configuration file with cluster names (one per line)
                    Default: ./clusters.conf (if not specified)

Example clusters.conf:
  prod-workload-01
  prod-workload-02
  uat-system-01

Features:
  - Auto-discovers cluster metadata from TMC
  - Auto-creates TMC contexts based on naming patterns
  - Caches cluster metadata for performance
  - Compares POST results with PRE results
  - PRE vs POST comparison table with deltas
  - Plain English summary of changes
  - Enhanced health summary with HEALTHY/WARNINGS/CRITICAL status

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
  WINDOWS_POST_PATH            Windows destination path for POST reports

Options:
  -h, --help           Show this help message
  --cache-status       Show cache status (metadata and kubeconfig cache)
  --clear-cache        Clear all cached data

Examples:
  # Run health check using default ./clusters.conf
  $0 ./health-check-results/pre-20250122_143000

  # Run health check with specific config file
  $0 ./clusters.conf ./health-check-results/pre-20250122_143000

  # With debug output
  DEBUG=on $0 ./health-check-results/pre-20250122_143000

  # With TMC credentials in environment
  TMC_SELF_MANAGED_USERNAME=myuser TMC_SELF_MANAGED_PASSWORD=mypass $0 ./health-check-results/pre-20250122_143000

  # View cache status
  $0 --cache-status

  # Clear cache
  $0 --clear-cache

EOF
    exit 0
}

#===============================================================================
# Main Health Check Function
#===============================================================================

run_health_checks() {
    local config_file="$1"
    local pre_results_dir="$2"

    # Validate PRE-results directory
    if [[ ! -d "${pre_results_dir}" ]]; then
        error "PRE-results directory not found: ${pre_results_dir}"
        exit 1
    fi

    # Validate and load configuration
    if ! load_configuration "${config_file}"; then
        exit 1
    fi

    # Display banner
    print_section "Kubernetes Post-Change Health Check"

    display_info "Configuration File" "${config_file}"
    display_info "PRE Results Directory" "${pre_results_dir}"
    display_info "Started" "$(get_formatted_timestamp)"
    echo ""

    # Verify TMC CLI is available
    if ! command_exists tanzu; then
        error "Tanzu CLI not found. Please install tanzu CLI."
        exit 1
    fi

    # Create output directory
    local timestamp=$(get_timestamp)
    local output_base_dir="${SCRIPT_DIR}/health-check-results/post-${timestamp}"
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

        # Ensure TMC context exists for this cluster
        if ! ensure_tmc_context "${cluster_name}"; then
            error "Failed to create/verify TMC context for ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            failed_count=$((failed_count + 1))
            continue
        fi

        # Create cluster output directory
        local cluster_output_dir="${output_base_dir}/${cluster_name}"
        mkdir -p "${cluster_output_dir}"

        # Fetch kubeconfig with auto-discovery
        local kubeconfig_file="${cluster_output_dir}/kubeconfig"
        if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}"; then
            error "Failed to fetch kubeconfig for ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            failed_count=$((failed_count + 1))
            continue
        fi

        # Set kubeconfig for health checks
        export KUBECONFIG="${kubeconfig_file}"

        # Test connectivity
        progress "Verifying connectivity to ${cluster_name}..."
        if ! test_kubeconfig_connectivity "${kubeconfig_file}"; then
            error "Cannot connect to cluster ${cluster_name}. Skipping health check."
            failed_clusters+=("${cluster_name}")
            failed_count=$((failed_count + 1))
            continue
        fi

        success "Connected to cluster ${cluster_name}"

        # Run health check
        progress "Running post-change health check for ${cluster_name}..."

        local report_file="${cluster_output_dir}/health-check-report.txt"

        {
            print_header "KUBERNETES CLUSTER HEALTH CHECK - POST-CHANGE"
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

        } > "${report_file}" 2>&1

        # Capture Section 18 summary with health indicators for console display
        local nodes_total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' | tr -d ' ')
        local nodes_notready=$((nodes_total - nodes_ready))
        local pods_total=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local pods_running=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running | tr -d ' ')
        local pods_crashloop=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic CrashLoopBackOff || true)
        pods_crashloop=$(echo "${pods_crashloop}" | tr -d ' \n\r')
        pods_crashloop=${pods_crashloop:-0}
        local pods_pending=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic Pending || true)
        pods_pending=$(echo "${pods_pending}" | tr -d ' \n\r')
        pods_pending=${pods_pending:-0}
        local pods_completed=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic Completed || true)
        pods_completed=$(echo "${pods_completed}" | tr -d ' \n\r')
        pods_completed=${pods_completed:-0}
        local deploys_total=$(kubectl get deploy -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local deploys_notready=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')
        local ds_total=$(kubectl get ds -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local ds_notready=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$4 != $6 {count++} END{print count+0}' | tr -d ' ')
        local sts_total=$(kubectl get sts -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local sts_notready=$(kubectl get sts -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')
        local pvc_total=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local pvc_notbound=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -v Bound | wc -l | tr -d ' ')
        local helm_total=$(helm list -A --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo '0')
        local helm_failed=$(helm list -A --failed --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo '0')

        # Determine health status
        local health_status="HEALTHY"
        local critical_count=0
        local warning_count=0
        [ "${nodes_notready:-0}" -gt 0 ] && critical_count=$((critical_count + 1))
        [ "${pods_crashloop:-0}" -gt 0 ] && critical_count=$((critical_count + 1))
        [ "${pods_pending:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
        [ "${deploys_notready:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
        [ "${ds_notready:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
        [ "${sts_notready:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
        [ "${pvc_notbound:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
        [ "${helm_failed:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
        [ "$critical_count" -gt 0 ] && health_status="CRITICAL"
        [ "$critical_count" -eq 0 ] && [ "$warning_count" -gt 0 ] && health_status="WARNINGS"

        local cluster_summary=$(cat << EOSUMMARY
CLUSTER: ${cluster_name}
  Nodes: ${nodes_ready}/${nodes_total} Ready
  Pods: ${pods_running}/${pods_total} Running
  Deployments: $((deploys_total - deploys_notready))/${deploys_total} Ready
  DaemonSets: $((ds_total - ds_notready))/${ds_total} Ready
  StatefulSets: $((sts_total - sts_notready))/${sts_total} Ready
  PVCs: $((pvc_total - pvc_notbound))/${pvc_total} Bound
  Helm: $((helm_total - helm_failed))/${helm_total} Deployed
  ---
  Health Indicators:
    Nodes NotReady: ${nodes_notready:-0}
    Pods CrashLoop: ${pods_crashloop:-0}
    Pods Pending: ${pods_pending:-0}
    Pods Completed: ${pods_completed:-0}
  ---
  HEALTH STATUS: ${health_status}
EOSUMMARY
)
        cluster_summaries+=("${cluster_summary}")

        success "Health check completed for ${cluster_name}"
        success "Report saved: ${report_file}"

        # Generate comparison report
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

        success_count=$((success_count + 1))

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
        copy_post_to_windows "${output_base_dir}"
    fi

    echo ""
    display_banner "Post-Change Health Check Complete!"
    echo ""
}

#===============================================================================
# Main Entry Point
#===============================================================================

main() {
    # Handle help
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
    fi

    # Handle cache management options first
    if [[ "$1" == "--cache-status" ]]; then
        get_cache_status
        exit 0
    fi

    if [[ "$1" == "--clear-cache" ]]; then
        clear_cache
        exit 0
    fi

    # Parse arguments - flexible handling
    # 0 args = use ./clusters.conf and ./health-check-results/latest/
    # 1 arg  = pre-results-dir (use default ./clusters.conf)
    # 2 args = clusters.conf + pre-results-dir OR pre-results-dir + clusters.conf
    local config_file=""
    local pre_results_dir=""
    local default_latest_dir="./health-check-results/latest"

    if [[ $# -eq 0 ]]; then
        # No arguments - use defaults (latest directory)
        config_file="./clusters.conf"
        pre_results_dir="${default_latest_dir}"

        # Check if latest directory exists
        if [[ ! -d "${pre_results_dir}" ]]; then
            error "No PRE-change results found in 'latest' directory"
            error "Run the PRE-change health check first: ./k8s-health-check-pre.sh"
            error "Or specify a PRE-results directory: $0 <pre-results-dir>"
            exit 1
        fi
        progress "Using latest PRE-change results from: ${pre_results_dir}"
    elif [[ $# -eq 1 ]]; then
        # Single argument - must be pre-results-dir, use default clusters.conf
        pre_results_dir="$1"
        config_file="./clusters.conf"
    elif [[ $# -ge 2 ]]; then
        # Two arguments - detect which is which
        if [[ -d "$1" ]]; then
            # First arg is directory (pre-results-dir)
            pre_results_dir="$1"
            config_file="${2:-./clusters.conf}"
        elif [[ -d "$2" ]]; then
            # Second arg is directory (pre-results-dir)
            config_file="$1"
            pre_results_dir="$2"
        else
            # Default: assume traditional order (config_file, pre_results_dir)
            config_file="$1"
            pre_results_dir="$2"
        fi
    fi

    # Resolve symlinks to get actual directory path (for display purposes)
    local actual_pre_dir="${pre_results_dir}"
    if [[ -L "${pre_results_dir}" ]]; then
        actual_pre_dir=$(readlink -f "${pre_results_dir}" 2>/dev/null || readlink "${pre_results_dir}" 2>/dev/null || echo "${pre_results_dir}")
        progress "Resolved 'latest' symlink to: ${actual_pre_dir}"
    fi

    # Validate config file exists
    if [ ! -f "${config_file}" ]; then
        error "Configuration file not found: ${config_file}"
        if [[ "$config_file" == "./clusters.conf" ]]; then
            error "Create a clusters.conf file with cluster names (one per line)"
            error "Or specify a config file: $0 <clusters.conf> <pre-results-dir>"
        fi
        exit 1
    fi

    # Validate PRE results directory exists
    if [ ! -d "${pre_results_dir}" ]; then
        error "PRE-results directory not found: ${pre_results_dir}"
        exit 1
    fi

    # Run health checks
    run_health_checks "${config_file}" "${pre_results_dir}"
}

main "$@"
