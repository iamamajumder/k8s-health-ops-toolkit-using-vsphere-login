# TODO List for Tomorrow 🚀

**Project:** K8s Health Check Tool v3.1
**Date Created:** 2026-01-22
**Status:** Ready for Implementation

---

## 1. ✅ Improve TMC Credential Prompting

**Priority:** HIGH
**Estimated Time:** 30 minutes

### Current Issue
Script throws error when TMC username/password environment variables are empty, instead of prompting the user interactively.

### Required Changes

**File:** `lib/tmc-context.sh` (lines 120-134)

**Current Behavior:**
```bash
if [[ -z "${username}" ]] || [[ -z "${password}" ]]; then
    error "Username and password are required for TMC authentication"
    return 1
fi
```

**New Behavior:**
```bash
# Prompt for username if empty
while [[ -z "${username}" ]]; do
    read -r -p "Enter TMC username (AO account): " username
    if [[ -z "${username}" ]]; then
        warning "Username cannot be empty"
    fi
done

# Prompt for password if empty
while [[ -z "${password}" ]]; do
    read -r -s -p "Enter TMC password: " password
    echo ""
    if [[ -z "${password}" ]]; then
        warning "Password cannot be empty"
    fi
done
```

### Testing
```bash
# Test 1: Without environment variables (should prompt)
unset TMC_SELF_MANAGED_USERNAME
unset TMC_SELF_MANAGED_PASSWORD
./k8s-health-check-pre.sh ./clusters.conf

# Test 2: With environment variables (should not prompt)
export TMC_SELF_MANAGED_USERNAME="myuser"
export TMC_SELF_MANAGED_PASSWORD="mypass"
./k8s-health-check-pre.sh ./clusters.conf
```

---

## 2. 🧹 Clean Up Duplicate Outputs in Health Check Modules

**Priority:** HIGH
**Estimated Time:** 2-3 hours (iterative)

### Current Issue
Some health check sections have duplicate, redundant, or overly verbose output that clutters the reports.

### Action Plan

1. **Review all 18 modules** in `lib/sections/*.sh`
2. **Identify issues:**
   - Duplicate information
   - Redundant checks
   - Verbose/unnecessary output
   - Commands that provide no actionable insights

3. **User will provide specific cleanup instructions per module**

### Modules to Review

| # | Module | File | Status |
|---|--------|------|--------|
| 1 | Cluster Overview | 01-cluster-overview.sh | ⏳ Pending review |
| 2 | Node Status | 02-node-status.sh | ⏳ Pending review |
| 3 | Pod Status | 03-pod-status.sh | ⏳ Pending review |
| 4 | Deployment Status | 04-deployment-status.sh | ⏳ Pending review |
| 5 | StatefulSet Status | 05-statefulset-status.sh | ⏳ Pending review |
| 6 | DaemonSet Status | 06-daemonset-status.sh | ⏳ Pending review |
| 7 | Storage | 07-storage.sh | ⏳ Pending review |
| 8 | Network Services | 08-network-services.sh | ⏳ Pending review |
| 9 | Ingress | 09-ingress.sh | ⏳ Pending review |
| 10 | ConfigMaps & Secrets | 10-configmaps-secrets.sh | ⏳ Pending review |
| 11 | Resource Quotas | 11-resource-quotas.sh | ⏳ Pending review |
| 12 | Network Policies | 12-network-policies.sh | ⏳ Pending review |
| 13 | Events | 13-events.sh | ⏳ Pending review |
| 14 | Cluster Add-ons | 14-cluster-addons.sh | ⏳ Pending review |
| 15 | Tanzu Packages | 15-tanzu-packages.sh | ⏳ Pending review |
| 16 | Helm Releases | 16-helm-releases.sh | ⏳ Pending review |
| 17 | Custom Resources | 17-custom-resources.sh | ⏳ Pending review |
| 18 | TMC Status | 18-tmc-status.sh | ⏳ Pending review |

### Process
1. User provides specific instructions per module
2. Implement cleanup for that module
3. Test to ensure functionality is preserved
4. Move to next module

### Questions for User
- Which modules have the most obvious duplicates?
- Any modules that can be combined?
- Any modules that should be removed entirely?
- Preferred level of detail (verbose vs. concise)?

---

## 3. 🔍 Enhance Comparison Logic

**Priority:** MEDIUM
**Estimated Time:** 2-3 hours

### Current Issues
- Comparison report may have false positives
- Difficult to distinguish critical changes from informational ones
- Need better filtering of expected changes during upgrades

### Proposed Improvements

