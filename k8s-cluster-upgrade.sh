#!/bin/bash

################################################################################
# Kubernetes Cluster Upgrade Script (v3.5)
#
# Simple orchestration script that delegates health checks to k8s-health-check.sh
#
# Architecture:
#   - Calls k8s-health-check.sh for PRE and POST health checks
#   - Orchestrates upgrade workflow with user confirmation
#   - Monitors upgrade progress every 2 minutes
#   - Dynamic timeout based on node count (nodes × 5 minutes)
#
# Usage:
#   ./k8s-cluster-upgrade.sh -c cluster-name          # Single cluster
#   ./k8s-cluster-upgrade.sh ./clusters.conf          # Multiple clusters
#   ./k8s-cluster-upgrade.sh -c cluster --timeout-multiplier 10
################################################################################

set -euo pipefail

# Script directory and version
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="3.5"

# Source library modules
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/tmc.sh"

# Default configuration
TIMEOUT_MULTIPLIER=5  # Minutes per node
DRY_RUN=false
SINGLE_CLUSTER=""
CONFIG_FILE=""

################################################################################
# Usage
################################################################################
usage() {
    cat << EOF
Kubernetes Cluster Upgrade Script (v${VERSION})

Simple orchestration script that coordinates PRE/POST health checks and upgrades.

USAGE:
    $0                                  # Use default ./clusters.conf
    $0 -c CLUSTER_NAME [OPTIONS]        # Single cluster upgrade
    $0 CONFIG_FILE [OPTIONS]            # Multiple clusters upgrade
    $0 --help                           # Show this help

MODES:
    (no arguments)                      Use default ./clusters.conf file
    -c CLUSTER_NAME                     Upgrade a single cluster
    CONFIG_FILE                         Upgrade multiple clusters from config file

OPTIONS:
    --timeout-multiplier N              Minutes per node for timeout (default: 5)
    --dry-run                           Show what would be done without executing
    --help                              Show this help message

WORKFLOW:
    1. Run PRE-upgrade health check (full output displayed)
    2. Prompt: "Do you want to upgrade [cluster]? (Y/N)"
    3. Execute TMC upgrade command
    4. Monitor progress every 2 minutes (elapsed time, phase, nodes remaining)
    5. Display completion message with new cluster version
    6. Run POST-upgrade health check with PRE vs POST comparison

TIMEOUT:
    Dynamic timeout = number of nodes × ${TIMEOUT_MULTIPLIER} minutes per node
    Example: 5-node cluster = 25 minute timeout

EXAMPLES:
    # Default: Use ./clusters.conf
    $0

    # Single cluster upgrade
    $0 -c prod-workload-01

    # Multiple clusters with custom config
    $0 ./my-clusters.conf

    # Custom timeout (10 minutes per node)
    $0 -c uat-system-01 --timeout-multiplier 10

    # Dry run
    $0 -c prod-workload-01 --dry-run

OUTPUT:
    upgrade-results/upgrade-YYYYMMDD_HHMMSS/
    └── cluster-name/
        ├── pre-upgrade-health.txt      (PRE health check report)
        ├── upgrade-log.txt             (Upgrade execution and monitoring)
        ├── post-upgrade-health.txt     (POST health check report)
        └── comparison-report.txt       (PRE vs POST comparison)

EOF
}

################################################################################
# Prerequisite Checks
################################################################################
check_prerequisites() {
    # Check required commands
    check_command kubectl "kubectl is required but not installed"
    check_command tanzu "tanzu CLI is required but not installed"
    check_command jq "jq is required but not installed"

    # Check health check script exists
    if [[ ! -f "${SCRIPT_DIR}/k8s-health-check.sh" ]]; then
        error "k8s-health-check.sh not found in ${SCRIPT_DIR}"
        exit 1
    fi

    # Verify health check script is executable
    if [[ ! -x "${SCRIPT_DIR}/k8s-health-check.sh" ]]; then
        warning "Making k8s-health-check.sh executable"
        chmod +x "${SCRIPT_DIR}/k8s-health-check.sh"
    fi
}

