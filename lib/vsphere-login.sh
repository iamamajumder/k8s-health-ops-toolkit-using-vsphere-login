#!/bin/bash
#===============================================================================
# vSphere Login Module (v2.0)
# Handles automated kubectl vsphere login for Supervisor and Workload clusters
#
# Architecture: Synchronous execution, called at the end of each script
# Flow: Ensure credentials → Group by supervisor → Login supervisor →
#       Discover workload namespaces → Login workload clusters
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
fi

#===============================================================================
# Configuration - Supervisor Cluster IP/FQDN Mapping
#===============================================================================
# User must update these with actual Supervisor cluster IPs or FQDNs
declare -A SUPERVISOR_IP_MAP=(
    ["prod-1"]="<supervisor-prod-1-ip-or-fqdn>"
    ["prod-2"]="<supervisor-prod-2-ip-or-fqdn>"
    ["prod-3"]="<supervisor-prod-3-ip-or-fqdn>"
    ["prod-4"]="<supervisor-prod-4-ip-or-fqdn>"
    ["system-1"]="<supervisor-system-1-ip-or-fqdn>"
    ["system-3"]="<supervisor-system-3-ip-or-fqdn>"
    ["uat-2"]="<supervisor-uat-2-ip-or-fqdn>"
    ["uat-4"]="<supervisor-uat-4-ip-or-fqdn>"
)

#===============================================================================
# Helper Functions
#===============================================================================

# Extract cluster suffix from full cluster name
# Examples: svcs-k8s-1-prod-1 → prod-1, app-uat-02 → uat-2
extract_cluster_suffix() {
    local cluster_name="$1"

    # Match patterns: -prod-[1-4], -uat-[1-4], -system-[1-4]
    if [[ "${cluster_name}" =~ -(prod|uat|system)-([1-4])$ ]]; then
        local env="${BASH_REMATCH[1]}"
        local num="${BASH_REMATCH[2]}"
        echo "${env}-${num}"
        return 0
    fi

    return 1
}

# Get supervisor IP/FQDN from map
get_supervisor_ip() {
    local suffix="$1"
    echo "${SUPERVISOR_IP_MAP[$suffix]:-}"
}

#===============================================================================
# Credential Management
#===============================================================================

# Ensure all required vSphere credentials are available before any login attempt
# Checks env vars first, prompts interactively if missing
ensure_vsphere_credentials() {
    local cluster_list="$1"

    # --- AO Credentials (used for all supervisor logins + prod workload logins) ---
    if [[ -z "${TMC_SELF_MANAGED_USERNAME:-}" ]]; then
        echo -n "Enter vSphere AO username (same as TMC username): " >&2
        read -r TMC_SELF_MANAGED_USERNAME </dev/tty
        if [[ -z "${TMC_SELF_MANAGED_USERNAME}" ]]; then
            error "Username cannot be empty"
            return 1
        fi
    fi
    if [[ -z "${TMC_SELF_MANAGED_PASSWORD:-}" ]]; then
        echo -n "Enter vSphere AO password (same as TMC password): " >&2
        read -r -s TMC_SELF_MANAGED_PASSWORD </dev/tty
        echo "" >&2
        if [[ -z "${TMC_SELF_MANAGED_PASSWORD}" ]]; then
            error "Password cannot be empty"
            return 1
        fi
    fi
    export TMC_SELF_MANAGED_USERNAME TMC_SELF_MANAGED_PASSWORD

    # --- Non-AO Credentials (only for non-prod workload logins) ---
    local has_nonprod=false
    while IFS= read -r cluster; do
        [[ -z "${cluster}" ]] && continue
        local env=$(determine_environment "${cluster}")
        if [[ "${env}" == "nonprod" ]]; then
            has_nonprod=true
            break
        fi
    done <<< "${cluster_list}"

    if [[ "${has_nonprod}" == "true" ]]; then
        if [[ -z "${VSPHERE_NONPROD_USERNAME:-}" ]]; then
            echo "" >&2
            echo -e "${YELLOW}Non-Prod vSphere credentials required (Non-AO account)${NC}" >&2
            echo "Used for workload cluster login to system-* and uat-* clusters." >&2
            echo "" >&2
            echo -n "Enter Non-Prod vSphere username: " >&2
            read -r VSPHERE_NONPROD_USERNAME </dev/tty
            if [[ -z "${VSPHERE_NONPROD_USERNAME}" ]]; then
                error "Username cannot be empty"
                return 1
            fi
        fi
        if [[ -z "${VSPHERE_NONPROD_PASSWORD:-}" ]]; then
            echo -n "Enter Non-Prod vSphere password: " >&2
            read -r -s VSPHERE_NONPROD_PASSWORD </dev/tty
            echo "" >&2
            if [[ -z "${VSPHERE_NONPROD_PASSWORD}" ]]; then
                error "Password cannot be empty"
                return 1
            fi
        fi
        export VSPHERE_NONPROD_USERNAME VSPHERE_NONPROD_PASSWORD
    fi

    return 0
}