#### A. Better Diff Detection
```bash
# Current: Basic grep and text comparison
# Proposed: Smart diff with context awareness

- Ignore timestamp differences
- Ignore pod restart counts within threshold
- Ignore expected changes during rolling updates
- Highlight only actionable differences
```

#### B. Intelligent Change Categorization
```
[CRITICAL]   - Requires immediate action (nodes down, pods crash-looping)
[WARNING]    - Monitor closely (deployment not ready, pending pods)
[EXPECTED]   - Normal during upgrade (image pulling, pod restarting)
[INFO]       - FYI only (version changed, new pods created)
```

#### C. Context-Aware Filtering
```bash
# If upgrade detected:
- Ignore "Pulling" events
- Ignore "Created" events for new pods
- Ignore version changes (expected)
- Focus on failures and unexpected states
```

#### D. Add Regression Detection
```bash
# Compare:
- PRE: 10/10 pods ready → POST: 8/10 pods ready [CRITICAL]
- PRE: 5 nodes ready    → POST: 4 nodes ready    [CRITICAL]
- PRE: 0 crash loops   → POST: 2 crash loops    [CRITICAL]
```

### Files to Modify
- `lib/comparison.sh` - All comparison functions
- Add new functions for intelligent filtering
- Enhance `generate_summary()` with regression detection

### Questions for User
- What specific comparison issues are you seeing?
- Examples of false positives?
- What changes should be ignored during upgrades?

---

## 4. 🚀 Add Cluster Upgrade Module via TMC

**Priority:** LOW (Future Feature)
**Estimated Time:** 4-6 hours

### Overview
Automate Kubernetes cluster upgrades using TMC API, integrated with pre/post health checks.

### Implementation Plan

#### Phase 1: Research TMC Upgrade Commands
```bash
# Commands to investigate:
tanzu tmc cluster list --help
tanzu tmc cluster get <cluster> -m <mgmt> -p <prov> -o json
tanzu tmc cluster update --help
tanzu tmc kubernetescluster update --help

# Research:
- How to get available upgrade versions
- How to trigger upgrade via TMC
- How to monitor upgrade progress
- Upgrade validation and rollback options
```

#### Phase 2: Create Upgrade Library
**New File:** `lib/upgrade.sh`

```bash
Functions needed:
- get_current_version()        # Get cluster's current K8s version
- list_available_versions()    # Get available upgrade versions
- validate_upgrade_path()      # Check if upgrade is supported
- trigger_upgrade()            # Initiate TMC upgrade
- monitor_upgrade_progress()   # Poll upgrade status
- validate_upgrade_success()   # Verify upgrade completed
```

#### Phase 3: Create Upgrade Script
**New File:** `k8s-cluster-upgrade.sh`

```bash
Workflow:
1. Read cluster list from clusters.conf
2. For each cluster:
   a. Run PRE health check
   b. Check if health check PASSED
   c. Get current version and available upgrades
   d. Prompt user to select target version
   e. Trigger upgrade via TMC
   f. Monitor progress (with timeout)
   g. Run POST health check
   h. Display comparison
   i. Mark upgrade as success/failure
3. Generate upgrade summary report
```

#### Phase 4: Integration
- Integrate with existing health check scripts
- Add upgrade option to main scripts with `--upgrade` flag
- Create rollback mechanism if POST health check fails

### Questions for User
- What TMC commands do you currently use for upgrades?
- Manual upgrade workflow to automate?
- Preferred upgrade strategy (all at once, one-by-one, manual approval)?
- Rollback requirements?

---

## 5. 📊 Multi-Cluster Command Execution Tool

**Priority:** LOW (Future Feature)
**Estimated Time:** 3-4 hours

### Overview
Execute kubectl commands across multiple clusters and aggregate results into reports.

### Use Cases
- **Audit Reports:** Get pod counts, resource usage, RBAC settings across all clusters
- **Configuration Checks:** Verify ingress controllers, cert-manager, monitoring agents
- **Security Scans:** Check for deprecated APIs, insecure configurations
- **Resource Inventory:** List all PVCs, services, ingress rules across clusters

### Implementation Plan

#### Create New Script
**New File:** `k8s-multi-cluster-exec.sh`

```bash
Usage:
  ./k8s-multi-cluster-exec.sh --command "kubectl get pods -A | wc -l"
  ./k8s-multi-cluster-exec.sh --script custom-check.sh
  ./k8s-multi-cluster-exec.sh --command "kubectl get nodes" --output nodes.txt
  ./k8s-multi-cluster-exec.sh --command "kubectl top nodes" --format csv

Options:
  --command <cmd>       Execute kubectl command on all clusters
  --script <file>       Execute custom script on all clusters
  --output <file>       Save results to file (default: stdout)
  --format <fmt>        Output format: table|csv|json (default: table)
  --parallel            Execute on clusters in parallel
  --continue-on-error   Don't stop if one cluster fails
```

