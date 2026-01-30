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
PARALLEL_MODE="true"        # Parallel execution enabled by default
BATCH_SIZE=6                # Default batch size for parallel execution
SINGLE_CLUSTER=""           # Single cluster name (overrides config file)

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
By default, processes clusters in parallel batches of 6.

Arguments:
  clusters.conf     Path to configuration file with cluster names (one per line)
                    Default: ./clusters.conf

Options:
  -h, --help              Show this help message
  -c, --cluster <name>    Upgrade a single cluster (overrides clusters.conf)
  --dry-run               Show what would be upgraded without actually upgrading
  --skip-health-check     Skip PRE-upgrade health check (not recommended)
  --force                 Skip confirmation prompts for WARNINGS status
  --timeout <minutes>     Upgrade timeout in minutes (default: 30)
  --sequential            Process clusters one at a time (default: parallel)
  --batch-size N          Number of clusters to process in parallel (default: 6)

Upgrade Decision Logic:
  HEALTHY   → Auto-proceed with upgrade
  WARNINGS  → Prompt user for confirmation (unless --force)
  CRITICAL  → Abort upgrade (fix issues first)

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output

Examples:
  # Upgrade clusters (parallel by default, 6 at a time)
  $0

  # Upgrade a single cluster by name
  $0 -c my-cluster-name

  # Upgrade clusters from specific config
  $0 ./upgrade-clusters.conf

  # Dry run (show what would happen)
  $0 --dry-run

  # Dry run for a single cluster
  $0 -c my-cluster-name --dry-run

  # Force upgrade even with warnings (skips prompts)
  $0 --force

  # Sequential execution (one cluster at a time)
  $0 --sequential

  # Custom batch size (10 clusters at a time)
  $0 --batch-size 10

  # Custom timeout (45 minutes)
  $0 --timeout 45

EOF
    exit 0
}

#===============================================================================
# Display Health Summary on CLI
#===============================================================================

