#!/bin/bash
#===============================================================================
# Kubernetes Cluster Upgrade Script v3.4
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Automated cluster upgrades with health validation
#          - PRE-upgrade health check
#          - Health-gated upgrade decision (HEALTHY/WARNINGS/CRITICAL)
#          - Upgrade monitoring
#          - POST-upgrade health check with comparison
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
source "${SCRIPT_DIR}/lib/health.sh"
source "${SCRIPT_DIR}/lib/comparison.sh"

#===============================================================================
# Script Configuration
#===============================================================================

DEFAULT_TIMEOUT=30          # Default upgrade timeout in minutes
DRY_RUN=false
SKIP_HEALTH_CHECK=false
FORCE_UPGRADE=false
UPGRADE_TIMEOUT=${DEFAULT_TIMEOUT}

#===============================================================================
# Prerequisite Checks
#===============================================================================

check_prerequisites() {
    # Check if kubectl is available
    if ! command_exists kubectl; then
        error "kubectl command not found in PATH"
        exit 1
    fi

    # Check if tanzu CLI is available
    if ! command_exists tanzu; then
        error "tanzu CLI not found in PATH"
        exit 1
    fi

    # Check if jq is available
    if ! command_exists jq; then
        error "jq command not found in PATH"
        exit 1
    fi
}

#===============================================================================
# Usage Function
#===============================================================================

show_usage() {
    cat << EOF
Kubernetes Cluster Upgrade Script v3.4

Usage: $0 [OPTIONS] [clusters.conf]

Automates cluster upgrades with health validation before and after upgrade.

Arguments:
  clusters.conf     Path to configuration file with cluster names (one per line)
                    Default: ./clusters.conf

Options:
  -h, --help              Show this help message
  --dry-run               Show what would be upgraded without actually upgrading
  --skip-health-check     Skip PRE-upgrade health check (not recommended)
  --force                 Skip confirmation prompts for WARNINGS status
  --timeout <minutes>     Upgrade timeout in minutes (default: 30)

Upgrade Decision Logic:
  HEALTHY   → Auto-proceed with upgrade
  WARNINGS  → Prompt user for confirmation (unless --force)
  CRITICAL  → Abort upgrade (fix issues first)

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output

Examples:
  # Upgrade clusters in default ./clusters.conf
  $0

  # Upgrade clusters from specific config
  $0 ./upgrade-clusters.conf

  # Dry run (show what would happen)
  $0 --dry-run

  # Force upgrade even with warnings
  $0 --force

  # Custom timeout (45 minutes)
  $0 --timeout 45

EOF
    exit 0
}

#===============================================================================
# Pre-Upgrade Health Validation
#===============================================================================

validate_pre_upgrade_health() {
    local cluster_name="$1"
    local output_dir="$2"

    progress "Running PRE-upgrade health check for ${cluster_name}..."

    # Collect health metrics
    collect_health_metrics
    calculate_health_status

    # Save PRE-upgrade health report
    local pre_report="${output_dir}/pre-upgrade-health.txt"
    {
        echo "================================================================================"
        echo "  PRE-UPGRADE HEALTH CHECK"
        echo "================================================================================"
        echo "Cluster: ${cluster_name}"
        echo "Timestamp: $(get_formatted_timestamp)"
        echo ""
        generate_health_summary "${cluster_name}"
    } > "${pre_report}"

    # Return status code based on health
    case "${HEALTH_STATUS}" in
        "HEALTHY")
            success "PRE-upgrade health: HEALTHY"
            return 0
            ;;
        "WARNINGS")
            warning "PRE-upgrade health: WARNINGS (${HEALTH_WARNING_COUNT} warning(s))"
            return 1
            ;;
        "CRITICAL")
            error "PRE-upgrade health: CRITICAL (${HEALTH_CRITICAL_COUNT} critical issue(s))"
            return 2
            ;;
        *)
            error "Unknown health status: ${HEALTH_STATUS}"
            return 2
            ;;
    esac
}

#===============================================================================
# Execute Upgrade Command
#===============================================================================

