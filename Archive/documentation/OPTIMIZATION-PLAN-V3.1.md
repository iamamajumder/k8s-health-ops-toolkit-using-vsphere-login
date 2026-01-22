# K8s Health Check v3.1 Optimization Plan

## Executive Summary

This document outlines the optimization plan to simplify the K8s Health Check project by:
- Removing single/multi-cluster distinction (always use clusters.conf)
- Auto-discovering cluster metadata from TMC
- Auto-creating TMC contexts based on cluster naming patterns
- Reducing code complexity by ~25% (from ~1070 to ~800 lines)
- Isolating all TMC logic for future flexibility

## 1. Simplified Configuration Format

### Current Format (v3.0)
```bash
# clusters.conf
# Format: cluster-name.management-cluster.provisioner
prod-workload-01.mgmt-cluster-01.vsphere-tkg
prod-workload-02.mgmt-cluster-01.vsphere-tkg
dev-workload-01.mgmt-cluster-02.vsphere-tkg
uat-system-01.mgmt-cluster-02.vsphere-tkg
```

### New Format (v3.1)
```bash
# clusters.conf
# Format: One cluster name per line (simple)
prod-workload-01
prod-workload-02
dev-workload-01
uat-system-01
```

**Benefits:**
- 60% less configuration effort
- No need to know management cluster or provisioner
- Less prone to typos and configuration errors
- Cleaner, more maintainable

## 2. TMC Context Auto-Creation

### New Module: lib/tmc-context.sh

Extract and optimize logic from tmcctx.sh to create TMC contexts automatically based on cluster naming patterns.

```bash
#!/bin/bash

# TMC endpoint configuration
NON_PROD_DNS="fqdn-of-non-prod-tmc-sm-url"
PROD_DNS="fqdn-of-prod-tmc-sm-url"
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

# Create TMC context if it doesn't exist
ensure_tmc_context() {
    local cluster_name="$1"

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
        tanzu context use "${context_name}" >/dev/null 2>&1
        return 0
    fi

    # Context doesn't exist, create it
    progress "Creating TMC context '${context_name}' for ${environment} environment"

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

export -f determine_environment
export -f get_tmc_context_name
export -f get_tmc_endpoint
export -f context_exists
export -f ensure_tmc_context
export -f recreate_tmc_context
```

## 3. Cluster Auto-Discovery

### Enhanced lib/tmc.sh

Add auto-discovery functionality to fetch management cluster and provisioner from TMC.

```bash
#!/bin/bash

# Cache file for discovered cluster metadata
CLUSTER_METADATA_CACHE="${TMPDIR:-/tmp}/k8s-health-check-cluster-cache-$$.txt"

# Discover cluster metadata from TMC
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

            echo "${management}|${provisioner}"
            return 0
        fi
    fi

    # Cache miss - query TMC
    progress "Discovering metadata for cluster '${cluster_name}' from TMC..."

    local tmc_output
    if ! tmc_output=$(tanzu tmc cluster list --name "${cluster_name}" -o json 2>&1); then
        error "Failed to query TMC for cluster '${cluster_name}'"
        return 1
    fi

    # Parse management cluster and provisioner from JSON output
    local management
    local provisioner

    management=$(echo "${tmc_output}" | jq -r '.[0].fullName.managementClusterName // empty' 2>/dev/null || echo "")
    provisioner=$(echo "${tmc_output}" | jq -r '.[0].fullName.provisionerName // empty' 2>/dev/null || echo "")

    if [[ -z "${management}" ]] || [[ -z "${provisioner}" ]]; then
        error "Cluster '${cluster_name}' not found in TMC or missing metadata"
        return 1
    fi

    # Cache the result
    echo "${cluster_name}:${management}:${provisioner}" >> "${CLUSTER_METADATA_CACHE}"

    success "Discovered: ${cluster_name} → Management: ${management}, Provisioner: ${provisioner}"

    echo "${management}|${provisioner}"
    return 0
}

# Fetch kubeconfig for cluster (using discovered metadata)
fetch_kubeconfig_auto() {
    local cluster_name="$1"
    local output_file="$2"

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
    fetch_kubeconfig "${cluster_name}" "${management}" "${provisioner}" "${output_file}"
}

# Original fetch_kubeconfig function (kept for backward compatibility if needed)
fetch_kubeconfig() {
    local cluster_name="$1"
    local mgmt_cluster="$2"
    local provisioner="$3"
    local output_file="$4"

    progress "Fetching kubeconfig for ${cluster_name}..."

    if tanzu tmc cluster admin-kubeconfig get "${cluster_name}" \
        -m "${mgmt_cluster}" \
        -p "${provisioner}" > "${output_file}" 2>/dev/null; then
        success "Kubeconfig fetched successfully"
        return 0
    else
        error "Failed to fetch kubeconfig for ${cluster_name}"
        return 1
    fi
}

# Verify TMC authentication
verify_tmc_auth() {
    progress "Verifying TMC authentication..."

    if tanzu tmc cluster list >/dev/null 2>&1; then
        success "TMC authentication verified"
        return 0
    else
        error "TMC authentication failed"
        return 1
    fi
}

# Test cluster connectivity
test_cluster_connectivity() {
    local kubeconfig_file="$1"

    if kubectl --kubeconfig="${kubeconfig_file}" cluster-info >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Cleanup cache file
cleanup_cluster_cache() {
    if [[ -f "${CLUSTER_METADATA_CACHE}" ]]; then
        rm -f "${CLUSTER_METADATA_CACHE}"
    fi
}

export -f discover_cluster_metadata
export -f fetch_kubeconfig_auto
export -f fetch_kubeconfig
export -f verify_tmc_auth
export -f test_cluster_connectivity
export -f cleanup_cluster_cache
```

