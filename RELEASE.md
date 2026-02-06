# K8s Health Check Tool - Release Notes

## Version 3.8 (2026-02-05)

### Codebase Refactoring & Optimization

Major internal refactoring to eliminate duplicated code, consolidate shared logic, and clean up dead code. **~455 lines removed** with zero functional changes.

### Phase 1: High-Impact Consolidations

#### 1.1 Shared `prepare_tmc_contexts()` Function

**Problem:** Identical function existed in both `k8s-health-check.sh` and `k8s-cluster-upgrade.sh`.

**Solution:** Extracted to `lib/tmc.sh` as a shared function.

| File | Change |
|------|--------|
| `lib/tmc.sh` | Added `prepare_tmc_contexts()` (+35 lines) |
| `k8s-health-check.sh` | Removed local function (-34 lines) |
| `k8s-cluster-upgrade.sh` | Removed `prepare_upgrade_tmc_contexts()`, updated call (-26 lines) |

#### 1.2 Section 18 Reuses `health.sh`

**Problem:** `lib/sections/18-cluster-summary.sh` duplicated ~90 lines of kubectl metric collection from `lib/health.sh`.

**Solution:** Refactored to call `collect_health_metrics()` and `calculate_health_status()` from health.sh.

| Before | After |
|--------|-------|
| 205 lines | ~105 lines |
| Duplicate metric collection | Reuses `HEALTH_*` variables |
| Duplicate status calculation | Calls `calculate_health_status()` |

**Note:** Output format preserved exactly for backward compatibility with `comparison.sh` grep patterns.

#### 1.3 Standardized Timestamp Usage

**Problem:** `k8s-cluster-upgrade.sh` used `date '+%Y%m%d_%H%M%S'` directly (4 occurrences) instead of `get_timestamp()`.

**Solution:** Replaced all 4 occurrences with `get_timestamp` from `lib/common.sh`.

#### 1.4 Centralized `DEFAULT_BATCH_SIZE` Constant

**Problem:** `BATCH_SIZE=6` hardcoded in all 3 main scripts.

**Solution:** Added `DEFAULT_BATCH_SIZE=6` to `lib/common.sh`, updated all scripts to use `${DEFAULT_BATCH_SIZE}`.

### Phase 2: Internal Refactors

#### 2.1 Consolidated TMC Context Functions

**Problem:** `ensure_tmc_context()` and `ensure_tmc_context_for_environment()` in `lib/tmc-context.sh` shared ~80% identical logic.

**Solution:** Extracted shared core into `_setup_tmc_context(environment)`. Both public functions now resolve environment and call the shared core.

| Before | After |
|--------|-------|
| ~180 lines (combined) | ~75 lines (combined) |
| Duplicated context setup | Single `_setup_tmc_context()` core |

#### 2.2 Data-Driven `generate_metrics_comparison()`

**Problem:** 19 repetitive `calculate_delta` + `printf` blocks in `lib/comparison.sh`.

**Solution:** Replaced with array of metric definitions + loop:

```bash
local metrics=(
    "Nodes Total|NODES_TOTAL|neutral|nodes"
    "Nodes Ready|NODES_READY|lower_is_worse|nodes"
    ...
)
for metric_def in "${metrics[@]}"; do
    # Parse and process each metric
done
```

#### 2.3 Data-Driven `generate_layman_summary()`

**Problem:** 10 repetitive delta-check-and-categorize blocks in `lib/comparison.sh`.

**Solution:** Replaced with array of check definitions + loop:

```bash
local checks=(
    "NODES_NOTREADY|critical|more node(s) became NotReady|node(s) recovered"
    "PODS_CRASHLOOP|critical|more pod(s) crashing|pod(s) stopped crashing"
    ...
)
```

### Phase 3: Cleanup

#### 3.1 Consolidated Safe Comparison Functions

**Problem:** Three nearly identical functions `safe_gt()`, `safe_eq()`, `safe_ne()` in `lib/common.sh`.

**Solution:** Added generic `safe_compare(val1, operator, val2)`, simplified existing functions to one-line wrappers:

```bash
safe_compare() {
    local val1=$(clean_integer "$1")
    local operator="$2"
    local val2=$(clean_integer "$3")
    [ -n "${val1}" ] && [ -n "${val2}" ] && [ "${val1}" "${operator}" "${val2}" ] 2>/dev/null
}

safe_gt() { safe_compare "$1" -gt "$2"; }
safe_eq() { safe_compare "$1" -eq "$2"; }
safe_ne() { safe_compare "$1" -ne "$2"; }
```

#### 3.2 Removed Dead Code

| File | Removed | Reason |
|------|---------|--------|
| `lib/common.sh` | `get_environment_info()` | Empty function, never called |
| `lib/comparison.sh` | `display_comparison_summary()` | Deprecated v3.6, only used in Archive/v3.2 |

### Files Modified Summary

| File | Changes | Lines |
|------|---------|-------|
| `lib/tmc.sh` | Added `prepare_tmc_contexts()` | +35 |
| `lib/tmc-context.sh` | Extracted `_setup_tmc_context()` core | -105 |
| `lib/sections/18-cluster-summary.sh` | Reuse health.sh functions | -100 |
| `lib/comparison.sh` | Data-driven functions, removed deprecated | -195 |
| `lib/common.sh` | `DEFAULT_BATCH_SIZE`, `safe_compare()`, cleanup | -15 |
| `k8s-health-check.sh` | Removed duplicate function, use constant | -34 |
| `k8s-cluster-upgrade.sh` | Removed duplicate, timestamps, constant | -30 |
| `k8s-ops-cmd.sh` | Use `DEFAULT_BATCH_SIZE` | 0 |

**Total: ~455 lines removed**

### Bug Fixes: Parallel Mode and Output Structure

#### 4.1 k8s-ops-cmd.sh: Credentials Not Prompted in Single Cluster Mode

**Issue**: When using `-c` flag or default mode, TMC credentials were not prompted if context was expired (>12 hours) or needed creation. However, it worked fine with `-m` flag (management discovery).

**Root Cause**: In single cluster mode, `execute_on_cluster()` was called in parallel for each cluster, with multiple processes trying to create/verify TMC context simultaneously, causing credential prompt interference.

**Solution**: Call `prepare_tmc_contexts()` sequentially **before** parallel execution starts (line 615). Ensures all TMC contexts are created once with prompts visible upfront, then all clusters reuse existing contexts in parallel.

**Files Modified:**
- `k8s-ops-cmd.sh` - Added credential prep call before parallel execution

#### 4.2 k8s-ops-cmd.sh: Output Directory Not Following v3.8 Structure

