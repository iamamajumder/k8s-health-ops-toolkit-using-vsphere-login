#!/bin/bash

################################################################################
# Kubernetes Cluster Upgrade Script (v1.0)
#
# vSphere-only workflow:
#   - Runs PRE/POST health checks
#   - Discovers cluster namespace from Supervisor
#   - Upgrades via Supervisor CR patch
#     * cluster: spec.topology.version
#     * tanzukubernetescluster: spec.distribution.version
#   - Supports interactive version selection and parallel batches
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/vsphere-cluster.sh"

TIMEOUT_MULTIPLIER=5
DRY_RUN=false
SINGLE_CLUSTER=""
CONFIG_FILE=""
PARALLEL_MODE=false
BATCH_SIZE=${DEFAULT_BATCH_SIZE}
DEFAULT_CONFIG="./input.conf"

################################################################################
# Usage
################################################################################
usage() {
    cat << EOF
Kubernetes Cluster Upgrade Script (v${VERSION})

USAGE:
    $0                                  # Use default ./input.conf (sequential)
    $0 -c CLUSTER_NAME [OPTIONS]        # Single cluster upgrade
    $0 CONFIG_FILE [OPTIONS]            # Multi-cluster upgrade (sequential)
    $0 --parallel [OPTIONS]             # Parallel batch mode

OPTIONS:
    --parallel
    --batch-size N
    --timeout-multiplier N
    --dry-run
    --help

NOTES:
    - Upgrades are applied via Supervisor objects.
    - For TKC-managed clusters, you will be prompted for auto-retirement when required.

EOF
}

################################################################################
# Prerequisites
################################################################################
check_prerequisites() {
    check_command kubectl "kubectl is required but not installed"
    check_command jq "jq is required but not installed"

    if ! kubectl vsphere version >/dev/null 2>&1; then
        error "kubectl vsphere plugin is required but not available"
        exit 1
    fi

    if [[ ! -f "${SCRIPT_DIR}/k8s-health-check.sh" ]]; then
        error "k8s-health-check.sh not found in ${SCRIPT_DIR}"
        exit 1
    fi
}

################################################################################
# Health check wrappers
################################################################################
run_pre_health_check() {
    local cluster_name="$1"
    local output_dir="$2"

    progress "Running PRE-upgrade health check for ${cluster_name}..."
    local source_config="${CONFIG_FILE:-${DEFAULT_CONFIG}}"
    local temp_config
    if ! temp_config=$(create_single_cluster_config "${cluster_name}" "${source_config}"); then
        error "Failed to build single-cluster config from ${source_config}"
        return 1
    fi

    if "${SCRIPT_DIR}/k8s-health-check.sh" --mode pre "${temp_config}"; then
        rm -f "${temp_config}"
        local pre_hcr_dir="${OUTPUT_BASE_DIR}/${cluster_name}/h-c-r"
        local latest_pre
        latest_pre=$(ls -t "${pre_hcr_dir}"/pre-hcr-*.txt 2>/dev/null | head -1)
        if [[ -n "${latest_pre}" && -f "${latest_pre}" ]]; then
            local ts
            ts=$(get_timestamp)
            cp "${latest_pre}" "${output_dir}/pre-hcr-${ts}.txt"
            echo "${OUTPUT_BASE_DIR}" > "${output_dir}/.pre-results-path"
            return 0
        fi
    else
        rm -f "${temp_config}"
    fi

    error "PRE-upgrade health check failed for ${cluster_name}"
    return 1
}

run_post_health_check() {
    local cluster_name="$1"
    local output_dir="$2"

    progress "Running POST-upgrade health check for ${cluster_name}..."
    local source_config="${CONFIG_FILE:-${DEFAULT_CONFIG}}"
    local temp_config
    if ! temp_config=$(create_single_cluster_config "${cluster_name}" "${source_config}"); then
        error "Failed to build single-cluster config from ${source_config}"
        return 1
    fi

    local pre_results_path="${OUTPUT_BASE_DIR}"
    if [[ -f "${output_dir}/.pre-results-path" ]]; then
        pre_results_path=$(cat "${output_dir}/.pre-results-path")
    fi

    if "${SCRIPT_DIR}/k8s-health-check.sh" --mode post "${temp_config}" "${pre_results_path}"; then
        rm -f "${temp_config}"
        local post_hcr_dir="${OUTPUT_BASE_DIR}/${cluster_name}/h-c-r"
        local latest_post
        latest_post=$(ls -t "${post_hcr_dir}"/post-hcr-*.txt 2>/dev/null | head -1)
        if [[ -n "${latest_post}" && -f "${latest_post}" ]]; then
            local ts
            ts=$(get_timestamp)
            cp "${latest_post}" "${output_dir}/post-hcr-${ts}.txt"
            return 0
        fi
    else
        rm -f "${temp_config}"
    fi

    error "POST-upgrade health check failed for ${cluster_name}"
    return 1
}

