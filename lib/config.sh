#!/bin/bash
#===============================================================================
# Configuration Parser Library
# Functions for parsing and managing configuration files
# v1.0: vSphere-only configuration and supervisor discovery
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
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
# Skips comments, empty lines, and lines between ===SUPERVISORS=== / ===CREDENTIALS=== markers
get_cluster_list() {
    local config_file="$1"

    if [ ! -f "${config_file}" ]; then
        return 1
    fi

    # Extract cluster names (one per line)
    # Ignore comments, empty lines, supervisor mapping section, and credentials section
    local in_section=false
    while IFS= read -r line; do
        # Track section markers (supervisors and credentials)
        if [[ "${line}" =~ ===SUPERVISORS=== ]] || [[ "${line}" =~ ===CREDENTIALS=== ]]; then
            in_section=true
            continue
        fi
        if [[ "${line}" =~ ===END_SUPERVISORS=== ]] || [[ "${line}" =~ ===END_CREDENTIALS=== ]]; then
            in_section=false
            continue
        fi
        # Skip lines inside sections
        if [[ "${in_section}" == "true" ]]; then
            continue
        fi
        # Skip comments and empty lines
        [[ "${line}" =~ ^# ]] && continue
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        # Trim whitespace
        local cluster_name
        cluster_name=$(echo "${line}" | xargs)
        echo "${cluster_name}"
    done < "${config_file}"
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

    # Check if file has at least one valid cluster name (excluding supervisor section)
    local cluster_count
    cluster_count=$(get_cluster_list "${config_file}" | wc -l | tr -d ' ')

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
# Credentials Loading (from input.conf)
#===============================================================================

# Load credentials from config file's ===CREDENTIALS=== section
# Sets env vars only if not already set (env var takes priority)
# Key mapping:
#   AO_ACCOUNT_USERNAME        -> AO_ACCOUNT_USERNAME
#   AO_ACCOUNT_PASSWORD        -> AO_ACCOUNT_PASSWORD
#   NONAO_ACCOUNT_USERNAME     -> NONAO_ACCOUNT_USERNAME
#   NONAO_ACCOUNT_PASSWORD     -> NONAO_ACCOUNT_PASSWORD
# Hyphenated config keys are also accepted and normalized to shell-safe names.
load_credentials() {
    local config_file="$1"

    if [[ -z "${config_file}" || ! -f "${config_file}" ]]; then
        debug "No config file for credentials loading, will use env vars or prompts"
        return 0
    fi

    local in_credentials=false
    local loaded=0
    while IFS= read -r line; do
        if [[ "${line}" =~ ===CREDENTIALS=== ]]; then
            in_credentials=true
            continue
        fi
        if [[ "${line}" =~ ===END_CREDENTIALS=== ]]; then
            in_credentials=false
            continue
        fi
        if [[ "${in_credentials}" == "true" ]]; then
            # Skip comments and empty lines
            [[ "${line}" =~ ^# ]] && continue
            [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
            # Parse key=value
            local key="${line%%=*}"
            local value="${line#*=}"
            key=$(echo "${key}" | xargs)
            value=$(echo "${value}" | xargs)
            [[ -z "${key}" || -z "${value}" ]] && continue

            # Map config keys to shell-safe env var names.
            case "${key}" in
                AO_ACCOUNT_USERNAME|AO-ACCOUNT_USERNAME)
                    if [[ -z "${AO_ACCOUNT_USERNAME:-}" ]]; then
                        export AO_ACCOUNT_USERNAME="${value}"
                        loaded=$((loaded + 1))
                    else
                        debug "AO_ACCOUNT_USERNAME already set via env var, skipping input.conf value"
                    fi
                    ;;
                AO_ACCOUNT_PASSWORD|AO-ACCOUNT_PASSWORD)
                    if [[ -z "${AO_ACCOUNT_PASSWORD:-}" ]]; then
                        export AO_ACCOUNT_PASSWORD="${value}"
                        loaded=$((loaded + 1))
                    else
                        debug "AO_ACCOUNT_PASSWORD already set via env var, skipping input.conf value"
                    fi
                    ;;
                NONAO_ACCOUNT_USERNAME|NONAO-ACCOUNT_USERNAME)
                    if [[ -z "${NONAO_ACCOUNT_USERNAME:-}" ]]; then
                        export NONAO_ACCOUNT_USERNAME="${value}"
                        loaded=$((loaded + 1))
                    else
                        debug "NONAO_ACCOUNT_USERNAME already set via env var, skipping input.conf value"
                    fi
                    ;;
                NONAO_ACCOUNT_PASSWORD|NONAO-ACCOUNT_PASSWORD)
                    if [[ -z "${NONAO_ACCOUNT_PASSWORD:-}" ]]; then
                        export NONAO_ACCOUNT_PASSWORD="${value}"
                        loaded=$((loaded + 1))
                    else
                        debug "NONAO_ACCOUNT_PASSWORD already set via env var, skipping input.conf value"
                    fi
                    ;;
                *)
                    debug "Unknown credential key in input.conf: ${key}"
                    ;;
            esac
        fi
    done < "${config_file}"

    if [[ ${loaded} -gt 0 ]]; then
        debug "Loaded ${loaded} credential(s) from input.conf"
    fi

    return 0
}

#===============================================================================
# Supervisor IP Mapping (loaded from input.conf)
#===============================================================================

# Load supervisor IP map from config file
# Parses lines between ===SUPERVISORS=== and ===END_SUPERVISORS=== markers
# Populates global SUPERVISOR_IP_MAP associative array
load_supervisor_map() {
    local config_file="$1"

    # Initialize empty map
    unset SUPERVISOR_IP_MAP 2>/dev/null
    declare -gA SUPERVISOR_IP_MAP

    if [[ -z "${config_file}" || ! -f "${config_file}" ]]; then
        warning "No config file provided for supervisor map, vSphere login may be limited"
        return 0
    fi

    local in_supervisors=false
    local count=0
    while IFS= read -r line; do
        if [[ "${line}" =~ ===SUPERVISORS=== ]]; then
            in_supervisors=true
            continue
        fi
        if [[ "${line}" =~ ===END_SUPERVISORS=== ]]; then
            in_supervisors=false
            continue
        fi
        if [[ "${in_supervisors}" == "true" ]]; then
            # Skip comments and empty lines within section
            [[ "${line}" =~ ^# ]] && continue
            [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
            # Parse key=value
            local key="${line%%=*}"
            local value="${line#*=}"
            key=$(echo "${key}" | xargs)
            value=$(echo "${value}" | xargs)
            if [[ -n "${key}" && -n "${value}" ]]; then
                SUPERVISOR_IP_MAP["${key}"]="${value}"
                count=$((count + 1))
            fi
        fi
    done < "${config_file}"

    if [[ ${count} -eq 0 ]]; then
        info "No supervisor mappings found in ${config_file}"
    else
        debug "Loaded ${count} supervisor mapping(s) from ${config_file}"
    fi

    return 0
}

# Build a temporary single-cluster config while preserving credentials/supervisor sections.
# Args:
#   $1 cluster name (required)
#   $2 source config file to copy sections from (required for vSphere supervisor flows)
#   $3 output file path (optional; mktemp if omitted)
# Prints: output config path on stdout
create_single_cluster_config() {
    local cluster_name="$1"
    local source_config="$2"
    local output_file="${3:-}"

    if [[ -z "${cluster_name}" ]]; then
        error "Cluster name is required to build single-cluster config"
        return 1
    fi

    if [[ -z "${source_config}" || ! -f "${source_config}" ]]; then
        error "Source config with supervisor mappings not found: ${source_config:-<empty>}"
        return 1
    fi

    if [[ -z "${output_file}" ]]; then
        output_file=$(mktemp)
    fi
    : > "${output_file}" || return 1

    local line
    local in_credentials=false
    local in_supervisors=false

    while IFS= read -r line; do
        if [[ "${line}" == *"===CREDENTIALS==="* ]]; then
            in_credentials=true
        fi
        if [[ "${in_credentials}" == "true" ]]; then
            echo "${line}" >> "${output_file}"
        fi
        if [[ "${line}" == *"===END_CREDENTIALS==="* ]]; then
            in_credentials=false
            echo "" >> "${output_file}"
        fi

        if [[ "${line}" == *"===SUPERVISORS==="* ]]; then
            in_supervisors=true
        fi
        if [[ "${in_supervisors}" == "true" ]]; then
            echo "${line}" >> "${output_file}"
        fi
        if [[ "${line}" == *"===END_SUPERVISORS==="* ]]; then
            in_supervisors=false
            echo "" >> "${output_file}"
        fi
    done < "${source_config}"

    echo "${cluster_name}" >> "${output_file}"
    echo "${output_file}"
    return 0
}

#===============================================================================
# Supervisor-based Discovery Functions
#===============================================================================

# Get cluster list from supervisor environment discovery
get_cluster_list_from_management() {
    local env_flag="$1"
    local config_file="${MANAGEMENT_DISCOVERY_CONFIG_FILE:-./input.conf}"

    # discover_clusters_by_supervisor_env is provided by lib/vsphere-cluster.sh
    if ! command -v discover_clusters_by_supervisor_env >/dev/null 2>&1; then
        error "Supervisor discovery helper not loaded"
        return 1
    fi

    local cluster_data
    if ! cluster_data=$(discover_clusters_by_supervisor_env "${env_flag}" "${config_file}"); then
        return 1
    fi

    if [[ -z "${cluster_data}" ]]; then
        return 0
    fi

    # Already returns one cluster per line
    echo "${cluster_data}"
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
export -f load_credentials
export -f validate_config_file
export -f validate_cluster_format
export -f load_configuration
export -f display_configuration
export -f count_clusters
export -f display_cluster_list
export -f load_supervisor_map
export -f create_single_cluster_config
export -f get_cluster_list_from_management
export -f validate_management_environment
export -f count_clusters_from_list

