#!/bin/bash
#===============================================================================
# Multi-Cluster Kubernetes Health Check - PRE-CHANGE Orchestrator
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Execute pre-change health checks across multiple clusters
#          and copy results to Windows machine
#===============================================================================

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration file
CONFIG_FILE="${1:-${SCRIPT_DIR}/clusters.conf}"

# Validate configuration file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo -e "${RED}[ERROR] Configuration file not found: ${CONFIG_FILE}${NC}"
    echo ""
    echo "Usage: $0 [config-file]"
    echo "Example: $0 ./clusters.conf"
    exit 1
fi

# Function to display progress
progress() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to display success
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to display error
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display warning
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to display section header
print_section() {
    echo ""
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================================${NC}"
    echo ""
}

# Function to parse configuration file
parse_config() {
    local config_file="$1"
    local param_name="$2"

    grep "^${param_name}=" "${config_file}" | cut -d'=' -f2- | tr -d ' '
}

# Function to get cluster list from config
get_cluster_list() {
    local config_file="$1"

    # Extract lines that match pattern: name.management.provisioner
    # Ignore comments and empty lines
    grep -E "^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$" "${config_file}"
}

# Function to fetch kubeconfig via TMC
fetch_kubeconfig() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"

    progress "Fetching kubeconfig for cluster: ${cluster_name}"

    # Execute TMC command to get kubeconfig
    if tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" &>/dev/null; then
        if tanzu tmc cluster kubeconfig get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}" &>/dev/null; then
            success "Kubeconfig fetched successfully for ${cluster_name}"
            return 0
        else
            error "Failed to fetch kubeconfig for ${cluster_name}"
            return 1
        fi
    else
        error "Cluster ${cluster_name} not found or not accessible"
        return 1
    fi
}

# Function to run pre-check for a single cluster
run_pre_check() {
    local cluster_full_name="$1"
    local cluster_name=$(echo "${cluster_full_name}" | cut -d'.' -f1)
    local mgmt_cluster=$(echo "${cluster_full_name}" | cut -d'.' -f2)
    local provisioner=$(echo "${cluster_full_name}" | cut -d'.' -f3)
    local output_dir="$2"

    print_section "Processing Cluster: ${cluster_name}"

    progress "Management Cluster: ${mgmt_cluster}"
    progress "Provisioner: ${provisioner}"

    # Fetch kubeconfig
    if ! fetch_kubeconfig "${cluster_name}" "${mgmt_cluster}" "${provisioner}"; then
        error "Skipping health check for ${cluster_name} due to kubeconfig fetch failure"
        return 1
    fi

    # Verify kubectl connectivity
    progress "Verifying connectivity to ${cluster_name}..."
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to cluster ${cluster_name}. Skipping health check."
        return 1
    fi

    success "Connected to cluster ${cluster_name}"

    # Run pre-change health check script
    progress "Running pre-change health check for ${cluster_name}..."

    if [ -f "${SCRIPT_DIR}/k8s-health-check-pre.sh" ]; then
        if bash "${SCRIPT_DIR}/k8s-health-check-pre.sh" "${cluster_name}" "${output_dir}"; then
            success "Pre-change health check completed for ${cluster_name}"
            return 0
        else
            error "Pre-change health check failed for ${cluster_name}"
            return 1
        fi
    else
        error "k8s-health-check-pre.sh not found in ${SCRIPT_DIR}"
        return 1
    fi
}

