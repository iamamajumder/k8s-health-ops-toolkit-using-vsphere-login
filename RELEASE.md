# K8s Health Check Tool - Release Notes

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
