#!/bin/bash

# TMC Context Management Module
# Handles automatic TMC context creation based on cluster naming patterns

# TMC endpoint configuration
NON_PROD_DNS="tmc-1.tzm.ntrs.com"
PROD_DNS="tmc-2-prod.tzm.ntrs.com"
TMC_SM_CONTEXT_PROD="tmc-sm-prod"
TMC_SM_CONTEXT_NONPROD="tmc-sm-nonprod"

# Context cache configuration
CONTEXT_CACHE_DIR="${HOME}/.k8s-health-check"
CONTEXT_TIMESTAMP_FILE="${CONTEXT_CACHE_DIR}/context-timestamps.cache"
CONTEXT_CACHE_EXPIRY=43200  # 12 hours in seconds

# Track which contexts have been setup in this script run
declare -A CONTEXT_SETUP_DONE 2>/dev/null || CONTEXT_SETUP_DONE=""
PROD_CONTEXT_READY=""
NONPROD_CONTEXT_READY=""

# Track if credentials have been prompted in this session
TMC_CREDENTIALS_PROMPTED=""

#===============================================================================
# Prompt for TMC credentials if not set
#===============================================================================

prompt_tmc_credentials() {
    # Skip if already prompted or credentials are set
    if [[ -n "${TMC_CREDENTIALS_PROMPTED}" ]]; then
        return 0
    fi

    # Check if credentials are already set via environment variables
    if [[ -n "${TMC_SELF_MANAGED_USERNAME:-}" ]] && [[ -n "${TMC_SELF_MANAGED_PASSWORD:-}" ]]; then
        TMC_CREDENTIALS_PROMPTED="true"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}TMC credentials required${NC}"
    echo "Credentials will be used for TMC context authentication."
    echo ""

    # Prompt for username if not provided
    if [[ -z "${TMC_SELF_MANAGED_USERNAME:-}" ]]; then
        echo -n "Enter TMC username (AO account): "
        read -r TMC_SELF_MANAGED_USERNAME </dev/tty
        if [[ -z "${TMC_SELF_MANAGED_USERNAME}" ]]; then
            error "Username cannot be empty"
            return 1
        fi
        export TMC_SELF_MANAGED_USERNAME
    fi

    # Prompt for password if not provided
    if [[ -z "${TMC_SELF_MANAGED_PASSWORD:-}" ]]; then
        echo -n "Enter TMC password: "
        read -r -s TMC_SELF_MANAGED_PASSWORD </dev/tty
        echo ""
        if [[ -z "${TMC_SELF_MANAGED_PASSWORD}" ]]; then
            error "Password cannot be empty"
            return 1
        fi
        export TMC_SELF_MANAGED_PASSWORD
    fi

    TMC_CREDENTIALS_PROMPTED="true"
    success "TMC credentials configured"
    echo ""
    return 0
}

# Initialize context cache directory
init_context_cache() {
    if [[ ! -d "${CONTEXT_CACHE_DIR}" ]]; then
        mkdir -p "${CONTEXT_CACHE_DIR}"
        chmod 700 "${CONTEXT_CACHE_DIR}"
    fi
}

# Get context creation timestamp from cache
get_context_timestamp() {
    local context_name="$1"

    if [[ -f "${CONTEXT_TIMESTAMP_FILE}" ]]; then
        grep "^${context_name}:" "${CONTEXT_TIMESTAMP_FILE}" 2>/dev/null | head -1 | cut -d':' -f2 | tr -d ' \n\r'
    fi
}

# Save context creation timestamp to cache
save_context_timestamp() {
    local context_name="$1"
    local timestamp=$(date +%s)

    init_context_cache

    # Remove old entry if exists and create new file with remaining entries
    if [[ -f "${CONTEXT_TIMESTAMP_FILE}" ]]; then
        # Create temp file with all entries EXCEPT the current context
        grep -v "^${context_name}:" "${CONTEXT_TIMESTAMP_FILE}" > "${CONTEXT_TIMESTAMP_FILE}.tmp" 2>/dev/null || true
        # Move temp file to replace original (even if empty)
        mv -f "${CONTEXT_TIMESTAMP_FILE}.tmp" "${CONTEXT_TIMESTAMP_FILE}" 2>/dev/null || rm -f "${CONTEXT_TIMESTAMP_FILE}"
    fi

    # Add new entry
    echo "${context_name}:${timestamp}" >> "${CONTEXT_TIMESTAMP_FILE}"
}

