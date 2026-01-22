#!/bin/bash
#===============================================================================
# Common Utility Functions Library
# Shared utilities for Kubernetes health check scripts
#===============================================================================

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# Image exclusion pattern (customize as needed)
export IMAGE_EXCLUSION_PATTERN='harbor|localhost:5000|image: sha256|vmware|broadcom|dynatrace|ghcr.io/northerntrust-internal'

# Events to ignore during comparison (expected during upgrades/rolling updates)
export EXPECTED_UPGRADE_EVENTS=(
    "Pulling"
    "Pulled"
    "Created"
    "Started"
    "Scheduled"
    "SuccessfulCreate"
    "Killing"
    "Deleted"
    "ScalingReplicaSet"
    "SuccessfulDelete"
    "NodeReady"
    "NodeNotReady"
    "RegisteredNode"
    "RemovingNode"
    "DeletingAllPods"
    "TerminatingEvictedPod"
)

#===============================================================================
# Logging Functions
#===============================================================================

# Display progress message
progress() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Display success message
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Display error message
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Display warning message
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Display debug message (only when DEBUG is enabled)
debug() {
    if [[ "${DEBUG}" == "on" ]] || [[ "${DEBUG}" == "true" ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
    fi
}

# Display section header
print_section() {
    echo ""
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================================${NC}"
    echo ""
}

#===============================================================================
# Health Check Functions
#===============================================================================

# Function to print section header in output file
print_header() {
    local title="$1"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║"
    echo "║  ${title}"
    echo "║"
    echo "║  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

# Function to run command and capture output
run_check() {
    local description="$1"
    local cmd="$2"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ ${description}"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    eval "${cmd}" 2>&1 || echo "[WARN] Command returned non-zero exit code"
    echo ""
    echo "───────────────────────────────────────────────────────────────────────────────"
}

#===============================================================================
# Validation Functions
#===============================================================================

# Verify kubectl connectivity
verify_kubectl_connectivity() {
    progress "Verifying cluster connectivity..."
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        return 1
    fi
    success "Connected to cluster"
    return 0
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

#===============================================================================
# File Management Functions
#===============================================================================

# Create output directory
create_output_directory() {
    local dir="$1"
    mkdir -p "${dir}" 2>/dev/null
    if [ ! -d "${dir}" ]; then
        error "Failed to create output directory: ${dir}"
        return 1
    fi
    return 0
}

# Create or update symlink
create_symlink() {
    local target="$1"
    local link_name="$2"

    ln -sf "$(basename "${target}")" "${link_name}" 2>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        warning "Failed to create symlink: ${link_name}"
        return 1
    fi
}

#===============================================================================
# String Processing Functions
#===============================================================================

# Extract section from health check file
extract_section() {
    local file="$1"
    local section="$2"
    local start_pattern="=== ${section}"
    local end_pattern="^=== SECTION"

    sed -n "/${start_pattern}/,/${end_pattern}/p" "${file}" | head -n -3
}

# Filter relevant events (remove expected upgrade events)
filter_relevant_events() {
    local input="$1"
    local exclude_pattern=$(IFS='|'; echo "${EXPECTED_UPGRADE_EVENTS[*]}")

    echo "${input}" | grep -vE "${exclude_pattern}" || true
}

# Trim whitespace and ensure clean integer
clean_integer() {
    local value="$1"
    value=$(echo "${value}" | tr -d ' ' | tr -d '\n')
    value=${value:-0}
    echo "${value}"
}

#===============================================================================
# Safe Integer Comparison Functions
#===============================================================================

# Safe integer comparison - greater than
safe_gt() {
    local val1="$1"
    local val2="$2"

    val1=$(clean_integer "${val1}")
    val2=$(clean_integer "${val2}")

    if [ -n "${val1}" ] && [ -n "${val2}" ] && [ "${val1}" -gt "${val2}" ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# Safe integer comparison - equal
safe_eq() {
    local val1="$1"
    local val2="$2"

    val1=$(clean_integer "${val1}")
    val2=$(clean_integer "${val2}")

    if [ "${val1}" -eq "${val2}" ] 2>/dev/null; then
        return 0
    fi
    return 1
}

# Safe integer comparison - not equal
safe_ne() {
    local val1="$1"
    local val2="$2"

    val1=$(clean_integer "${val1}")
    val2=$(clean_integer "${val2}")

    if [ "${val1}" -ne "${val2}" ] 2>/dev/null; then
        return 0
    fi
    return 1
}

#===============================================================================
# Display Functions
#===============================================================================

# Display script banner
display_banner() {
    local title="$1"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ${title}${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Display key-value pair
display_info() {
    local key="$1"
    local value="$2"
    echo -e "${key}: ${YELLOW}${value}${NC}"
}

#===============================================================================
# Environment Information
#===============================================================================

# Get environment details
get_environment_info() {
    echo "Environment: VMware Cloud Foundation 5.2.1 / VKS 3.3.3"
}

# Get current timestamp
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Get formatted timestamp
get_formatted_timestamp() {
    date '+%Y-%m-%d %H:%M:%S %Z'
}

#===============================================================================
# Initialization
#===============================================================================

# Export all functions for use in other scripts
export -f progress
export -f success
export -f error
export -f warning
export -f debug
export -f print_section
export -f print_header
export -f run_check
export -f verify_kubectl_connectivity
export -f command_exists
export -f create_output_directory
export -f create_symlink
export -f extract_section
export -f filter_relevant_events
export -f clean_integer
export -f safe_gt
export -f safe_eq
export -f safe_ne
export -f display_banner
export -f display_info
export -f get_environment_info
export -f get_timestamp
export -f get_formatted_timestamp
