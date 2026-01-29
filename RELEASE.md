# K8s Health Check Tool - Release Notes

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