# Check if context is still valid (less than 12 hours old)
is_context_valid() {
    local context_name="$1"
    local cached_timestamp

    cached_timestamp=$(get_context_timestamp "${context_name}")

    if [[ -z "${cached_timestamp}" ]]; then
        return 1  # No timestamp found, context needs recreation
    fi

    local current_time=$(date +%s)
    local age=$((current_time - cached_timestamp))

    if [ $age -lt $CONTEXT_CACHE_EXPIRY ]; then
        local age_hours=$((age / 3600))
        local age_mins=$(( (age % 3600) / 60 ))
        progress "Context '${context_name}' is ${age_hours}h ${age_mins}m old (valid for 12 hours)"
        return 0  # Valid
    else
        local age_hours=$((age / 3600))
        progress "Context '${context_name}' is ${age_hours} hours old (expired, max 12 hours)"
        return 1  # Expired
    fi
}

# Determine if cluster is production based on naming pattern
# Pattern: *-prod-[1-4] → production
# Pattern: *-uat-[1-4] or *-system-[1-4] → non-production
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

# Determine environment type from environment flag
determine_environment_from_flag() {
    local env_flag="$1"

    # Extract environment type (prefix before first hyphen)
    local env_type
    env_type=$(echo "${env_flag}" | cut -d'-' -f1)

    case "${env_type}" in
        prod)
            echo "prod"
            ;;
        uat|system|dev)
            echo "nonprod"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get TMC context name for environment
get_tmc_context_name() {
    local environment="$1"

    case "${environment}" in
        prod)
            echo "${TMC_SM_CONTEXT_PROD}"
            ;;
        nonprod)
            echo "${TMC_SM_CONTEXT_NONPROD}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get TMC endpoint DNS for environment
get_tmc_endpoint() {
    local environment="$1"

    case "${environment}" in
        prod)
            echo "${PROD_DNS}"
            ;;
        nonprod)
            echo "${NON_PROD_DNS}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if TMC context exists
context_exists() {
    local context_name="$1"
    tanzu context get "${context_name}" >/dev/null 2>&1
}

# Ensure TMC CLI is available
ensure_tanzu() {
    if ! command -v tanzu >/dev/null 2>&1; then
        error "tanzu CLI is not available in PATH"
        return 1
    fi
    return 0
}

#===============================================================================
# Core TMC Context Setup (shared logic)
#===============================================================================