################################################################################
# Run PRE-upgrade Health Check
################################################################################
run_pre_health_check() {
    local cluster_name="$1"
    local output_dir="$2"

    progress "Running PRE-upgrade health check for ${cluster_name}..."
    echo ""

    # Create temporary clusters.conf with single cluster
    local temp_config=$(mktemp)
    echo "${cluster_name}" > "${temp_config}"

    # Run health check (output goes to console and report file)
    if "${SCRIPT_DIR}/k8s-health-check.sh" --mode pre "${temp_config}"; then
        rm -f "${temp_config}"

        # Find the latest PRE results in new consolidated structure
        local output_base_dir="${HOME}/k8s-health-check/output"
        local pre_hcr_dir="${output_base_dir}/${cluster_name}/h-c-r"
        local latest_pre=$(ls -t "${pre_hcr_dir}"/pre-hcr-*.txt 2>/dev/null | head -1)

        if [[ -n "${latest_pre}" && -f "${latest_pre}" ]]; then
            # Copy PRE health check to upgrade results with timestamped name
            local timestamp=$(date '+%Y%m%d_%H%M%S')
            cp "${latest_pre}" "${output_dir}/pre-hcr-${timestamp}.txt"
            echo "${output_base_dir}" > "${output_dir}/.pre-results-path"
            success "PRE-upgrade health check completed"
            return 0
        else
            error "Could not find PRE health check results for ${cluster_name}"
            return 1
        fi
    else
        rm -f "${temp_config}"
        error "PRE-upgrade health check failed for ${cluster_name}"
        return 1
    fi
}

################################################################################
# Prompt User Confirmation
################################################################################
prompt_user_confirmation() {
    local cluster_name="$1"

    echo ""
    print_section "Upgrade Confirmation"
    echo -e "${YELLOW}Do you want to upgrade ${BOLD}${cluster_name}${RESET}${YELLOW}?${RESET}"
    echo -n "Enter (Y/N): "

    read -r response
    case "${response}" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

################################################################################
# Get Upgrade Inputs
################################################################################
get_upgrade_inputs() {
    local cluster_name="$1"

    progress "Retrieving cluster metadata from TMC..."

    # Discover cluster metadata from TMC (returns "management|provisioner")
    local metadata=$(discover_cluster_metadata "${cluster_name}")

    if [[ -z "${metadata}" ]]; then
        error "Failed to retrieve metadata for ${cluster_name}"
        return 1
    fi

    # Parse metadata (pipe-delimited format from discover_cluster_metadata)
    local mgmt_cluster=$(echo "${metadata}" | cut -d'|' -f1)
    local provisioner=$(echo "${metadata}" | cut -d'|' -f2)

    if [[ -z "${mgmt_cluster}" || -z "${provisioner}" ]]; then
        error "Incomplete metadata for ${cluster_name}"
        echo "  Management cluster: ${mgmt_cluster:-<missing>}"
        echo "  Provisioner: ${provisioner:-<missing>}"
        return 1
    fi

    # Export for use by caller
    echo "${mgmt_cluster}|${provisioner}"
    return 0
}

################################################################################
# Execute Upgrade
################################################################################
execute_upgrade() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"
    local output_dir="$4"

    progress "Initiating upgrade for ${cluster_name}..."
    echo ""

    # Timestamped upgrade log filename
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local upgrade_log="${output_dir}/upgrade-log-${timestamp}.txt"

    # Log upgrade command
    {
        echo "==================================="
        echo "Cluster Upgrade Execution"
        echo "==================================="
        echo "Cluster: ${cluster_name}"
        echo "Management Cluster: ${mgmt_cluster}"
        echo "Provisioner: ${provisioner}"
        echo "Command: tanzu tmc cluster upgrade ${cluster_name} -m ${mgmt_cluster} -p ${provisioner} --latest"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "==================================="
        echo ""
    } | tee -a "${upgrade_log}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        warning "DRY RUN: Would execute upgrade command"
        return 0
    fi

    # Execute upgrade
    if tanzu tmc cluster upgrade "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" --latest 2>&1 | tee -a "${upgrade_log}"; then
        success "Upgrade initiated successfully"
        return 0
    else
        error "Failed to initiate upgrade"
        return 1
    fi
}

