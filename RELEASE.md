# Release Notes

## [4.4] - 2026-02-28

### Health Check Optimization (18 Sections)

- **Section 01**: `kubectl version --short` (removed in K8s 1.28) → `kubectl version -o json | jq`
- **Section 02**: Replaced expensive `kubectl describe nodes` (2× full describe) with single `kubectl get nodes -o json` + jq for conditions and taints
- **Section 03**: Fixed header-line bypass bug in pod status filtering; K8s 1.28+ restart count format (`"3 (1h ago)"` → `gsub`); added OOMKilled detection
- **Section 04**: Fixed DaemonSet awk `$4!=$6` → `$3!=$5` (DESIRED vs READY); fixed ReplicaSet `$3!=$4` → `$3!=$5`; added HPA at-max-replicas detection
- **Section 05**: Single-fetch PV/PVC with proper empty-state; StorageClass default check
- **Section 06**: Replaced noisy full `svc -A` dump with counts-by-type + LB highlights; HTTPProxy valid/invalid signal
- **Section 07**: Removed slow log-tier-count (kubectl logs 1000 lines); replaced with DS DESIRED vs READY
- **Section 08**: PackageInstall failure filtering; TMC pod health signal; cleaned run_check noise
- **Section 09**: PDB disruptionsAllowed=0 detection (`[WARN]`); removed noisy kube-system SA dump
- **Section 10**: Removed `kubectl get cs` (removed in K8s 1.28); added /healthz, CAPI KCP, kube-proxy checks
- **Section 11**: Fixed `helm list --failed` empty-output bug (`|| echo` never fired; now capture-then-check)
- **Section 12**: Terminating namespace detection; replaced double raw dump with summary
- **Section 13**: Fixed `|| echo` fallbacks that never fired on empty ResourceQuota/LimitRange
- **Section 14**: Single JSON fetch (was 2 API calls); events.k8s.io/v1 field fallbacks; fixed empty-state
- **Section 15**: Fixed `SSL_VERIFY:OK` hardcoded false positive in curl format string
- **Section 16**: Fixed undefined `IMAGE_EXCLUSION_PATTERN` bug (was filtering ALL images); replaced YAML grep with jq
- **Section 17**: Added full certificate expiry checking (CRITICAL <7d, WARN <30d); cross-platform date parsing
- **Section 18**: Eliminated double health metrics collection (~22 redundant kubectl calls per cluster)

### Kubernetes Version-Agnostic Cleanup

- Removed all hardcoded K8s version strings from script headers and docs
- Replaced `kubectl version --short` in usage examples (removed in K8s 1.28)
- Fixed kube-proxy DaemonSet awk column bug in Section 10 (`$5/$3` → `$4/$2`)
- Added events API field fallbacks for K8s 1.33+ deprecation path (`lastTimestamp → eventTime`, `involvedObject → regarding`, `message → note`)
- Sort events by `.metadata.creationTimestamp` (works across all K8s versions and both Events APIs)
- **Compatibility**: Kubernetes 1.28–1.35 (all breaking changes handled)

### Files Changed

- All 18 `lib/sections/*.sh` files rewritten
- `k8s-health-check.sh` — header cleanup
- `k8s-cluster-upgrade.sh` — generalized VMware suffix comment
- `k8s-ops-cmd.sh` — replaced `kubectl version --short` in examples
- `CLAUDE.md` — removed version pins
- `README.md`, `README-DEV.md`, `RELEASE.md` — documentation updates

---

## [4.3] - 2026-02-20

### Configuration Refactor

- Renamed `clusters.conf` → `input.conf` (more descriptive filename)
- Added `[credentials]` section to input.conf: store TMC and vSphere credentials in one file
- **Credential priority**: environment variable → input.conf → interactive prompt
- New `load_credentials()` function in `lib/config.sh`, called early in each script's `main()`
- Added `[supervisors]` section for vSphere Supervisor IP/FQDN mapping
- Updated all scripts and documentation to reference new file name

### Key Mappings

| input.conf key | Environment variable |
|----------------|---------------------|
| `TMC_USERNAME` | `TMC_SELF_MANAGED_USERNAME` |
| `TMC_PASSWORD` | `TMC_SELF_MANAGED_PASSWORD` |
| `NONPROD_USERNAME` | `VSPHERE_NONPROD_USERNAME` |
| `NONPROD_PASSWORD` | `VSPHERE_NONPROD_PASSWORD` |

### Files Changed

- `lib/config.sh` — `load_credentials()` + `load_supervisor_map()` functions
- `k8s-health-check.sh`, `k8s-cluster-upgrade.sh`, `k8s-ops-cmd.sh` — call `load_credentials()` early
- `CLAUDE.md`, `README.md`, `README-DEV.md` — documentation updates