execute_upgrade() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"
    local output_dir="$4"

    local upgrade_log="${output_dir}/upgrade-log.txt"

    progress "Initiating upgrade for ${cluster_name}..."
    echo "Management Cluster: ${mgmt_cluster}"
    echo "Provisioner: ${provisioner}"

    if [ "${DRY_RUN}" = true ]; then
        echo "[DRY-RUN] Would execute: tanzu tmc cluster upgrade ${cluster_name} -m ${mgmt_cluster} -p ${provisioner} --latest"
        return 0
    fi

    # Execute upgrade command
    {
        echo "================================================================================"
        echo "  UPGRADE LOG"
        echo "================================================================================"
        echo "Cluster: ${cluster_name}"
        echo "Start Time: $(get_formatted_timestamp)"
        echo "Command: tanzu tmc cluster upgrade ${cluster_name} -m ${mgmt_cluster} -p ${provisioner} --latest"
        echo ""
    } > "${upgrade_log}"

    if tanzu tmc cluster upgrade "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" --latest >> "${upgrade_log}" 2>&1; then
        success "Upgrade initiated successfully"
        return 0
    else
        error "Failed to initiate upgrade"
        cat "${upgrade_log}"
        return 1
    fi
}

#===============================================================================
# Monitor Upgrade Progress
#===============================================================================

monitor_upgrade() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"
    local timeout_minutes="${4:-${UPGRADE_TIMEOUT}}"
    local output_dir="$5"

    if [ "${DRY_RUN}" = true ]; then
        echo "[DRY-RUN] Would monitor upgrade progress for ${timeout_minutes} minutes"
        return 0
    fi

    local start_time=$(date +%s)
    local timeout_seconds=$((timeout_minutes * 60))
    local upgrade_log="${output_dir}/upgrade-log.txt"

    progress "Monitoring upgrade progress (timeout: ${timeout_minutes} minutes)..."

    while true; do
        # Check elapsed time
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local elapsed_min=$((elapsed / 60))
        local elapsed_sec=$((elapsed % 60))

        if [ $elapsed -ge $timeout_seconds ]; then
            error "Upgrade timeout after ${timeout_minutes} minutes"
            echo "TIMEOUT: Upgrade exceeded ${timeout_minutes} minutes" >> "${upgrade_log}"
            return 2
        fi

        # Query cluster status from TMC
        local status_json
        if ! status_json=$(tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" -o json 2>/dev/null); then
            warning "Failed to query cluster status, retrying..."
            sleep 30
            continue
        fi

        local phase=$(echo "${status_json}" | jq -r '.status.phase // "UNKNOWN"')
        local k8s_version=$(echo "${status_json}" | jq -r '.status.kubeVersion // "unknown"')
        local conditions=$(echo "${status_json}" | jq -r '.status.conditions // []')

        # Log status
        echo "[${elapsed_min}m ${elapsed_sec}s] Phase: ${phase}, Version: ${k8s_version}" >> "${upgrade_log}"

        case "${phase}" in
            "READY")
                success "Upgrade completed! Cluster now running Kubernetes ${k8s_version}"
                echo "" >> "${upgrade_log}"
                echo "COMPLETED: Upgrade finished successfully at $(get_formatted_timestamp)" >> "${upgrade_log}"
                echo "Final Kubernetes Version: ${k8s_version}" >> "${upgrade_log}"
                return 0
                ;;
            "UPGRADING"|"UPDATING")
                printf "\r[%02dm %02ds] Upgrading... Phase: %s, Version: %s          " "${elapsed_min}" "${elapsed_sec}" "${phase}" "${k8s_version}"
                ;;
            "ERROR"|"FAILED")
                error "Upgrade failed! Phase: ${phase}"
                echo "FAILED: Upgrade failed at $(get_formatted_timestamp)" >> "${upgrade_log}"
                echo "Error conditions: ${conditions}" >> "${upgrade_log}"
                return 1
                ;;
            *)
                printf "\r[%02dm %02ds] Phase: %s, Version: %s          " "${elapsed_min}" "${elapsed_sec}" "${phase}" "${k8s_version}"
                ;;
        esac

        sleep 30  # Check every 30 seconds
    done
}

#===============================================================================
# Post-Upgrade Health Validation
#===============================================================================

