#!/bin/bash
#===============================================================================
# Kubernetes Cluster Health Check - PRE-CHANGE Script v3.1
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Capture cluster state before upgrades/changes
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
Kubernetes Pre-Change Health Check v3.1

Usage: $0 <clusters.conf>

Arguments:
  clusters.conf    Path to configuration file with cluster names (one per line)

Example clusters.conf:
  prod-workload-01
  prod-workload-02
  uat-system-01

Features:
  - Auto-discovers cluster metadata from TMC
  - Auto-creates TMC contexts based on naming patterns
  - Caches cluster metadata for performance

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

Options:
  -h, --help           Show this help message

Examples:
  # Run health check on all clusters in config
  $0 ./clusters.conf

  # With debug output
  DEBUG=on $0 ./clusters.conf

  # With TMC credentials in environment
  TMC_SELF_MANAGED_USERNAME=myuser TMC_SELF_MANAGED_PASSWORD=mypass $0 ./clusters.conf

EOF
    exit 0
}

#===============================================================================
# Main Health Check Function
#===============================================================================

run_health_checks() {
    local config_file="$1"

    # Validate and load configuration
    if ! load_configuration "${config_file}"; then
        exit 1
    fi

    # Display banner
    print_section "Kubernetes Pre-Change Health Check v3.1"

    display_info "Configuration File" "${config_file}"
    display_info "Script Directory" "${SCRIPT_DIR}"
    display_info "Started" "$(get_formatted_timestamp)"
    echo ""

    # Verify TMC CLI is available
    if ! command_exists tanzu; then
        error "Tanzu CLI not found. Please install tanzu CLI."
        exit 1
    fi

    # Create output directory
    local timestamp=$(get_timestamp)
    local output_base_dir="${SCRIPT_DIR}/health-check-results/pre-${timestamp}"
    mkdir -p "${output_base_dir}"

    progress "Output directory: ${output_base_dir}"
    echo ""

    # Get cluster list
    local cluster_list=$(get_cluster_list "${config_file}")
    if [ -z "${cluster_list}" ]; then
        error "No clusters found in configuration file"
        exit 1
    fi

    local cluster_count=$(count_clusters "${config_file}")
    progress "Found ${cluster_count} cluster(s) in configuration"
    echo ""

    # Display cluster list
    display_cluster_list "${config_file}" || exit 1

    # Confirm execution
    read -p "$(echo -e ${YELLOW}Continue with pre-change health checks? [y/N]: ${NC})" -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Operation cancelled by user"
        exit 0
    fi

    echo ""

    # Initialize counters
    local success_count=0
    local failed_count=0
    local current=0
    local failed_clusters=()

    # Process each cluster
    while IFS= read -r cluster_name; do
        current=$((current + 1))

        echo ""
        echo -e "${MAGENTA}[${current}/${cluster_count}]${NC} Processing: ${YELLOW}${cluster_name}${NC}"
        echo ""

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
        progress "Running pre-change health check for ${cluster_name}..."

        local report_file="${cluster_output_dir}/health-check-report.txt"

        {
            print_header "KUBERNETES CLUSTER HEALTH CHECK - PRE-CHANGE v3.1"
            echo "Cluster: ${cluster_name}"
            echo "Check Started: $(get_formatted_timestamp)"
            echo "$(get_environment_info)"
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

        success "Health check completed for ${cluster_name}"
        success "Report saved: ${report_file}"

        success_count=$((success_count + 1))

    done < <(get_cluster_list "${config_file}")

    # Cleanup cache
    cleanup_cluster_cache

    # Display summary
    echo ""
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

    # Optional: Copy to Windows
    if [[ -n "${WINDOWS_SCP_ENABLED:-}" ]] && [[ "${WINDOWS_SCP_ENABLED}" == "true" ]]; then
        echo ""
        progress "Copying results to Windows machine..."
        copy_pre_to_windows "${output_base_dir}"
    fi

    echo ""
    display_banner "Pre-Change Health Check Complete!"
    echo ""
}

#===============================================================================
# Main Entry Point
#===============================================================================

main() {
    # Parse arguments
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
    fi

    local config_file="$1"

    # Validate config file exists
    if [ ! -f "${config_file}" ]; then
        error "Configuration file not found: ${config_file}"
        exit 1
    fi

    # Run health checks
    run_health_checks "${config_file}"
}

main "$@"