---

## [4.2] - 2026-02-12

### New Features ✨

#### Interactive Version Selection for Cluster Upgrades
- **Interactive Version Menu**: Users can now view and select specific Kubernetes versions during cluster upgrades instead of always defaulting to latest
- **TMC Version Query**: Queries available upgrade versions from TMC using `tanzu tmc cluster upgrade available-version CLUSTER_NAME`
- **User-Friendly Display**: Versions shown as numbered menu (newest first) with current version highlighted
- **Selection Options**:
  - Select specific version number (1-N)
  - Choose option 0 for "latest" (traditional behavior)
  - Cancel at any time with 'c'
- **Input Validation**: Retry logic with max 3 attempts for invalid inputs
- **Graceful Fallback**: Automatically falls back to `--latest` if version query fails (network issues, TMC unavailable)
- **Audit Trail**: Target version logged in upgrade logs for compliance and troubleshooting

### How It Works 🔄

**Sequential Mode:**
1. PRE health check runs
2. User confirms upgrade (Y/N)
3. **NEW**: Available versions queried and displayed
4. **NEW**: User selects target version
5. Upgrade executes to selected version
6. Monitoring and POST health check proceed as usual

**Parallel Mode:**
1. **Phase 1 (Sequential)**: PRE health checks + upgrade confirmation + **version selection** for each cluster
2. **Phase 2 (Parallel)**: Upgrades execute in parallel batches using selected versions
3. **Phase 3-5**: Monitoring and POST health checks proceed

### Usage Examples 💡

```bash
# Single cluster upgrade with version selection
./k8s-cluster-upgrade.sh -c prod-workload-01

# Sequential mode - select version for each cluster
./k8s-cluster-upgrade.sh

# Parallel mode - version selection in Phase 1, upgrades in Phase 2
./k8s-cluster-upgrade.sh --parallel --batch-size 3
```

**Example Interactive Prompt:**
```
=== Upgrade Version Selection ===
Cluster: prod-workload-01
Current Version: v1.28.8+vmware.1

Available upgrade versions:
  0) Use latest available version
  1) v1.30.14+vmware.1
  2) v1.29.15+vmware.1
  3) v1.29.14+vmware.1

Select version number (0-3) or 'c' to cancel: 2

Selected version: v1.29.15+vmware.1
```

### Technical Details 🔧

**New Functions in `k8s-cluster-upgrade.sh`:**
- `query_available_versions()` - Queries TMC for available versions, returns sorted list (newest first)
- `prompt_version_selection()` - Displays interactive menu and handles user input with validation

**Modified Functions:**
- `execute_upgrade()` - Now accepts optional 5th parameter `target_version` (defaults to "latest" for backward compatibility)
  - Uses `--latest` flag if target_version is "latest"
  - Uses specific version string if target_version is a version number
- `monitor_and_post_upgrade()` - Added `target_version` parameter for logging in parallel mode

**Enhanced Logging:**
- Upgrade logs now include "Target Version" field
- Parallel mode results display target version in summary (e.g., `[SUCCESS] cluster: v1.28.8 → v1.29.15 (target: v1.29.15, 12 min)`)

### Backward Compatibility ✅

- **Fully backward compatible**: Default parameter ensures existing automation continues to work
- **No breaking changes**: All existing command-line arguments and workflows preserved
- **Graceful degradation**: Falls back to `--latest` if version query fails

### Error Handling 🛡️

| Scenario | Behavior |
|----------|----------|
| TMC query fails | Warning logged, fallback to `--latest`, upgrade continues |
| No versions returned | Warning logged, fallback to `--latest`, upgrade continues |
| User cancels selection | Upgrade aborted for that cluster (exit code 1 in sequential, skip in parallel) |
| Invalid version selected by user | Retry with max 3 attempts, then abort if still invalid |
| Network timeout during query | Caught as query failure, fallback to `--latest` |

### Files Modified 📝

- **Modified**: `k8s-cluster-upgrade.sh` (~100 lines added)
  - Added `query_available_versions()` function (line ~250)
  - Added `prompt_version_selection()` function (line ~290)
  - Modified `execute_upgrade()` to accept target_version parameter (line ~350)
  - Integrated version selection in sequential mode (line ~730)
  - Integrated version selection in parallel mode Phase 1 (line ~1040)
  - Enhanced logging in `monitor_and_post_upgrade()` (line ~900)
- **Updated**: `CLAUDE.md` (added version selection examples)
- **Updated**: `README.md` (added "Interactive Version Selection" section)

### Testing Verified ✅

