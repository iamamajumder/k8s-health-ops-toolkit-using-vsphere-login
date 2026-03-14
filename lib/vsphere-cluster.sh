#!/bin/bash
#===============================================================================
# vSphere Cluster Operations Library
# v1.0: vSphere-only runtime helpers for kubeconfig, discovery, and upgrades
#===============================================================================

# Source common functions if not already loaded
if [[ -z "${COMMON_LIB_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
fi

#===============================================================================
# Configuration
#===============================================================================

VSPHERE_CACHE_DIR="${HOME}/.k8s-health-check"
VSPHERE_NAMESPACE_CACHE="${VSPHERE_CACHE_DIR}/vsphere-namespaces.cache"
KUBECONFIG_CACHE_EXPIRY=43200  # 12 hours
NAMESPACE_CACHE_EXPIRY=43200   # 12 hours

# Session-level caches to avoid repeated supervisor login/discovery
declare -A _VSPHERE_SUPERVISOR_READY 2>/dev/null || _VSPHERE_SUPERVISOR_READY=""
declare -A _VSPHERE_NAMESPACE_BY_CLUSTER 2>/dev/null || _VSPHERE_NAMESPACE_BY_CLUSTER=""

AO_ACCOUNT_CREDENTIALS_READY="${AO_ACCOUNT_CREDENTIALS_READY:-}"
NONAO_ACCOUNT_CREDENTIALS_READY="${NONAO_ACCOUNT_CREDENTIALS_READY:-}"
VSPHERE_PLUGIN_CHECKED="${VSPHERE_PLUGIN_CHECKED:-}"

#===============================================================================
# Utilities
#===============================================================================

init_vsphere_cache_dir() {
    if [[ ! -d "${VSPHERE_CACHE_DIR}" ]]; then
        mkdir -p "${VSPHERE_CACHE_DIR}"
        chmod 700 "${VSPHERE_CACHE_DIR}" 2>/dev/null || true
    fi
}

is_cache_valid() {
    local cache_timestamp="$1"
    local expiry_seconds="$2"
    local current_time
    current_time=$(date +%s)
    local age=$((current_time - cache_timestamp))
    [[ ${age} -lt ${expiry_seconds} ]]
}

extract_cluster_suffix() {
    local cluster_name="$1"
    if [[ "${cluster_name}" =~ -(prod|uat|system)-([1-4])$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

determine_environment() {
    local cluster_name="$1"
    if [[ "${cluster_name}" =~ -prod-[1-4]$ ]]; then
        echo "prod"
    elif [[ "${cluster_name}" =~ -uat-[1-4]$ ]] || [[ "${cluster_name}" =~ -system-[1-4]$ ]]; then
        echo "nonprod"
    else
        echo "unknown"
    fi
}

determine_environment_from_flag() {
    local env_flag="$1"
    local env_type
    env_type=$(echo "${env_flag}" | cut -d'-' -f1)
    case "${env_type}" in
        prod) echo "prod" ;;
        uat|system|dev) echo "nonprod" ;;
        *) echo "unknown" ;;
    esac
}

normalize_version_base() {
    local v="$1"
    echo "${v%%+*}" | tr -d ' \n\r\t'
}

version_in_list() {
    local target="$1"
    local list="$2"
    while IFS= read -r item; do
        [[ -z "${item}" ]] && continue
        if [[ "${item}" == "${target}" ]]; then
            return 0
        fi
    done <<< "${list}"
    return 1
}

test_kubeconfig_connectivity() {
    local kubeconfig_file="$1"
    if [[ ! -f "${kubeconfig_file}" ]]; then
        error "Kubeconfig file not found: ${kubeconfig_file}"
        return 1
    fi
    if kubectl --kubeconfig="${kubeconfig_file}" cluster-info >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

ensure_vsphere_plugin() {
    if [[ -n "${VSPHERE_PLUGIN_CHECKED}" ]]; then
        return 0
    fi
    if ! kubectl vsphere version >/dev/null 2>&1; then
        error "kubectl vsphere plugin not found. Install vSphere plugin for kubectl."
        return 1
    fi
    VSPHERE_PLUGIN_CHECKED="true"
    return 0
}

#===============================================================================
# Credentials
#===============================================================================

ensure_vsphere_credentials() {
    local cluster_list="${1:-}"

    local requires_prod=false
    local requires_nonprod_workload=false

    # All supervisor logins use the production credential set.
    # Non-production workload logins additionally need the non-prod workload set.
    while IFS= read -r cluster; do
        [[ -z "${cluster}" ]] && continue

        local env_type
        env_type=$(determine_environment "${cluster}")

        if [[ "${cluster}" =~ ^prod-[1-4]$ ]]; then
            requires_prod=true
            continue
        fi
        if [[ "${cluster}" =~ ^(uat|system|dev)-[1-4]$ ]]; then
            requires_prod=true
            continue
        fi

        if [[ "${env_type}" == "prod" ]]; then
            requires_prod=true
        elif [[ "${env_type}" == "nonprod" ]]; then
            requires_prod=true
            requires_nonprod_workload=true
        fi
    done <<< "${cluster_list}"

    # Default to production creds if no explicit environment could be inferred.
    if [[ "${requires_prod}" == "false" && "${requires_nonprod_workload}" == "false" ]]; then
        requires_prod=true
    fi

    if [[ "${requires_prod}" == "true" ]]; then
        if [[ -z "${AO_ACCOUNT_USERNAME:-}" ]]; then
            echo -n "Enter AO account username: " >&2
            read -r AO_ACCOUNT_USERNAME </dev/tty
            if [[ -z "${AO_ACCOUNT_USERNAME}" ]]; then
                error "AO account username cannot be empty"
                return 1
            fi
            export AO_ACCOUNT_USERNAME
        fi

        if [[ -z "${AO_ACCOUNT_PASSWORD:-}" ]]; then
            echo -n "Enter AO account password: " >&2
            read -r -s AO_ACCOUNT_PASSWORD </dev/tty
            echo "" >&2
            if [[ -z "${AO_ACCOUNT_PASSWORD}" ]]; then
                error "AO account password cannot be empty"
                return 1
            fi
            export AO_ACCOUNT_PASSWORD
        fi

        AO_ACCOUNT_CREDENTIALS_READY="true"
    fi

    if [[ "${requires_nonprod_workload}" == "true" ]]; then
        if [[ -z "${NONAO_ACCOUNT_USERNAME:-}" ]]; then
            echo -n "Enter Non-AO account username: " >&2
            read -r NONAO_ACCOUNT_USERNAME </dev/tty
            if [[ -z "${NONAO_ACCOUNT_USERNAME}" ]]; then
                error "Non-AO account username cannot be empty"
                return 1
            fi
            export NONAO_ACCOUNT_USERNAME
        fi

        if [[ -z "${NONAO_ACCOUNT_PASSWORD:-}" ]]; then
            echo -n "Enter Non-AO account password: " >&2
            read -r -s NONAO_ACCOUNT_PASSWORD </dev/tty
            echo "" >&2
            if [[ -z "${NONAO_ACCOUNT_PASSWORD}" ]]; then
                error "Non-AO account password cannot be empty"
                return 1
            fi
            export NONAO_ACCOUNT_PASSWORD
        fi

        NONAO_ACCOUNT_CREDENTIALS_READY="true"
    fi

    return 0
}

get_workload_credentials_for_cluster() {
    local cluster_name="$1"
    local env
    env=$(determine_environment "${cluster_name}")

    if [[ "${env}" == "prod" ]]; then
        echo "${AO_ACCOUNT_USERNAME}|${AO_ACCOUNT_PASSWORD}"
    else
        echo "${NONAO_ACCOUNT_USERNAME}|${NONAO_ACCOUNT_PASSWORD}"
    fi
}

get_supervisor_credentials_for_suffix() {
    local suffix="$1"
    if [[ -z "${AO_ACCOUNT_USERNAME:-}" || -z "${AO_ACCOUNT_PASSWORD:-}" ]]; then
        error "Missing supervisor credentials for suffix '${suffix}'"
        return 1
    fi

    echo "${AO_ACCOUNT_USERNAME}|${AO_ACCOUNT_PASSWORD}"
}

#===============================================================================
# Supervisor Session and Namespace Discovery
#===============================================================================

get_supervisor_for_cluster() {
    local cluster_name="$1"
    local config_file="$2"
    local suffix
    if ! suffix=$(extract_cluster_suffix "${cluster_name}"); then
        return 1
    fi

    load_supervisor_map "${config_file}"
    local supervisor="${SUPERVISOR_IP_MAP[$suffix]:-}"
    if [[ -z "${supervisor}" ]]; then
        return 1
    fi
    echo "${suffix}|${supervisor}"
    return 0
}

ensure_supervisor_session_for_suffix() {
    local suffix="$1"
    local config_file="$2"
    local cluster_hint="${3:-}"

    if [[ -n "${_VSPHERE_SUPERVISOR_READY[$suffix]:-}" ]]; then
        return 0
    fi

    if ! ensure_vsphere_plugin; then
        return 1
    fi

    local credential_hint="${cluster_hint:-${suffix}}"
    if ! ensure_vsphere_credentials "${credential_hint}"; then
        return 1
    fi

    load_supervisor_map "${config_file}"
    local supervisor="${SUPERVISOR_IP_MAP[$suffix]:-}"
    if [[ -z "${supervisor}" ]]; then
        error "Supervisor mapping not found for suffix '${suffix}' in ${config_file}"
        return 1
    fi

    local supervisor_creds sup_user sup_password
    if ! supervisor_creds=$(get_supervisor_credentials_for_suffix "${suffix}"); then
        return 1
    fi
    sup_user=$(echo "${supervisor_creds}" | cut -d'|' -f1)
    sup_password=$(echo "${supervisor_creds}" | cut -d'|' -f2-)

    local login_output
    login_output=$(KUBECTL_VSPHERE_PASSWORD="${sup_password}" kubectl vsphere login \
        --server "${supervisor}" \
        --vsphere-username "${sup_user}" \
        --insecure-skip-tls-verify 2>&1)
    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        error "Supervisor login failed for ${suffix} (${supervisor})"
        [[ -n "${login_output}" ]] && error "${login_output}"
        return 1
    fi

    # Ensure context is on supervisor for discovery calls
    kubectl config use-context "${supervisor}" >/dev/null 2>&1 || true
    _VSPHERE_SUPERVISOR_READY["${suffix}"]="true"
    return 0
}

get_cached_namespace_for_cluster() {
    local cluster_name="$1"
    local suffix="$2"

    if [[ -n "${_VSPHERE_NAMESPACE_BY_CLUSTER[$cluster_name]:-}" ]]; then
        echo "${_VSPHERE_NAMESPACE_BY_CLUSTER[$cluster_name]}"
        return 0
    fi

    if [[ ! -f "${VSPHERE_NAMESPACE_CACHE}" ]]; then
        return 1
    fi

    local cached
    cached=$(grep "^${cluster_name}:${suffix}:" "${VSPHERE_NAMESPACE_CACHE}" 2>/dev/null | tail -1 || true)
    if [[ -z "${cached}" ]]; then
        return 1
    fi

    local namespace
    local ts
    namespace=$(echo "${cached}" | cut -d':' -f3)
    ts=$(echo "${cached}" | cut -d':' -f4)
    if [[ -z "${namespace}" || -z "${ts}" ]]; then
        return 1
    fi

    if ! is_cache_valid "${ts}" "${NAMESPACE_CACHE_EXPIRY}"; then
        return 1
    fi

    _VSPHERE_NAMESPACE_BY_CLUSTER["${cluster_name}"]="${namespace}"
    echo "${namespace}"
    return 0
}

save_namespace_cache_entry() {
    local cluster_name="$1"
    local suffix="$2"
    local namespace="$3"
    local ts
    ts=$(date +%s)

    init_vsphere_cache_dir
    if [[ -f "${VSPHERE_NAMESPACE_CACHE}" ]]; then
        grep -v "^${cluster_name}:${suffix}:" "${VSPHERE_NAMESPACE_CACHE}" > "${VSPHERE_NAMESPACE_CACHE}.tmp" 2>/dev/null || true
        mv -f "${VSPHERE_NAMESPACE_CACHE}.tmp" "${VSPHERE_NAMESPACE_CACHE}" 2>/dev/null || true
    fi
    echo "${cluster_name}:${suffix}:${namespace}:${ts}" >> "${VSPHERE_NAMESPACE_CACHE}"
    chmod 600 "${VSPHERE_NAMESPACE_CACHE}" 2>/dev/null || true
    _VSPHERE_NAMESPACE_BY_CLUSTER["${cluster_name}"]="${namespace}"
}

discover_cluster_namespace() {
    local cluster_name="$1"
    local config_file="$2"

    local suffix_supervisor
    if ! suffix_supervisor=$(get_supervisor_for_cluster "${cluster_name}" "${config_file}"); then
        error "Cannot resolve supervisor for cluster ${cluster_name}"
        return 1
    fi
    local suffix supervisor
    suffix=$(echo "${suffix_supervisor}" | cut -d'|' -f1)
    supervisor=$(echo "${suffix_supervisor}" | cut -d'|' -f2)

    local cached_ns
    if cached_ns=$(get_cached_namespace_for_cluster "${cluster_name}" "${suffix}"); then
        echo "${cached_ns}"
        return 0
    fi

    if ! ensure_supervisor_session_for_suffix "${suffix}" "${config_file}" "${cluster_name}"; then
        return 1
    fi

    kubectl config use-context "${supervisor}" >/dev/null 2>&1 || true
    local data
    data=$(kubectl get cluster -A --no-headers 2>/dev/null || true)
    if [[ -z "${data}" ]]; then
        error "Failed to discover workload clusters from supervisor ${supervisor}"
        return 1
    fi

    local namespace=""
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        local ns name
        ns=$(echo "${line}" | awk '{print $1}')
        name=$(echo "${line}" | awk '{print $2}')
        [[ -z "${name}" || -z "${ns}" ]] && continue
        save_namespace_cache_entry "${name}" "${suffix}" "${ns}"
        if [[ "${name}" == "${cluster_name}" ]]; then
            namespace="${ns}"
        fi
    done <<< "${data}"

    if [[ -z "${namespace}" ]]; then
        error "Namespace not found for cluster ${cluster_name} on supervisor ${supervisor}"
        return 1
    fi

    echo "${namespace}"
    return 0
}

discover_clusters_by_supervisor_env() {
    local env_flag="$1"
    local config_file="$2"

    load_supervisor_map "${config_file}"
    local supervisor="${SUPERVISOR_IP_MAP[$env_flag]:-}"
    if [[ -z "${supervisor}" ]]; then
        error "Supervisor mapping not found for environment '${env_flag}'"
        return 1
    fi

    if ! ensure_supervisor_session_for_suffix "${env_flag}" "${config_file}"; then
        return 1
    fi

    kubectl config use-context "${supervisor}" >/dev/null 2>&1 || true
    local data
    data=$(kubectl get cluster -A --no-headers 2>/dev/null || true)
    if [[ -z "${data}" ]]; then
        return 0
    fi

    echo "${data}" | awk '{print $2}' | sed '/^[[:space:]]*$/d' | sort -u
}

#===============================================================================
# Kubeconfig Management
#===============================================================================

fetch_kubeconfig_via_vsphere() {
    local cluster_name="$1"
    local output_file="${2:-}"
    local config_file="$3"

    local consolidated_path="${OUTPUT_BASE_DIR}/${cluster_name}/kubeconfig"
    mkdir -p "$(dirname "${consolidated_path}")"

    local target_path="${consolidated_path}"
    if [[ -n "${output_file}" ]]; then
        target_path="${output_file}"
        mkdir -p "$(dirname "${target_path}")"
    fi

    if [[ -f "${consolidated_path}" ]]; then
        local ts
        ts=$(stat -c %Y "${consolidated_path}" 2>/dev/null || stat -f %m "${consolidated_path}" 2>/dev/null || echo "0")
        if is_cache_valid "${ts}" "${KUBECONFIG_CACHE_EXPIRY}"; then
            if [[ "${target_path}" != "${consolidated_path}" ]]; then
                cp "${consolidated_path}" "${target_path}"
            fi
            return 0
        fi
    fi

    if ! ensure_vsphere_credentials "${cluster_name}"; then
        return 1
    fi

    local suffix_supervisor
    if ! suffix_supervisor=$(get_supervisor_for_cluster "${cluster_name}" "${config_file}"); then
        error "Unable to resolve supervisor mapping for ${cluster_name}"
        return 1
    fi
    local suffix supervisor
    suffix=$(echo "${suffix_supervisor}" | cut -d'|' -f1)
    supervisor=$(echo "${suffix_supervisor}" | cut -d'|' -f2)

    if ! ensure_supervisor_session_for_suffix "${suffix}" "${config_file}" "${cluster_name}"; then
        return 1
    fi

    local namespace
    if ! namespace=$(discover_cluster_namespace "${cluster_name}" "${config_file}"); then
        return 1
    fi

    local creds
    creds=$(get_workload_credentials_for_cluster "${cluster_name}")
    local wl_user wl_password
    wl_user=$(echo "${creds}" | cut -d'|' -f1)
    wl_password=$(echo "${creds}" | cut -d'|' -f2-)

    if [[ -z "${wl_user}" || -z "${wl_password}" ]]; then
        error "Missing workload credentials for ${cluster_name}"
        return 1
    fi

    local login_output
    login_output=$(KUBECTL_VSPHERE_PASSWORD="${wl_password}" kubectl vsphere login \
        --server "${supervisor}" \
        --vsphere-username "${wl_user}" \
        --tanzu-kubernetes-cluster-name "${cluster_name}" \
        --tanzu-kubernetes-cluster-namespace "${namespace}" \
        --insecure-skip-tls-verify 2>&1)
    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        error "Workload login failed for ${cluster_name}"
        [[ -n "${login_output}" ]] && error "${login_output}"
        return 1
    fi

    local ctx
    ctx=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -z "${ctx}" ]]; then
        error "Unable to determine current kubectl context after vSphere login"
        return 1
    fi

    if ! kubectl config view --raw --minify --context "${ctx}" > "${consolidated_path}" 2>/dev/null; then
        error "Failed to export kubeconfig for ${cluster_name}"
        return 1
    fi
    chmod 600 "${consolidated_path}" 2>/dev/null || true

    if [[ "${target_path}" != "${consolidated_path}" ]]; then
        cp "${consolidated_path}" "${target_path}"
    fi

    return 0
}

prepare_vsphere_kubeconfigs_from_list() {
    local cluster_list="$1"
    local config_file="$2"
    local failed_clusters=()

    ensure_vsphere_credentials "${cluster_list}" || return 1

    while IFS= read -r cluster_name; do
        [[ -z "${cluster_name}" ]] && continue
        if ! fetch_kubeconfig_via_vsphere "${cluster_name}" "" "${config_file}"; then
            warning "Failed to prefetch kubeconfig for ${cluster_name}"
            failed_clusters+=("${cluster_name}")
        fi
    done <<< "${cluster_list}"

    if [[ ${#failed_clusters[@]} -gt 0 ]]; then
        warning "Kubeconfig prefetch failed for ${#failed_clusters[@]} cluster(s)"
    fi
    return 0
}

prepare_vsphere_kubeconfigs() {
    local config_file="$1"
    local cluster_list
    cluster_list=$(get_cluster_list "${config_file}")
    prepare_vsphere_kubeconfigs_from_list "${cluster_list}" "${config_file}"
}

#===============================================================================
# Cache management (health-check flags compatibility)
#===============================================================================

get_cache_status() {
    init_vsphere_cache_dir
    echo ""
    echo "=== Cache Status ==="
    echo "Cache Directory: ${VSPHERE_CACHE_DIR}"
    echo ""

    if [[ -f "${VSPHERE_NAMESPACE_CACHE}" ]]; then
        local entries
        entries=$(wc -l < "${VSPHERE_NAMESPACE_CACHE}" 2>/dev/null || echo "0")
        echo "Namespace Cache: ${VSPHERE_NAMESPACE_CACHE}"
        echo "  - Entries: ${entries}"
    else
        echo "Namespace Cache: Not found"
    fi
    echo ""

    local kubeconfig_count
    kubeconfig_count=$(find "${OUTPUT_BASE_DIR}" -type f -name kubeconfig 2>/dev/null | wc -l | tr -d ' ')
    echo "Output kubeconfig cache: ${OUTPUT_BASE_DIR}"
    echo "  - Cached kubeconfigs: ${kubeconfig_count:-0}"
    echo ""
}

clear_cache() {
    progress "Clearing vSphere cache..."
    rm -f "${VSPHERE_NAMESPACE_CACHE}" 2>/dev/null || true
    find "${OUTPUT_BASE_DIR}" -type f -name kubeconfig -delete 2>/dev/null || true
    success "Cache cleared"
}

cleanup_cluster_cache() {
    rm -f "${VSPHERE_NAMESPACE_CACHE}" 2>/dev/null || true
}

#===============================================================================
# Upgrade helpers
#===============================================================================

detect_cluster_kind() {
    local cluster_name="$1"
    local namespace="$2"

    if kubectl get tanzukubernetescluster "${cluster_name}" -n "${namespace}" >/dev/null 2>&1; then
        echo "tkc"
        return 0
    fi
    if kubectl get cluster "${cluster_name}" -n "${namespace}" >/dev/null 2>&1; then
        echo "cluster"
        return 0
    fi
    return 1
}

get_current_cluster_spec_version() {
    local kind="$1"
    local cluster_name="$2"
    local namespace="$3"

    if [[ "${kind}" == "tkc" ]]; then
        kubectl get tanzukubernetescluster "${cluster_name}" -n "${namespace}" -o jsonpath='{.spec.distribution.version}' 2>/dev/null || true
    else
        kubectl get cluster "${cluster_name}" -n "${namespace}" -o jsonpath='{.spec.topology.version}' 2>/dev/null || true
    fi
}

get_updates_available_versions() {
    local kind="$1"
    local cluster_name="$2"
    local namespace="$3"

    local resource="cluster"
    if [[ "${kind}" == "tkc" ]]; then
        resource="tanzukubernetescluster"
    fi

    local updates
    updates=$(kubectl get "${resource}" "${cluster_name}" -n "${namespace}" -o json 2>/dev/null | \
        jq -r '.status.updatesAvailable // [] | .[] | if type=="string" then . else (.version // .name // empty) end' 2>/dev/null || true)

    if [[ -n "${updates}" ]]; then
        echo "${updates}" | sed '/^[[:space:]]*$/d' | sort -V -r | uniq
        return 0
    fi

    # Fallback to Supervisor KR list
    kubectl get kr -A --no-headers 2>/dev/null | awk '{print $2}' | sed '/^[[:space:]]*$/d' | sort -V -r | uniq || true
}

needs_tkc_retirement() {
    local kind="$1"
    local cluster_name="$2"
    local namespace="$3"
    local target_version="$4"

    [[ "${kind}" != "tkc" ]] && return 1

    local updates
    updates=$(get_updates_available_versions "${kind}" "${cluster_name}" "${namespace}")
    if [[ -z "${updates}" ]]; then
        return 1
    fi

    if version_in_list "${target_version}" "${updates}"; then
        return 1
    fi
    return 0
}

auto_retire_tkc_cluster() {
    local cluster_name="$1"
    local namespace="$2"
    local timeout_seconds="${3:-1800}"

    progress "Enabling TKC auto-retirement for ${cluster_name}..."

    if ! kubectl label tanzukubernetescluster "${cluster_name}" -n "${namespace}" kubernetes.vmware.com/retire-tkc="" --overwrite >/dev/null 2>&1; then
        error "Failed to label TKC for retirement"
        return 1
    fi

    local start_time
    start_time=$(date +%s)
    while true; do
        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))
        if [[ ${elapsed} -ge ${timeout_seconds} ]]; then
            error "Timed out waiting for TKC retirement transition"
            return 1
        fi

        local tkc_exists=true
        local capi_exists=false
        kubectl get tanzukubernetescluster "${cluster_name}" -n "${namespace}" >/dev/null 2>&1 || tkc_exists=false
        kubectl get cluster "${cluster_name}" -n "${namespace}" >/dev/null 2>&1 && capi_exists=true

        if [[ "${tkc_exists}" == "false" && "${capi_exists}" == "true" ]]; then
            success "TKC retirement completed for ${cluster_name}"
            return 0
        fi

        sleep 15
    done
}

apply_upgrade_patch() {
    local kind="$1"
    local cluster_name="$2"
    local namespace="$3"
    local target_version="$4"
    local dry_run="${5:-false}"

    if [[ "${dry_run}" == "true" ]]; then
        return 0
    fi

    if [[ "${kind}" == "tkc" ]]; then
        kubectl patch tanzukubernetescluster "${cluster_name}" -n "${namespace}" \
            --type merge \
            -p "{\"spec\":{\"distribution\":{\"version\":\"${target_version}\"}}}" >/dev/null
    else
        kubectl patch cluster "${cluster_name}" -n "${namespace}" \
            --type merge \
            -p "{\"spec\":{\"topology\":{\"version\":\"${target_version}\"}}}" >/dev/null
    fi
}

wait_for_upgrade_completion() {
    local cluster_name="$1"
    local target_version="$2"
    local kubeconfig_file="$3"
    local timeout_minutes="$4"
    local log_file="$5"

    local target_base
    target_base=$(normalize_version_base "${target_version}")
    local start_time
    start_time=$(date +%s)
    local interval=120

    while true; do
        local now
        now=$(date +%s)
        local elapsed_min=$(( (now - start_time) / 60 ))

        if [[ ${elapsed_min} -ge ${timeout_minutes} ]]; then
            return 2
        fi

        local current_version
        current_version=$(kubectl --kubeconfig="${kubeconfig_file}" version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // empty' | tr -d ' \n\r')
        local current_base
        current_base=$(normalize_version_base "${current_version}")

        local nodes_total
        local nodes_ready
        nodes_total=$(kubectl --kubeconfig="${kubeconfig_file}" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        nodes_total=${nodes_total:-0}
        nodes_ready=$(kubectl --kubeconfig="${kubeconfig_file}" get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
        nodes_ready=${nodes_ready:-0}

        {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] elapsed=${elapsed_min}m version=${current_version:-unknown} nodes=${nodes_ready}/${nodes_total}"
        } >> "${log_file}"

        if [[ -n "${current_base}" && "${current_base}" == "${target_base}" && "${nodes_total}" -gt 0 && "${nodes_total}" -eq "${nodes_ready}" ]]; then
            return 0
        fi

        sleep "${interval}"
    done
}

#===============================================================================
# Exports
#===============================================================================

export -f init_vsphere_cache_dir
export -f is_cache_valid
export -f extract_cluster_suffix
export -f determine_environment
export -f determine_environment_from_flag
export -f normalize_version_base
export -f version_in_list
export -f test_kubeconfig_connectivity
export -f ensure_vsphere_plugin
export -f ensure_vsphere_credentials
export -f get_workload_credentials_for_cluster
export -f get_supervisor_credentials_for_suffix
export -f get_supervisor_for_cluster
export -f ensure_supervisor_session_for_suffix
export -f get_cached_namespace_for_cluster
export -f save_namespace_cache_entry
export -f discover_cluster_namespace
export -f discover_clusters_by_supervisor_env
export -f fetch_kubeconfig_via_vsphere
export -f prepare_vsphere_kubeconfigs_from_list
export -f prepare_vsphere_kubeconfigs
export -f get_cache_status
export -f clear_cache
export -f cleanup_cluster_cache
export -f detect_cluster_kind
export -f get_current_cluster_spec_version
export -f get_updates_available_versions
export -f needs_tkc_retirement
export -f auto_retire_tkc_cluster
export -f apply_upgrade_patch
export -f wait_for_upgrade_completion