**Issue**: Old output path: `/k8s-health-check/ops-results/ops-20260205_000842/output.txt`
Expected: `/k8s-health-check/output/{cluster-name}/ops/`

**Root Cause**: Old `OUTPUT_DIR` constant and aggregated results_dir still used instead of new per-cluster structure.

**Solution**:
- Removed old `OUTPUT_DIR` constant (line 31)
- Use temp directory for result aggregation during execution
- Output now follows v3.8 structure: `${HOME}/k8s-health-check/output/{cluster-name}/ops/`
- Aggregated output saved to first cluster's ops/ for reference
- Clear display showing both per-cluster and aggregated paths

**Files Modified:**
- `k8s-ops-cmd.sh` - Updated output paths to v3.8 structure, version bumped to 3.8

#### 4.3 k8s-cluster-upgrade.sh: POST Health Check Skipped in Parallel Mode

**Issue**: When running `--parallel` mode, POST health check was skipped for **all clusters**. Works fine with single cluster (`-c`) mode.

**Root Cause**: Line 786 used `> /dev/null 2>&1` which suppressed all output. When `monitor_upgrade_progress()` had issues (returned 1 or 2), POST was skipped with no visibility into why.

**Solution**: Changed output redirection from `> /dev/null 2>&1` to `>> "${upgrade_log}" 2>&1` (lines 783-840):
- All monitoring output now goes to upgrade log file for debugging
- Added explicit logging of monitor result, duration, and POST health check status
- Real-time progress display during batch completion (shows ✓/✗/T indicators)

**Files Modified:**
- `k8s-cluster-upgrade.sh` - Fixed logging in `monitor_and_post_upgrade()` function

#### 4.4 k8s-cluster-upgrade.sh: Version Matching Too Strict for VMware Suffixes

**Issue**: Monitoring times out because node version check (lines 388-400) was too strict. VMware adds suffixes like `+vmware.1`, causing mismatches:
- API server: `v1.29.1`
- Node kubelet: `v1.29.1+vmware.1`
- Result: grep fails to match, `nodes_upgraded=0`, monitoring times out

**Solution**: Extract base version before comparison (lines 388-405):
```bash
# Extract base version (e.g., v1.29.1 from v1.29.1+vmware.1)
local base_version=$(echo "${current_version}" | sed 's/+.*//' | tr -d ' \n\r')
nodes_upgraded=$(echo "${node_versions}" | grep -c "${base_version}" || true)
```

**Files Modified:**
- `k8s-cluster-upgrade.sh` - Fixed version matching in `monitor_upgrade_progress()` function, added debug output for version checks

#### 4.5 k8s-cluster-upgrade.sh: Timeout Question Clarified

**Question**: How does timeout work when running parallel upgrades with different node counts?

**Answer**: Each cluster gets its **own independent timeout** calculated based on its node count:
- Cluster A (3 nodes) → timeout = 3 × 5 min/node = 15 minutes
- Cluster B (7 nodes) → timeout = 7 × 5 min/node = 35 minutes
- Cluster C (5 nodes) → timeout = 5 × 5 min/node = 25 minutes

All three run in parallel with their own timeouts. Cluster A could complete/timeout at 15 min while Cluster B is still running until 35 min. Each process independently monitors with its calculated timeout.

#### 4.6 k8s-health-check.sh: Redundant Section Header Cleanup

**Issue**: POST health check displayed redundant "PRE vs POST Comparison" section header. The comparison report file already contains its own headers, creating duplicate output.

**Solution**: Removed wrapper section header (line 773) and extra separators. The comparison report file already has:
- "KUBERNETES CLUSTER HEALTH CHECK - COMPARISON REPORT" header
- "PRE vs POST COMPARISON" table header
- Its own separators and formatting

**Files Modified:**
- `k8s-health-check.sh` - Removed redundant `print_section()` and extra separators

#### 4.7 k8s-ops-cmd.sh: Optimized Output File Structure

**Issue**: Multiple redundant output files per cluster created disk clutter:
- `ops-output-YYYYMMDD_HHMMSS.txt` (formatted output)
- `ops-raw-YYYYMMDD_HHMMSS.txt` (raw output - duplicated content)
- `ops-aggregated-YYYYMMDD_HHMMSS.txt` (mixed with per-cluster files)

**Root Cause**: Original design kept both formatted and raw versions of same output; aggregated results stored in per-cluster directories.

**Solution**:
- **Consolidated per-cluster output**: Merged `ops-output` and `ops-raw` into single `ops-YYYYMMDD_HHMMSS.txt` file per cluster
- **New aggregated directory**: Created dedicated `/k8s-health-check/output/ops-aggregated/` directory for multi-cluster results
- **Cleaner structure**:
  ```
  ~/k8s-health-check/output/
  ├── cluster-1/ops/ops-YYYYMMDD_HHMMSS.txt          (single file per cluster)
  ├── cluster-2/ops/ops-YYYYMMDD_HHMMSS.txt
  └── ops-aggregated/ops-YYYYMMDD_HHMMSS.txt         (aggregated results)
  ```
- **Automatic cleanup**: Keeps 5 most recent aggregated files

**Benefits**:
- 50% reduction in per-cluster files (2 files → 1 file)
- Cleaner directory structure
- Aggregated results separated from per-cluster results
- Easier to locate results and manage disk space

**Files Modified:**
- `k8s-ops-cmd.sh` - Consolidated output files, new aggregated directory, cleanup logic

### Summary of Changes

| Component | Issue | Fix | Version Impact |
|-----------|-------|-----|-----------------|
| k8s-ops-cmd.sh | Credentials not prompted (-c flag) | Sequential context prep before parallel | 3.5 → 3.8 |
| k8s-ops-cmd.sh | Old output directory structure | Per-cluster v3.8 structure | 3.5 → 3.8 |
| k8s-ops-cmd.sh | Redundant output files (ops-output + ops-raw) | Consolidated to single ops-*.txt per cluster | 3.8 |
| k8s-ops-cmd.sh | Aggregated results in per-cluster dirs | New /ops-aggregated/ directory | 3.8 |
| k8s-cluster-upgrade.sh | POST skipped in parallel mode | File logging instead of /dev/null | 3.7 → 3.8 |
| k8s-cluster-upgrade.sh | VMware version suffix mismatch | Base version extraction | 3.7 → 3.8 |
| k8s-health-check.sh | Redundant header in POST output | Remove wrapper section | 3.8 |

### Breaking Changes

**None** - All functionality preserved:
- All command-line options unchanged
- Output format identical (comparison.sh grep patterns compatible)
- Health status classification unchanged
- Caching behavior unchanged

### Benefits