## 4. Simplified lib/config.sh

Remove complex parsing logic, support simple cluster names only.

```bash
#!/bin/bash

# Validate configuration file
validate_config_file() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        error "Configuration file not found: ${config_file}"
        return 1
    fi

    if [[ ! -r "${config_file}" ]]; then
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

# Get list of clusters from configuration file
get_cluster_list() {
    local config_file="$1"

    # Read cluster names (skip comments and empty lines)
    grep -v '^#' "${config_file}" | grep -v '^[[:space:]]*$' | while read -r cluster_name; do
        # Trim whitespace
        cluster_name=$(echo "${cluster_name}" | xargs)
        echo "${cluster_name}"
    done
}

# Load and validate configuration
load_configuration() {
    local config_file="$1"

    if ! validate_config_file "${config_file}"; then
        return 1
    fi

    local cluster_count
    cluster_count=$(get_cluster_list "${config_file}" | wc -l | tr -d ' ')

    progress "Loaded ${cluster_count} cluster(s) from configuration"

    return 0
}

export -f validate_config_file
export -f get_cluster_list
export -f load_configuration
```

## 5. Unified Main Scripts

### Simplified k8s-health-check-pre.sh

Remove `--multi` flag, always use clusters.conf format.

```bash
#!/bin/bash

# K8s Health Check - PRE-change (v3.1)
# Simplified: Always reads from clusters.conf

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/tmc-context.sh"
source "${SCRIPT_DIR}/lib/tmc.sh"
source "${SCRIPT_DIR}/lib/scp.sh"

# Source all health check sections
for section in "${SCRIPT_DIR}"/lib/sections/*.sh; do
    source "${section}"
done

# Usage
usage() {
    cat <<'EOF'
K8s Health Check - PRE-change (v3.1)

Usage: ./k8s-health-check-pre.sh <clusters.conf>

Arguments:
  clusters.conf    Path to configuration file with cluster names (one per line)

Example clusters.conf:
  prod-workload-01
  prod-workload-02
  uat-system-01

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output

EOF
    exit 1
}

# Main execution
main() {
    if [[ $# -ne 1 ]]; then
        usage
    fi

    local config_file="$1"

    print_header "K8s Health Check - PRE-change (v3.1)"

    # Load configuration
    if ! load_configuration "${config_file}"; then
        exit 1
    fi

    # Create output directory
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_base_dir="${SCRIPT_DIR}/health-check-results/pre-${timestamp}"
    mkdir -p "${output_base_dir}"

    progress "Output directory: ${output_base_dir}"

    # Process each cluster
    local cluster_count=0
    local success_count=0
    local failed_clusters=()

    while read -r cluster_name; do
        ((cluster_count++))

        print_header "Processing cluster ${cluster_count}: ${cluster_name}"

        # Ensure TMC context exists for this cluster
        if ! ensure_tmc_context "${cluster_name}"; then
            error "Failed to create/verify TMC context for ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            continue
        fi

        # Create cluster output directory
        local cluster_output_dir="${output_base_dir}/${cluster_name}"
        mkdir -p "${cluster_output_dir}"

        # Fetch kubeconfig with auto-discovery
        local kubeconfig_file="${cluster_output_dir}/kubeconfig"
        if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}"; then
            error "Failed to fetch kubeconfig for ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            continue
        fi

        # Test connectivity
        if ! test_cluster_connectivity "${kubeconfig_file}"; then
            error "Failed to connect to cluster ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            continue
        fi

        # Set kubeconfig for health checks
        export KUBECONFIG="${kubeconfig_file}"

        # Run all health check sections
        local report_file="${cluster_output_dir}/health-check-report.txt"

        {
            echo "================================================================"
            echo "K8s Health Check Report - PRE-change"
            echo "Cluster: ${cluster_name}"
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "================================================================"
            echo ""

            # Execute all health check sections
            run_check "01-cluster-overview"
            run_check "02-node-status"
            run_check "03-pod-status"
            run_check "04-workload-status"
            run_check "05-storage-status"
            run_check "06-networking"
            run_check "07-antrea-cni"
            run_check "08-tanzu-vmware"
            run_check "09-security-rbac"
            run_check "10-component-status"
            run_check "11-helm-releases"
            run_check "12-namespaces"
            run_check "13-resource-quotas"
            run_check "14-events"
            run_check "15-connectivity"
            run_check "16-images-audit"
            run_check "17-certificates"
            run_check "18-cluster-summary"

        } > "${report_file}"

        success "Health check completed for ${cluster_name}"
        success "Report saved: ${report_file}"

        ((success_count++))

    done < <(get_cluster_list "${config_file}")

    # Cleanup cache
    cleanup_cluster_cache

    # Summary
    print_header "Execution Summary"
    echo "Total clusters processed: ${cluster_count}"
    echo "Successful: ${success_count}"
    echo "Failed: $((cluster_count - success_count))"

    if [[ ${#failed_clusters[@]} -gt 0 ]]; then
        echo ""
        echo "Failed clusters:"
        for failed_cluster in "${failed_clusters[@]}"; do
            echo "  - ${failed_cluster}"
        done
    fi

    echo ""
    echo "Results directory: ${output_base_dir}"

    # Optional: Copy to Windows
    if [[ -n "${WINDOWS_SCP_ENABLED:-}" ]] && [[ "${WINDOWS_SCP_ENABLED}" == "true" ]]; then
        copy_pre_to_windows "${output_base_dir}"
    fi
}

main "$@"
```

