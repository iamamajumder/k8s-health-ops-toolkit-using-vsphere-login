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
    ["prod-1"]="supvr-w11c1-prod-1.k8s.ntrs.com"
    ["prod-2"]="supvr-w11c1-prod-2.k8s.ntrs.com"
    ["prod-3"]="supvr-w11c2-prod-3.k8s.ntrs.com"
    ["prod-4"]="supvr-w11c2-prod-4.k8s.ntrs.com"
    ["system-1"]="supvr-w10c1-system-1.k8s.ntrs.com"
    ["system-3"]="supvr-w10c2-system-3.k8s.ntrs.com"
    ["uat-2"]="supvr-w10c1-uat-2.k8s.ntrs.com"
    ["uat-4"]="supvr-w10c2-uat-4.k8s.ntrs.com"
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

    info "[vSphere] Step 1: Checking credentials..."

    # --- AO Credentials (used for all supervisor logins + prod workload logins) ---
    if [[ -n "${TMC_SELF_MANAGED_USERNAME:-}" ]]; then
        info "[vSphere]   AO username: found in env var (${TMC_SELF_MANAGED_USERNAME})"
    else
        info "[vSphere]   AO username: NOT in env, prompting..."
        echo -n "Enter vSphere AO username (same as TMC username): " >&2
        read -r TMC_SELF_MANAGED_USERNAME </dev/tty
        if [[ -z "${TMC_SELF_MANAGED_USERNAME}" ]]; then
            error "Username cannot be empty"
            return 1
        fi
    fi
    if [[ -n "${TMC_SELF_MANAGED_PASSWORD:-}" ]]; then
        info "[vSphere]   AO password: found in env var"
    else
        info "[vSphere]   AO password: NOT in env, prompting..."
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
    info "[vSphere]   Scanning cluster list for non-prod clusters..."
    local has_nonprod=false
    while IFS= read -r cluster; do
        [[ -z "${cluster}" ]] && continue
        local env=$(determine_environment "${cluster}")
        if [[ "${env}" == "nonprod" ]]; then
            info "[vSphere]   Found non-prod cluster: ${cluster} (env=${env})"
            has_nonprod=true
            break
        fi
    done <<< "${cluster_list}"

    if [[ "${has_nonprod}" == "true" ]]; then
        if [[ -n "${VSPHERE_NONPROD_USERNAME:-}" ]]; then
            info "[vSphere]   Non-AO username: found in env var (${VSPHERE_NONPROD_USERNAME})"
        else
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
        if [[ -n "${VSPHERE_NONPROD_PASSWORD:-}" ]]; then
            info "[vSphere]   Non-AO password: found in env var"
        else
            echo -n "Enter Non-Prod vSphere password: " >&2
            read -r -s VSPHERE_NONPROD_PASSWORD </dev/tty
            echo "" >&2
            if [[ -z "${VSPHERE_NONPROD_PASSWORD}" ]]; then
                error "Password cannot be empty"
                return 1
            fi
        fi
        export VSPHERE_NONPROD_USERNAME VSPHERE_NONPROD_PASSWORD
    else
        info "[vSphere]   No non-prod clusters detected, skipping Non-AO credentials"
    fi

    info "[vSphere]   Credentials ready"
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

    info "[vSphere]   Supervisor login: ${suffix} (server=${supervisor_ip}, user=${username})"
    info "[vSphere]   Running: kubectl vsphere login --server ${supervisor_ip} --vsphere-username ${username} --insecure-skip-tls-verify"

    local login_output
    local exit_code

    # Pipe password via stdin instead of --vsphere-password flag
    # The --vsphere-password flag returns exit 0 but may not store valid tokens in kubeconfig
    login_output=$(echo "${password}" | kubectl vsphere login \
        --server "${supervisor_ip}" \
        --vsphere-username "${username}" \
        --insecure-skip-tls-verify 2>&1) || true
    exit_code=${PIPESTATUS[1]}

    info "[vSphere]   Login output: ${login_output}"

    if [[ ${exit_code} -eq 0 ]] && echo "${login_output}" | grep -qi "logged in successfully"; then
        echo -e "${GREEN}[vSphere Login]${NC} Supervisor ${suffix}: login successful"
        return 0
    else
        echo -e "${RED}[vSphere Login]${NC} Supervisor ${suffix}: login failed (exit code: ${exit_code})"
        if [[ -n "${login_output}" ]]; then
            echo -e "${RED}[vSphere Login]${NC}   output: ${login_output}"
        fi
        return 1
    fi
}