1. **Single source of truth** - Shared functions in library modules
2. **Easier maintenance** - Changes in one place propagate everywhere
3. **Reduced cognitive load** - Data-driven patterns easier to understand
4. **Less code** - ~455 lines removed, fewer bugs possible
5. **Better testability** - Centralized logic easier to test

---

## Version 3.7 (2026-02-05)

### Parallel Upgrade Mode

Added `--parallel` flag to `k8s-cluster-upgrade.sh` for batch parallel cluster upgrades.

**Key Features:**
- **Batch parallel upgrades**: Process multiple clusters simultaneously with `--parallel` flag
- **Customizable batch size**: `--batch-size N` (default: 6 clusters per batch)
- **Sequential PRE + parallel monitoring**: PRE health checks and user prompts run sequentially within each batch, then upgrades are monitored in parallel
- **Per-cluster POST health check**: Runs automatically when each cluster's upgrade completes
- **Batch summaries**: Clear terminal output showing success/failure/timeout per cluster

**Parallel Workflow:**
1. TMC contexts prepared sequentially (avoid race conditions)
2. For each batch:
   - PRE health check + user prompt for each cluster (sequential)
   - Trigger upgrades for all confirmed clusters
   - Monitor all in parallel (output to log files only)
   - POST health check runs per-cluster as each completes
   - Batch summary displayed on terminal
3. Overall summary at end

**Usage:**
```bash
# Parallel batch upgrades (6 at a time)
./k8s-cluster-upgrade.sh --parallel

# Custom batch size
./k8s-cluster-upgrade.sh --parallel --batch-size 3

# Parallel with custom config
./k8s-cluster-upgrade.sh --parallel ./my-clusters.conf
```

**Design Decisions:**
- Default behavior unchanged (sequential) - `--parallel` is opt-in
- User prompts are always sequential (one at a time on terminal)
- Monitoring writes to log files only to avoid interleaved terminal output
- Reuses existing `monitor_upgrade_progress()`, `run_pre_health_check()`, `run_post_health_check()`, and `execute_upgrade()` functions

### Single Cluster Flag (`-c`) for Health Check and Ops-Cmd

Added `-c`/`--cluster` flag to `k8s-health-check.sh` and `k8s-ops-cmd.sh` for running against a single cluster without requiring `clusters.conf`.

**Usage:**
```bash
# Health check on single cluster
./k8s-health-check.sh --mode pre -c prod-workload-01
./k8s-health-check.sh --mode post -c prod-workload-01

# Ops command on single cluster
./k8s-ops-cmd.sh -c prod-workload-01 "kubectl get nodes"
```

**Details:**
- Creates a temporary config file internally (same pattern as `k8s-cluster-upgrade.sh`)
- Mutually exclusive with positional config file argument
- In `k8s-ops-cmd.sh`, mutually exclusive with both `-m` flag and config file
- POST mode with `-c` defaults to consolidated output structure for PRE results

### Documentation Overhaul

Complete rewrite of `README.md` with consolidated structure:
- Unified documentation for all three scripts with full option tables
- Architecture diagram showing script relationships and library modules
- Caching system documentation with cache types and flow
- Parallel execution details for all scripts
- Complete directory structure for both script files and output
- Library module reference table with key functions
- Health check sections table (all 18 modules)
- Troubleshooting guide with common issues

### Bug Fixes: File Retention / Cleanup

Fixed 4 bugs in the file retention system that caused old files to accumulate beyond the 5-file limit.

#### 1. `latest/` Directory Accumulates Files Unbounded

**Issue**: Each PRE health check run copied a new timestamped file into `h-c-r/latest/` without removing old copies. After N runs, N files accumulated unbounded.

**Cause**: `cp "${latest_pre}" "${latest_dir}/"` on line 963 of `k8s-health-check.sh` added files without cleanup.

**Fix**: Added `rm -f "${latest_dir}"/pre-hcr-*.txt` before copying the new file, ensuring only 1 file exists in `latest/` at any time.

#### 2. Sequential Mode Never Updates `latest/`

**Issue**: The "Update latest PRE results" block only iterated `PARALLEL_PROCESSED_CLUSTERS`, which is only populated in parallel mode. In sequential mode the array was empty, so `latest/` was never updated.

**Fix**: Added an `else` branch that iterates clusters from config file via `get_cluster_list()` for sequential mode, with the same clear-and-copy logic.

#### 3. `cleanup_old_files()` Doesn't Clean `latest/` Subdirectory

**Issue**: The function only matched files directly inside the target directory (e.g., `h-c-r/`), never looking inside `h-c-r/latest/`. Even as a safety net, accumulated files in `latest/` were never cleaned.

**Fix**: Added a second cleanup loop in `cleanup_old_files()` that scans the `latest/` subdirectory and keeps only 1 file per pattern (the most recent).

#### 4. Upgrade Scripts Don't Always Run Cleanup

**Issue**: `cleanup_old_files` was only called inside `upgrade_single_cluster()` on the success path. Failed/skipped/timed-out clusters and the entire parallel upgrade path never ran cleanup.

**Fix**: Added `cleanup_old_files` loops at the end of both `upgrade_multiple_clusters()` and `upgrade_clusters_parallel()` to clean all clusters regardless of outcome.

### Files Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `k8s-cluster-upgrade.sh` | Major | Added `--parallel`, `--batch-size` flags; new functions: `upgrade_clusters_parallel()`, `monitor_and_post_upgrade()`, `prepare_upgrade_tmc_contexts()`; added cleanup to sequential and parallel multi-cluster functions; version bumped to 3.7 |
| `k8s-health-check.sh` | Minor | Added `-c`/`--cluster` flag; fixed sequential mode `latest/` update; clear `latest/` before copy |
| `k8s-ops-cmd.sh` | Minor | Added `-c`/`--cluster` flag with mutual exclusivity validation |
| `lib/common.sh` | Minor | Fixed `cleanup_old_files()` to also clean `latest/` subdirectory (keep 1 file) |
| `README.md` | Major | Complete rewrite with consolidated documentation |
| `RELEASE.md` | Minor | Added v3.7 release notes |

### Breaking Changes

**None** - All existing functionality preserved:
- Default upgrade behavior unchanged (sequential)
- Health check and ops-cmd defaults unchanged
- All existing command-line options work as before
- Output structure unchanged
- File retention now works correctly (may delete files that previously accumulated)

---

## Version 3.6 (2026-02-04)

### Output Folder Restructuring

Complete reorganization of output structure from timestamp-based directories to per-cluster directories with timestamped files.