# Internal function: Setup TMC context for a given environment
# Usage: _setup_tmc_context "prod|nonprod"
_setup_tmc_context() {
    local environment="$1"

    local context_name=$(get_tmc_context_name "${environment}")
    local endpoint=$(get_tmc_endpoint "${environment}")

    # Check if we've already setup this context in this script run
    if [[ "${environment}" == "prod" ]] && [[ -n "${PROD_CONTEXT_READY}" ]]; then
        tanzu context use "${context_name}" >/dev/null 2>&1
        return 0
    fi
    if [[ "${environment}" == "nonprod" ]] && [[ -n "${NONPROD_CONTEXT_READY}" ]]; then
        tanzu context use "${context_name}" >/dev/null 2>&1
        return 0
    fi

    # Check if context exists and is still valid (less than 12 hours old)
    if tanzu context list 2>/dev/null | grep -q "${context_name}"; then
        if is_context_valid "${context_name}"; then
            # Context exists and is valid, just switch to it
            if tanzu context use "${context_name}" >/dev/null 2>&1; then
                success "Reusing existing TMC context '${context_name}'"
                if [[ "${environment}" == "prod" ]]; then
                    PROD_CONTEXT_READY="true"
                else
                    NONPROD_CONTEXT_READY="true"
                fi
                return 0
            fi
            progress "Context exists but cannot be used, recreating..."
        else
            progress "Context '${context_name}' has expired, recreating..."
        fi
        # Delete the existing context
        progress "Deleting existing TMC context '${context_name}'..."
        tanzu context delete "${context_name}" -y >/dev/null 2>&1 || true
    fi

    # Create fresh context
    progress "Creating TMC context '${context_name}' for ${environment} environment"
    progress "Endpoint: ${endpoint}"

    # Prompt for credentials if not set (only prompts once per session)
    if ! prompt_tmc_credentials; then
        return 1
    fi

    # Create context using exported credentials
    # Capture error output for debugging
    local tanzu_output
    local tanzu_exit_code

    tanzu_output=$(TMC_SELF_MANAGED_USERNAME="${TMC_SELF_MANAGED_USERNAME}" \
       TMC_SELF_MANAGED_PASSWORD="${TMC_SELF_MANAGED_PASSWORD}" \
       tanzu tmc context create "${context_name}" \
           --endpoint "${endpoint}" \
           -i pinniped \
           --basic-auth 2>&1)
    tanzu_exit_code=$?

    if [ ${tanzu_exit_code} -eq 0 ]; then
        success "TMC context '${context_name}' created successfully"
        save_context_timestamp "${context_name}"
        if [[ "${environment}" == "prod" ]]; then
            PROD_CONTEXT_READY="true"
        else
            NONPROD_CONTEXT_READY="true"
        fi
        return 0
    else
        error "Failed to create TMC context '${context_name}'"
        error "Please verify your credentials and endpoint configuration"
        if [[ -n "${tanzu_output}" ]]; then
            echo ""
            echo -e "${YELLOW}Tanzu CLI Error Output:${NC}"
            echo "${tanzu_output}"
            echo ""
        fi
        return 1
    fi
}

#===============================================================================
# Public TMC Context Functions
#===============================================================================

# Create TMC context based on cluster name
ensure_tmc_context() {
    local cluster_name="$1"

    if ! ensure_tanzu; then
        return 1
    fi

    local environment=$(determine_environment "${cluster_name}")

    if [[ "${environment}" == "unknown" ]]; then
        error "Cannot determine environment for cluster ${cluster_name}"
        error "Expected naming pattern: *-prod-[1-4], *-uat-[1-4], or *-system-[1-4]"
        return 1
    fi

    _setup_tmc_context "${environment}"
}

# Create TMC context based on environment flag (e.g., prod-1, uat-2)
ensure_tmc_context_for_environment() {
    local env_flag="$1"

    local environment=$(determine_environment_from_flag "${env_flag}")

    if [[ "${environment}" == "unknown" ]]; then
        error "Cannot determine environment for: ${env_flag}"
        error "Expected format: prod-N, uat-N, or system-N"
        return 1
    fi

    _setup_tmc_context "${environment}"
}

# Delete existing context and recreate (for troubleshooting)
recreate_tmc_context() {
    local cluster_name="$1"

    local environment=$(determine_environment "${cluster_name}")

    if [[ "${environment}" == "unknown" ]]; then
        error "Cannot determine environment for cluster ${cluster_name}"
        return 1
    fi

    local context_name=$(get_tmc_context_name "${environment}")

    if context_exists "${context_name}"; then
        progress "Deleting existing context '${context_name}'"
        tanzu context delete "${context_name}" -y >/dev/null 2>&1
    fi

    ensure_tmc_context "${cluster_name}"
}

# Verify TMC context is valid and authenticated
verify_tmc_context() {
    local context_name="$1"

    if ! context_exists "${context_name}"; then
        return 1
    fi

    # Switch to context
    if ! tanzu context use "${context_name}" >/dev/null 2>&1; then
        return 1
    fi

    # Verify authentication by listing clusters
    if tanzu tmc cluster list --limit 1 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

#===============================================================================
# Export Functions
#===============================================================================

export -f init_context_cache
export -f get_context_timestamp
export -f save_context_timestamp
export -f is_context_valid
export -f determine_environment
export -f determine_environment_from_flag
export -f get_tmc_context_name
export -f get_tmc_endpoint
export -f context_exists
export -f ensure_tanzu
export -f prompt_tmc_credentials
export -f _setup_tmc_context
export -f ensure_tmc_context
export -f ensure_tmc_context_for_environment
export -f recreate_tmc_context
export -f verify_tmc_context
