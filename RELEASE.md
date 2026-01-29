# K8s Health Check Tool - Release Notes

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
- Keeps output cleaner and more focused on important information

#### 5. Reduced Multi-line Spacing
- Removed excessive blank lines between sections in console output
- Removed extra blank line after each cluster summary
- Cleaner, more compact output

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