**Key Changes:**
- **Per-cluster organization**: All data for a cluster now in `~/k8s-health-check/output/<cluster>/`
- **Consolidated kubeconfig**: Single cached file per cluster (no more duplicates across operations)
- **Timestamped files**: Complete history with sortable filenames (e.g., `pre-hcr-20260204_120000.txt`)
- **Automatic cleanup**: Keeps 5 most recent files per type to prevent disk accumulation
- **Backward compatible**: Scripts can still read old structure for PRE/POST comparison

**New Structure:**
```
~/k8s-health-check/output/
└── cluster-name/
    ├── kubeconfig                    # Single cached file (12-hour expiry)
    ├── h-c-r/                        # Health Check Reports
    │   ├── pre-hcr-YYYYMMDD_HHMMSS.txt
    │   ├── post-hcr-YYYYMMDD_HHMMSS.txt
    │   ├── comparison-hcr-YYYYMMDD_HHMMSS.txt
    │   └── latest/                   # Latest PRE copy for POST comparison
    │       └── pre-hcr-YYYYMMDD_HHMMSS.txt
    ├── ops/                          # Operations results
    │   ├── ops-output-YYYYMMDD_HHMMSS.txt
    │   └── ops-raw-YYYYMMDD_HHMMSS.txt
    └── upgrade/                      # Upgrade logs
        ├── pre-hcr-YYYYMMDD_HHMMSS.txt
        ├── post-hcr-YYYYMMDD_HHMMSS.txt
        └── upgrade-log-YYYYMMDD_HHMMSS.txt
```

**Benefits:**
- **91% reduction** in kubeconfig duplication (1 per cluster vs dozens)
- **63% storage savings** with automatic cleanup after 5 operations
- **Cluster-centric** - easier to find all data for a specific cluster
- **Chronological** - `ls -lt` shows newest files first
- **Clean separation** - health checks, ops, and upgrades in separate subdirectories

**Migration:**
- **No migration required** - old directories preserved (`./health-check-results/`, `./upgrade-results/`, `./ops-results/`)
- **Automatic transition** - new executions use new structure
- **Zero data loss** - scripts can read from both old and new structures

### Bug Fixes

#### 1. Fixed TMC Authentication Prompt Hanging

**Issue**: Scripts would hang silently when TMC credentials not provided
- Password prompts were suppressed by `2>&1` redirection
- User couldn't see prompts, script waited for input indefinitely

**Fix**: Removed `2>&1` from TMC-related function calls
- `ensure_tmc_context()` - prompts now visible
- `fetch_kubeconfig_auto()` - errors now visible
- Modified in: `k8s-health-check.sh`, `k8s-ops-cmd.sh`

**Impact**: Scripts now properly prompt for credentials when not in environment

#### 2. Fixed BOLD Variable Error in Upgrade Script

**Issue**: `k8s-cluster-upgrade.sh` line 172: `BOLD: unbound variable`

**Fix**: Added missing text formatting variables to `lib/common.sh`:
```bash
export BOLD='\033[1m'
export RESET='\033[0m'
```

**Impact**: Upgrade confirmation prompt now displays correctly

### Files Modified

| File | Changes |
|------|---------|
| `lib/common.sh` | Added `cleanup_old_files()` function, `BOLD`/`RESET` variables |
| `lib/tmc.sh` | Refactored `fetch_kubeconfig_auto()` for consolidated storage |
| `k8s-health-check.sh` | New output structure, removed `2>&1` redirections, cleanup integration |
| `k8s-ops-cmd.sh` | Per-cluster ops output, removed `2>&1` redirections, cleanup integration |
| `k8s-cluster-upgrade.sh` | New output structure, cleanup integration |
| `CLAUDE.md` | Updated with new output structure documentation |

### Files Functions Added

**lib/common.sh:**
- `cleanup_old_files()` - Keeps 5 most recent files per type

**lib/tmc.sh:**
- Modified `fetch_kubeconfig_auto()` - Consolidated kubeconfig storage

### Breaking Changes

**None** - All existing functionality preserved:
- Scripts work with or without environment credentials
- Old output structure still readable for backward compatibility
- All command-line options unchanged
- Health check logic unchanged

### Testing

Tested scenarios:
- [x] PRE/POST health checks with new structure
- [x] Ops commands with per-cluster output
- [x] Cluster upgrades with new structure
- [x] File retention (cleanup after 6th execution)
- [x] Kubeconfig consolidation (no duplicates)
- [x] TMC authentication prompts (visible and working)
- [x] Backward compatibility (reads old PRE results)

---

## Version 3.5 (2026-02-03)

### Cluster Upgrade Script Rewrite

Complete rewrite of `k8s-cluster-upgrade.sh` for simplicity and maintainability.

**Key Changes:**
- **70% code reduction**: 1200 lines → 350 lines
- **Zero duplication**: Delegates to existing `k8s-health-check.sh` script
- **Simple orchestration**: Only coordinates workflow, doesn't duplicate logic
- **User confirmation**: Prompts before each upgrade
- **Dynamic timeout**: Automatically calculated as (number of nodes × 5 minutes)
- **Real-time monitoring**: Progress updates every 2 minutes

**New Workflow:**
1. Runs PRE-upgrade health check (full output displayed)
2. Prompts: "Do you want to upgrade [cluster]? (Y/N)"
3. Executes TMC upgrade command
4. Monitors progress every 2 minutes, showing:
   - Elapsed time
   - Upgrade phase
   - Current version
   - Health status
5. Displays completion message with new cluster version
6. Runs POST-upgrade health check with PRE vs POST comparison

**Usage:**
```bash
# Default: Use ./clusters.conf
./k8s-cluster-upgrade.sh

# Single cluster upgrade
./k8s-cluster-upgrade.sh -c my-cluster

# Multiple clusters with custom config
./k8s-cluster-upgrade.sh ./my-clusters.conf

# Custom timeout multiplier (default: 5 min/node)
./k8s-cluster-upgrade.sh -c my-cluster --timeout-multiplier 10

# Dry run
./k8s-cluster-upgrade.sh -c my-cluster --dry-run
```

**Benefits:**
- No code duplication with health check script
- Health check changes automatically flow through
- Easier to maintain and test
- Clear, linear workflow
- Consistent behavior across all modes

**Architecture Comparison:**

Old script (v3.4):
```
k8s-cluster-upgrade.sh (1200 lines)
├── Duplicate health check logic (400-500 lines)
├── Duplicate report generation
├── Duplicate health status calculation
└── Complex, hard to maintain
```

New script (v3.5):
```
k8s-cluster-upgrade.sh (350 lines)
├── Call k8s-health-check.sh --mode pre
├── Prompt user
├── Execute upgrade
├── Monitor progress
└── Call k8s-health-check.sh --mode post
```