################################################################################
# Prompts
################################################################################
prompt_user_confirmation() {
    local cluster_name="$1"
    echo ""
    print_section "Upgrade Confirmation"
    echo -e "${YELLOW}Do you want to upgrade ${BOLD}${cluster_name}${RESET}${YELLOW}?${RESET}"
    echo -n "Enter (Y/N): "
    local response
    read -r response </dev/tty
    [[ "${response}" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

prompt_auto_retire_confirmation() {
    echo -n "Do you want to enable Auto-retire the workload cluster from tkc to cluster api? (Y/N): "
    local response
    read -r response </dev/tty
    [[ "${response}" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

prompt_version_selection() {
    local cluster_name="$1"
    local current_version="$2"
    local available_versions="$3"

    echo "" >&2
    echo -e "${BOLD}${CYAN}=== Upgrade Version Selection ===${NC}" >&2
    echo -e "Cluster: ${YELLOW}${cluster_name}${NC}" >&2
    echo -e "Current Version: ${GREEN}${current_version:-unknown}${NC}" >&2
    echo "" >&2
    echo "Available upgrade versions:" >&2

    local -a version_array
    while IFS= read -r version; do
        [[ -z "${version}" ]] && continue
        version_array+=("${version}")
    done <<< "${available_versions}"

    echo -e "  ${BOLD}0)${NC} Use latest available version" >&2
    for i in "${!version_array[@]}"; do
        local num=$((i + 1))
        echo -e "  ${BOLD}${num})${NC} ${version_array[$i]}" >&2
    done
    echo "" >&2

    local attempts=0
    while [[ ${attempts} -lt 3 ]]; do
        echo -n "Select version number (0-${#version_array[@]}) or 'c' to cancel: " >&2
        local selection
        read -r selection </dev/tty

        if [[ "${selection,,}" == "c" ]]; then
            return 2
        fi
        if [[ "${selection}" == "0" ]]; then
            echo "latest"
            return 0
        fi
        if [[ "${selection}" =~ ^[0-9]+$ ]] && [[ ${selection} -ge 1 ]] && [[ ${selection} -le ${#version_array[@]} ]]; then
            echo "${version_array[$((selection - 1))]}"
            return 0
        fi

        attempts=$((attempts + 1))
        echo -e "${RED}Invalid selection.${NC}" >&2
    done

    return 2
}

################################################################################
# Cluster metadata
################################################################################
get_upgrade_inputs() {
    local cluster_name="$1"

    local suffix_supervisor
    if ! suffix_supervisor=$(get_supervisor_for_cluster "${cluster_name}" "${CONFIG_FILE}"); then
        error "Unable to resolve supervisor for ${cluster_name}"
        return 1
    fi

    local supervisor
    supervisor=$(echo "${suffix_supervisor}" | cut -d'|' -f2)
    local namespace
    if ! namespace=$(discover_cluster_namespace "${cluster_name}" "${CONFIG_FILE}"); then
        error "Unable to discover namespace for ${cluster_name}"
        return 1
    fi

    local kind
    if ! kind=$(detect_cluster_kind "${cluster_name}" "${namespace}"); then
        error "Unable to detect cluster kind for ${cluster_name} in namespace ${namespace}"
        return 1
    fi

    echo "${supervisor}|${namespace}|${kind}"
}

query_available_versions() {
    local cluster_name="$1"
    local namespace="$2"
    local kind="$3"
    local result_file="$4"

    local versions
    versions=$(get_updates_available_versions "${kind}" "${cluster_name}" "${namespace}" || true)
    if [[ -z "${versions}" ]]; then
        return 1
    fi

    echo "${versions}" | sed '/^[[:space:]]*$/d' | sort -V -r | uniq > "${result_file}"
    [[ -s "${result_file}" ]]
}

get_cluster_runtime_version() {
    local cluster_name="$1"
    local cluster_kubeconfig="${OUTPUT_BASE_DIR}/${cluster_name}/kubeconfig"
    if [[ ! -f "${cluster_kubeconfig}" ]]; then
        echo "unknown"
        return 0
    fi
    kubectl --kubeconfig="${cluster_kubeconfig}" version -o json 2>/dev/null | \
        jq -r '.serverVersion.gitVersion // "unknown"' | tr -d ' \n\r'
}

get_node_count() {
    local cluster_name="$1"
    local cluster_kubeconfig="${OUTPUT_BASE_DIR}/${cluster_name}/kubeconfig"

    if [[ -f "${cluster_kubeconfig}" ]]; then
        local node_count
        node_count=$(kubectl --kubeconfig="${cluster_kubeconfig}" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' \n\r')
        node_count=${node_count:-0}
        if [[ "${node_count}" -gt 0 ]]; then
            echo "${node_count}"
            return 0
        fi
    fi

    echo "5"
}

################################################################################
# Upgrade execution
################################################################################
execute_upgrade() {
    local cluster_name="$1"
    local namespace="$2"
    local kind="$3"
    local output_dir="$4"
    local target_version="$5"

    local ts
    ts=$(get_timestamp)
    local upgrade_log="${output_dir}/upgrade-log-${ts}.txt"

    {
        echo "==================================="
        echo "Cluster Upgrade Execution"
        echo "==================================="
        echo "Cluster: ${cluster_name}"
        echo "Namespace: ${namespace}"
        echo "Kind: ${kind}"
        echo "Target Version: ${target_version}"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "==================================="
        echo ""
    } | tee -a "${upgrade_log}"

    # If selected "latest", resolve to actual highest available version.
    if [[ "${target_version}" == "latest" ]]; then
        local resolved
        resolved=$(get_updates_available_versions "${kind}" "${cluster_name}" "${namespace}" | head -1)
        if [[ -n "${resolved}" ]]; then
            target_version="${resolved}"
        else
            error "Could not resolve latest target version for ${cluster_name}" | tee -a "${upgrade_log}"
            return 1
        fi
    fi

    if [[ "${kind}" == "tkc" ]] && needs_tkc_retirement "${kind}" "${cluster_name}" "${namespace}" "${target_version}"; then
        echo "" | tee -a "${upgrade_log}"
        warning "Target ${target_version} is not currently available through TKC path for ${cluster_name}" | tee -a "${upgrade_log}"
        if prompt_auto_retire_confirmation; then
            if ! auto_retire_tkc_cluster "${cluster_name}" "${namespace}" 1800 | tee -a "${upgrade_log}"; then
                error "Auto-retire failed for ${cluster_name}" | tee -a "${upgrade_log}"
                return 1
            fi
            kind="cluster"
            success "Retirement completed; continuing with Cluster API path" | tee -a "${upgrade_log}"
        else
            warning "Upgrade skipped by user (TKC retirement not approved)" | tee -a "${upgrade_log}"
            return 2
        fi
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        warning "DRY RUN: would patch ${kind}/${cluster_name} in namespace ${namespace} to ${target_version}" | tee -a "${upgrade_log}"
        echo "${kind}" > "${output_dir}/.kind"
        echo "${target_version}" > "${output_dir}/.target-version"
        return 0
    fi

    if ! apply_upgrade_patch "${kind}" "${cluster_name}" "${namespace}" "${target_version}" "false" >> "${upgrade_log}" 2>&1; then
        error "Failed to apply upgrade patch" | tee -a "${upgrade_log}"
        return 1
    fi

    echo "${kind}" > "${output_dir}/.kind"
    echo "${target_version}" > "${output_dir}/.target-version"
    success "Upgrade patch submitted successfully" | tee -a "${upgrade_log}"
    return 0
}

monitor_upgrade_progress() {
    local cluster_name="$1"
    local timeout_minutes="$2"
    local output_dir="$3"
    local pre_version="$4"
    local target_version="$5"

    local upgrade_log
    upgrade_log=$(ls -t "${output_dir}"/upgrade-log-*.txt 2>/dev/null | head -1)
    if [[ -z "${upgrade_log}" ]]; then
        error "Could not find upgrade log file in ${output_dir}"
        return 1
    fi

    local cluster_kubeconfig="${OUTPUT_BASE_DIR}/${cluster_name}/kubeconfig"
    if [[ ! -f "${cluster_kubeconfig}" ]]; then
        error "Missing kubeconfig for cluster ${cluster_name}" | tee -a "${upgrade_log}"
        return 1
    fi

    echo "${pre_version}" > "${output_dir}/.pre-version"

    wait_for_upgrade_completion "${cluster_name}" "${target_version}" "${cluster_kubeconfig}" "${timeout_minutes}" "${upgrade_log}"
    local rc=$?
    if [[ ${rc} -eq 0 ]]; then
        local post_version
        post_version=$(get_cluster_runtime_version "${cluster_name}")
        echo "${post_version}" > "${output_dir}/.post-version"
    fi
    return ${rc}
}

################################################################################
# Orchestration
################################################################################
upgrade_single_cluster() {
    local cluster_name="$1"

    local output_dir="${OUTPUT_BASE_DIR}/${cluster_name}/upgrade"
    mkdir -p "${output_dir}"

    print_section "Upgrading Cluster: ${cluster_name}"

    if ! run_pre_health_check "${cluster_name}" "${output_dir}"; then
        echo "FAILED" > "${output_dir}/status.txt"
        return 1
    fi

    if ! prompt_user_confirmation "${cluster_name}"; then
        warning "Upgrade skipped by user for ${cluster_name}"
        echo "SKIPPED" > "${output_dir}/status.txt"
        return 2
    fi

    local inputs
    if ! inputs=$(get_upgrade_inputs "${cluster_name}"); then
        echo "FAILED" > "${output_dir}/status.txt"
        return 1
    fi
    local supervisor namespace kind
    supervisor=$(echo "${inputs}" | cut -d'|' -f1)
    namespace=$(echo "${inputs}" | cut -d'|' -f2)
    kind=$(echo "${inputs}" | cut -d'|' -f3)

    local pre_version
    pre_version=$(get_cluster_runtime_version "${cluster_name}")
    pre_version=${pre_version:-unknown}
    echo "Cluster Metadata:"
    echo "  Supervisor: ${supervisor}"
    echo "  Namespace: ${namespace}"
    echo "  Kind: ${kind}"
    echo "  Current Version: ${pre_version}"
    echo ""

    local versions_file
    versions_file=$(mktemp)
    local target_version="latest"
    if query_available_versions "${cluster_name}" "${namespace}" "${kind}" "${versions_file}" && [[ -s "${versions_file}" ]]; then
        local available_versions
        available_versions=$(cat "${versions_file}")
        target_version=$(prompt_version_selection "${cluster_name}" "${pre_version}" "${available_versions}")
        local pick_rc=$?
        if [[ ${pick_rc} -eq 2 ]]; then
            rm -f "${versions_file}"
            warning "Version selection cancelled for ${cluster_name}"
            echo "SKIPPED" > "${output_dir}/status.txt"
            return 2
        fi
    else
        warning "Could not query available versions; defaulting to latest"
    fi
    rm -f "${versions_file}"

    local exec_rc=0
    if execute_upgrade "${cluster_name}" "${namespace}" "${kind}" "${output_dir}" "${target_version}"; then
        exec_rc=0
    else
        exec_rc=$?
    fi
    if [[ ${exec_rc} -ne 0 ]]; then
        if [[ ${exec_rc} -eq 2 ]]; then
            echo "SKIPPED" > "${output_dir}/status.txt"
            return 2
        fi
        echo "FAILED" > "${output_dir}/status.txt"
        return 1
    fi

    local node_count
    node_count=$(get_node_count "${cluster_name}")
    local timeout_minutes=$((node_count * TIMEOUT_MULTIPLIER))
    progress "Monitoring upgrade (timeout: ${timeout_minutes} min)..."

    monitor_upgrade_progress "${cluster_name}" "${timeout_minutes}" "${output_dir}" "${pre_version}" "${target_version}"
    local monitor_rc=$?
    case ${monitor_rc} in
        0)
            success "Upgrade completed successfully for ${cluster_name}"
            ;;
        2)
            error "Upgrade timed out for ${cluster_name}"
            echo "TIMEOUT" > "${output_dir}/status.txt"
            return 1
            ;;
        *)
            error "Upgrade failed for ${cluster_name}"
            echo "FAILED" > "${output_dir}/status.txt"
            return 1
            ;;
    esac

    if ! run_post_health_check "${cluster_name}" "${output_dir}"; then
        warning "POST health check failed for ${cluster_name}"
        echo "SUCCESS_WITH_HEALTH_CHECK_FAILED" > "${output_dir}/status.txt"
        return 0
    fi

    echo "SUCCESS" > "${output_dir}/status.txt"
    cleanup_old_files "${OUTPUT_BASE_DIR}/${cluster_name}" "upgrade"
    return 0
}

monitor_and_post_upgrade() {
    local cluster_name="$1"
    local timeout_minutes="$2"
    local output_dir="$3"
    local pre_version="$4"
    local target_version="$5"
    local results_file="$6"

    local status="SUCCESS"
    local duration_start
    duration_start=$(date +%s)

    monitor_upgrade_progress "${cluster_name}" "${timeout_minutes}" "${output_dir}" "${pre_version}" "${target_version}"
    local rc=$?

    case ${rc} in
        0)
            if ! run_post_health_check "${cluster_name}" "${output_dir}" >> "${output_dir}/upgrade-log-$(get_timestamp).txt" 2>&1; then
                status="SUCCESS_POST_FAILED"
            fi
            ;;
        2)
            status="TIMEOUT"
            ;;
        *)
            status="FAILED"
            ;;
    esac

    local duration_end
    duration_end=$(date +%s)
    local duration=$(( (duration_end - duration_start) / 60 ))
    local post_version="unknown"
    [[ -f "${output_dir}/.post-version" ]] && post_version=$(cat "${output_dir}/.post-version")

    {
        echo "===UPGRADE_START==="
        echo "CLUSTER:${cluster_name}"
        echo "STATUS:${status}"
        echo "PRE_VERSION:${pre_version}"
        echo "TARGET_VERSION:${target_version}"
        echo "POST_VERSION:${post_version}"
        echo "DURATION:${duration}"
        echo "===UPGRADE_END==="
    } >> "${results_file}"
}

upgrade_multiple_clusters() {
    local config_file="$1"
    local cluster_list
    cluster_list=$(get_cluster_list "${config_file}")
    local total
    total=$(echo "${cluster_list}" | wc -l | tr -d ' ')
    local success_count=0 failed_count=0 skipped_count=0

    print_section "Multi-Cluster Upgrade"
    echo "Total clusters: ${total}"
    echo "Config file: ${config_file}"
    echo ""

    while IFS= read -r cluster_name; do
        [[ -z "${cluster_name}" ]] && continue
        upgrade_single_cluster "${cluster_name}"
        local rc=$?
        case ${rc} in
            0) success_count=$((success_count + 1)) ;;
            2) skipped_count=$((skipped_count + 1)) ;;
            *) failed_count=$((failed_count + 1)) ;;
        esac
        echo ""
    done <<< "${cluster_list}"

    print_section "Upgrade Summary"
    echo "Total: ${total}"
    echo "Successful: ${success_count}"
    echo "Failed: ${failed_count}"
    echo "Skipped: ${skipped_count}"
    echo ""

    while IFS= read -r cluster_name; do
        [[ -z "${cluster_name}" ]] && continue
        cleanup_old_files "${OUTPUT_BASE_DIR}/${cluster_name}" "upgrade"
    done <<< "${cluster_list}"

    [[ ${failed_count} -eq 0 ]]
}