### Simplified k8s-health-check-post.sh

Similar structure, includes comparison logic.

```bash
#!/bin/bash

# K8s Health Check - POST-change (v3.1)
# Simplified: Always reads from clusters.conf

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/tmc-context.sh"
source "${SCRIPT_DIR}/lib/tmc.sh"
source "${SCRIPT_DIR}/lib/scp.sh"
source "${SCRIPT_DIR}/lib/comparison.sh"

# Source all health check sections
for section in "${SCRIPT_DIR}"/lib/sections/*.sh; do
    source "${section}"
done

# Usage
usage() {
    cat <<'EOF'
K8s Health Check - POST-change (v3.1)

Usage: ./k8s-health-check-post.sh <clusters.conf> <pre-results-dir>

Arguments:
  clusters.conf     Path to configuration file with cluster names (one per line)
  pre-results-dir   Path to PRE-change results directory for comparison

Example:
  ./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20250122_143000

Environment Variables:
  TMC_SELF_MANAGED_USERNAME    TMC username (optional, will prompt if not set)
  TMC_SELF_MANAGED_PASSWORD    TMC password (optional, will prompt if not set)
  DEBUG                        Set to 'on' for verbose output

EOF
    exit 1
}

# Main execution
main() {
    if [[ $# -ne 2 ]]; then
        usage
    fi

    local config_file="$1"
    local pre_results_dir="$2"

    print_header "K8s Health Check - POST-change (v3.1)"

    # Validate pre-results directory
    if [[ ! -d "${pre_results_dir}" ]]; then
        error "PRE-results directory not found: ${pre_results_dir}"
        exit 1
    fi

    # Load configuration
    if ! load_configuration "${config_file}"; then
        exit 1
    fi

    # Create output directory
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_base_dir="${SCRIPT_DIR}/health-check-results/post-${timestamp}"
    mkdir -p "${output_base_dir}"

    progress "Output directory: ${output_base_dir}"

    # Process each cluster
    local cluster_count=0
    local success_count=0
    local failed_clusters=()

    while read -r cluster_name; do
        ((cluster_count++))

        print_header "Processing cluster ${cluster_count}: ${cluster_name}"

        # Ensure TMC context exists for this cluster
        if ! ensure_tmc_context "${cluster_name}"; then
            error "Failed to create/verify TMC context for ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            continue
        fi

        # Create cluster output directory
        local cluster_output_dir="${output_base_dir}/${cluster_name}"
        mkdir -p "${cluster_output_dir}"

        # Fetch kubeconfig with auto-discovery
        local kubeconfig_file="${cluster_output_dir}/kubeconfig"
        if ! fetch_kubeconfig_auto "${cluster_name}" "${kubeconfig_file}"; then
            error "Failed to fetch kubeconfig for ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            continue
        fi

        # Test connectivity
        if ! test_cluster_connectivity "${kubeconfig_file}"; then
            error "Failed to connect to cluster ${cluster_name}, skipping"
            failed_clusters+=("${cluster_name}")
            continue
        fi

        # Set kubeconfig for health checks
        export KUBECONFIG="${kubeconfig_file}"

        # Run all health check sections
        local report_file="${cluster_output_dir}/health-check-report.txt"

        {
            echo "================================================================"
            echo "K8s Health Check Report - POST-change"
            echo "Cluster: ${cluster_name}"
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "================================================================"
            echo ""

            # Execute all health check sections
            run_check "01-cluster-overview"
            run_check "02-node-status"
            run_check "03-pod-status"
            run_check "04-workload-status"
            run_check "05-storage-status"
            run_check "06-networking"
            run_check "07-antrea-cni"
            run_check "08-tanzu-vmware"
            run_check "09-security-rbac"
            run_check "10-component-status"
            run_check "11-helm-releases"
            run_check "12-namespaces"
            run_check "13-resource-quotas"
            run_check "14-events"
            run_check "15-connectivity"
            run_check "16-images-audit"
            run_check "17-certificates"
            run_check "18-cluster-summary"

        } > "${report_file}"

        success "Health check completed for ${cluster_name}"

        # Generate comparison report
        local pre_cluster_dir="${pre_results_dir}/${cluster_name}"
        if [[ -d "${pre_cluster_dir}" ]]; then
            local comparison_file="${cluster_output_dir}/comparison-report.txt"
            generate_comparison_report \
                "${pre_cluster_dir}/health-check-report.txt" \
                "${report_file}" \
                "${comparison_file}"
            success "Comparison report generated: ${comparison_file}"
        else
            warning "No PRE-change results found for ${cluster_name}, skipping comparison"
        fi

        ((success_count++))

    done < <(get_cluster_list "${config_file}")

    # Cleanup cache
    cleanup_cluster_cache

    # Summary
    print_header "Execution Summary"
    echo "Total clusters processed: ${cluster_count}"
    echo "Successful: ${success_count}"
    echo "Failed: $((cluster_count - success_count))"

    if [[ ${#failed_clusters[@]} -gt 0 ]]; then
        echo ""
        echo "Failed clusters:"
        for failed_cluster in "${failed_clusters[@]}"; do
            echo "  - ${failed_cluster}"
        done
    fi

    echo ""
    echo "Results directory: ${output_base_dir}"

    # Optional: Copy to Windows
    if [[ -n "${WINDOWS_SCP_ENABLED:-}" ]] && [[ "${WINDOWS_SCP_ENABLED}" == "true" ]]; then
        copy_post_to_windows "${output_base_dir}"
    fi
}

main "$@"
```