#===============================================================================
# vSphere Login Functions
#===============================================================================

# Login to Supervisor cluster
vsphere_supervisor_login() {
    local suffix="$1"
    local supervisor_ip="$2"
    local username="$3"
    local password="$4"

    debug "[vSphere Login] Logging in to Supervisor ${suffix}..."

    local error_output
    error_output=$(mktemp)

    if kubectl vsphere login \
        --server "${supervisor_ip}" \
        --username "${username}" \
        --password "${password}" \
        --insecure-skip-tls-verify >/dev/null 2>"${error_output}"; then
        echo -e "${GREEN}[vSphere Login]${NC} Supervisor ${suffix}: login successful"
        rm -f "${error_output}"
        return 0
    else
        local error_msg=$(cat "${error_output}" | head -n 1)
        if [[ -n "${error_msg}" ]]; then
            echo -e "${RED}[vSphere Login]${NC} Supervisor ${suffix}: login failed - ${error_msg}"
        else
            echo -e "${RED}[vSphere Login]${NC} Supervisor ${suffix}: login failed"
        fi
        rm -f "${error_output}"
        return 1
    fi
}

# Discover workload cluster namespaces from supervisor
# Output: lines of "NAMESPACE CLUSTER_NAME"
discover_workload_namespaces() {
    local supervisor_ip="$1"

    kubectl --server="https://${supervisor_ip}" get cluster -A --no-headers 2>/dev/null | \
        awk '{print $1, $2}'
}

# Login to Workload cluster
vsphere_workload_login() {
    local cluster_name="$1"
    local supervisor_ip="$2"
    local namespace="$3"
    local username="$4"
    local password="$5"

    debug "[vSphere Login] Logging in to workload cluster ${cluster_name} (ns: ${namespace})..."

    local error_output
    error_output=$(mktemp)

    if kubectl vsphere login \
        --server "${supervisor_ip}" \
        --username "${username}" \
        --password "${password}" \
        --tanzu-kubernetes-cluster-name "${cluster_name}" \
        --tanzu-kubernetes-cluster-namespace "${namespace}" \
        --insecure-skip-tls-verify >/dev/null 2>"${error_output}"; then
        echo -e "${GREEN}[vSphere Login]${NC} ${cluster_name}: login successful"
        rm -f "${error_output}"
        return 0
    else
        local error_msg=$(cat "${error_output}" | head -n 1)
        if [[ -n "${error_msg}" ]]; then
            echo -e "${RED}[vSphere Login]${NC} ${cluster_name}: login failed - ${error_msg}"
        else
            echo -e "${RED}[vSphere Login]${NC} ${cluster_name}: login failed"
        fi
        rm -f "${error_output}"
        return 1
    fi
}

#===============================================================================
# Main Login Orchestration
#===============================================================================