- ✅ Sequential mode with version selection
- ✅ Parallel mode with version selection
- ✅ Cancellation handling (user presses 'c')
- ✅ Fallback to --latest on query failure
- ✅ Backward compatibility (existing scripts work unchanged)
- ✅ Input validation with retry logic

---

## [4.1] - 2026-02-07

### New Features ✨

#### Portable Output Directory Structure
- **Repository-Agnostic Output Location**: Changed output directory from `~/k8s-health-check/output/` to `<script-dir>/output/` for portability
- **Benefits**:
  - Independent of repository name (works with any project name)
  - Output stays with the toolkit installation
  - Easier to manage multiple installations
- **Centralized Configuration**: Added `OUTPUT_BASE_DIR` constant in `lib/common.sh`
- **All Scripts Updated**: k8s-health-check.sh, k8s-cluster-upgrade.sh, k8s-ops-cmd.sh, lib/tmc.sh

#### Automated vSphere Login (`lib/vsphere-login.sh`)
- **Synchronous vSphere Login**: Automatically logs into Supervisor clusters and Workload clusters using `kubectl vsphere login`, running at the **end** of each script after main operations complete
- **Dual Credential System**:
  - **Supervisor & Prod Workloads**: Uses TMC (AO) credentials (`TMC_SELF_MANAGED_USERNAME`/`TMC_SELF_MANAGED_PASSWORD`)
  - **Non-Prod Workloads**: Uses separate Non-AO credentials (`VSPHERE_NONPROD_USERNAME`/`VSPHERE_NONPROD_PASSWORD`) - prompted interactively if needed
- **Supervisor IP Mapping**: Configurable static mapping of cluster suffixes to Supervisor IP/FQDN in `SUPERVISOR_IP_MAP`
- **Namespace Discovery**: After supervisor login, runs `kubectl get cluster -A` to discover workload cluster namespaces
- **Intelligent Deduplication**: Only one Supervisor login per unique suffix (e.g., prod-1, uat-2)
- **Graceful Degradation**: Skips automatically if `kubectl vsphere` plugin not available

### Integration Points 🔗

**All three main scripts integrated:**
1. **k8s-health-check.sh** - Calls `run_vsphere_login()` at end of `main()`
2. **k8s-cluster-upgrade.sh** - Calls `run_vsphere_login()` after upgrade operations complete
3. **k8s-ops-cmd.sh** - Calls `run_vsphere_login()` at end of `run_ops_command()`

### Configuration Required 🔧

Edit `lib/vsphere-login.sh` lines 16-26 to configure Supervisor cluster IPs/FQDNs:

```bash
declare -A SUPERVISOR_IP_MAP=(
    ["prod-1"]="<supervisor-prod-1-ip-or-fqdn>"
    ["prod-2"]="<supervisor-prod-2-ip-or-fqdn>"
    ["prod-3"]="<supervisor-prod-3-ip-or-fqdn>"
    ["prod-4"]="<supervisor-prod-4-ip-or-fqdn>"
    ["system-1"]="<supervisor-system-1-ip-or-fqdn>"
    ["system-3"]="<supervisor-system-3-ip-or-fqdn>"
    ["uat-2"]="<supervisor-uat-2-ip-or-fqdn>"
    ["uat-4"]="<supervisor-uat-4-ip-or-fqdn>"
)
```

### Environment Variables Added 📋

| Variable | Purpose | Example |
|----------|---------|---------|
| `VSPHERE_NONPROD_USERNAME` | Non-AO username for non-prod clusters | `vsphere_nonprod_user` |
| `VSPHERE_NONPROD_PASSWORD` | Non-AO password for non-prod clusters | (prompted if not set) |

### Usage Examples 💡

```bash
# vSphere login runs automatically at the end of all scripts

# Health check - vSphere login runs after health checks complete
./k8s-health-check.sh --mode pre

# Upgrade - vSphere login runs after upgrade completes
./k8s-cluster-upgrade.sh -c prod-workload-01

# Multi-cluster ops - vSphere login runs after ops command completes
./k8s-ops-cmd.sh "kubectl get nodes"

# Pre-export credentials to avoid interactive prompts
export TMC_SELF_MANAGED_USERNAME='ao-user'
export TMC_SELF_MANAGED_PASSWORD='ao-pass'
export VSPHERE_NONPROD_USERNAME='nonao-user'
export VSPHERE_NONPROD_PASSWORD='nonao-pass'
```

### Console Output 📟

When vSphere login runs at the end, you'll see:

```
=== vSphere Login ===
[vSphere Login] Supervisor prod-1: login successful
[vSphere Login] prod-workload-01: login successful
[vSphere Login] Supervisor uat-2: login successful
[vSphere Login] uat-system-01: login successful

vSphere Login Summary: 4 successful, 0 failed
```