## 6. Code Reduction Analysis

### Lines of Code Comparison

| Component | v3.0 Lines | v3.1 Lines | Reduction |
|-----------|------------|------------|-----------|
| lib/config.sh | 120 | 45 | -62% |
| lib/tmc.sh | 85 | 130 | +53% (added discovery) |
| lib/tmc-context.sh | 0 | 145 | +145 (new module) |
| k8s-health-check-pre.sh | 280 | 180 | -36% |
| k8s-health-check-post.sh | 350 | 220 | -37% |
| Removed: multi-cluster-*.sh | 235 | 0 | -100% |
| **Total** | **1070** | **720** | **-33%** |

### Complexity Reduction

**Removed:**
- `--multi` flag handling and validation
- Dual-mode execution logic (single vs multi)
- Manual parsing of `management.provisioner.cluster` format
- Manual TMC context management
- Duplicate code between single/multi scripts

**Added:**
- Auto-discovery of cluster metadata
- Smart TMC context creation
- Cluster naming pattern detection
- Metadata caching

**Net Effect:**
- 33% less code
- 50% fewer user-facing options
- 60% simpler configuration
- 0% loss of functionality

## 7. Implementation Phases

### Phase 1: Create New Modules (2 hours)
1. Create lib/tmc-context.sh with context management
2. Enhance lib/tmc.sh with auto-discovery
3. Simplify lib/config.sh for new format
4. Test each module independently

