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

    # Remove old entry if exists
    if [[ -f "${CONTEXT_TIMESTAMP_FILE}" ]]; then
        grep -v "^${context_name}:" "${CONTEXT_TIMESTAMP_FILE}" > "${CONTEXT_TIMESTAMP_FILE}.tmp" 2>/dev/null && \
        mv "${CONTEXT_TIMESTAMP_FILE}.tmp" "${CONTEXT_TIMESTAMP_FILE}" || true
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

# Create TMC context if it doesn't exist
ensure_tmc_context() {
    local cluster_name="$1"

    # Ensure tanzu CLI is available
    if ! ensure_tanzu; then
        return 1
    fi

    # Determine environment from cluster name
    local environment
    environment=$(determine_environment "${cluster_name}")

    if [[ "${environment}" == "unknown" ]]; then
        error "Cannot determine environment for cluster ${cluster_name}"
        error "Expected naming pattern: *-prod-[1-4], *-uat-[1-4], or *-system-[1-4]"
        return 1
    fi

    local context_name
    context_name=$(get_tmc_context_name "${environment}")

    local endpoint
    endpoint=$(get_tmc_endpoint "${environment}")

    # Check if we've already setup this context in this script run
    if [[ "${environment}" == "prod" ]] && [[ -n "${PROD_CONTEXT_READY}" ]]; then
        # Already setup, just switch to it silently
        tanzu context use "${context_name}" >/dev/null 2>&1
        return 0
    fi
    if [[ "${environment}" == "nonprod" ]] && [[ -n "${NONPROD_CONTEXT_READY}" ]]; then
        # Already setup, just switch to it silently
        tanzu context use "${context_name}" >/dev/null 2>&1
        return 0
    fi

    # Check if context exists and is still valid (less than 12 hours old)
    if tanzu context list 2>/dev/null | grep -q "${context_name}"; then
        if is_context_valid "${context_name}"; then
            # Context exists and is valid, just switch to it (skip auth check)
            if tanzu context use "${context_name}" >/dev/null 2>&1; then
                success "Reusing existing TMC context '${context_name}'"
                # Mark as ready for subsequent calls in this run
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

    # Get credentials from environment variables or prompt
    local username="${TMC_SELF_MANAGED_USERNAME:-}"
    local password="${TMC_SELF_MANAGED_PASSWORD:-}"

    # Prompt for username if not provided
    if [[ -z "${username}" ]]; then
        echo -n "Enter TMC username (AO account): "
        read -r username </dev/tty
        if [[ -z "${username}" ]]; then
            error "Username cannot be empty"
            return 1
        fi
    fi

    # Prompt for password if not provided
    if [[ -z "${password}" ]]; then
        echo -n "Enter TMC password: "
        read -r -s password </dev/tty
        echo ""
        if [[ -z "${password}" ]]; then
            error "Password cannot be empty"
            return 1
        fi
    fi

    # Create context
    if TMC_SELF_MANAGED_USERNAME="${username}" \
       TMC_SELF_MANAGED_PASSWORD="${password}" \
       tanzu tmc context create "${context_name}" \
           --endpoint "${endpoint}" \
           -i pinniped \
           --basic-auth >/dev/null 2>&1; then
        success "TMC context '${context_name}' created successfully"
        # Save timestamp for 12-hour validity check
        save_context_timestamp "${context_name}"
        # Mark as ready for subsequent calls in this run
        if [[ "${environment}" == "prod" ]]; then
            PROD_CONTEXT_READY="true"
        else
            NONPROD_CONTEXT_READY="true"
        fi
        return 0
    else
        error "Failed to create TMC context '${context_name}'"
        error "Please verify your credentials and endpoint configuration"
        return 1
    fi
}

# Delete existing context and recreate (for troubleshooting)
recreate_tmc_context() {
    local cluster_name="$1"

    local environment
    environment=$(determine_environment "${cluster_name}")

    if [[ "${environment}" == "unknown" ]]; then
        error "Cannot determine environment for cluster ${cluster_name}"
        return 1
    fi

    local context_name
    context_name=$(get_tmc_context_name "${environment}")

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

export -f init_context_cache
export -f get_context_timestamp
export -f save_context_timestamp
export -f is_context_valid
export -f determine_environment
export -f get_tmc_context_name
export -f get_tmc_endpoint
export -f context_exists
export -f ensure_tanzu
export -f ensure_tmc_context
export -f recreate_tmc_context
export -f verify_tmc_context