display_health_summary_cli() {
    local cluster_name="$1"
    local mode="$2"  # "PRE" or "POST"

    echo ""
    echo -e "${CYAN}--- ${mode} Health Check Summary: ${cluster_name} ---${NC}"
    echo ""
    echo "--- Resource Counts ---"
    echo ""
    echo "Nodes Total: ${HEALTH_NODES_TOTAL:-0}"
    echo "Nodes Ready: ${HEALTH_NODES_READY:-0}"
    echo "Pods Total: ${HEALTH_PODS_TOTAL:-0}"
    echo "Pods Running: ${HEALTH_PODS_RUNNING:-0}"
    echo "Pods Not Running: $((${HEALTH_PODS_TOTAL:-0} - ${HEALTH_PODS_RUNNING:-0}))"
    echo "Deployments Total: ${HEALTH_DEPLOYS_TOTAL:-0}"
    echo "DaemonSets Total: ${HEALTH_DS_TOTAL:-0}"
    echo "StatefulSets Total: ${HEALTH_STS_TOTAL:-0}"
    echo "PVCs Total: ${HEALTH_PVC_TOTAL:-0}"
    echo "Helm Releases: ${HEALTH_HELM_TOTAL:-0}"
    echo ""
    echo "--- Health Indicators ---"
    echo ""

    # Nodes NotReady
    if [[ "${HEALTH_NODES_NOTREADY:-0}" -gt 0 ]]; then
        printf "Nodes NotReady: %-6s ${RED}[CRITICAL]${NC}\n" "${HEALTH_NODES_NOTREADY:-0}"
    else
        printf "Nodes NotReady: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_NODES_NOTREADY:-0}"
    fi

    # Pods CrashLoop
    if [[ "${HEALTH_PODS_CRASHLOOP:-0}" -gt 0 ]]; then
        printf "Pods CrashLoop: %-6s ${RED}[CRITICAL]${NC}\n" "${HEALTH_PODS_CRASHLOOP:-0}"
    else
        printf "Pods CrashLoop: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_PODS_CRASHLOOP:-0}"
    fi

    # Pods Pending
    if [[ "${HEALTH_PODS_PENDING:-0}" -gt 0 ]]; then
        printf "Pods Pending: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_PODS_PENDING:-0}"
    else
        printf "Pods Pending: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_PODS_PENDING:-0}"
    fi

    # Deployments NotReady
    if [[ "${HEALTH_DEPLOYS_NOTREADY:-0}" -gt 0 ]]; then
        printf "Deploys NotReady: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_DEPLOYS_NOTREADY:-0}"
    else
        printf "Deploys NotReady: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_DEPLOYS_NOTREADY:-0}"
    fi

    # DaemonSets NotReady
    if [[ "${HEALTH_DS_NOTREADY:-0}" -gt 0 ]]; then
        printf "DS NotReady: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_DS_NOTREADY:-0}"
    else
        printf "DS NotReady: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_DS_NOTREADY:-0}"
    fi

    # StatefulSets NotReady
    if [[ "${HEALTH_STS_NOTREADY:-0}" -gt 0 ]]; then
        printf "STS NotReady: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_STS_NOTREADY:-0}"
    else
        printf "STS NotReady: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_STS_NOTREADY:-0}"
    fi

    # PVCs NotBound
    if [[ "${HEALTH_PVC_NOTBOUND:-0}" -gt 0 ]]; then
        printf "PVCs NotBound: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_PVC_NOTBOUND:-0}"
    else
        printf "PVCs NotBound: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_PVC_NOTBOUND:-0}"
    fi

    # Helm Failed
    if [[ "${HEALTH_HELM_FAILED:-0}" -gt 0 ]]; then
        printf "Helm Failed: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_HELM_FAILED:-0}"
    else
        printf "Helm Failed: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_HELM_FAILED:-0}"
    fi

    # Pods Completed
    printf "Pods Completed: %-6s ${CYAN}[INFO]${NC}\n" "${HEALTH_PODS_COMPLETED:-0}"

    # Pods Unaccounted
    if [[ "${HEALTH_PODS_UNACCOUNTED:-0}" -gt 0 ]]; then
        printf "Pods Unaccounted: %-6s ${YELLOW}[WARNING]${NC}\n" "${HEALTH_PODS_UNACCOUNTED:-0}"
    else
        printf "Pods Unaccounted: %-6s ${GREEN}[OK]${NC}\n" "${HEALTH_PODS_UNACCOUNTED:-0}"
    fi

    echo ""
    echo "=================================================================================="
    if [[ "${HEALTH_STATUS}" == "CRITICAL" ]]; then
        echo -e "CLUSTER HEALTH: ${RED}${HEALTH_STATUS}${NC}"
    elif [[ "${HEALTH_STATUS}" == "WARNINGS" ]]; then
        echo -e "CLUSTER HEALTH: ${YELLOW}${HEALTH_STATUS}${NC}"
    else
        echo -e "CLUSTER HEALTH: ${GREEN}${HEALTH_STATUS}${NC}"
    fi
    echo "  Critical Issues: ${HEALTH_CRITICAL_COUNT:-0}"
    echo "  Warnings: ${HEALTH_WARNING_COUNT:-0}"
    echo "=================================================================================="
    echo ""
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

    # Display health summary on CLI
    display_health_summary_cli "${cluster_name}" "PRE-Upgrade"

    # Save PRE-upgrade health report
    local pre_report="${output_dir}/pre-upgrade-health.txt"
    {
        echo "================================================================================"
        echo "  PRE-UPGRADE HEALTH CHECK"
        echo "================================================================================"
        echo "Cluster: ${cluster_name}"
        echo "Timestamp: $(get_formatted_timestamp)"
        echo ""
        echo "--- Resource Counts ---"
        echo ""
        echo "Nodes Total: ${HEALTH_NODES_TOTAL:-0}"
        echo "Nodes Ready: ${HEALTH_NODES_READY:-0}"
        echo "Pods Total: ${HEALTH_PODS_TOTAL:-0}"
        echo "Pods Running: ${HEALTH_PODS_RUNNING:-0}"
        echo "Pods Not Running: $((${HEALTH_PODS_TOTAL:-0} - ${HEALTH_PODS_RUNNING:-0}))"
        echo "Deployments Total: ${HEALTH_DEPLOYS_TOTAL:-0}"
        echo "DaemonSets Total: ${HEALTH_DS_TOTAL:-0}"
        echo "StatefulSets Total: ${HEALTH_STS_TOTAL:-0}"
        echo "PVCs Total: ${HEALTH_PVC_TOTAL:-0}"
        echo "Helm Releases: ${HEALTH_HELM_TOTAL:-0}"
        echo ""
        echo "--- Health Indicators ---"
        echo ""
        echo "Nodes NotReady: ${HEALTH_NODES_NOTREADY:-0}"
        echo "Pods CrashLoop: ${HEALTH_PODS_CRASHLOOP:-0}"
        echo "Pods Pending: ${HEALTH_PODS_PENDING:-0}"
        echo "Deploys NotReady: ${HEALTH_DEPLOYS_NOTREADY:-0}"
        echo "DS NotReady: ${HEALTH_DS_NOTREADY:-0}"
        echo "STS NotReady: ${HEALTH_STS_NOTREADY:-0}"
        echo "PVCs NotBound: ${HEALTH_PVC_NOTBOUND:-0}"
        echo "Helm Failed: ${HEALTH_HELM_FAILED:-0}"
        echo "Pods Completed: ${HEALTH_PODS_COMPLETED:-0}"
        echo "Pods Unaccounted: ${HEALTH_PODS_UNACCOUNTED:-0}"
        echo ""
        echo "CLUSTER HEALTH: ${HEALTH_STATUS}"
        echo "  Critical Issues: ${HEALTH_CRITICAL_COUNT:-0}"
        echo "  Warnings: ${HEALTH_WARNING_COUNT:-0}"
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

    # Display health summary on CLI
    display_health_summary_cli "${cluster_name}" "POST-Upgrade"

    # Save POST-upgrade health report
    local post_report="${output_dir}/post-upgrade-health.txt"
    {
        echo "================================================================================"
        echo "  POST-UPGRADE HEALTH CHECK"
        echo "================================================================================"
        echo "Cluster: ${cluster_name}"
        echo "Timestamp: $(get_formatted_timestamp)"
        echo ""
        echo "--- Resource Counts ---"
        echo ""
        echo "Nodes Total: ${HEALTH_NODES_TOTAL:-0}"
        echo "Nodes Ready: ${HEALTH_NODES_READY:-0}"
        echo "Pods Total: ${HEALTH_PODS_TOTAL:-0}"
        echo "Pods Running: ${HEALTH_PODS_RUNNING:-0}"
        echo "Pods Not Running: $((${HEALTH_PODS_TOTAL:-0} - ${HEALTH_PODS_RUNNING:-0}))"
        echo "Deployments Total: ${HEALTH_DEPLOYS_TOTAL:-0}"
        echo "DaemonSets Total: ${HEALTH_DS_TOTAL:-0}"
        echo "StatefulSets Total: ${HEALTH_STS_TOTAL:-0}"
        echo "PVCs Total: ${HEALTH_PVC_TOTAL:-0}"
        echo "Helm Releases: ${HEALTH_HELM_TOTAL:-0}"
        echo ""
        echo "--- Health Indicators ---"
        echo ""
        echo "Nodes NotReady: ${HEALTH_NODES_NOTREADY:-0}"
        echo "Pods CrashLoop: ${HEALTH_PODS_CRASHLOOP:-0}"
        echo "Pods Pending: ${HEALTH_PODS_PENDING:-0}"
        echo "Deploys NotReady: ${HEALTH_DEPLOYS_NOTREADY:-0}"
        echo "DS NotReady: ${HEALTH_DS_NOTREADY:-0}"
        echo "STS NotReady: ${HEALTH_STS_NOTREADY:-0}"
        echo "PVCs NotBound: ${HEALTH_PVC_NOTBOUND:-0}"
        echo "Helm Failed: ${HEALTH_HELM_FAILED:-0}"
        echo "Pods Completed: ${HEALTH_PODS_COMPLETED:-0}"
        echo "Pods Unaccounted: ${HEALTH_PODS_UNACCOUNTED:-0}"
        echo ""
        echo "CLUSTER HEALTH: ${HEALTH_STATUS}"
        echo "  Critical Issues: ${HEALTH_CRITICAL_COUNT:-0}"
        echo "  Warnings: ${HEALTH_WARNING_COUNT:-0}"
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
# Upgrade Single Cluster (For Parallel Execution)
#===============================================================================

upgrade_cluster_parallel() {
    local cluster_name="$1"
    local output_base_dir="$2"
    local results_file="$3"

    local status="SUCCESS"
    local exit_code=0

    # Create cluster output directory
    local cluster_output_dir="${output_base_dir}/${cluster_name}"
    mkdir -p "${cluster_output_dir}"

    # Step 1: Fetch kubeconfig (TMC context already prepared)
    local kubeconfig_file="${cluster_output_dir}/kubeconfig"
    if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}" >/dev/null 2>&1; then
        echo "CLUSTER:${cluster_name}|STATUS:FAILED|REASON:Failed to fetch kubeconfig" >> "${results_file}"
        return 1
    fi
    export KUBECONFIG="${kubeconfig_file}"

    # Step 2: Test connectivity
    if ! test_kubeconfig_connectivity "${kubeconfig_file}" >/dev/null 2>&1; then
        echo "CLUSTER:${cluster_name}|STATUS:FAILED|REASON:Cannot connect to cluster" >> "${results_file}"
        return 1
    fi

    # Step 3: Get cluster metadata
    local metadata
    if ! metadata=$(discover_cluster_metadata "${cluster_name}" 2>/dev/null); then
        echo "CLUSTER:${cluster_name}|STATUS:FAILED|REASON:Failed to discover metadata" >> "${results_file}"
        return 1
    fi
    local mgmt_cluster=$(echo "${metadata}" | cut -d'|' -f1)
    local provisioner=$(echo "${metadata}" | cut -d'|' -f2)

    # Step 4: PRE-upgrade health check (unless skipped)
    if [ "${SKIP_HEALTH_CHECK}" = false ]; then
        collect_health_metrics
        calculate_health_status

        # Save PRE-upgrade health report
        local pre_report="${cluster_output_dir}/pre-upgrade-health.txt"
        {
            echo "PRE-UPGRADE HEALTH CHECK"
            echo "Cluster: ${cluster_name}"
            echo "Timestamp: $(get_formatted_timestamp)"
            echo "Status: ${HEALTH_STATUS}"
        } > "${pre_report}"

        case "${HEALTH_STATUS}" in
            "HEALTHY")
                # Proceed
                ;;
            "WARNINGS")
                if [ "${FORCE_UPGRADE}" = false ] && [ "${DRY_RUN}" = false ]; then
                    # In parallel mode, we can't prompt - skip if not --force
                    echo "CLUSTER:${cluster_name}|STATUS:SKIPPED|REASON:Cluster has warnings (use --force to override)" >> "${results_file}"
                    return 2
                fi
                ;;
            "CRITICAL")
                echo "CLUSTER:${cluster_name}|STATUS:SKIPPED|REASON:Cluster has CRITICAL issues" >> "${results_file}"
                return 2
                ;;
        esac
    fi

    # Step 5: Execute upgrade (if not dry-run)
    if [ "${DRY_RUN}" = true ]; then
        echo "CLUSTER:${cluster_name}|STATUS:DRYRUN|REASON:Would upgrade cluster" >> "${results_file}"
        return 0
    fi

    # Initiate upgrade
    local upgrade_log="${cluster_output_dir}/upgrade-log.txt"
    {
        echo "UPGRADE LOG"
        echo "Start Time: $(get_formatted_timestamp)"
        echo "Command: tanzu tmc cluster upgrade ${cluster_name} -m ${mgmt_cluster} -p ${provisioner} --latest"
    } > "${upgrade_log}"

    if ! tanzu tmc cluster upgrade "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" --latest >> "${upgrade_log}" 2>&1; then
        echo "CLUSTER:${cluster_name}|STATUS:FAILED|REASON:Failed to initiate upgrade" >> "${results_file}"
        return 1
    fi

    # Step 6: Monitor upgrade
    local start_time=$(date +%s)
    local timeout_seconds=$((UPGRADE_TIMEOUT * 60))

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout_seconds ]; then
            echo "CLUSTER:${cluster_name}|STATUS:FAILED|REASON:Upgrade timeout after ${UPGRADE_TIMEOUT} minutes" >> "${results_file}"
            return 1
        fi

        local status_json
        if status_json=$(tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" -o json 2>/dev/null); then
            local phase=$(echo "${status_json}" | jq -r '.status.phase // "UNKNOWN"')

            case "${phase}" in
                "READY")
                    break
                    ;;
                "ERROR"|"FAILED")
                    echo "CLUSTER:${cluster_name}|STATUS:FAILED|REASON:Upgrade failed (phase: ${phase})" >> "${results_file}"
                    return 1
                    ;;
            esac
        fi

        sleep 30
    done

    # Step 7: POST-upgrade health check
    sleep 10  # Wait for cluster to stabilize

    # Refresh kubeconfig
    fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}" >/dev/null 2>&1
    export KUBECONFIG="${kubeconfig_file}"

    collect_health_metrics
    calculate_health_status

    local post_report="${cluster_output_dir}/post-upgrade-health.txt"
    {
        echo "POST-UPGRADE HEALTH CHECK"
        echo "Cluster: ${cluster_name}"
        echo "Timestamp: $(get_formatted_timestamp)"
        echo "Status: ${HEALTH_STATUS}"
    } > "${post_report}"

    # Write success
    echo "CLUSTER:${cluster_name}|STATUS:SUCCESS|REASON:Upgrade completed (${HEALTH_STATUS})" >> "${results_file}"
    return 0
}