validate_post_upgrade_health() {
    local cluster_name="$1"
    local output_dir="$2"

    if [ "${DRY_RUN}" = true ]; then
        echo "[DRY-RUN] Would run POST-upgrade health check"
        return 0
    fi

    progress "Running POST-upgrade health check for ${cluster_name}..."

    # Wait for cluster to stabilize
    sleep 10

    # Refresh kubeconfig after upgrade
    local kubeconfig_file="${output_dir}/kubeconfig"
    if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}"; then
        warning "Failed to refresh kubeconfig after upgrade"
    fi
    export KUBECONFIG="${kubeconfig_file}"

    # Collect health metrics
    collect_health_metrics
    calculate_health_status

    # Save POST-upgrade health report
    local post_report="${output_dir}/post-upgrade-health.txt"
    {
        echo "================================================================================"
        echo "  POST-UPGRADE HEALTH CHECK"
        echo "================================================================================"
        echo "Cluster: ${cluster_name}"
        echo "Timestamp: $(get_formatted_timestamp)"
        echo ""
        generate_health_summary "${cluster_name}"
    } > "${post_report}"

    # Generate comparison report
    local pre_report="${output_dir}/pre-upgrade-health.txt"
    local comparison_file="${output_dir}/comparison-report.txt"

    if [[ -f "${pre_report}" ]]; then
        progress "Generating PRE vs POST comparison..."
        generate_comparison_report "${cluster_name}" "${pre_report}" "${post_report}" "${comparison_file}"
        display_comparison_summary "${comparison_file}" "${cluster_name}"
    fi

    # Return status
    case "${HEALTH_STATUS}" in
        "HEALTHY")
            success "POST-upgrade health: HEALTHY"
            return 0
            ;;
        "WARNINGS")
            warning "POST-upgrade health: WARNINGS (${HEALTH_WARNING_COUNT} warning(s))"
            return 1
            ;;
        "CRITICAL")
            error "POST-upgrade health: CRITICAL (${HEALTH_CRITICAL_COUNT} critical issue(s))"
            return 2
            ;;
    esac
}

#===============================================================================
# Upgrade Single Cluster
#===============================================================================

upgrade_cluster() {
    local cluster_name="$1"
    local output_base_dir="$2"

    print_section "Upgrading Cluster: ${cluster_name}"

    # Create cluster output directory
    local cluster_output_dir="${output_base_dir}/${cluster_name}"
    mkdir -p "${cluster_output_dir}"

    # Step 1: Ensure TMC context
    if ! ensure_tmc_context "${cluster_name}"; then
        error "Failed to create/verify TMC context for ${cluster_name}"
        return 1
    fi

    # Step 2: Fetch kubeconfig
    local kubeconfig_file="${cluster_output_dir}/kubeconfig"
    if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}"; then
        error "Failed to fetch kubeconfig for ${cluster_name}"
        return 1
    fi
    export KUBECONFIG="${kubeconfig_file}"

    # Step 3: Test connectivity
    if ! test_kubeconfig_connectivity "${kubeconfig_file}"; then
        error "Cannot connect to cluster ${cluster_name}"
        return 1
    fi
    success "Connected to cluster ${cluster_name}"

    # Step 4: Get cluster metadata (management cluster, provisioner)
    local metadata
    if ! metadata=$(discover_cluster_metadata "${cluster_name}"); then
        error "Failed to discover metadata for ${cluster_name}"
        return 1
    fi
    local mgmt_cluster=$(echo "${metadata}" | cut -d'|' -f1)
    local provisioner=$(echo "${metadata}" | cut -d'|' -f2)

    # Step 5: PRE-upgrade health check (unless skipped)
    if [ "${SKIP_HEALTH_CHECK}" = false ]; then
        local health_status
        validate_pre_upgrade_health "${cluster_name}" "${cluster_output_dir}"
        health_status=$?

        case $health_status in
            0)  # HEALTHY - auto-proceed
                success "Cluster is healthy, proceeding with upgrade..."
                ;;
            1)  # WARNINGS - prompt unless --force
                if [ "${FORCE_UPGRADE}" = true ]; then
                    warning "Proceeding with upgrade despite warnings (--force)"
                elif [ "${DRY_RUN}" = true ]; then
                    echo "[DRY-RUN] Would prompt for confirmation due to warnings"
                else
                    echo ""
                    echo -n "Cluster has warnings. Continue with upgrade? (y/n): "
                    read -r response < /dev/tty
                    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
                        warning "Upgrade skipped by user"
                        return 2
                    fi
                fi
                ;;
            2)  # CRITICAL - abort
                error "Cluster has CRITICAL issues. Fix them before upgrading."
                error "Upgrade aborted for ${cluster_name}"
                return 2
                ;;
        esac
    else
        warning "PRE-upgrade health check skipped (--skip-health-check)"
    fi

    # Step 6: Execute upgrade
    if ! execute_upgrade "${cluster_name}" "${mgmt_cluster}" "${provisioner}" "${cluster_output_dir}"; then
        error "Failed to execute upgrade for ${cluster_name}"
        return 1
    fi

    # Step 7: Monitor upgrade progress
    echo ""
    local monitor_result
    monitor_upgrade "${cluster_name}" "${mgmt_cluster}" "${provisioner}" "${UPGRADE_TIMEOUT}" "${cluster_output_dir}"
    monitor_result=$?

    case $monitor_result in
        0)  # Success
            success "Upgrade completed successfully for ${cluster_name}"
            ;;
        1)  # Failed
            error "Upgrade failed for ${cluster_name}"
            return 1
            ;;
        2)  # Timeout
            error "Upgrade timed out for ${cluster_name}"
            return 1
            ;;
    esac

    # Step 8: POST-upgrade health check
    echo ""
    validate_post_upgrade_health "${cluster_name}" "${cluster_output_dir}"

    success "Cluster ${cluster_name} upgrade process completed"
    return 0
}