**Deliverables:**
- lib/tmc-context.sh
- Enhanced lib/tmc.sh
- Simplified lib/config.sh
- Unit test results

### Phase 2: Update Main Scripts (1.5 hours)
1. Simplify k8s-health-check-pre.sh
2. Simplify k8s-health-check-post.sh
3. Remove `--multi` flag handling
4. Update error handling for new flow

**Deliverables:**
- Updated k8s-health-check-pre.sh
- Updated k8s-health-check-post.sh
- Removed obsolete code

### Phase 3: Update Documentation (1 hour)
1. Update K8S-HEALTH-CHECK-README.md
2. Create MIGRATION-GUIDE-V3.1.md
3. Update example clusters.conf
4. Document new environment variables

**Deliverables:**
- Updated README
- Migration guide v3.0 → v3.1
- Example configurations

### Phase 4: Testing (2 hours)
1. Test with prod cluster names
2. Test with uat/system cluster names
3. Test cluster not found scenario
4. Test invalid cluster names
5. Test TMC context creation and reuse
6. Test metadata caching
7. Test full PRE/POST comparison workflow

**Deliverables:**
- Test results document
- Bug fixes (if any)
- Performance metrics

### Phase 5: Cleanup & Finalization (0.5 hours)
1. Remove old multi-cluster scripts
2. Archive v3.0 to backup directory
3. Update version numbers
4. Final code review

**Deliverables:**
- Clean project structure
- Archived v3.0
- v3.1 release

**Total Estimated Effort:** 7 hours

## 8. Testing Strategy

### Test Cases

#### TC1: Production Cluster
```bash
# clusters.conf
prod-workload-01

# Expected:
# - Auto-detect environment: prod
# - Create/use TMC context: tmc-sm-prod
# - Use PROD_DNS endpoint
# - Auto-discover management/provisioner
# - Fetch kubeconfig successfully
# - Run health checks
```

#### TC2: UAT Cluster
```bash
# clusters.conf
uat-system-01

# Expected:
# - Auto-detect environment: nonprod
# - Create/use TMC context: tmc-sm-nonprod
# - Use NON_PROD_DNS endpoint
# - Auto-discover management/provisioner
# - Fetch kubeconfig successfully
# - Run health checks
```

#### TC3: Multiple Clusters
```bash
# clusters.conf
prod-workload-01
prod-workload-02
uat-system-01
dev-workload-01

# Expected:
# - Process all 4 clusters sequentially
# - Create contexts: tmc-sm-prod and tmc-sm-nonprod
# - Cache metadata for reuse
# - Generate 4 individual reports
```

#### TC4: Cluster Not Found
```bash
# clusters.conf
nonexistent-cluster-01

# Expected:
# - Auto-detect environment based on name
# - Create TMC context successfully
# - Fail during auto-discovery with clear error
# - Log warning and skip cluster
# - Continue with remaining clusters (if any)
```

#### TC5: Invalid Cluster Name
```bash
# clusters.conf
invalid-cluster-name

# Expected:
# - Fail environment detection
# - Show error: "Expected naming pattern: *-prod-[1-4], *-uat-[1-4], or *-system-[1-4]"
# - Skip cluster
# - Continue with remaining clusters
```

#### TC6: Metadata Caching
```bash
# First execution - should query TMC
./k8s-health-check-pre.sh clusters.conf

# Second execution in same run - should use cache
# Verify no additional TMC queries

# Expected:
# - First cluster: Query TMC API
# - Subsequent same cluster: Use cached metadata
# - Cache cleared at end of execution
```

#### TC7: TMC Context Reuse
```bash
# First run - creates context
./k8s-health-check-pre.sh clusters.conf

# Second run - reuses existing context
./k8s-health-check-pre.sh clusters.conf

# Expected:
# - First run: Create tmc-sm-prod/nonprod contexts
# - Second run: Detect existing contexts and reuse
# - No duplicate context creation
```

## 9. Migration Path (v3.0 → v3.1)