upgrade_clusters_parallel() {
    local config_file="$1"
    local cluster_list
    cluster_list=$(get_cluster_list "${config_file}")
    local -a clusters=()
    while IFS= read -r c; do
        [[ -z "${c}" ]] && continue
        clusters+=("${c}")
    done <<< "${cluster_list}"

    local total=${#clusters[@]}
    local num_batches=$(( (total + BATCH_SIZE - 1) / BATCH_SIZE ))
    local overall_success=0 overall_failed=0 overall_skipped=0 overall_timeout=0

    print_section "Parallel Multi-Cluster Upgrade"
    echo "Total clusters: ${total}"
    echo "Batch size: ${BATCH_SIZE}"
    echo "Batches: ${num_batches}"
    echo ""

    local global_idx=0
    local batch_num=0
    while [[ ${global_idx} -lt ${total} ]]; do
        batch_num=$((batch_num + 1))
        local batch_start=${global_idx}
        local batch_end=$((global_idx + BATCH_SIZE))
        [[ ${batch_end} -gt ${total} ]] && batch_end=${total}

        echo -e "${CYAN}--- Batch ${batch_num}/${num_batches} ---${NC}"

        local -a monitor_clusters=()
        local -a monitor_timeouts=()
        local -a monitor_output_dirs=()
        local -a monitor_pre_versions=()
        local -a monitor_target_versions=()

        # Phase 1: PRE + prompt + version + patch trigger (sequential)
        for ((i=batch_start; i<batch_end; i++)); do
            local cluster_name="${clusters[$i]}"
            local output_dir="${OUTPUT_BASE_DIR}/${cluster_name}/upgrade"
            mkdir -p "${output_dir}"

            echo -e "${MAGENTA}[${i}/${total}]${NC} ${cluster_name}"
            if ! run_pre_health_check "${cluster_name}" "${output_dir}"; then
                echo "FAILED" > "${output_dir}/status.txt"
                overall_failed=$((overall_failed + 1))
                continue
            fi
            if ! prompt_user_confirmation "${cluster_name}"; then
                echo "SKIPPED" > "${output_dir}/status.txt"
                overall_skipped=$((overall_skipped + 1))
                continue
            fi

            local inputs
            if ! inputs=$(get_upgrade_inputs "${cluster_name}"); then
                echo "FAILED" > "${output_dir}/status.txt"
                overall_failed=$((overall_failed + 1))
                continue
            fi
            local namespace kind
            namespace=$(echo "${inputs}" | cut -d'|' -f2)
            kind=$(echo "${inputs}" | cut -d'|' -f3)

            local pre_version
            pre_version=$(get_cluster_runtime_version "${cluster_name}")
            pre_version=${pre_version:-unknown}

            local versions_file
            versions_file=$(mktemp)
            local target_version="latest"
            if query_available_versions "${cluster_name}" "${namespace}" "${kind}" "${versions_file}" && [[ -s "${versions_file}" ]]; then
                local available_versions
                available_versions=$(cat "${versions_file}")
                target_version=$(prompt_version_selection "${cluster_name}" "${pre_version}" "${available_versions}")
                local pick_rc=$?
                if [[ ${pick_rc} -eq 2 ]]; then
                    rm -f "${versions_file}"
                    echo "SKIPPED" > "${output_dir}/status.txt"
                    overall_skipped=$((overall_skipped + 1))
                    continue
                fi
            fi
            rm -f "${versions_file}"

            execute_upgrade "${cluster_name}" "${namespace}" "${kind}" "${output_dir}" "${target_version}"
            local exec_rc=$?
            if [[ ${exec_rc} -eq 2 ]]; then
                echo "SKIPPED" > "${output_dir}/status.txt"
                overall_skipped=$((overall_skipped + 1))
                continue
            elif [[ ${exec_rc} -ne 0 ]]; then
                echo "FAILED" > "${output_dir}/status.txt"
                overall_failed=$((overall_failed + 1))
                continue
            fi

            local node_count timeout_minutes
            node_count=$(get_node_count "${cluster_name}")
            timeout_minutes=$((node_count * TIMEOUT_MULTIPLIER))

            monitor_clusters+=("${cluster_name}")
            monitor_timeouts+=("${timeout_minutes}")
            monitor_output_dirs+=("${output_dir}")
            monitor_pre_versions+=("${pre_version}")
            monitor_target_versions+=("${target_version}")
        done

        if [[ ${#monitor_clusters[@]} -eq 0 ]]; then
            global_idx=${batch_end}
            continue
        fi

        # Phase 2: monitor + POST in parallel
        local results_file
        results_file=$(mktemp)
        > "${results_file}"
        declare -A pids=()
        declare -A cluster_result_files=()

        for ((j=0; j<${#monitor_clusters[@]}; j++)); do
            local cluster_name="${monitor_clusters[$j]}"
            local cluster_rf
            cluster_rf=$(mktemp)
            cluster_result_files["${cluster_name}"]="${cluster_rf}"

            monitor_and_post_upgrade \
                "${monitor_clusters[$j]}" \
                "${monitor_timeouts[$j]}" \
                "${monitor_output_dirs[$j]}" \
                "${monitor_pre_versions[$j]}" \
                "${monitor_target_versions[$j]}" \
                "${cluster_rf}" &
            pids["${cluster_name}"]=$!
        done

        for cluster_name in "${!pids[@]}"; do
            wait "${pids[$cluster_name]}" 2>/dev/null || true
            if [[ -f "${cluster_result_files[$cluster_name]}" ]]; then
                cat "${cluster_result_files[$cluster_name]}" >> "${results_file}"
                rm -f "${cluster_result_files[$cluster_name]}"
            fi
        done

        # Parse batch results
        local r_cluster="" r_status="" r_pre="" r_target="" r_post="" r_duration=""
        while IFS= read -r line; do
            if [[ "${line}" == "===UPGRADE_START===" ]]; then
                r_cluster=""; r_status=""; r_pre=""; r_target=""; r_post=""; r_duration=""
                continue
            fi
            if [[ "${line}" == "===UPGRADE_END===" ]]; then
                case "${r_status}" in
                    SUCCESS|SUCCESS_POST_FAILED)
                        overall_success=$((overall_success + 1))
                        ;;
                    TIMEOUT)
                        overall_timeout=$((overall_timeout + 1))
                        ;;
                    *)
                        overall_failed=$((overall_failed + 1))
                        ;;
                esac
                continue
            fi
            local key="${line%%:*}"
            local value="${line#*:}"
            case "${key}" in
                CLUSTER) r_cluster="${value}" ;;
                STATUS) r_status="${value}" ;;
                PRE_VERSION) r_pre="${value}" ;;
                TARGET_VERSION) r_target="${value}" ;;
                POST_VERSION) r_post="${value}" ;;
                DURATION) r_duration="${value}" ;;
            esac
        done < "${results_file}"
        rm -f "${results_file}"

        global_idx=${batch_end}
    done

    print_section "Parallel Upgrade Summary"
    echo "Successful: ${overall_success}"
    echo "Failed: ${overall_failed}"
    echo "Timeout: ${overall_timeout}"
    echo "Skipped: ${overall_skipped}"
    echo ""

    while IFS= read -r cluster_name; do
        [[ -z "${cluster_name}" ]] && continue
        cleanup_old_files "${OUTPUT_BASE_DIR}/${cluster_name}" "upgrade"
    done <<< "${cluster_list}"

    [[ $((overall_failed + overall_timeout)) -eq 0 ]]
}