# Discover workload cluster namespaces from supervisor
# Relies on kubeconfig context already being set to the supervisor after vsphere_supervisor_login
# Output: lines of "NAMESPACE CLUSTER_NAME"
discover_workload_namespaces() {
    info "[vSphere]   Running: kubectl get cluster -A --no-headers"

    local raw_output
    raw_output=$(kubectl get cluster -A --no-headers 2>&1)
    local exit_code=$?

    info "[vSphere]   kubectl get cluster exit code: ${exit_code}"

    if [[ ${exit_code} -ne 0 ]]; then
        info "[vSphere]   kubectl get cluster FAILED, output: ${raw_output}"
        echo ""
        return 1
    fi

    if [[ -z "${raw_output}" ]]; then
        info "[vSphere]   kubectl get cluster returned EMPTY output"
        echo ""
        return 0
    fi

    # Show raw output for debugging
    local line_count=$(echo "${raw_output}" | wc -l | tr -d ' ')
    info "[vSphere]   kubectl get cluster returned ${line_count} line(s)"
    info "[vSphere]   Raw output:"
    while IFS= read -r line; do
        info "[vSphere]     ${line}"
    done <<< "${raw_output}"

    # Parse: column 1 = namespace, column 2 = cluster name
    echo "${raw_output}" | awk '{print $1, $2}'
}