#### Features
```bash
1. Auto-discover clusters from clusters.conf
2. Reuse existing kubeconfig fetch logic
3. Execute command on each cluster
4. Aggregate results with cluster name prefix
5. Export to multiple formats (CSV, JSON, table)
6. Parallel execution option for speed
7. Error handling and reporting
```

#### Example Output
```bash
$ ./k8s-multi-cluster-exec.sh --command "kubectl get nodes --no-headers | wc -l"

╔═══════════════════════════════════════════════════════════════╗
║  Multi-Cluster Command Execution                              ║
╚═══════════════════════════════════════════════════════════════╝

Command: kubectl get nodes --no-headers | wc -l
Clusters: 5

┌─────────────────────┬────────┬──────────────┐
│ Cluster             │ Nodes  │ Status       │
├─────────────────────┼────────┼──────────────┤
│ prod-workload-01    │ 12     │ ✓ Success    │
│ prod-workload-02    │ 10     │ ✓ Success    │
│ uat-system-01       │ 5      │ ✓ Success    │
│ uat-system-02       │ 5      │ ✓ Success    │
│ dev-sandbox-01      │ 3      │ ✓ Success    │
└─────────────────────┴────────┴──────────────┘

Total nodes across all clusters: 35
```

### Questions for User
- What common commands do you run across multiple clusters?
- Preferred output format?
- Need for custom report templates?

---

## 6. ⚡ Cache Verification & Optimization

**Priority:** HIGH
**Estimated Time:** 2-3 hours

### Goals
1. Verify current cache is working for cluster metadata
2. Measure performance improvements
3. Extend caching to static data
4. Implement kubeconfig caching with expiry
5. Add cache management commands

---

### A. Verify Current Cache Works

**Current Cache Location:** `/tmp/k8s-health-check-cluster-cache-$$.txt`
**Cache Format:** `cluster-name:management:provisioner`

#### Test Plan
```bash
# Test 1: First run (cache MISS)
rm -f /tmp/k8s-health-check-cluster-cache-*.txt
echo "=== First Run (Cache MISS) ==="
time ./k8s-health-check-pre.sh ./clusters.conf

# Check if cache file was created
ls -lh /tmp/k8s-health-check-cluster-cache-*.txt
cat /tmp/k8s-health-check-cluster-cache-*.txt

# Test 2: Second run (cache HIT)
echo "=== Second Run (Cache HIT) ==="
time ./k8s-health-check-pre.sh ./clusters.conf

# Expected: Second run should be faster (no TMC API call for metadata)
```

#### Metrics to Track
```bash
# Add timing to discover_cluster_metadata function
Operation                    | Run 1 (Cache Miss) | Run 2 (Cache Hit)
-----------------------------|-------------------|------------------
TMC metadata discovery       | 2.5s              | 0.0s
Kubeconfig fetch             | 3.0s              | 3.0s
Total script runtime         | 45s               | 42.5s
```

---

### B. Improve Cache Strategy

#### Current Limitations
1. **Cache is process-specific** (`$$` in filename)
   - Each script run creates new cache
   - Cache not shared between PRE and POST scripts
   - Cache lost after script exits

2. **No expiry mechanism**
   - Cache never expires
   - Stale data if cluster metadata changes

3. **Limited scope**
   - Only caches cluster metadata (management/provisioner)
   - Doesn't cache kubeconfig files

#### Proposed Improvements

##### 1. Persistent Shared Cache
```bash
# Change from:
CLUSTER_METADATA_CACHE="${TMPDIR:-/tmp}/k8s-health-check-cluster-cache-$$.txt"

# To:
CLUSTER_METADATA_CACHE="${HOME}/.k8s-health-check/metadata.cache"
KUBECONFIG_CACHE_DIR="${HOME}/.k8s-health-check/kubeconfigs/"

# Benefits:
- Shared between PRE and POST scripts
- Persists across script runs
- Centralized cache management
```

##### 2. Cache with Timestamps
```bash
# Enhanced cache format:
cluster-name:management:provisioner:timestamp:kubeconfig-path

# Example:
svcs-k8s-1-prod-1:supvr-w11c1-prod-1:prod-1-ns-svcs-1:1674389527:/home/user/.k8s-health-check/kubeconfigs/svcs-k8s-1-prod-1.kubeconfig
```