################################################################################
# Args / main
################################################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--cluster)
                if [[ -n "${2:-}" ]] && [[ ! "${2}" =~ ^- ]]; then
                    SINGLE_CLUSTER="$2"
                    shift 2
                else
                    error "Cluster name required for -c/--cluster option"
                    exit 1
                fi
                ;;
            --parallel)
                PARALLEL_MODE=true
                shift
                ;;
            --batch-size)
                shift
                if [[ -n "${1:-}" ]] && [[ "${1}" =~ ^[0-9]+$ ]] && [[ "${1}" -gt 0 ]]; then
                    BATCH_SIZE="$1"
                else
                    error "Invalid batch size: ${1:-}"
                    exit 1
                fi
                shift
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

    if [[ -z "${CONFIG_FILE}" ]]; then
        CONFIG_FILE="${DEFAULT_CONFIG}"
    fi
    if [[ -n "${SINGLE_CLUSTER}" && "${PARALLEL_MODE}" == "true" ]]; then
        error "Cannot combine --parallel with single-cluster mode"
        exit 1
    fi
}

main() {
    echo "========================================================================"
    echo "Kubernetes Cluster Upgrade Script (v${VERSION})"
    echo "========================================================================"
    echo ""

    check_prerequisites
    parse_arguments "$@"

    if [[ -n "${CONFIG_FILE}" ]]; then
        load_credentials "${CONFIG_FILE}"
    fi

    local rc=0
    if [[ -n "${SINGLE_CLUSTER}" ]]; then
        upgrade_single_cluster "${SINGLE_CLUSTER}" || rc=$?
    elif [[ "${PARALLEL_MODE}" == "true" ]]; then
        upgrade_clusters_parallel "${CONFIG_FILE}" || rc=$?
    else
        upgrade_multiple_clusters "${CONFIG_FILE}" || rc=$?
    fi

    exit ${rc}
}

main "$@"