# Login to Workload cluster
vsphere_workload_login() {
    local cluster_name="$1"
    local supervisor_ip="$2"
    local namespace="$3"
    local username="$4"
    local password="$5"

    info "[vSphere]   Workload login: ${cluster_name} (server=${supervisor_ip}, ns=${namespace}, user=${username})"
    info "[vSphere]   Running: kubectl vsphere login --server ${supervisor_ip} --vsphere-username ${username} --tanzu-kubernetes-cluster-name ${cluster_name} --tanzu-kubernetes-cluster-namespace ${namespace} --insecure-skip-tls-verify"

    local login_output
    local exit_code

    # Pipe password via stdin instead of --vsphere-password flag
    login_output=$(echo "${password}" | kubectl vsphere login \
        --server "${supervisor_ip}" \
        --vsphere-username "${username}" \
        --tanzu-kubernetes-cluster-name "${cluster_name}" \
        --tanzu-kubernetes-cluster-namespace "${namespace}" \
        --insecure-skip-tls-verify 2>&1) || true
    exit_code=${PIPESTATUS[1]}

    info "[vSphere]   Login output: ${login_output}"

    if [[ ${exit_code} -eq 0 ]] && echo "${login_output}" | grep -qi "logged in successfully"; then
        echo -e "${GREEN}[vSphere Login]${NC} ${cluster_name}: login successful"
        return 0
    else
        echo -e "${RED}[vSphere Login]${NC} ${cluster_name}: login failed (exit code: ${exit_code})"
        if [[ -n "${login_output}" ]]; then
            echo -e "${RED}[vSphere Login]${NC}   output: ${login_output}"
        fi
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
        info "[vSphere] No clusters provided, skipping"
        return 0
    fi

    # Reset KUBECONFIG to default (~/.kube/config) so vsphere login operations
    # don't conflict with TMC-managed kubeconfig files from main script operations
    local saved_kubeconfig="${KUBECONFIG:-}"
    unset KUBECONFIG
    info "[vSphere] Reset KUBECONFIG to default (~/.kube/config)"

    # Check if kubectl vsphere plugin is available
    info "[vSphere] Checking kubectl vsphere plugin..."
    if ! kubectl vsphere version >/dev/null 2>&1; then
        info "[vSphere] kubectl vsphere plugin not available, skipping"
        [[ -n "${saved_kubeconfig}" ]] && export KUBECONFIG="${saved_kubeconfig}"
        return 0
    fi
    info "[vSphere] kubectl vsphere plugin: available"

    echo ""
    print_section "vSphere Login"

    # Show cluster list being processed
    info "[vSphere] Cluster list to process:"
    while IFS= read -r cl; do
        [[ -z "${cl}" ]] && continue
        info "[vSphere]   - ${cl}"
    done <<< "${cluster_list}"

    # Step 1: Collect all credentials upfront
    if ! ensure_vsphere_credentials "${cluster_list}"; then
        warning "[vSphere] Credentials not available, skipping vSphere login"
        [[ -n "${saved_kubeconfig}" ]] && export KUBECONFIG="${saved_kubeconfig}"
        return 0
    fi

    # Step 2: Group clusters by supervisor suffix
    info "[vSphere] Step 2: Grouping clusters by supervisor suffix..."
    declare -A supervisor_clusters  # suffix → newline-separated cluster list
    declare -A suffix_ip            # suffix → supervisor IP
    local login_success=0
    local login_failed=0

    while IFS= read -r cluster_name; do
        [[ -z "${cluster_name}" ]] && continue

        local suffix
        if ! suffix=$(extract_cluster_suffix "${cluster_name}"); then
            warning "[vSphere] Cannot extract suffix from '${cluster_name}', skipping"
            login_failed=$((login_failed + 1))
            continue
        fi

        local supervisor_ip=$(get_supervisor_ip "${suffix}")
        info "[vSphere]   ${cluster_name} -> suffix=${suffix}, supervisor_ip=${supervisor_ip}"

        if [[ -z "${supervisor_ip}" || "${supervisor_ip}" == "<"* ]]; then
            warning "[vSphere] Supervisor IP not configured for ${suffix}, skipping ${cluster_name}"
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

    # Show grouping result
    info "[vSphere] Supervisor groups:"
    for suffix in "${!suffix_ip[@]}"; do
        local cluster_count=$(echo "${supervisor_clusters[$suffix]}" | wc -l | tr -d ' ')
        info "[vSphere]   ${suffix} (${suffix_ip[$suffix]}): ${cluster_count} cluster(s)"
        while IFS= read -r cl; do
            info "[vSphere]     - ${cl}"
        done <<< "${supervisor_clusters[$suffix]}"
    done

    # Step 3: Process each supervisor group
    info "[vSphere] Step 3: Processing supervisor groups..."
    for suffix in "${!suffix_ip[@]}"; do
        local supervisor_ip="${suffix_ip[$suffix]}"

        echo ""
        info "[vSphere] --- Processing supervisor: ${suffix} (${supervisor_ip}) ---"

        # Login to supervisor (AO credentials for all supervisors)
        if ! vsphere_supervisor_login "${suffix}" "${supervisor_ip}" "${TMC_SELF_MANAGED_USERNAME}" "${TMC_SELF_MANAGED_PASSWORD}"; then
            # Supervisor login failed - skip all workload clusters in this group
            local skip_count=$(echo "${supervisor_clusters[$suffix]}" | wc -l | tr -d ' ')
            warning "[vSphere] Skipping ${skip_count} workload cluster(s) under supervisor ${suffix}"
            login_failed=$((login_failed + skip_count))
            continue
        fi

        # Explicitly switch to supervisor context to ensure kubectl targets the right cluster
        info "[vSphere]   Switching kubectl context to supervisor: ${supervisor_ip}"
        if ! kubectl config use-context "${supervisor_ip}" >/dev/null 2>&1; then
            warning "[vSphere] Failed to switch context to ${supervisor_ip}"
        fi

        # Discover workload cluster namespaces from supervisor
        info "[vSphere]   Discovering workload cluster namespaces..."
        local namespace_data
        namespace_data=$(discover_workload_namespaces)

        if [[ -z "${namespace_data}" ]]; then
            info "[vSphere]   No namespace data from supervisor discovery"
        else
            info "[vSphere]   Parsed namespace mappings:"
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                info "[vSphere]     ${line}"
            done <<< "${namespace_data}"
        fi

        # Process each cluster in this supervisor group
        while IFS= read -r cluster_name; do
            [[ -z "${cluster_name}" ]] && continue

            echo ""
            info "[vSphere]   --- Processing workload cluster: ${cluster_name} ---"

            # Find namespace for this cluster from discovered metadata
            local namespace=""
            if [[ -n "${namespace_data}" ]]; then
                namespace=$(echo "${namespace_data}" | awk -v name="${cluster_name}" '$2 == name {print $1; exit}')
                if [[ -n "${namespace}" ]]; then
                    info "[vSphere]   Namespace from supervisor discovery: ${namespace}"
                else
                    info "[vSphere]   Cluster '${cluster_name}' NOT found in supervisor discovery output"
                fi
            fi

            if [[ -z "${namespace}" ]]; then
                warning "[vSphere] Cannot determine namespace for ${cluster_name}, skipping"
                login_failed=$((login_failed + 1))
                continue
            fi

            # Determine credentials (prod → AO, non-prod → Non-AO)
            local environment=$(determine_environment "${cluster_name}")
            local wl_username wl_password

            if [[ "${environment}" == "prod" ]]; then
                wl_username="${TMC_SELF_MANAGED_USERNAME}"
                wl_password="${TMC_SELF_MANAGED_PASSWORD}"
                info "[vSphere]   Environment: prod -> using AO credentials (${wl_username})"
            else
                wl_username="${VSPHERE_NONPROD_USERNAME}"
                wl_password="${VSPHERE_NONPROD_PASSWORD}"
                info "[vSphere]   Environment: ${environment} -> using Non-AO credentials (${wl_username:-<empty>})"
            fi

            if [[ -z "${wl_username}" || -z "${wl_password}" ]]; then
                warning "[vSphere] Credentials not available for ${cluster_name} (${environment}), skipping"
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
    info "[vSphere] Step 4: Complete"
    echo -e "${CYAN}vSphere Login Summary:${NC} ${GREEN}${login_success} successful${NC}, ${RED}${login_failed} failed${NC}"
    echo ""

    # Restore original KUBECONFIG if it was set
    if [[ -n "${saved_kubeconfig}" ]]; then
        export KUBECONFIG="${saved_kubeconfig}"
        info "[vSphere] Restored KUBECONFIG to: ${saved_kubeconfig}"
    fi

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
