#!/bin/bash

# TMC Context Management Module
# Handles automatic TMC context creation based on cluster naming patterns

# TMC endpoint configuration
NON_PROD_DNS="tmc-1.tzm.ntrs.com"
PROD_DNS="tmc-2-prod.tzm.ntrs.com"
TMC_SM_CONTEXT_PROD="tmc-sm-prod"
TMC_SM_CONTEXT_NONPROD="tmc-sm-nonprod"

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

    # Check if context already exists
    if context_exists "${context_name}"; then
        progress "TMC context '${context_name}' already exists, reusing it"

        # Set as current context
        if tanzu context use "${context_name}" >/dev/null 2>&1; then
            return 0
        else
            warning "Failed to switch to context '${context_name}', attempting to recreate"
            # Delete and recreate if switch fails
            tanzu context delete "${context_name}" -y >/dev/null 2>&1
        fi
    fi

    # Context doesn't exist or failed to switch, create it
    progress "Creating TMC context '${context_name}' for ${environment} environment"
    progress "Endpoint: ${endpoint}"

    # Get credentials from environment variables or prompt
    local username="${TMC_SELF_MANAGED_USERNAME:-}"
    local password="${TMC_SELF_MANAGED_PASSWORD:-}"

    if [[ -z "${username}" ]]; then
        read -r -p "Enter TMC username (AO account): " username
    fi

    if [[ -z "${password}" ]]; then
        read -r -s -p "Enter TMC password: " password
        echo ""
    fi

    # Validate credentials are not empty
    if [[ -z "${username}" ]] || [[ -z "${password}" ]]; then
        error "Username and password are required for TMC authentication"
        return 1
    fi

    # Create context
    if TMC_SELF_MANAGED_USERNAME="${username}" \
       TMC_SELF_MANAGED_PASSWORD="${password}" \
       tanzu tmc context create "${context_name}" \
           --endpoint "${endpoint}" \
           -i pinniped \
           --basic-auth >/dev/null 2>&1; then
        success "TMC context '${context_name}' created successfully"
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

export -f determine_environment
export -f get_tmc_context_name
export -f get_tmc_endpoint
export -f context_exists
export -f ensure_tanzu
export -f ensure_tmc_context
export -f recreate_tmc_context
export -f verify_tmc_context
