#!/bin/bash
#===============================================================================
# Configuration Parser Library
# Functions for parsing and managing configuration files
# v3.1: Simplified to support simple cluster names (one per line)
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
    export COMMON_LIB_LOADED=1
fi

#===============================================================================
# Configuration Parsing Functions
#===============================================================================

# Parse configuration file parameter
parse_config() {
    local config_file="$1"
    local param_name="$2"

    if [ ! -f "${config_file}" ]; then
        return 1
    fi

    grep "^${param_name}=" "${config_file}" 2>/dev/null | cut -d'=' -f2- | tr -d ' '
}

# Get cluster list from config file
get_cluster_list() {
    local config_file="$1"

    if [ ! -f "${config_file}" ]; then
        return 1
    fi

    # Extract cluster names (one per line)
    # Ignore comments and empty lines
    # Trim whitespace
    grep -v '^#' "${config_file}" | grep -v '^[[:space:]]*$' | while read -r cluster_name; do
        # Trim leading and trailing whitespace
        cluster_name=$(echo "${cluster_name}" | xargs)
        echo "${cluster_name}"
    done
}

# Validate configuration file exists and has content
validate_config_file() {
    local config_file="$1"

    if [ ! -f "${config_file}" ]; then
        error "Configuration file not found: ${config_file}"
        return 1
    fi

    if [ ! -r "${config_file}" ]; then
        error "Configuration file is not readable: ${config_file}"
        return 1
    fi

    # Check if file has at least one non-empty, non-comment line
    local cluster_count
    cluster_count=$(grep -v '^#' "${config_file}" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')

    if [[ "${cluster_count}" -eq 0 ]]; then
        error "Configuration file contains no valid cluster names"
        return 1
    fi

    return 0
}

# Validate cluster name format (simple cluster name, no dots)
validate_cluster_format() {
    local cluster_name="$1"

    # Simple cluster name: alphanumeric, hyphens, underscores
    if echo "${cluster_name}" | grep -qE "^[a-zA-Z0-9_-]+$"; then
        return 0
    else
        error "Invalid cluster name format: ${cluster_name}"
        error "Expected format: simple cluster name (e.g., prod-workload-01)"
        return 1
    fi
}

# Load configuration from file
load_configuration() {
    local config_file="$1"

    if ! validate_config_file "${config_file}"; then
        return 1
    fi

    local cluster_count
    cluster_count=$(count_clusters "${config_file}")

    progress "Loaded ${cluster_count} cluster(s) from configuration"

    return 0
}

# Display configuration summary
display_configuration() {
    local config_file="$1"
    local output_dir="${2:-}"

    echo -e "${CYAN}Configuration:${NC}"
    echo -e "  Config File:   ${config_file}"

    if [ -n "${output_dir}" ]; then
        echo -e "  Output Dir:    ${output_dir}"
    fi

    echo ""
}

# Count clusters in config
count_clusters() {
    local config_file="$1"

    get_cluster_list "${config_file}" | wc -l | tr -d ' '
}

# Display cluster list
display_cluster_list() {
    local config_file="$1"

    local cluster_list=$(get_cluster_list "${config_file}")

    if [ -z "${cluster_list}" ]; then
        warning "No clusters found in configuration file"
        return 1
    fi

    echo -e "${CYAN}Clusters to process:${NC}"
    echo "${cluster_list}" | nl -w2 -s'. '
    echo ""

    return 0
}

#===============================================================================
# Management Cluster Discovery Functions (v3.5)
#===============================================================================

# Get cluster list from management cluster discovery
get_cluster_list_from_management() {
    local env_flag="$1"

    # Get management cluster name
    local mgmt_cluster
    if ! mgmt_cluster=$(get_management_cluster_for_environment "${env_flag}"); then
        return 1
    fi

    debug "Matched management cluster: ${mgmt_cluster}"

    # Discover clusters
    local cluster_data
    if ! cluster_data=$(discover_clusters_by_management "${mgmt_cluster}"); then
        return 1
    fi

    if [[ -z "${cluster_data}" ]]; then
        return 0
    fi

    # Extract just cluster names (first field before |)
    echo "${cluster_data}" | cut -d'|' -f1
    return 0
}

# Validate environment format
validate_management_environment() {
    local env_flag="$1"

    # Check format: alphanumeric + hyphens
    if ! echo "${env_flag}" | grep -qE "^[a-zA-Z0-9-]+$"; then
        error "Invalid environment format: ${env_flag}"
        error "Expected format: prod-1, uat-2, system-3, etc."
        return 1
    fi

    return 0
}

# Count clusters from a list string
count_clusters_from_list() {
    local cluster_list="$1"

    if [[ -z "${cluster_list}" ]]; then
        echo "0"
    else
        echo "${cluster_list}" | grep -c . || echo "0"
    fi
}

#===============================================================================
# Export Functions
#===============================================================================

export -f parse_config
export -f get_cluster_list
export -f validate_config_file
export -f validate_cluster_format
export -f load_configuration
export -f display_configuration
export -f count_clusters
export -f display_cluster_list
export -f get_cluster_list_from_management
export -f validate_management_environment
export -f count_clusters_from_list
