#!/bin/bash
#===============================================================================
# TMC Integration Library
# Functions for Tanzu Mission Control (TMC) cluster management
# v3.1: Added auto-discovery functionality for cluster metadata
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
    export COMMON_LIB_LOADED=1
fi

#===============================================================================
# Configuration
#===============================================================================

# Cache file for discovered cluster metadata
CLUSTER_METADATA_CACHE="${TMPDIR:-/tmp}/k8s-health-check-cluster-cache-$$.txt"

#===============================================================================
# TMC Functions
#===============================================================================

# Discover cluster metadata from TMC (management cluster and provisioner)
discover_cluster_metadata() {
    local cluster_name="$1"

    # Check cache first
    if [[ -f "${CLUSTER_METADATA_CACHE}" ]]; then
        local cached_data
        cached_data=$(grep "^${cluster_name}:" "${CLUSTER_METADATA_CACHE}" 2>/dev/null || true)

        if [[ -n "${cached_data}" ]]; then
            # Cache hit - extract management and provisioner
            local management
            local provisioner
            management=$(echo "${cached_data}" | cut -d':' -f2)
            provisioner=$(echo "${cached_data}" | cut -d':' -f3)

            debug "Using cached metadata for ${cluster_name}: ${management}/${provisioner}" >&2
            echo "${management}|${provisioner}"
            return 0
        fi
    fi

    # Cache miss - query TMC
    progress "Discovering metadata for cluster '${cluster_name}' from TMC..." >&2

    local tmc_output
    if ! tmc_output=$(tanzu tmc cluster list --name "${cluster_name}" -o json 2>&1); then
        error "Failed to query TMC for cluster '${cluster_name}'" >&2
        return 1
    fi

    # Parse management cluster and provisioner from JSON output
    local management
    local provisioner

    # Parse JSON using jq (required prerequisite)
    management=$(echo "${tmc_output}" | jq -r '.clusters[0].fullName.managementClusterName // empty' 2>/dev/null || echo "")
    provisioner=$(echo "${tmc_output}" | jq -r '.clusters[0].fullName.provisionerName // empty' 2>/dev/null || echo "")

    if [[ -z "${management}" ]] || [[ -z "${provisioner}" ]]; then
        error "Cluster '${cluster_name}' not found in TMC or missing metadata" >&2
        warning "Please verify the cluster name is correct and accessible in TMC" >&2
        return 1
    fi

    # Cache the result
    echo "${cluster_name}:${management}:${provisioner}" >> "${CLUSTER_METADATA_CACHE}"

    success "Discovered: ${cluster_name} → Management: ${management}, Provisioner: ${provisioner}" >&2

    echo "${management}|${provisioner}"
    return 0
}

# Fetch kubeconfig using auto-discovered metadata
fetch_kubeconfig_auto() {
    local cluster_name="$1"
    local output_file="${2:-}"

    # Discover metadata
    local metadata
    if ! metadata=$(discover_cluster_metadata "${cluster_name}"); then
        return 1
    fi

    local management
    local provisioner
    management=$(echo "${metadata}" | cut -d'|' -f1)
    provisioner=$(echo "${metadata}" | cut -d'|' -f2)

    # Fetch kubeconfig using discovered metadata
    if [[ -n "${output_file}" ]]; then
        fetch_kubeconfig "${cluster_name}" "${management}" "${provisioner}" "${output_file}"
    else
        fetch_kubeconfig "${cluster_name}" "${management}" "${provisioner}"
    fi
}

# Fetch kubeconfig via TMC (original function with output file support)
fetch_kubeconfig() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"
    local output_file="${4:-}"

    progress "Fetching kubeconfig for cluster: ${cluster_name}"
    debug "Using management cluster: ${mgmt_cluster}"
    debug "Using provisioner: ${provisioner}"

    # Check if cluster exists
    debug "Running: tanzu tmc cluster get ${cluster_name} -m ${mgmt_cluster} -p ${provisioner}"
    if tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" &>/dev/null; then
        # Fetch kubeconfig
        if [[ -n "${output_file}" ]]; then
            # Output to file
            if tanzu tmc cluster admin-kubeconfig get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" > "${output_file}" 2>/dev/null; then
                success "Kubeconfig fetched successfully for ${cluster_name}"
                return 0
            else
                error "Failed to fetch kubeconfig for ${cluster_name}"
                return 1
            fi
        else
            # Output to stdout
            if tanzu tmc cluster admin-kubeconfig get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" 2>/dev/null; then
                success "Kubeconfig fetched successfully for ${cluster_name}"
                return 0
            else
                error "Failed to fetch kubeconfig for ${cluster_name}"
                return 1
            fi
        fi
    else
        error "Cluster ${cluster_name} not found or not accessible in TMC"
        error "Tried: tanzu tmc cluster get ${cluster_name} -m ${mgmt_cluster} -p ${provisioner}"
        warning "Verify the cluster exists with: tanzu tmc cluster list --name ${cluster_name}"
        return 1
    fi
}

# Verify TMC authentication
verify_tmc_auth() {
    progress "Verifying TMC authentication..."

    if ! command_exists tanzu; then
        error "Tanzu CLI not found. Please install tanzu CLI."
        return 1
    fi

    if tanzu tmc cluster list &>/dev/null; then
        success "TMC authentication successful"
        return 0
    else
        error "TMC authentication failed. Please run: tanzu tmc login"
        return 1
    fi
}

# List available clusters in TMC
list_tmc_clusters() {
    if command_exists tanzu; then
        tanzu tmc cluster list 2>/dev/null
    else
        error "Tanzu CLI not found"
        return 1
    fi
}

# Test cluster connectivity via TMC
test_cluster_connectivity() {
    local cluster_name="$1"
    local mgmt_cluster="${2:-}"
    local provisioner="${3:-}"

    # If mgmt_cluster and provisioner provided, use them
    if [[ -n "${mgmt_cluster}" ]] && [[ -n "${provisioner}" ]]; then
        tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" &>/dev/null
        return $?
    fi

    # Otherwise, discover metadata first
    local metadata
    if ! metadata=$(discover_cluster_metadata "${cluster_name}"); then
        return 1
    fi

    mgmt_cluster=$(echo "${metadata}" | cut -d'|' -f1)
    provisioner=$(echo "${metadata}" | cut -d'|' -f2)

    tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" &>/dev/null
    return $?
}

# Test kubeconfig file connectivity
test_kubeconfig_connectivity() {
    local kubeconfig_file="$1"

    if [[ ! -f "${kubeconfig_file}" ]]; then
        error "Kubeconfig file not found: ${kubeconfig_file}"
        return 1
    fi

    if kubectl --kubeconfig="${kubeconfig_file}" cluster-info &>/dev/null; then
        success "Cluster connectivity verified"
        return 0
    else
        error "Failed to connect to cluster using kubeconfig"
        return 1
    fi
}

# Cleanup cluster metadata cache
cleanup_cluster_cache() {
    if [[ -f "${CLUSTER_METADATA_CACHE}" ]]; then
        debug "Cleaning up cluster metadata cache"
        rm -f "${CLUSTER_METADATA_CACHE}"
    fi
}

#===============================================================================
# Export Functions
#===============================================================================

export -f discover_cluster_metadata
export -f fetch_kubeconfig_auto
export -f fetch_kubeconfig
export -f verify_tmc_auth
export -f list_tmc_clusters
export -f test_cluster_connectivity
export -f test_kubeconfig_connectivity
export -f cleanup_cluster_cache
