#!/bin/bash
#===============================================================================
# vSphere Login Module
# Handles automated kubectl vsphere login for Supervisor and Workload clusters
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
# Non-Prod Credential Variables
#===============================================================================
# Separate credentials for non-prod workload cluster login (Non-AO account)
VSPHERE_NONPROD_USERNAME=""
VSPHERE_NONPROD_PASSWORD=""
VSPHERE_NONPROD_CREDENTIALS_PROMPTED=""

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

# Prompt for Non-Prod vSphere credentials (Non-AO account)
prompt_vsphere_nonprod_credentials() {
    # Skip if already prompted or credentials are set
    if [[ -n "${VSPHERE_NONPROD_CREDENTIALS_PROMPTED}" ]]; then
        return 0
    fi

    # Check if credentials are already set via environment variables
    if [[ -n "${VSPHERE_NONPROD_USERNAME:-}" ]] && [[ -n "${VSPHERE_NONPROD_PASSWORD:-}" ]]; then
        VSPHERE_NONPROD_CREDENTIALS_PROMPTED="true"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Non-Prod vSphere credentials required (Non-AO account)${NC}"
    echo "Used for workload cluster login to system-* and uat-* clusters."
    echo ""

    # Prompt for username if not provided
    if [[ -z "${VSPHERE_NONPROD_USERNAME:-}" ]]; then
        echo -n "Enter Non-Prod vSphere username: "
        read -r VSPHERE_NONPROD_USERNAME </dev/tty
        if [[ -z "${VSPHERE_NONPROD_USERNAME}" ]]; then
            error "Username cannot be empty"
            return 1
        fi
        export VSPHERE_NONPROD_USERNAME
    fi

    # Prompt for password if not provided
    if [[ -z "${VSPHERE_NONPROD_PASSWORD:-}" ]]; then
        echo -n "Enter Non-Prod vSphere password: "
        read -r -s VSPHERE_NONPROD_PASSWORD </dev/tty
        echo ""
        if [[ -z "${VSPHERE_NONPROD_PASSWORD}" ]]; then
            error "Password cannot be empty"
            return 1
        fi
        export VSPHERE_NONPROD_PASSWORD
    fi

    VSPHERE_NONPROD_CREDENTIALS_PROMPTED="true"
    success "Non-Prod vSphere credentials configured"
    echo ""
    return 0
}

#===============================================================================
# vSphere Login Functions
#===============================================================================

# Login to Supervisor cluster
vsphere_supervisor_login() {
    local suffix="$1"
    local supervisor_ip="$2"
    local username="${TMC_SELF_MANAGED_USERNAME}"
    local password="${TMC_SELF_MANAGED_PASSWORD}"

    debug "[vSphere Login] Logging in to Supervisor ${suffix}..."

    if kubectl vsphere login \
        --server "${supervisor_ip}" \
        --username "${username}" \
        --password "${password}" \
        --insecure-skip-tls-verify >/dev/null 2>&1; then
        echo -e "${GREEN}[vSphere Login]${NC} Success login to Supervisor ${suffix}"
        return 0
    else
        echo -e "${RED}[vSphere Login]${NC} Failed login to Supervisor ${suffix}"
        return 1
    fi
}

# Login to Workload cluster
vsphere_workload_login() {
    local cluster_name="$1"
    local suffix="$2"
    local supervisor_ip="$3"
    local provisioner="$4"
    local environment="$5"  # "prod" or "nonprod"

    # Determine credentials based on environment
    local username
    local password

    if [[ "${environment}" == "prod" ]]; then
        username="${TMC_SELF_MANAGED_USERNAME}"
        password="${TMC_SELF_MANAGED_PASSWORD}"
    else
        username="${VSPHERE_NONPROD_USERNAME}"
        password="${VSPHERE_NONPROD_PASSWORD}"
    fi

    debug "[vSphere Login] Logging in to Workload cluster ${cluster_name}..."

    if kubectl vsphere login \
        --server "${supervisor_ip}" \
        --username "${username}" \
        --password "${password}" \
        --tanzu-kubernetes-cluster-name "${cluster_name}" \
        --tanzu-kubernetes-cluster-namespace "${provisioner}" \
        --insecure-skip-tls-verify >/dev/null 2>&1; then
        echo -e "${GREEN}[vSphere Login]${NC} Success login to ${cluster_name}"
        return 0
    else
        echo -e "${RED}[vSphere Login]${NC} Failed login to ${cluster_name}"
        return 1
    fi
}