#===============================================================================
# Prepare TMC Contexts (Sequential - to avoid race conditions)
#===============================================================================

prepare_upgrade_tmc_contexts() {
    local config_file="$1"

    # Note: Credentials will be prompted inside ensure_tmc_context() only if
    # a new context needs to be created (existing valid contexts are reused)

    progress "Preparing TMC contexts for all clusters..."

    local cluster_list=$(get_cluster_list "${config_file}")
    local cluster_count=$(count_clusters "${config_file}")
    local current=0

    while IFS= read -r cluster_name; do
        current=$((current + 1))
        debug "[${current}/${cluster_count}] Preparing TMC context for ${cluster_name}..."

        ensure_tmc_context "${cluster_name}" >/dev/null 2>&1
    done < <(echo "${cluster_list}")

    success "TMC contexts prepared"
}

#===============================================================================
# Run Upgrades in Parallel (Batch-based)
#===============================================================================

run_upgrades_parallel() {
    local config_file="$1"
    local output_base_dir="$2"
    local batch_size="$3"

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
            echo -e "${MAGENTA}[${display_idx}/${cluster_count}]${NC} Launching upgrade: ${YELLOW}${cluster_name}${NC}"

            upgrade_cluster_parallel "${cluster_name}" "${output_base_dir}" "${results_file}" &
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

    success "All ${cluster_count} upgrades processed"
    echo ""

    # Parse results
    local success_count=0
    local failed_count=0
    local skipped_count=0
    local dryrun_count=0
    local failed_clusters=()
    local skipped_clusters=()

    print_section "Results Summary"

    while IFS= read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi

        local cluster_name=$(echo "${line}" | cut -d'|' -f1 | cut -d':' -f2)
        local status=$(echo "${line}" | cut -d'|' -f2 | cut -d':' -f2)
        local reason=$(echo "${line}" | cut -d'|' -f3 | cut -d':' -f2-)

        case "${status}" in
            "SUCCESS")
                success_count=$((success_count + 1))
                echo -e "${GREEN}[SUCCESS]${NC} ${cluster_name}: ${reason}"
                ;;
            "FAILED")
                failed_count=$((failed_count + 1))
                failed_clusters+=("${cluster_name}")
                echo -e "${RED}[FAILED]${NC} ${cluster_name}: ${reason}"
                ;;
            "SKIPPED")
                skipped_count=$((skipped_count + 1))
                skipped_clusters+=("${cluster_name}")
                echo -e "${YELLOW}[SKIPPED]${NC} ${cluster_name}: ${reason}"
                ;;
            "DRYRUN")
                dryrun_count=$((dryrun_count + 1))
                echo -e "${CYAN}[DRY-RUN]${NC} ${cluster_name}: ${reason}"
                ;;
        esac
    done < "${results_file}"

    # Cleanup temp file
    rm -f "${results_file}"

    # Return values via global variables
    PARALLEL_SUCCESS_COUNT=${success_count}
    PARALLEL_FAILED_COUNT=${failed_count}
    PARALLEL_SKIPPED_COUNT=${skipped_count}
    PARALLEL_DRYRUN_COUNT=${dryrun_count}
    PARALLEL_FAILED_CLUSTERS=("${failed_clusters[@]}")
    PARALLEL_SKIPPED_CLUSTERS=("${skipped_clusters[@]}")
}