################################################################################
# Get Node Count for Timeout Calculation
################################################################################
get_node_count() {
    local cluster_name="$1"

    # Try to get node count from current kubeconfig
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' \n\r')
    node_count=${node_count:-0}

    if [[ ${node_count} -eq 0 ]]; then
        # Fallback: use default if kubectl unavailable
        debug "Could not determine node count via kubectl, using default"
        node_count=5  # Default fallback for timeout calculation
    fi

    echo "${node_count}"
}

################################################################################
# Monitor Upgrade Progress
################################################################################
monitor_upgrade_progress() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"
    local timeout_minutes="$4"
    local output_dir="$5"

    local upgrade_log="${output_dir}/upgrade-log.txt"
    local start_time=$(date +%s)
    local check_interval=120  # 2 minutes

    echo "" | tee -a "${upgrade_log}"
    progress "Monitoring upgrade progress (updates every 2 minutes)..."
    echo "Timeout: ${timeout_minutes} minutes" | tee -a "${upgrade_log}"
    echo "" | tee -a "${upgrade_log}"

    while true; do
        local current_time=$(date +%s)
        local elapsed=$(( (current_time - start_time) / 60 ))

        # Query cluster status
        local status_json=$(tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" -o json 2>/dev/null || echo "{}")

        local phase=$(echo "${status_json}" | jq -r '.status.phase // "UNKNOWN"')
        local version=$(echo "${status_json}" | jq -r '.status.kubeVersion // "unknown"')
        local health=$(echo "${status_json}" | jq -r '.status.health // "UNKNOWN"')

        # Check for completion
        if [[ "${phase}" == "READY" ]]; then
            echo "" | tee -a "${upgrade_log}"
            success "Upgrade completed successfully!" | tee -a "${upgrade_log}"
            echo "  Cluster: ${cluster_name}" | tee -a "${upgrade_log}"
            echo "  Version: ${version}" | tee -a "${upgrade_log}"
            echo "  Health: ${health}" | tee -a "${upgrade_log}"
            echo "  Duration: ${elapsed} minutes" | tee -a "${upgrade_log}"
            echo "" | tee -a "${upgrade_log}"
            return 0
        fi

        # Check for error states
        if [[ "${phase}" == "ERROR" || "${health}" == "UNHEALTHY" ]]; then
            echo "" | tee -a "${upgrade_log}"
            error "Upgrade failed or cluster unhealthy!" | tee -a "${upgrade_log}"
            echo "  Phase: ${phase}" | tee -a "${upgrade_log}"
            echo "  Health: ${health}" | tee -a "${upgrade_log}"
            echo "  Version: ${version}" | tee -a "${upgrade_log}"
            echo "" | tee -a "${upgrade_log}"
            return 1
        fi

        # Display progress
        printf "[%3d min] Phase: %-12s | Version: %-10s | Health: %s\n" \
            "${elapsed}" "${phase}" "${version}" "${health}" | tee -a "${upgrade_log}"

        # Check timeout
        if [[ ${elapsed} -ge ${timeout_minutes} ]]; then
            echo "" | tee -a "${upgrade_log}"
            error "Upgrade timeout after ${timeout_minutes} minutes" | tee -a "${upgrade_log}"
            echo "  Last known phase: ${phase}" | tee -a "${upgrade_log}"
            echo "  Last known version: ${version}" | tee -a "${upgrade_log}"
            echo "" | tee -a "${upgrade_log}"
            return 2
        fi

        # Wait before next check
        sleep ${check_interval}
    done
}