### Step 1: Backup Current Setup
```bash
cd "d:\Ankur\K8 Health Check"
mkdir -p backup_v3.0
cp -r lib/ backup_v3.0/
cp k8s-health-check-*.sh backup_v3.0/
cp clusters.conf backup_v3.0/
```

### Step 2: Update Configuration File
```bash
# Convert old format to new format
# OLD: prod-workload-01.mgmt-cluster-01.vsphere-tkg
# NEW: prod-workload-01

cat clusters.conf | cut -d'.' -f1 > clusters.conf.new
mv clusters.conf.new clusters.conf
```

### Step 3: Update TMC Endpoint Configuration
```bash
# Edit lib/tmc-context.sh
# Set your actual TMC endpoints:
NON_PROD_DNS="your-nonprod-tmc-url"
PROD_DNS="your-prod-tmc-url"
```

### Step 4: Test New Version
```bash
# Test with single cluster first
echo "prod-workload-01" > test-cluster.conf
./k8s-health-check-pre.sh test-cluster.conf

# Verify output
ls -la health-check-results/pre-*/prod-workload-01/
```

### Step 5: Run Full Migration
```bash
# Run PRE-change with all clusters
./k8s-health-check-pre.sh clusters.conf

# Perform changes...

# Run POST-change with comparison
./k8s-health-check-post.sh clusters.conf ./health-check-results/pre-20250122_143000
```

## 10. Benefits Summary

### For Users
- **60% less configuration effort** - Just cluster names, no need to know management/provisioner
- **Automatic context management** - No manual TMC login required
- **Intelligent environment detection** - Automatically uses correct TMC endpoint
- **Faster execution** - Metadata caching reduces API calls
- **Better error handling** - Clear messages for common issues

### For Maintainers
- **33% less code** - Easier to maintain and debug
- **Single execution path** - No more single vs multi distinction
- **Modular TMC logic** - Easy to swap kubeconfig source in future
- **Better separation of concerns** - Each module has clear responsibility
- **Improved testability** - Smaller, focused functions

### For Operations
- **Consistent execution** - Same command for 1 or 100 clusters
- **Better observability** - Clear progress indicators and error messages
- **Caching for efficiency** - Reduces load on TMC API
- **Flexible authentication** - Environment variables or interactive prompts

## 11. Future Flexibility

The modular design supports future enhancements:

### Alternative Kubeconfig Sources
```bash
# Future: Add lib/kubeconfig-file.sh
# Support reading kubeconfig from local files instead of TMC

# Future: Add lib/kubeconfig-vault.sh
# Support fetching kubeconfig from HashiCorp Vault
```

### Multi-Tenancy Support
```bash
# Future: Add lib/tmc-multi-org.sh
# Support multiple TMC organizations
```

### Cloud Provider Integration
```bash
# Future: Add lib/eks.sh, lib/aks.sh, lib/gke.sh
# Support native cloud provider kubeconfig fetching
```

The isolated TMC logic in lib/tmc.sh and lib/tmc-context.sh makes these future enhancements possible without touching core health check logic.

## 12. Risk Assessment

### Low Risk
- Configuration format change (simple migration)
- TMC context auto-creation (safe, no destructive operations)
- Metadata caching (temp file, auto-cleanup)

### Medium Risk
- Auto-discovery API calls (depends on TMC API availability)
  - **Mitigation:** Graceful error handling, skip failed clusters
- Cluster naming pattern detection (assumes naming convention)
  - **Mitigation:** Clear error messages, validation

### Minimal Risk
- Code reduction (removing duplicate code, not features)
- Module isolation (improves maintainability)

## 13. Success Criteria

### Functional
- ✅ All 18 health check sections execute correctly
- ✅ PRE/POST comparison works with new format
- ✅ TMC context auto-creation succeeds
- ✅ Cluster auto-discovery works for all cluster types
- ✅ Error handling gracefully skips failed clusters

### Non-Functional
- ✅ Execution time ≤ v3.0 (caching should improve)
- ✅ Code reduced by 25-35%
- ✅ Configuration effort reduced by 60%
- ✅ Zero breaking changes to health check output format

### Documentation
- ✅ Complete migration guide v3.0 → v3.1
- ✅ Updated README with new usage examples
- ✅ Clear examples for all use cases

## Conclusion

Version 3.1 represents a significant simplification while maintaining all functionality. The auto-discovery and smart context management remove operational burden from users, while the modular design provides flexibility for future enhancements.

**Recommendation:** Proceed with implementation in the outlined phases, with thorough testing at each step.