#===============================================================================
# Main Upgrade Orchestration
#===============================================================================

run_cluster_upgrades() {
    local config_file="$1"

    # Validate configuration
    if ! load_configuration "${config_file}"; then
        exit 1
    fi

    # Display banner
    print_section "Kubernetes Cluster Upgrade"

    display_info "Configuration File" "${config_file}"
    display_info "Upgrade Timeout" "${UPGRADE_TIMEOUT} minutes"
    display_info "Dry Run" "${DRY_RUN}"
    display_info "Force Mode" "${FORCE_UPGRADE}"
    display_info "Started" "$(get_formatted_timestamp)"
    echo ""

    # Create output directory
    local timestamp=$(get_timestamp)
    local output_base_dir="${SCRIPT_DIR}/upgrade-results/upgrade-${timestamp}"
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
    local skipped_count=0
    local current=0
    local failed_clusters=()
    local skipped_clusters=()

    # Process each cluster
    while IFS= read -r cluster_name; do
        current=$((current + 1))

        echo ""
        echo -e "${MAGENTA}[${current}/${cluster_count}]${NC} Upgrading: ${YELLOW}${cluster_name}${NC}"

        local result
        upgrade_cluster "${cluster_name}" "${output_base_dir}"
        result=$?

        case $result in
            0)
                success_count=$((success_count + 1))
                ;;
            1)
                failed_count=$((failed_count + 1))
                failed_clusters+=("${cluster_name}")
                ;;
            2)
                skipped_count=$((skipped_count + 1))
                skipped_clusters+=("${cluster_name}")
                ;;
        esac

    done < <(get_cluster_list "${config_file}")

    # Display summary
    echo ""
    print_section "Upgrade Summary"
    echo -e "${CYAN}Total clusters: ${NC}${cluster_count}"
    echo -e "${GREEN}Successful: ${NC}${success_count}"
    echo -e "${RED}Failed: ${NC}${failed_count}"
    echo -e "${YELLOW}Skipped: ${NC}${skipped_count}"

    if [ ${failed_count} -gt 0 ]; then
        echo ""
        echo -e "${RED}Failed clusters:${NC}"
        for cluster in "${failed_clusters[@]}"; do
            echo "  - ${cluster}"
        done
    fi

    if [ ${skipped_count} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Skipped clusters:${NC}"
        for cluster in "${skipped_clusters[@]}"; do
            echo "  - ${cluster}"
        done
    fi

    echo ""
    echo -e "${CYAN}Results directory: ${NC}${output_base_dir}"
    echo ""
    display_banner "Cluster Upgrade Complete!"
    echo ""

    # Return overall status
    if [ ${failed_count} -gt 0 ]; then
        return 1
    fi
    return 0
}

#===============================================================================
# Argument Parsing
#===============================================================================

parse_arguments() {
    local config_file="./clusters.conf"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-health-check)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            --force)
                FORCE_UPGRADE=true
                shift
                ;;
            --timeout)
                shift
                if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                    UPGRADE_TIMEOUT="$1"
                else
                    error "Invalid timeout value: $1"
                    exit 1
                fi
                shift
                ;;
            -*)
                error "Unknown option: $1"
                show_usage
                ;;
            *)
                config_file="$1"
                shift
                ;;
        esac
    done

    # Validate config file
    if [[ ! -f "${config_file}" ]]; then
        error "Configuration file not found: ${config_file}"
        exit 1
    fi

    CONFIG_FILE="${config_file}"
}

#===============================================================================
# Main Entry Point
#===============================================================================

main() {
    check_prerequisites
    parse_arguments "$@"
    run_cluster_upgrades "${CONFIG_FILE}"
}

main "$@"