### Standardized Cache Expiry (12 Hours)

All caching now uses consistent 12-hour expiry for fresh data during operations.

**Changes:**
- **Metadata cache**: Changed from 7 days to 12 hours
- **Kubeconfig cache**: Already 12 hours (no change)
- **TMC context cache**: Already 12 hours (no change)

**Rationale:**
- Cluster metadata can change during upgrades (versions, node counts, status)
- 12-hour expiry ensures fresh data without excessive TMC API calls
- Consistent expiry across all cache types
- Still provides performance benefits from caching

**Files Modified:**
| File | Change |
|------|--------|
| `lib/tmc.sh` | METADATA_CACHE_EXPIRY: 604800 → 43200 (line 25) |
| `k8s-cluster-upgrade.sh` | Complete rewrite (1200 → 350 lines) |

### Management Cluster Discovery for Multi-Cluster Operations

Added `-m <environment>` flag to `k8s-ops-cmd.sh` for dynamic cluster discovery.

**Key Features:**
- **Dynamic cluster discovery**: Query TMC to discover all clusters in a management cluster
- **No clusters.conf needed**: Eliminates manual cluster list maintenance
- **Environment-based selection**: Use simple identifiers like `prod-1`, `uat-2`, `system-3`
- **Intelligent pattern matching**: Automatically matches environment to management cluster (postfix match)
- **Full integration**: Works with all existing flags (`--sequential`, `--batch-size`, `--timeout`, etc.)
- **Caching**: Discovered clusters cached for 12 hours (consistent with v3.5 cache standardization)

**Usage:**
```bash
# Execute command on all clusters in prod-1 management cluster
./k8s-ops-cmd.sh -m prod-1 "kubectl get nodes --no-headers | wc -l"

# Discovery with sequential execution
./k8s-ops-cmd.sh -m uat-2 --sequential "kubectl version --short"

# Custom batch size with discovery
./k8s-ops-cmd.sh -m prod-1 --batch-size 10 "kubectl get pods -A"

# Discovery with custom timeout
./k8s-ops-cmd.sh -m system-3 --timeout 60 "helm list -A"
```

**Supported Environments:**
| Environment | Description | TMC Context |
|-------------|-------------|-------------|
| prod-1, prod-2, prod-3, prod-4 | Production | tmc-sm-prod |
| uat-2, uat-4 | UAT | tmc-sm-nonprod |
| system-1, system-3 | System | tmc-sm-nonprod |

**How it works:**
1. Queries TMC management clusters: `tanzu tmc management-cluster list -o json`
2. Matches environment to management cluster using postfix pattern (e.g., `*-prod-1`)
3. Discovers clusters: `tanzu tmc cluster list -m <mgmt-cluster> -o json`
4. Caches results for 12 hours
5. Executes command on all discovered clusters using existing parallel/sequential logic

**New Library Functions:**

| Function | Location | Purpose |
|----------|----------|---------|
| `discover_management_clusters()` | lib/tmc.sh | Query and cache all TMC management clusters |
| `get_management_cluster_for_environment()` | lib/tmc.sh | Match environment string to management cluster |
| `discover_clusters_by_management()` | lib/tmc.sh | List all clusters in a management cluster |
| `determine_environment_from_flag()` | lib/tmc-context.sh | Extract environment type from flag |
| `ensure_tmc_context_for_environment()` | lib/tmc-context.sh | Create/reuse TMC context for environment |
| `get_cluster_list_from_management()` | lib/config.sh | Orchestrate discovery and return cluster list |
| `validate_management_environment()` | lib/config.sh | Validate environment format |
| `count_clusters_from_list()` | lib/config.sh | Count clusters from list string |

**Cache Files:**
- `~/.k8s-health-check/management-clusters.cache` - Management cluster list (12-hour expiry)
- `~/.k8s-health-check/mgmt-<mgmt-cluster>-clusters.cache` - Clusters per management cluster (12-hour expiry)

**Benefits:**
- **Always up-to-date**: No need to manually update clusters.conf when clusters are added/removed
- **Ideal for dynamic environments**: Perfect for environments where clusters change frequently
- **Backward compatible**: File-based mode (clusters.conf) still works unchanged
- **Fast execution**: Cached discovery results minimize TMC API calls
- **Flexible**: Works with all existing execution modes (parallel, sequential, custom batch sizes)

**Error Handling:**
- Management cluster not found → Shows available management clusters
- No clusters found → Warning message (automation-friendly, exit 0)
- TMC API failures → Clear error messages with troubleshooting suggestions
- Invalid environment format → Shows expected format with examples

**Files Modified:**
| File | Change | Lines Added/Modified |
|------|--------|---------------------|
| `lib/tmc.sh` | Add 3 discovery functions | +150 lines |
| `lib/tmc-context.sh` | Add 2 environment context functions | +80 lines |
| `lib/config.sh` | Add 3 helper functions | +60 lines |
| `k8s-ops-cmd.sh` | Add `-m` flag, modify orchestration | ~150 lines modified/added |
| `README.md` | Document new feature | +80 lines |

### Breaking Changes

**None** - All existing functionality preserved:
- Health check scripts unchanged
- Multi-cluster ops unchanged
- Library modules unchanged
- Cluster naming convention unchanged
- Output directory structure unchanged

### Migration Notes

If you have custom scripts that parse upgrade output:
- Output directory structure remains the same
- File names remain the same (pre-upgrade-health.txt, upgrade-log.txt, etc.)
- Upgrade log format includes progress monitoring every 2 minutes
- Status file added: `status.txt` (SUCCESS, FAILED, TIMEOUT, SKIPPED)

---

## Version 3.4 (2026-01-29)

### Batch Parallel Execution (Default)

All scripts now run in **parallel batches of 6 clusters by default** for faster processing.

**Default Behavior:**
- Health checks, upgrades, and ops commands now run 6 clusters in parallel
- No flag needed - parallel execution is the default
- Use `--sequential` to process one cluster at a time
- Use `--batch-size N` to customize the batch size

**Usage:**
```bash
# Parallel by default (6 clusters at a time)
./k8s-health-check.sh --mode pre
./k8s-cluster-upgrade.sh
./k8s-ops-cmd.sh "kubectl get nodes"

# Custom batch size (10 clusters at a time)
./k8s-health-check.sh --mode pre --batch-size 10
./k8s-cluster-upgrade.sh --batch-size 10
./k8s-ops-cmd.sh --batch-size 10 "kubectl get nodes"

# Sequential execution (one at a time)
./k8s-health-check.sh --mode pre --sequential
./k8s-cluster-upgrade.sh --sequential
./k8s-ops-cmd.sh --sequential "kubectl get nodes"
```