##### 3. Cache Expiry Logic
```bash
# Configurable expiry times
METADATA_CACHE_EXPIRY=604800    # 7 days (rarely changes)
KUBECONFIG_CACHE_EXPIRY=86400   # 24 hours (expires daily)

# Check cache age before using:
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
```

##### 4. Kubeconfig Caching
```bash
# Cache kubeconfig files to avoid repeated TMC API calls

cache_kubeconfig() {
    local cluster_name="$1"
    local kubeconfig_content="$2"
    local cache_file="${KUBECONFIG_CACHE_DIR}/${cluster_name}.kubeconfig"

    mkdir -p "${KUBECONFIG_CACHE_DIR}"
    echo "${kubeconfig_content}" > "${cache_file}"
    chmod 600 "${cache_file}"  # Secure permissions

    echo "${cache_file}"
}

fetch_kubeconfig_cached() {
    local cluster_name="$1"
    local cache_file="${KUBECONFIG_CACHE_DIR}/${cluster_name}.kubeconfig"

    # Check if cached kubeconfig exists and is < 24h old
    if [[ -f "${cache_file}" ]]; then
        local file_age=$(($(date +%s) - $(stat -c %Y "${cache_file}")))
        if [ $file_age -lt $KUBECONFIG_CACHE_EXPIRY ]; then
            debug "Using cached kubeconfig for ${cluster_name}" >&2
            echo "${cache_file}"
            return 0
        fi
    fi

    # Cache miss or expired - fetch fresh kubeconfig
    fetch_kubeconfig_auto "${cluster_name}" "${cache_file}"
}
```

---

### C. Static Data Cache

**Data that changes rarely (99% static):**
- Management cluster names
- Provisioner names
- TMC endpoint URLs
- Cluster to management/provisioner mappings

#### Implementation

**New File:** `${HOME}/.k8s-health-check/static-mappings.conf`

```bash
# Format: cluster:management:provisioner:last_verified
svcs-k8s-1-prod-1:supvr-w11c1-prod-1:prod-1-ns-svcs-1:1674389527
svcs-k8s-2-prod-1:supvr-w11c1-prod-1:prod-1-ns-svcs-1:1674389527
uat-k8s-1-nonprod-1:supvr-w11c1-nonprod-1:nonprod-1-ns-uat:1674389527

# Cache invalidation:
- Auto-refresh if > 30 days old
- Manual refresh: ./k8s-health-check-pre.sh --refresh-cache
- Manual edit: nano ~/.k8s-health-check/static-mappings.conf
```

#### Lookup Strategy
```bash
discover_cluster_metadata() {
    local cluster_name="$1"

    # 1. Check static mappings file (fastest)
    if metadata=$(lookup_static_mapping "${cluster_name}"); then
        debug "Found in static mappings" >&2
        echo "${metadata}"
        return 0
    fi

    # 2. Check runtime cache (session-based)
    if metadata=$(lookup_runtime_cache "${cluster_name}"); then
        debug "Found in runtime cache" >&2
        echo "${metadata}"
        return 0
    fi

    # 3. Query TMC API (slowest, but always accurate)
    if metadata=$(query_tmc_api "${cluster_name}"); then
        # Cache for future use
        cache_metadata "${cluster_name}" "${metadata}"
        echo "${metadata}"
        return 0
    fi

    return 1
}
```

---

### D. Cache Management Commands

Add command-line flags for cache management:

```bash
# View cache status
./k8s-health-check-pre.sh --cache-status

Output:
╔═══════════════════════════════════════════════════════════════╗
║  Cache Status                                                 ║
╚═══════════════════════════════════════════════════════════════╝

Metadata Cache: /home/user/.k8s-health-check/metadata.cache
  - Entries: 5
  - Size: 1.2 KB
  - Last updated: 2026-01-22 13:45:00
  - Status: ✓ Valid

Kubeconfig Cache: /home/user/.k8s-health-check/kubeconfigs/
  - Cached configs: 5
  - Total size: 25 KB
  - Oldest: svcs-k8s-1-prod-1.kubeconfig (6 hours old)
  - Status: ✓ Valid

Static Mappings: /home/user/.k8s-health-check/static-mappings.conf
  - Entries: 10
  - Last verified: 2026-01-15
  - Status: ⚠ Should refresh soon (>7 days old)

# Clear all caches
./k8s-health-check-pre.sh --clear-cache

# Refresh metadata cache
./k8s-health-check-pre.sh --refresh-cache

# Clear kubeconfig cache only
./k8s-health-check-pre.sh --clear-kubeconfigs
```