# Function to copy results to Windows machine
copy_to_windows() {
    local output_dir="$1"
    local windows_user="$2"
    local windows_host="$3"
    local windows_path="$4"

    print_section "Copying Results to Windows Machine"

    progress "Source: ${output_dir}"
    progress "Destination: ${windows_user}@${windows_host}:${windows_path}"

    # Check if scp is available
    if ! command -v scp &>/dev/null; then
        error "scp command not found. Cannot copy files to Windows machine."
        error "Please install openssh-client or ensure scp is in PATH."
        return 1
    fi

    # Create timestamped subdirectory name
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local remote_subdir="${windows_path}\\${timestamp}"

    progress "Creating remote directory: ${remote_subdir}"

    # Copy all pre-change files
    progress "Copying pre-change health check files..."

    # Use scp with Windows path format
    # Note: This assumes SSH key is configured or will prompt for password
    if scp -r "${output_dir}"/*_pre_change_*.txt "${windows_user}@${windows_host}:${windows_path}/" 2>/dev/null; then
        success "Files copied successfully to Windows machine"
        success "Location: ${windows_user}@${windows_host}:${windows_path}/"
        return 0
    else
        warning "SCP copy failed. Please copy files manually from ${output_dir}"
        warning "Target: ${windows_user}@${windows_host}:${windows_path}/"
        return 1
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

print_section "Multi-Cluster Pre-Change Health Check Orchestrator"

echo -e "Configuration File: ${YELLOW}${CONFIG_FILE}${NC}"
echo -e "Script Directory: ${YELLOW}${SCRIPT_DIR}${NC}"
echo -e "Started: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
echo ""

# Parse configuration
progress "Reading configuration file..."

WINDOWS_USER=$(parse_config "${CONFIG_FILE}" "WINDOWS_SCP_USER")
WINDOWS_HOST=$(parse_config "${CONFIG_FILE}" "WINDOWS_SCP_HOST")
WINDOWS_PRE_PATH=$(parse_config "${CONFIG_FILE}" "WINDOWS_PRE_PATH")
LOCAL_OUTPUT_DIR=$(parse_config "${CONFIG_FILE}" "LOCAL_OUTPUT_DIR")

# Use default if not specified in config
LOCAL_OUTPUT_DIR="${LOCAL_OUTPUT_DIR:-./k8s-healthcheck}"

progress "Local output directory: ${LOCAL_OUTPUT_DIR}"
progress "Windows SCP target: ${WINDOWS_USER}@${WINDOWS_HOST}:${WINDOWS_PRE_PATH}"

# Create local output directory
mkdir -p "${LOCAL_OUTPUT_DIR}"

# Get cluster list
CLUSTER_LIST=$(get_cluster_list "${CONFIG_FILE}")

if [ -z "${CLUSTER_LIST}" ]; then
    error "No clusters found in configuration file"
    exit 1
fi

# Count clusters
CLUSTER_COUNT=$(echo "${CLUSTER_LIST}" | wc -l)
progress "Found ${CLUSTER_COUNT} cluster(s) in configuration"
echo ""

# Display cluster list
echo -e "${CYAN}Clusters to process:${NC}"
echo "${CLUSTER_LIST}" | nl -w2 -s'. '
echo ""

# Confirm execution
read -p "$(echo -e ${YELLOW}Continue with pre-change health checks? [y/N]: ${NC})" -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warning "Operation cancelled by user"
    exit 0
fi

# Initialize counters
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Process each cluster
CURRENT=0
while IFS= read -r cluster_full_name; do
    CURRENT=$((CURRENT + 1))

    echo ""
    echo -e "${MAGENTA}[${CURRENT}/${CLUSTER_COUNT}]${NC} Processing: ${YELLOW}${cluster_full_name}${NC}"
    echo ""

    if run_pre_check "${cluster_full_name}" "${LOCAL_OUTPUT_DIR}"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    # Add separator between clusters
    if [ "${CURRENT}" -lt "${CLUSTER_COUNT}" ]; then
        echo ""
        echo -e "${BLUE}───────────────────────────────────────────────────────────────────────────────${NC}"
    fi

done <<< "${CLUSTER_LIST}"

#===============================================================================
# COPY RESULTS TO WINDOWS
#===============================================================================

if [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo ""
    if [ -n "${WINDOWS_USER}" ] && [ -n "${WINDOWS_HOST}" ] && [ -n "${WINDOWS_PRE_PATH}" ]; then
        copy_to_windows "${LOCAL_OUTPUT_DIR}" "${WINDOWS_USER}" "${WINDOWS_HOST}" "${WINDOWS_PRE_PATH}"
    else
        warning "Windows SCP configuration incomplete. Skipping copy to Windows machine."
        warning "Please configure WINDOWS_SCP_USER, WINDOWS_SCP_HOST, and WINDOWS_PRE_PATH in ${CONFIG_FILE}"
    fi
fi

#===============================================================================
# FINAL SUMMARY
#===============================================================================

print_section "Execution Summary"

echo -e "Total Clusters:    ${YELLOW}${CLUSTER_COUNT}${NC}"
echo -e "Successful:        ${GREEN}${SUCCESS_COUNT}${NC}"
echo -e "Failed:            ${RED}${FAILED_COUNT}${NC}"
echo -e "Completed:         ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
echo ""

if [ "${SUCCESS_COUNT}" -eq "${CLUSTER_COUNT}" ]; then
    success "All pre-change health checks completed successfully!"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Review health check reports in: ${LOCAL_OUTPUT_DIR}"
    echo "  2. Perform your cluster changes/upgrades"
    echo "  3. Run post-change checks: ./multi-cluster-post-check.sh"
    echo ""
    exit 0
elif [ "${SUCCESS_COUNT}" -gt 0 ]; then
    warning "Pre-change health checks completed with some failures"
    echo ""
    echo -e "${CYAN}Action Required:${NC}"
    echo "  1. Review failed clusters and retry if needed"
    echo "  2. Check logs above for error details"
    echo "  3. Successful reports are in: ${LOCAL_OUTPUT_DIR}"
    echo ""
    exit 1
else
    error "All pre-change health checks failed"
    echo ""
    echo -e "${CYAN}Action Required:${NC}"
    echo "  1. Verify TMC-SM connectivity and cluster access"
    echo "  2. Check configuration file: ${CONFIG_FILE}"
    echo "  3. Review error messages above"
    echo ""
    exit 1
fi