# Public entry point - orchestrates the full vSphere login flow
# Usage: run_vsphere_login "cluster1\ncluster2\ncluster3"
run_vsphere_login() {
    local cluster_list="$1"

    # Skip if no clusters provided
    if [[ -z "${cluster_list}" ]]; then
        debug "[vSphere Login] No clusters provided, skipping"
        return 0
    fi

    # Check if kubectl vsphere plugin is available
    if ! kubectl vsphere version >/dev/null 2>&1; then
        debug "[vSphere Login] kubectl vsphere plugin not available, skipping"
        return 0
    fi

    echo ""
    print_section "vSphere Login"

    # Step 1: Collect all credentials upfront
    if ! ensure_vsphere_credentials "${cluster_list}"; then
        warning "[vSphere Login] Credentials not available, skipping vSphere login"
        return 0
    fi

    # Step 2: Group clusters by supervisor suffix
    declare -A supervisor_clusters  # suffix → newline-separated cluster list
    declare -A suffix_ip            # suffix → supervisor IP
    local login_success=0
    local login_failed=0

    while IFS= read -r cluster_name; do
        [[ -z "${cluster_name}" ]] && continue

        local suffix
        if ! suffix=$(extract_cluster_suffix "${cluster_name}"); then
            warning "[vSphere Login] Cannot extract suffix from ${cluster_name}, skipping"
            login_failed=$((login_failed + 1))
            continue
        fi

        local supervisor_ip=$(get_supervisor_ip "${suffix}")
        if [[ -z "${supervisor_ip}" || "${supervisor_ip}" == "<"* ]]; then
            warning "[vSphere Login] Supervisor IP not configured for ${suffix}, skipping ${cluster_name}"
            login_failed=$((login_failed + 1))
            continue
        fi

        suffix_ip["${suffix}"]="${supervisor_ip}"

        if [[ -n "${supervisor_clusters[$suffix]:-}" ]]; then
            supervisor_clusters["${suffix}"]="${supervisor_clusters[$suffix]}
${cluster_name}"
        else
            supervisor_clusters["${suffix}"]="${cluster_name}"
        fi
    done <<< "${cluster_list}"

    # Step 3: Process each supervisor group
    for suffix in "${!suffix_ip[@]}"; do
        local supervisor_ip="${suffix_ip[$suffix]}"

        # Login to supervisor (AO credentials for all supervisors)
        if ! vsphere_supervisor_login "${suffix}" "${supervisor_ip}" "${TMC_SELF_MANAGED_USERNAME}" "${TMC_SELF_MANAGED_PASSWORD}"; then
            # Supervisor login failed - skip all workload clusters in this group
            local skip_count=$(echo "${supervisor_clusters[$suffix]}" | wc -l | tr -d ' ')
            warning "[vSphere Login] Skipping ${skip_count} workload cluster(s) under supervisor ${suffix}"
            login_failed=$((login_failed + skip_count))
            continue
        fi

        # Discover workload cluster namespaces from supervisor
        local namespace_data
        namespace_data=$(discover_workload_namespaces "${supervisor_ip}")

        # Process each cluster in this supervisor group
        while IFS= read -r cluster_name; do
            [[ -z "${cluster_name}" ]] && continue

            # Find namespace for this cluster from discovered metadata
            local namespace=""
            if [[ -n "${namespace_data}" ]]; then
                namespace=$(echo "${namespace_data}" | awk -v name="${cluster_name}" '$2 == name {print $1; exit}')
            fi

            if [[ -z "${namespace}" ]]; then
                # Fallback: try to get provisioner from TMC metadata cache
                local metadata
                if metadata=$(discover_cluster_metadata "${cluster_name}" 2>/dev/null); then
                    namespace=$(echo "${metadata}" | cut -d'|' -f2 | tr -d ' \n\r\t')
                fi
            fi

            if [[ -z "${namespace}" ]]; then
                warning "[vSphere Login] Cannot determine namespace for ${cluster_name}, skipping"
                login_failed=$((login_failed + 1))
                continue
            fi

            # Determine credentials (prod → AO, non-prod → Non-AO)
            local environment=$(determine_environment "${cluster_name}")
            local wl_username wl_password

            if [[ "${environment}" == "prod" ]]; then
                wl_username="${TMC_SELF_MANAGED_USERNAME}"
                wl_password="${TMC_SELF_MANAGED_PASSWORD}"
            else
                wl_username="${VSPHERE_NONPROD_USERNAME}"
                wl_password="${VSPHERE_NONPROD_PASSWORD}"
            fi

            if [[ -z "${wl_username}" || -z "${wl_password}" ]]; then
                warning "[vSphere Login] Credentials not available for ${cluster_name} (${environment}), skipping"
                login_failed=$((login_failed + 1))
                continue
            fi

            # Login to workload cluster
            if vsphere_workload_login "${cluster_name}" "${supervisor_ip}" "${namespace}" "${wl_username}" "${wl_password}"; then
                login_success=$((login_success + 1))
            else
                login_failed=$((login_failed + 1))
            fi

        done <<< "${supervisor_clusters[$suffix]}"
    done

    # Step 4: Print summary
    echo ""
    echo -e "${CYAN}vSphere Login Summary:${NC} ${GREEN}${login_success} successful${NC}, ${RED}${login_failed} failed${NC}"
    echo ""

    return 0
}

#===============================================================================
# Export Functions
#===============================================================================

export -f extract_cluster_suffix
export -f get_supervisor_ip
export -f ensure_vsphere_credentials
export -f vsphere_supervisor_login
export -f discover_workload_namespaces
export -f vsphere_workload_login
export -f run_vsphere_login