#===============================================================================
# Main Login Orchestration
#===============================================================================

# Login to all clusters (Supervisor + Workload)
vsphere_login_all() {
    local cluster_list="$1"

    # Track logged supervisors to avoid duplicates
    declare -A logged_supervisors

    # Process each cluster
    while IFS= read -r cluster_name; do
        # Extract suffix
        local suffix
        if ! suffix=$(extract_cluster_suffix "${cluster_name}"); then
            warning "[vSphere Login] Cannot extract suffix from ${cluster_name}, skipping"
            continue
        fi

        # Get supervisor IP
        local supervisor_ip=$(get_supervisor_ip "${suffix}")
        if [[ -z "${supervisor_ip}" || "${supervisor_ip}" == "<"* ]]; then
            warning "[vSphere Login] Supervisor IP not configured for ${suffix}, skipping ${cluster_name}"
            continue
        fi

        # Determine environment (prod/nonprod)
        local environment=$(determine_environment "${cluster_name}")
        if [[ "${environment}" == "unknown" ]]; then
            warning "[vSphere Login] Unknown environment for ${cluster_name}, skipping"
            continue
        fi

        # Login to Supervisor (once per suffix)
        if [[ -z "${logged_supervisors[$suffix]:-}" ]]; then
            vsphere_supervisor_login "${suffix}" "${supervisor_ip}"
            logged_supervisors[$suffix]="done"
        fi

        # Discover provisioner/namespace for workload cluster login
        local metadata
        if ! metadata=$(discover_cluster_metadata "${cluster_name}" 2>/dev/null); then
            warning "[vSphere Login] Cannot discover metadata for ${cluster_name}, skipping workload login"
            continue
        fi

        local provisioner
        provisioner=$(echo "${metadata}" | cut -d'|' -f2 | tr -d ' \n\r\t')

        if [[ -z "${provisioner}" ]]; then
            warning "[vSphere Login] Cannot determine provisioner for ${cluster_name}, skipping workload login"
            continue
        fi

        # Login to Workload cluster
        vsphere_workload_login "${cluster_name}" "${suffix}" "${supervisor_ip}" "${provisioner}" "${environment}"

    done <<< "${cluster_list}"
}

#===============================================================================
# Public Entry Point
#===============================================================================

# Start vSphere login in background
# Usage: start_vsphere_login_background "cluster1\ncluster2\ncluster3"
start_vsphere_login_background() {
    local cluster_list="$1"

    # Guard: Skip if already done (prevents duplicate in upgrade→health-check subprocess)
    if [[ -n "${VSPHERE_LOGIN_DONE:-}" ]]; then
        debug "[vSphere Login] Already completed in parent process, skipping"
        return 0
    fi

    # Check if kubectl vsphere plugin is available
    if ! kubectl vsphere version >/dev/null 2>&1; then
        debug "[vSphere Login] kubectl vsphere plugin not available, skipping"
        return 0
    fi

    # Ensure TMC credentials are available (should already be prompted)
    if [[ -z "${TMC_SELF_MANAGED_USERNAME:-}" ]] || [[ -z "${TMC_SELF_MANAGED_PASSWORD:-}" ]]; then
        warning "[vSphere Login] TMC credentials not available, skipping"
        return 0
    fi

    # Check if any non-prod clusters exist in the list
    local has_nonprod=false
    while IFS= read -r cluster_name; do
        local env=$(determine_environment "${cluster_name}")
        if [[ "${env}" == "nonprod" ]]; then
            has_nonprod=true
            break
        fi
    done <<< "${cluster_list}"

    # Prompt for non-prod credentials in foreground if needed
    if [[ "${has_nonprod}" == "true" ]]; then
        if ! prompt_vsphere_nonprod_credentials; then
            warning "[vSphere Login] Non-Prod credentials not available, skipping non-prod clusters"
        fi
    fi

    # Mark as done before backgrounding (so subprocess sees it)
    export VSPHERE_LOGIN_DONE="true"

    # Start background login process
    progress "[vSphere Login] Starting background login process..."
    vsphere_login_all "${cluster_list}" &

    return 0
}

#===============================================================================
# Export Functions
#===============================================================================

export -f extract_cluster_suffix
export -f get_supervisor_ip
export -f prompt_vsphere_nonprod_credentials
export -f vsphere_supervisor_login
export -f vsphere_workload_login
export -f vsphere_login_all
export -f start_vsphere_login_background