################################################################################
# Run POST-upgrade Health Check
################################################################################
run_post_health_check() {
    local cluster_name="$1"
    local output_dir="$2"

    # Get PRE results path
    local pre_results_path=""
    if [[ -f "${output_dir}/.pre-results-path" ]]; then
        pre_results_path=$(cat "${output_dir}/.pre-results-path")
    fi

    if [[ -z "${pre_results_path}" || ! -d "${pre_results_path}" ]]; then
        warning "Could not find PRE results path, using latest"
        pre_results_path="latest"
    fi

    echo ""
    progress "Running POST-upgrade health check for ${cluster_name}..."
    echo ""

    # Create temporary clusters.conf with single cluster
    local temp_config=$(mktemp)
    echo "${cluster_name}" > "${temp_config}"

    # Run POST health check with comparison
    if "${SCRIPT_DIR}/k8s-health-check.sh" --mode post "${temp_config}" "${pre_results_path}"; then
        rm -f "${temp_config}"

        # Find the latest POST results in new consolidated structure
        local output_base_dir="${HOME}/k8s-health-check/output"
        local post_hcr_dir="${output_base_dir}/${cluster_name}/h-c-r"
        local latest_post=$(ls -t "${post_hcr_dir}"/post-hcr-*.txt 2>/dev/null | head -1)

        if [[ -n "${latest_post}" && -f "${latest_post}" ]]; then
            # Copy POST health check to upgrade results with timestamped name
            local timestamp=$(date '+%Y%m%d_%H%M%S')
            cp "${latest_post}" "${output_dir}/post-hcr-${timestamp}.txt"

            # Comparison reports stay in h-c-r directory, no need to copy (avoid duplication)
            success "POST-upgrade health check completed"
            success "Comparison report available in: ${post_hcr_dir}/"
            return 0
        else
            error "Could not find POST health check results for ${cluster_name}"
            return 1
        fi
    else
        rm -f "${temp_config}"
        error "POST-upgrade health check failed for ${cluster_name}"
        return 1
    fi
}

################################################################################
# Upgrade Single Cluster (Main Orchestration)
################################################################################
upgrade_single_cluster() {
    local cluster_name="$1"

    # Create output directory (new consolidated structure)
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local output_base_dir="${HOME}/k8s-health-check/output"
    local output_dir="${output_base_dir}/${cluster_name}/upgrade"
    mkdir -p "${output_dir}"

    print_section "Upgrading Cluster: ${cluster_name}"
    echo ""

    # Step 1: Run PRE-upgrade health check
    if ! run_pre_health_check "${cluster_name}" "${output_dir}"; then
        error "PRE-upgrade health check failed. Aborting upgrade."
        return 1
    fi

    # Step 2: Prompt user confirmation
    if ! prompt_user_confirmation "${cluster_name}"; then
        warning "Upgrade skipped by user for ${cluster_name}"
        echo "SKIPPED" > "${output_dir}/status.txt"
        return 2
    fi

    # Step 3: Get upgrade inputs (metadata)
    local inputs=$(get_upgrade_inputs "${cluster_name}")
    if [[ $? -ne 0 ]]; then
        error "Failed to retrieve cluster metadata. Aborting upgrade."
        echo "FAILED" > "${output_dir}/status.txt"
        return 1
    fi

    local mgmt_cluster=$(echo "${inputs}" | cut -d'|' -f1)
    local provisioner=$(echo "${inputs}" | cut -d'|' -f2)

    echo ""
    echo "Cluster Metadata:"
    echo "  Name: ${cluster_name}"
    echo "  Management Cluster: ${mgmt_cluster}"
    echo "  Provisioner: ${provisioner}"
    echo ""

    # Step 4: Execute upgrade
    if ! execute_upgrade "${cluster_name}" "${mgmt_cluster}" "${provisioner}" "${output_dir}"; then
        error "Failed to initiate upgrade for ${cluster_name}"
        echo "FAILED" > "${output_dir}/status.txt"
        return 1
    fi

    # Step 5: Calculate timeout and get node count
    local node_count=$(get_node_count "${cluster_name}")
    local timeout_minutes=$((node_count * TIMEOUT_MULTIPLIER))

    echo ""
    echo "Upgrade Configuration:"
    echo "  Node count: ${node_count}"
    echo "  Timeout: ${timeout_minutes} minutes (${node_count} nodes × ${TIMEOUT_MULTIPLIER} min/node)"
    echo ""

    # Step 6: Monitor upgrade progress
    local monitor_result=0
    monitor_upgrade_progress "${cluster_name}" "${mgmt_cluster}" "${provisioner}" "${timeout_minutes}" "${output_dir}"
    monitor_result=$?

    case ${monitor_result} in
        0)
            success "Upgrade monitoring completed successfully"
            ;;
        1)
            error "Upgrade failed during execution"
            echo "FAILED" > "${output_dir}/status.txt"
            return 1
            ;;
        2)
            error "Upgrade monitoring timed out"
            echo "TIMEOUT" > "${output_dir}/status.txt"
            return 1
            ;;
    esac

    # Step 7: Run POST-upgrade health check
    if ! run_post_health_check "${cluster_name}" "${output_dir}"; then
        warning "POST-upgrade health check failed, but upgrade completed"
        echo "SUCCESS_WITH_HEALTH_CHECK_FAILED" > "${output_dir}/status.txt"
        return 0  # Don't fail entire upgrade if POST check fails
    fi

    # Success
    echo "SUCCESS" > "${output_dir}/status.txt"

    # Cleanup old files
    cleanup_old_files "${output_base_dir}/${cluster_name}" "upgrade"

    echo ""
    success "Cluster upgrade completed successfully for ${cluster_name}"
    echo ""
    echo "Results saved to: ${output_dir}"
    echo ""

    return 0
}