### Files Modified 📝

- **Rewritten**: `lib/vsphere-login.sh` (~280 lines, synchronous architecture)
- **Modified**: `k8s-health-check.sh` (vsphere login at end of main)
- **Modified**: `k8s-cluster-upgrade.sh` (vsphere login after upgrade operations)
- **Modified**: `k8s-ops-cmd.sh` (vsphere login at end of run_ops_command)
- **Updated**: `CLAUDE.md` (documentation on new module)
- **Updated**: `README.md` (added configuration steps, environment variables)

### Backward Compatibility ✅

- All changes are **backward compatible**
- Existing scripts work unchanged (vSphere login is optional enhancement)
- TMC credential flow unchanged (same single prompt per session)
- No breaking changes to any public functions or flags

### Testing Checklist ✓

- ✓ vSphere login runs synchronously at end of each script
- ✓ Credentials prompted upfront before any login attempt
- ✓ Supervisor logins deduplicated (only one per suffix)
- ✓ Namespace discovery via `kubectl get cluster -A` on supervisor
- ✓ Gracefully skips if kubectl vsphere plugin unavailable
- ✓ All three scripts integrate correctly

---

## [3.8] - 2025-12-20

### Improvements 🔄

- Codebase refactoring: ~455 lines removed across all scripts
- Extracted shared upgrade functions into reusable modules
- Data-driven comparison logic for better maintainability
- Fixed POST health check output in parallel mode
- Improved version matching for VMware-versioned releases (e.g., v1.29.1+vmware.1)

### Files Changed

- `k8s-cluster-upgrade.sh` (850 → 650 lines)
- `lib/health.sh` (enhanced metrics collection)
- `lib/comparison.sh` (new data-driven format)

---

## [3.7] - 2025-11-15

### Features 🎯

- **Parallel batch upgrades**: `--parallel --batch-size N` for k8s-cluster-upgrade.sh
- **Single cluster flag**: `-c` flag now works for health-check.sh and k8s-ops-cmd.sh
- **Dynamic timeout calculation**: nodes × 5 minutes per node (customizable with --timeout-multiplier)
- **File retention improvements**: Auto-cleanup keeps 5 most recent files per cluster

### Enhancements 📈

- Improved error messages for missing clusters
- Better handling of long-running operations
- Cache expiry notifications in debug mode

---

## [3.6] - 2025-10-01

### Breaking Changes ⚠️

- **Output directory restructure**: From timestamp-based to per-cluster directories
- Old structure preserved at `./health-check-results/` for backward compatibility

### Features 🎯

- **Consolidated kubeconfig cache**: Single file per cluster (12-hour expiry)
- **Per-cluster organization**: All data for a cluster in one location
- **Automatic cleanup**: Keeps 5 most recent files per type

### Directory Structure

```
~/k8s-health-check/output/
└── cluster-name/
    ├── kubeconfig
    ├── h-c-r/
    │   ├── pre-hcr-YYYYMMDD_HHMMSS.txt
    │   ├── post-hcr-YYYYMMDD_HHMMSS.txt
    │   └── comparison-hcr-YYYYMMDD_HHMMSS.txt
    ├── ops/
    └── upgrade/
```

---

## [3.5] - 2025-08-15

### Features 🎯

- **Management cluster discovery** via `-m` flag
- **Simplified upgrade script**: Delegates health checks to k8s-health-check.sh
- **Standardized 12-hour cache expiry** across all modules
- **Enhanced metadata caching** for faster operations

### Improvements 📈

- Reduced code duplication between scripts
- More predictable cache behavior
- Better TMC context reuse

---

## [3.4] - 2025-07-01

### Features 🎯

- **Parallel batch execution** (default: 6 clusters at a time)
- **Automated cluster upgrades** via TMC
- **Multi-cluster ops command** (k8s-ops-cmd.sh)

### Architecture 🏗️

- Marker-based result collection for safe parallel concatenation
- Sequential TMC context preparation to avoid race conditions
- Per-cluster background worker processes

---

## [3.3] - 2025-05-10

### Features 🎯

- **Unified health check script** with `--mode pre|post` flag
- **Centralized health metrics module** (lib/health.sh)
- **PRE/POST comparison reports** with delta analysis
- **18 comprehensive health check sections**

### Breaking Changes ⚠️

- Separate PRE/POST scripts merged into single script with `--mode` flag
- Old scripts preserved in `Archive/v3.2/` for backward compatibility

---

## [3.2] - 2025-03-01

### Initial Release 🚀

- Separate PRE and POST health check scripts
- Basic TMC integration
- Single-cluster operations only