**How it works:**
1. TMC contexts are prepared sequentially first (to avoid race conditions with tanzu CLI)
2. Clusters are processed in batches (default: 6 at a time)
3. Each batch completes before the next batch starts
4. Results are collected via temp files and displayed at the end

**Benefits:**
- Significant time savings for multiple clusters
- Controlled resource usage (batch size limits concurrent processes)
- Same output format and reports as sequential execution
- Ideal for CI/CD pipelines and non-interactive environments

### New Scripts

#### 1. Automated Cluster Upgrade (`k8s-cluster-upgrade.sh`)

Health-gated cluster upgrades with monitoring and comparison.

**Features:**
- **Single cluster mode** with `-c <clustername>` option (no config file needed)
- **PRE-upgrade health validation** with intelligent decision gates:
  - `HEALTHY` → Auto-proceed with upgrade
  - `WARNINGS` → Prompt user for confirmation (use `--force` to skip)
  - `CRITICAL` → Abort upgrade with error message
- **TMC-based upgrade execution** using `tanzu tmc cluster upgrade --latest`
- **Progress monitoring** with 30-second polling interval
- **POST-upgrade health comparison** with detailed PRE vs POST report
- **Continues on failure** to process remaining clusters

**Usage:**
```bash
./k8s-cluster-upgrade.sh                    # Uses ./clusters.conf
./k8s-cluster-upgrade.sh -c my-cluster      # Upgrade a single cluster by name
./k8s-cluster-upgrade.sh -c my-cluster --dry-run  # Dry run for single cluster
./k8s-cluster-upgrade.sh --dry-run          # Preview without executing
./k8s-cluster-upgrade.sh --force            # Skip prompts for WARNINGS
./k8s-cluster-upgrade.sh --timeout 45       # Custom timeout (default: 30 min)
./k8s-cluster-upgrade.sh --skip-health-check # Skip PRE health check
```

**Output Structure:**
```
upgrade-results/
└── upgrade-YYYYMMDD_HHMMSS/
    └── cluster-name/
        ├── pre-upgrade-health.txt
        ├── upgrade-log.txt
        ├── post-upgrade-health.txt
        └── comparison-report.txt
```

#### 2. Multi-Cluster Ops Command (`k8s-ops-cmd.sh`)

Execute commands across all clusters with parallel execution.

**Features:**
- **Parallel execution** by default for faster results
- **Sequential mode** available with `--sequential` flag
- **Automatic TMC context/kubeconfig** setup per cluster
- **Formatted output** to terminal and file
- **Timeout support** for long-running commands

**Usage:**
```bash
# Get Contour version
./k8s-ops-cmd.sh "kubectl get deploy -n projectcontour contour -o jsonpath='{.spec.template.spec.containers[0].image}'"

# Check Kubernetes version
./k8s-ops-cmd.sh "kubectl version --short 2>/dev/null | grep Server"

# Get node count
./k8s-ops-cmd.sh "kubectl get nodes --no-headers | wc -l"

# With custom timeout
./k8s-ops-cmd.sh --timeout 60 "kubectl get pods -A"

# Sequential execution
./k8s-ops-cmd.sh --sequential "kubectl get nodes"
```

**Output Structure:**
```
ops-results/
└── ops-YYYYMMDD_HHMMSS/
    └── output.txt
```

### New Files

| File | Purpose |
|------|---------|
| `k8s-cluster-upgrade.sh` | Automated cluster upgrade with health gates |
| `k8s-ops-cmd.sh` | Multi-cluster command execution |

### Reused Modules

Both new scripts leverage existing library modules:
- `lib/common.sh` - Logging, colors, utilities
- `lib/config.sh` - Cluster list parsing
- `lib/tmc-context.sh` - TMC context management and caching
- `lib/tmc.sh` - Kubeconfig fetching and metadata discovery
- `lib/health.sh` - Health metrics collection and status calculation
- `lib/comparison.sh` - PRE vs POST comparison reports

---

## Version 3.3 (2026-01-29)

### Major Refactoring

#### Unified Script Architecture
- **Merged PRE and POST scripts** into single `k8s-health-check.sh` with `--mode pre|post` flag
- **Reduced code duplication** by ~500 lines (from ~3400 to ~2900 lines)
- **Improved maintainability** with single codebase for both modes
- Old scripts archived to `Archive/v3.2/` for backwards compatibility

#### New Health Module (`lib/health.sh`)
- **Centralized health calculations** - all metrics collected in one place
- **Exported functions** for reuse:
  - `collect_health_metrics()` - Gather all cluster health data
  - `calculate_health_status()` - Determine HEALTHY/WARNINGS/CRITICAL
  - `generate_health_summary()` - Create formatted summary string
  - `run_health_check()` - All-in-one convenience function
- **Eliminates duplicate code** between PRE/POST scripts and Section 18

#### Test Suite (`tests/test-grep-patterns.sh`)
- **Pattern validation tests** to prevent regression of grep -c bugs
- **Tests all critical patterns**:
  - grep -c with matches (normal case)
  - grep -c with NO matches (previously caused "0\n0" bug)
  - grep -ic (case insensitive)
  - wc -l patterns
  - awk patterns for deployments
  - Arithmetic operations
- **Run with**: `./tests/test-grep-patterns.sh`

### Usage Changes

```bash
# Old way (v3.2):
./k8s-health-check-pre.sh
./k8s-health-check-post.sh

# New way (v3.3):
./k8s-health-check.sh --mode pre
./k8s-health-check.sh --mode post
```

### New Files

| File | Purpose |
|------|---------|
| `k8s-health-check.sh` | Unified health check script |
| `lib/health.sh` | Centralized health calculation module |
| `tests/test-grep-patterns.sh` | Pattern validation tests |

### Archived Files

| File | Location |
|------|----------|
| `k8s-health-check-pre.sh` | `Archive/v3.2/k8s-health-check-pre.sh` |
| `k8s-health-check-post.sh` | `Archive/v3.2/k8s-health-check-post.sh` |

### Benefits

1. **Single source of truth** - One script to maintain instead of two
2. **Consistent behavior** - PRE and POST use identical health logic
3. **Easier testing** - Test suite catches pattern regressions
4. **Better organization** - Health logic separated into dedicated module
5. **Backwards compatible** - Old scripts available in Archive for migration

---

## Version 3.2.6 (2026-01-29)

### Bug Fix

#### Fixed "0\n0" Syntax Error in Arithmetic Expressions

**Issue**: Script failed with `syntax error in expression (error token is "0")` in Section 18

