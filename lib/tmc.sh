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

# Cache directory and files
CACHE_DIR="${HOME}/.k8s-health-check"
CLUSTER_METADATA_CACHE="${CACHE_DIR}/metadata.cache"
KUBECONFIG_CACHE_DIR="${CACHE_DIR}/kubeconfigs"

# Cache expiry times (in seconds)
METADATA_CACHE_EXPIRY=604800    # 7 days - metadata rarely changes
KUBECONFIG_CACHE_EXPIRY=43200   # 12 hours - kubeconfig refreshed twice daily

# Initialize cache directory
init_cache_dir() {
    if [[ ! -d "${CACHE_DIR}" ]]; then
        mkdir -p "${CACHE_DIR}"
        chmod 700 "${CACHE_DIR}"
    fi
    if [[ ! -d "${KUBECONFIG_CACHE_DIR}" ]]; then
        mkdir -p "${KUBECONFIG_CACHE_DIR}"
        chmod 700 "${KUBECONFIG_CACHE_DIR}"
    fi
}

# Check if cache entry is still valid based on timestamp
is_cache_valid() {
    local cache_timestamp="$1"
    local expiry_seconds="$2"
    local current_time=$(date +%s)
    local age=$((current_time - cache_timestamp))

    if [ $age -lt $expiry_seconds ]; then
        return 0  # Valid
    else
        return 1  # Expired
    fi
}

# Get cache status
get_cache_status() {
    init_cache_dir
    echo ""
    echo "=== Cache Status ==="
    echo "Cache Directory: ${CACHE_DIR}"
    echo ""

    if [[ -f "${CLUSTER_METADATA_CACHE}" ]]; then
        local entries=$(wc -l < "${CLUSTER_METADATA_CACHE}" 2>/dev/null || echo "0")
        local cache_age=$(stat -c %Y "${CLUSTER_METADATA_CACHE}" 2>/dev/null || stat -f %m "${CLUSTER_METADATA_CACHE}" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local age_days=$(( (current_time - cache_age) / 86400 ))
        echo "Metadata Cache: ${CLUSTER_METADATA_CACHE}"
        echo "  - Entries: ${entries}"
        echo "  - Age: ${age_days} day(s)"
    else
        echo "Metadata Cache: Not found"
    fi
    echo ""

    if [[ -d "${KUBECONFIG_CACHE_DIR}" ]]; then
        local kubeconfig_count=$(ls -1 "${KUBECONFIG_CACHE_DIR}"/*.kubeconfig 2>/dev/null | wc -l || echo "0")
        echo "Kubeconfig Cache: ${KUBECONFIG_CACHE_DIR}"
        echo "  - Cached configs: ${kubeconfig_count}"
    else
        echo "Kubeconfig Cache: Not found"
    fi
    echo ""
}

# Clear all caches
clear_cache() {
    progress "Clearing all caches..."
    rm -f "${CLUSTER_METADATA_CACHE}" 2>/dev/null
    rm -rf "${KUBECONFIG_CACHE_DIR}"/*.kubeconfig 2>/dev/null
    success "Cache cleared"
}

# Initialize cache on module load
init_cache_dir

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
            # Cache hit - extract management, provisioner, and timestamp
            local management
            local provisioner
            local cache_timestamp
            management=$(echo "${cached_data}" | cut -d':' -f2)
            provisioner=$(echo "${cached_data}" | cut -d':' -f3)
            cache_timestamp=$(echo "${cached_data}" | cut -d':' -f4)

            # Check if cache is still valid (if timestamp exists)
            if [[ -n "${cache_timestamp}" ]]; then
                if is_cache_valid "${cache_timestamp}" "${METADATA_CACHE_EXPIRY}"; then
                    debug "Using cached metadata for ${cluster_name}: ${management}/${provisioner}" >&2
                    echo "${management}|${provisioner}"
                    return 0
                else
                    debug "Cache expired for ${cluster_name}, refreshing..." >&2
                    # Remove expired entry
                    sed -i "/^${cluster_name}:/d" "${CLUSTER_METADATA_CACHE}" 2>/dev/null || true
                fi
            else
                # Old cache format without timestamp, use it but don't validate expiry
                debug "Using cached metadata (no timestamp) for ${cluster_name}: ${management}/${provisioner}" >&2
                echo "${management}|${provisioner}"
                return 0
            fi
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

    # Cache the result with timestamp
    local current_timestamp=$(date +%s)
    echo "${cluster_name}:${management}:${provisioner}:${current_timestamp}" >> "${CLUSTER_METADATA_CACHE}"

    success "Discovered: ${cluster_name} → Management: ${management}, Provisioner: ${provisioner}" >&2

    echo "${management}|${provisioner}"
    return 0
}

# Fetch kubeconfig using auto-discovered metadata (with caching)
fetch_kubeconfig_auto() {
    local cluster_name="$1"
    local output_file="${2:-}"

    # Check for cached kubeconfig first
    local cached_kubeconfig="${KUBECONFIG_CACHE_DIR}/${cluster_name}.kubeconfig"
    if [[ -f "${cached_kubeconfig}" ]]; then
        local file_timestamp=$(stat -c %Y "${cached_kubeconfig}" 2>/dev/null || stat -f %m "${cached_kubeconfig}" 2>/dev/null || echo "0")
        if is_cache_valid "${file_timestamp}" "${KUBECONFIG_CACHE_EXPIRY}"; then
            debug "Using cached kubeconfig for ${cluster_name}" >&2
            if [[ -n "${output_file}" ]]; then
                cp "${cached_kubeconfig}" "${output_file}"
                success "Kubeconfig loaded from cache for ${cluster_name}"
            else
                cat "${cached_kubeconfig}"
            fi
            return 0
        else
            debug "Cached kubeconfig expired for ${cluster_name}, refreshing..." >&2
        fi
    fi

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
        if fetch_kubeconfig "${cluster_name}" "${management}" "${provisioner}" "${output_file}"; then
            # Cache the kubeconfig
            cp "${output_file}" "${cached_kubeconfig}" 2>/dev/null
            chmod 600 "${cached_kubeconfig}" 2>/dev/null
            return 0
        fi
        return 1
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
