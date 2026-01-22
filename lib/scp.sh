#!/bin/bash
#===============================================================================
# SCP (Windows File Transfer) Library
# Functions for copying health check reports to Windows machines
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
    export COMMON_LIB_LOADED=1
fi

#===============================================================================
# SCP Functions
#===============================================================================

# Copy pre-change files to Windows
copy_pre_to_windows() {
    local output_dir="$1"
    local windows_user="$2"
    local windows_host="$3"
    local windows_path="$4"

    print_section "Copying Pre-Change Reports to Windows Machine"

    # Validate parameters
    if [ -z "${windows_user}" ] || [ -z "${windows_host}" ] || [ -z "${windows_path}" ]; then
        warning "Windows SCP configuration incomplete. Skipping copy to Windows machine."
        warning "Please configure WINDOWS_SCP_USER, WINDOWS_SCP_HOST, and WINDOWS_PRE_PATH"
        return 1
    fi

    progress "Source: ${output_dir}"
    progress "Destination: ${windows_user}@${windows_host}:${windows_path}"

    # Check if scp is available
    if ! command_exists scp; then
        error "scp command not found. Cannot copy files to Windows machine."
        error "Please install openssh-client or ensure scp is in PATH."
        return 1
    fi

    # Copy all pre-change files
    progress "Copying pre-change health check files..."

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

# Copy post-change files to Windows
copy_post_to_windows() {
    local output_dir="$1"
    local windows_user="$2"
    local windows_host="$3"
    local windows_path="$4"

    print_section "Copying Post-Change Reports to Windows Machine"

    # Validate parameters
    if [ -z "${windows_user}" ] || [ -z "${windows_host}" ] || [ -z "${windows_path}" ]; then
        warning "Windows SCP configuration incomplete. Skipping copy to Windows machine."
        warning "Please configure WINDOWS_SCP_USER, WINDOWS_SCP_HOST, and WINDOWS_POST_PATH"
        return 1
    fi

    progress "Source: ${output_dir}"
    progress "Destination: ${windows_user}@${windows_host}:${windows_path}"

    # Check if scp is available
    if ! command_exists scp; then
        error "scp command not found. Cannot copy files to Windows machine."
        error "Please install openssh-client or ensure scp is in PATH."
        return 1
    fi

    # Copy all post-change and comparison files
    progress "Copying post-change health check and comparison files..."

    if scp -r "${output_dir}"/*_post_change_*.txt "${output_dir}"/*_comparison_*.txt "${windows_user}@${windows_host}:${windows_path}/" 2>/dev/null; then
        success "Files copied successfully to Windows machine"
        success "Location: ${windows_user}@${windows_host}:${windows_path}/"
        return 0
    else
        warning "SCP copy failed. Please copy files manually from ${output_dir}"
        warning "Target: ${windows_user}@${windows_host}:${windows_path}/"
        return 1
    fi
}

# Test SCP connectivity to Windows
test_scp_connectivity() {
    local windows_user="$1"
    local windows_host="$2"

    if [ -z "${windows_user}" ] || [ -z "${windows_host}" ]; then
        return 1
    fi

    # Try SSH connection
    ssh -o ConnectTimeout=5 -o BatchMode=yes "${windows_user}@${windows_host}" "exit" &>/dev/null
    return $?
}

# Display SCP configuration
display_scp_config() {
    local windows_user="$1"
    local windows_host="$2"
    local windows_pre_path="$3"
    local windows_post_path="$4"

    if [ -n "${windows_user}" ] && [ -n "${windows_host}" ]; then
        echo -e "${CYAN}Windows SCP Configuration:${NC}"
        echo -e "  User:      ${windows_user}"
        echo -e "  Host:      ${windows_host}"
        echo -e "  Pre Path:  ${windows_pre_path}"
        echo -e "  Post Path: ${windows_post_path}"
        echo ""
    fi
}

#===============================================================================
# Export Functions
#===============================================================================

export -f copy_pre_to_windows
export -f copy_post_to_windows
export -f test_scp_connectivity
export -f display_scp_config