#===============================================================================
# Main Upgrade Orchestration
#===============================================================================

run_cluster_upgrades() {
    local config_file="$1"
    local parallel="$2"
    local batch_size="$3"
    local single_cluster="$4"

    local cluster_list=""
    local cluster_count=0

    # Display banner
    print_section "Kubernetes Cluster Upgrade"

    # Handle single cluster mode
    if [[ -n "${single_cluster}" ]]; then
        cluster_list="${single_cluster}"
        cluster_count=1
        parallel="false"  # No need for parallel with single cluster

        display_info "Cluster" "${single_cluster}"
        display_info "Mode" "Single Cluster"
    else
        # Validate configuration
        if ! load_configuration "${config_file}"; then
            exit 1
        fi

        # Get cluster list from config
        cluster_list=$(get_cluster_list "${config_file}")
        if [ -z "${cluster_list}" ]; then
            error "No clusters found in configuration file"
            exit 1
        fi
        cluster_count=$(count_clusters "${config_file}")

        display_info "Configuration File" "${config_file}"
        if [[ "${parallel}" == "true" ]]; then
            display_info "Execution Mode" "Parallel (batch size: ${batch_size})"
        else
            display_info "Execution Mode" "Sequential"
        fi
    fi

    display_info "Upgrade Timeout" "${UPGRADE_TIMEOUT} minutes"
    display_info "Dry Run" "${DRY_RUN}"
    display_info "Force Mode" "${FORCE_UPGRADE}"
    display_info "Started" "$(get_formatted_timestamp)"
    echo ""

    # Create output directory
    local timestamp=$(get_timestamp)
    local output_base_dir="${SCRIPT_DIR}/upgrade-results/upgrade-${timestamp}"
    mkdir -p "${output_base_dir}"

    # Display cluster list (only for multi-cluster mode)
    if [[ -z "${single_cluster}" ]]; then
        display_cluster_list "${config_file}" || exit 1
    else
        echo -e "${CYAN}Target Cluster:${NC} ${single_cluster}"
        echo ""
    fi

    # Initialize counters
    local success_count=0
    local failed_count=0
    local skipped_count=0
    local current=0
    local failed_clusters=()
    local skipped_clusters=()

    if [[ "${parallel}" == "true" ]]; then
        # Parallel execution (batch-based)
        echo ""

        # Prepare TMC contexts sequentially first (to avoid race conditions)
        prepare_upgrade_tmc_contexts "${config_file}"
        echo ""

        # Run upgrades in parallel batches
        run_upgrades_parallel "${config_file}" "${output_base_dir}" "${batch_size}"

        # Get results from global variables
        success_count=${PARALLEL_SUCCESS_COUNT}
        failed_count=${PARALLEL_FAILED_COUNT}
        skipped_count=${PARALLEL_SKIPPED_COUNT}
        failed_clusters=("${PARALLEL_FAILED_CLUSTERS[@]}")
        skipped_clusters=("${PARALLEL_SKIPPED_CLUSTERS[@]}")
    else
        # Sequential execution (original behavior or single cluster mode)
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

        done < <(echo "${cluster_list}")
    fi

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
            -c|--cluster)
                shift
                if [[ -n "$1" ]] && [[ ! "$1" =~ ^- ]]; then
                    SINGLE_CLUSTER="$1"
                else
                    error "Cluster name required for -c/--cluster option"
                    exit 1
                fi
                shift
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

    # If single cluster is specified, skip config file validation
    if [[ -n "${SINGLE_CLUSTER}" ]]; then
        CONFIG_FILE=""
        return
    fi

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
    run_cluster_upgrades "${CONFIG_FILE}" "${PARALLEL_MODE}" "${BATCH_SIZE}" "${SINGLE_CLUSTER}"
}

main "$@"