################################################################################
# Upgrade Multiple Clusters
################################################################################
upgrade_multiple_clusters() {
    local config_file="$1"

    # Validate config file
    if [[ ! -f "${config_file}" ]]; then
        error "Config file not found: ${config_file}"
        exit 1
    fi

    # Get cluster list
    local cluster_list=$(get_cluster_list "${config_file}")
    local total=$(echo "${cluster_list}" | wc -l)
    local current=0
    local success_count=0
    local failed_count=0
    local skipped_count=0

    print_section "Multi-Cluster Upgrade"
    echo "Total clusters: ${total}"
    echo "Config file: ${config_file}"
    echo ""

    while IFS= read -r cluster_name; do
        current=$((current + 1))

        echo ""
        echo "========================================================================"
        echo "Cluster ${current}/${total}: ${cluster_name}"
        echo "========================================================================"
        echo ""

        upgrade_single_cluster "${cluster_name}"
        local result=$?

        case ${result} in
            0)
                success_count=$((success_count + 1))
                success "✓ Cluster ${current}/${total} succeeded: ${cluster_name}"
                ;;
            1)
                failed_count=$((failed_count + 1))
                error "✗ Cluster ${current}/${total} failed: ${cluster_name}"
                ;;
            2)
                skipped_count=$((skipped_count + 1))
                warning "○ Cluster ${current}/${total} skipped: ${cluster_name}"
                ;;
        esac

        echo ""
    done <<< "${cluster_list}"

    # Display summary
    echo ""
    print_section "Upgrade Summary"
    echo "Total clusters: ${total}"
    echo "Successful: ${success_count}"
    echo "Failed: ${failed_count}"
    echo "Skipped: ${skipped_count}"
    echo ""

    if [[ ${failed_count} -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

################################################################################
# Argument Parsing
################################################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--cluster)
                SINGLE_CLUSTER="$2"
                shift 2
                ;;
            --timeout-multiplier)
                TIMEOUT_MULTIPLIER="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                if [[ -z "${CONFIG_FILE}" ]]; then
                    CONFIG_FILE="$1"
                    shift
                else
                    error "Unknown argument: $1"
                    usage
                    exit 1
                fi
                ;;
        esac
    done

    # Default to ./clusters.conf if no arguments provided
    if [[ -z "${SINGLE_CLUSTER}" && -z "${CONFIG_FILE}" ]]; then
        CONFIG_FILE="./clusters.conf"
        progress "No arguments provided, defaulting to ${CONFIG_FILE}"
    fi

    # Validate arguments
    if [[ -n "${SINGLE_CLUSTER}" && -n "${CONFIG_FILE}" ]]; then
        error "Cannot specify both -c CLUSTER and CONFIG_FILE"
        usage
        exit 1
    fi
}

################################################################################
# Main Entry Point
################################################################################
main() {
    echo "========================================================================"
    echo "Kubernetes Cluster Upgrade Script (v${VERSION})"
    echo "========================================================================"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Parse arguments
    parse_arguments "$@"

    # Execute appropriate mode
    if [[ -n "${SINGLE_CLUSTER}" ]]; then
        upgrade_single_cluster "${SINGLE_CLUSTER}"
        exit $?
    elif [[ -n "${CONFIG_FILE}" ]]; then
        upgrade_multiple_clusters "${CONFIG_FILE}"
        exit $?
    else
        error "No cluster or config file specified"
        usage
        exit 1
    fi
}

# Run main function
main "$@"