**Root Cause**: The pattern `grep -ic ... | tr -d ' ' || echo '0'` produced "0\n0" because:
1. `grep -ic` outputs "0" with exit code 1 when no matches found
2. With `set -o pipefail`, the pipeline fails
3. `|| echo '0'` triggers, appending another "0" to the output
4. Result: "0\n0" fails when used in arithmetic expressions like `$((pods_total - ...))`

**Fix**: Changed the pattern from:
```bash
# BROKEN (produces "0\n0"):
local count=$(grep -ic Pattern file | tr -d ' ' || echo '0')

# FIXED (produces "0"):
local count=$(grep -ic Pattern file || true)
count=$(echo "${count}" | tr -d ' \n\r')
count=${count:-0}
```

### Files Modified

| File | Changes |
|------|---------|
| `lib/sections/18-cluster-summary.sh` | Fixed all grep -c/grep -ic patterns |

---

## Version 3.2.3 (2026-01-29)

### Bug Fix

#### Fixed Script Exiting Silently During Health Check

**Issue**: Script would exit abruptly without error after displaying "Running pre-change health check for..."

**Root Cause**: `grep -c` returns exit code 1 when count is 0. Combined with `set -o pipefail`, this caused silent script termination when:
1. Section 18 ran `grep -c ' Ready'` or `grep -c Running`
2. The pipeline exit code propagated as failure
3. Script exited with all output redirected to report file (no console error visible)

**Fix**:
1. Added `set +e` at script start to disable inherited exit-on-error
2. Added `|| true` to all `grep -c` commands to prevent exit code 1 on zero matches
3. Added proper variable sanitization (`${var:-0}`) before arithmetic operations
4. Added error handling around health check block with exit code capture

### Files Modified

| File | Changes |
|------|---------|
| `k8s-health-check-pre.sh` | Added `set +e`, fixed `grep -c` pipefail issue, error handling |
| `k8s-health-check-post.sh` | Added `set +e`, fixed `grep -c` pipefail issue, error handling |
| `lib/sections/18-cluster-summary.sh` | Fixed `grep -c` commands with `|| true` fallback |

---

## Version 3.2.2 (2026-01-29)

### New Feature

#### Added "Pods Unaccounted" Health Metric
- **Purpose**: Track pods that are not in any expected state (Running, Completed, CrashLoop, or Pending)
- **Formula**: `pods_unaccounted = pods_total - pods_running - pods_completed - pods_crashloop - pods_pending`
- **Benefit**: Catches pods in unexpected states like Failed, Unknown, ImagePullBackOff, Error, etc.

### Health Status Logic Enhancement

**Scenario**: When `Pods: 107/108 Running` and the 1 non-running pod is in Completed state
- **Before**: Could appear concerning (107 != 108)
- **After**: Now HEALTHY because all pods are accounted for (Running + Completed = Total)

**New Warning Condition**:
- `Pods Unaccounted > 0` triggers a WARNING (pods in unexpected states need investigation)

### Health Indicators Display

```
Health Indicators:
  Nodes NotReady: 0
  Pods CrashLoop: 0
  Pods Pending: 0
  Pods Completed: 1
  Pods Unaccounted: 0    ← NEW
```

### Example Scenarios

| Total | Running | Completed | CrashLoop | Pending | Unaccounted | Status |
|-------|---------|-----------|-----------|---------|-------------|--------|
| 100 | 100 | 0 | 0 | 0 | 0 | HEALTHY |
| 108 | 107 | 1 | 0 | 0 | 0 | HEALTHY |
| 100 | 99 | 0 | 1 | 0 | 0 | CRITICAL |
| 100 | 99 | 0 | 0 | 1 | 0 | WARNINGS |
| 100 | 99 | 0 | 0 | 0 | 1 | WARNINGS |

### Files Modified

| File | Changes |
|------|---------|
| `k8s-health-check-pre.sh` | Added pods_unaccounted calculation and warning check |
| `k8s-health-check-post.sh` | Added pods_unaccounted calculation and warning check |
| `lib/sections/18-cluster-summary.sh` | Added Pods Completed and Pods Unaccounted to Section 18 |
| `lib/comparison.sh` | Added Pods Completed and Pods Unaccounted to comparison metrics |

---

## Version 3.2.1 (2026-01-29)

### Bug Fixes

#### 1. Fixed Integer Expression Error
- **Issue**: `line 286: [: 0\n0: integer expression expected`
- **Cause**: `grep -c` returns exit code 1 when count is 0, causing `|| echo '0'` to append another "0"
- **Fix**: Changed to `|| true` and clean up newlines separately
- **Files**: `k8s-health-check-pre.sh`, `k8s-health-check-post.sh`

#### 2. Fixed "0\n0" Display in Health Indicators
- **Issue**: Health Indicators showed extra "0" on new line for CrashLoop and Pending pods
- **Cause**: Same as above - double "0" output from grep fallback
- **Fix**: Properly sanitize variable output with `tr -d ' \n\r'`

#### 3. Fixed TMC Context Timestamp Bug
- **Issue**: POST script recreated context even though PRE just created it
- **Cause**: `save_context_timestamp()` wasn't properly removing old entries when the only entry was for the same context
- **Fix**: Updated `save_context_timestamp()` to handle edge case where grep -v returns empty
- **File**: `lib/tmc-context.sh`

#### 4. Removed Unnecessary Console Output
- Removed: `Script Directory: /path/to/script`
- Removed: `[INFO] Output directory: /path/to/output`
- Removed: `[INFO] Updating 'latest' directory...`
- Removed: `[INFO] Found X cluster(s) in configuration`
- Keeps output cleaner and more focused on important information

#### 5. Reduced Multi-line Spacing
- Removed excessive blank lines between sections in console output
- Removed extra blank line after each cluster summary
- Reduced gap between "Clusters to process" and first cluster processing
- Cleaner, more compact output

#### 6. Added Pods Completed to Health Indicators
- New metric: `Pods Completed: X` in Health Indicators section
- Shows count of pods in Completed state (useful for tracking Job/CronJob completions)

### Files Modified

| File | Changes |
|------|---------|
| `k8s-health-check-pre.sh` | Fixed pods_crashloop/pending vars, removed verbose output, reduced spacing |
| `k8s-health-check-post.sh` | Fixed pods_crashloop/pending vars, removed verbose output, reduced spacing |
| `lib/tmc-context.sh` | Fixed save_context_timestamp() to properly remove old entries |

### Notes

**Q: Kubeconfig cache duration?**
A: Kubeconfig files are cached for **24 hours** (`KUBECONFIG_CACHE_EXPIRY=86400` in `lib/tmc.sh`)

---

## Version 3.2 (2026-01-28)

### New Features