---

### E. Performance Metrics

Add performance tracking to measure cache effectiveness:

**New File:** `lib/performance.sh`

```bash
# Track operation timing
track_operation_time() {
    local operation="$1"
    local start_time="$2"
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))  # milliseconds

    echo "${operation}: ${duration}ms" >> "${HOME}/.k8s-health-check/performance.log"
}

# Generate performance report
generate_performance_report() {
    cat << EOF
╔═══════════════════════════════════════════════════════════════╗
║  Performance Report                                           ║
╚═══════════════════════════════════════════════════════════════╝

Operation Breakdown:
  TMC Context Creation:     850ms
  Metadata Discovery:       0ms (cached)
  Kubeconfig Fetch:         0ms (cached)
  Health Check Execution:   38s
  Report Generation:        2s
  ----------------------------------------
  Total Runtime:            41s

Cache Effectiveness:
  Metadata Cache Hits:      5/5 (100%)
  Kubeconfig Cache Hits:    5/5 (100%)
  Time Saved by Caching:    ~15s
EOF
}
```

---

### Implementation Priority

**Phase 1 (Today/Tomorrow):**
1. ✅ Verify current cache works
2. ✅ Measure baseline performance
3. 🔄 Move cache to persistent location
4. 🔄 Add cache expiry logic

**Phase 2 (This Week):**
5. Add kubeconfig caching
6. Implement static mappings file
7. Add cache management commands

**Phase 3 (Future):**
8. Add performance tracking
9. Optimize cache lookup strategy
10. Add cache monitoring/reporting

---

### Questions for User

1. **Cache Expiry Times:**
   - Metadata cache: 7 days? 30 days? Manual refresh only?
   - Kubeconfig cache: 24 hours? 12 hours? Never cache?

2. **Cache Location:**
   - OK to use `~/.k8s-health-check/` directory?
   - Or prefer different location?

3. **Static Mappings:**
   - Should we create this file automatically after first discovery?
   - Or user maintains it manually?

4. **Performance Tracking:**
   - Should we log performance metrics by default?
   - Or only with `--track-performance` flag?

---

## Priority Order for Tomorrow

### Morning (High Priority)
1. **#1: Fix TMC credential prompting** ⏱ 30 min
   - Quick, high impact improvement
   - Test with/without env variables

2. **#6A: Verify cache works** ⏱ 30 min
   - Test cache hit/miss scenarios
   - Measure actual performance gains
   - Document findings

### Afternoon (Medium Priority)
3. **#6B: Improve cache strategy** ⏱ 2 hours
   - Move to persistent location
   - Add expiry logic
   - Implement kubeconfig caching

4. **#2: Start module cleanup** ⏱ 1-2 hours
   - Review first 5 modules
   - Get user feedback on cleanup approach
   - Implement approved changes

### Evening (Documentation)
5. **Document changes** ⏱ 30 min
   - Update README with new cache behavior
   - Document new command-line flags
   - Update troubleshooting section

---

## Notes & Reminders

- **Commit frequently** - Each major change should be a separate commit
- **Test after each change** - Don't accumulate untested changes
- **Update README** - Keep documentation in sync with code
- **Ask for clarification** - Better to ask than assume

---

## Questions to Ask User Tomorrow Morning

Before starting work, clarify these points:

### For Task #2 (Module Cleanup):
- Which modules have the most obvious duplicates?
- Can you provide 1-2 examples of what you consider "duplicate output"?
- Preferred level of detail: verbose (current) or concise?
- Any modules that should be combined or removed?

### For Task #3 (Comparison Logic):
- What specific issues are you seeing in comparison reports?
- Examples of false positives?
- What changes should be ignored during upgrades?

### For Task #6 (Caching):
- Acceptable cache expiry time for metadata? (7 days, 30 days, never?)
- Should kubeconfig files be cached? If yes, for how long?
- OK to create `~/.k8s-health-check/` directory for persistent cache?
- Should performance metrics be logged by default or opt-in?

---

## Success Criteria

By end of tomorrow, we should have:

- ✅ Interactive TMC credential prompting working
- ✅ Cache verification complete with performance metrics
- ✅ Enhanced cache implementation with persistent storage
- ✅ At least 5 modules cleaned up (if user provides feedback)
- ✅ All changes committed to Git with clear commit messages
- ✅ Updated documentation

---

**Created by:** Claude Code
**Last Updated:** 2026-01-22
**Status:** Ready for Implementation 🚀