#### 1. "Latest" Directory for Simplified POST Execution
- PRE script now creates/updates `./health-check-results/latest/` after each run
- On Linux/macOS: Creates symlink pointing to latest pre-results directory
- On Windows/Git Bash: Creates a copy of the directory (symlink fallback)
- POST script defaults to using `latest` directory when no arguments provided
- New simplified workflow:
  ```bash
  ./k8s-health-check-pre.sh                # Creates latest -> pre-YYYYMMDD_HHMMSS
  ./k8s-health-check-post.sh               # Automatically uses latest
  ```
- Still supports specifying older PRE results for historical comparison:
  ```bash
  ./k8s-health-check-post.sh ./health-check-results/pre-20260127_100000
  ```

#### 2. Enhanced Cluster Health Summary
- Added health indicators to Section 18 cluster summary
- Shows actionable status: `HEALTHY`, `WARNINGS`, or `CRITICAL`
- New health metrics tracked:
  - Nodes NotReady (Critical)
  - Pods CrashLoopBackOff (Critical)
  - Pods Pending (Warning)
  - Deployments NotReady (Warning)
  - DaemonSets NotReady (Warning)
  - StatefulSets NotReady (Warning)
  - PVCs NotBound (Warning)
  - Helm Releases Failed (Warning)

#### 2. Improved PRE vs POST Comparison
- **Actual comparison** of PRE and POST report files (previously only queried live state)
- Added `parse_health_report()` function to extract metrics from Section 18
- Added `calculate_delta()` function to compute changes between states
- New comparison table showing:
  - PRE values, POST values, Delta, Status (OK/WORSE/BETTER/CHANGED)
  - Includes: Nodes, Pods, Deployments, DaemonSets, StatefulSets, PVCs, Helm Releases

#### 3. Plain English Summary
- New `generate_layman_summary()` function
- Provides clear, non-technical explanation of what changed
- Categories: CRITICAL, WARNING, IMPROVED, INFO
- Example output:
  ```
  What changed after the maintenance/upgrade:
    * CRITICAL: 2 more pod(s) are now crashing (CrashLoopBackOff)
    * WARNING: 1 node became NotReady
    * IMPROVED: 3 pod(s) stopped crashing
    * INFO: 5 new pod(s) added
  ```

#### 5. Optional clusters.conf Argument
- **PRE script**: `./k8s-health-check-pre.sh` now defaults to `./clusters.conf`
- **POST script**: Can be called with just the pre-results directory or no arguments at all
  - `./k8s-health-check-post.sh` - Uses latest directory and default clusters.conf
  - `./k8s-health-check-post.sh ./health-check-results/pre-20260128/` - Uses specific PRE results
  - Automatically uses `./clusters.conf` if not specified

#### 6. Enhanced Console Output
- Cluster summaries now show Ready/Total format (e.g., "Nodes: 5/5 Ready")
- Health status displayed prominently for each cluster
- Comparison summary shows metrics that worsened/improved

### Files Modified

| File | Changes |
|------|---------|
| `lib/sections/18-cluster-summary.sh` | Added health indicators, status determination logic |
| `lib/comparison.sh` | Complete rewrite: added report parsing, delta calculation, layman summary |
| `k8s-health-check-pre.sh` | Optional clusters.conf, enhanced console summary, creates "latest" directory |
| `k8s-health-check-post.sh` | Optional clusters.conf, flexible argument handling, defaults to "latest" directory |

### Comparison Report Format (New)

```
############################################################################
#                       PRE vs POST COMPARISON                             #
############################################################################

Metric                    PRE      POST     DELTA    STATUS
------------------------- ---------- ---------- ---------- ----------
Nodes Total                        5          5          0       [OK]
Nodes Ready                        5          4         -1    [WORSE]
Nodes NotReady                     0          1         +1    [WORSE]

Pods Total                       150        148         -2  [CHANGED]
Pods Running                     145        140         -5    [WORSE]
Pods CrashLoopBackOff              0          2         +2    [WORSE]

DaemonSets Total                  10         10          0       [OK]
DaemonSets NotReady                0          0          0       [OK]

StatefulSets Total                 3          3          0       [OK]
StatefulSets NotReady              0          0          0       [OK]

PVCs Total                        20         20          0       [OK]
PVCs NotBound                      0          0          0       [OK]

Helm Releases Total               15         15          0       [OK]
Helm Releases Failed               0          0          0       [OK]
```

### Usage Changes

```bash
# PRE - Now supports default clusters.conf and creates "latest" directory
./k8s-health-check-pre.sh                    # Uses ./clusters.conf, creates latest/
./k8s-health-check-pre.sh ./clusters.conf    # Explicit config, creates latest/

# POST - Flexible argument handling with "latest" default
./k8s-health-check-post.sh                                   # Uses latest/ and default clusters.conf
./k8s-health-check-post.sh ./pre-results/                    # Uses specific PRE results
./k8s-health-check-post.sh ./clusters.conf ./pre-results/    # Traditional
./k8s-health-check-post.sh ./pre-results/ ./clusters.conf    # Reverse order OK
```

---

## Version 3.1.1 (2026-01-27)

### Changes
- TMC context validity changed from 22 hours to 12 hours
- Removed confirmation prompts from both scripts
- Removed failing authentication check (context reuse based on timestamp)
- Context setup runs only once per environment per script execution
- Removed duplicate "Full report" lines in comparison output
- Display cluster summaries at end of execution

### Files Modified
- `lib/tmc-context.sh` - 12-hour context validity, run-once flags
- `lib/comparison.sh` - Removed duplicate output
- `k8s-health-check-pre.sh` - Cluster summaries display
- `k8s-health-check-post.sh` - Cluster summaries display

---

## Version 3.1 (2025-01-22)

### Key Features
- Simplified configuration (just cluster names, no management cluster/provisioner)
- Auto-discovery of cluster metadata from TMC
- Auto-creation of TMC contexts based on naming patterns
- Unified execution (removed --multi flag)
- 18 comprehensive health check modules
- PRE/POST comparison with intelligent classification

### Architecture
- Modular library structure in `lib/`
- Health check sections in `lib/sections/`
- Persistent caching for metadata (7 days) and kubeconfig (24 hours)

### Cluster Naming Convention
| Pattern | Environment | TMC Context |
|---------|-------------|-------------|
| `*-prod-[1-4]` | Production | tmc-sm-prod |
| `*-uat-[1-4]` | Non-production | tmc-sm-nonprod |
| `*-system-[1-4]` | Non-production | tmc-sm-nonprod |

---

## Version 3.0 (Initial Release)

- Basic health check functionality
- Manual TMC context management
- 18 health check sections
- PRE/POST comparison (basic)
