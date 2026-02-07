# Release Notes

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
- **Background vSphere Login Process**: Automatically logs into Supervisor clusters and Workload clusters using `kubectl vsphere login` as a background process, running parallel to main operations
- **Dual Credential System**:
  - **Supervisor & Prod Workloads**: Uses TMC (AO) credentials (`TMC_SELF_MANAGED_USERNAME`/`TMC_SELF_MANAGED_PASSWORD`)
  - **Non-Prod Workloads**: Uses separate Non-AO credentials (`VSPHERE_NONPROD_USERNAME`/`VSPHERE_NONPROD_PASSWORD`) - prompted interactively if needed
- **Supervisor IP Mapping**: Configurable static mapping of cluster suffixes to Supervisor IP/FQDN in `SUPERVISOR_IP_MAP`
- **Intelligent Deduplication**: Only one Supervisor login per unique suffix (e.g., prod-1, uat-2)
- **Cross-Script Guard**: `VSPHERE_LOGIN_DONE` flag prevents duplicate logins when upgrade script calls health-check as subprocess
- **Graceful Degradation**: Skips automatically if `kubectl vsphere` plugin not available

### Integration Points 🔗

**All three main scripts integrated:**
1. **k8s-health-check.sh**
   - Calls `prepare_tmc_contexts()` for both parallel and sequential modes (previously parallel-only)
   - Starts vSphere login in background after TMC context preparation

2. **k8s-cluster-upgrade.sh**
   - **Single cluster mode**: Prepares TMC context + starts vSphere login before PRE health check
   - **Multi-cluster sequential**: Prepares all contexts + starts vSphere login before cluster loop
   - **Multi-cluster parallel**: Starts vSphere login after context preparation

3. **k8s-ops-cmd.sh**
   - Starts vSphere login after TMC context preparation (works for both management and file-based modes)

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
| `VSPHERE_LOGIN_DONE` | Internal guard flag (set automatically) | (do not set manually) |

### Usage Examples 💡

```bash
# vSphere login happens automatically in background with all scripts

# Health check - vSphere login runs after TMC context prep
./k8s-health-check.sh --mode pre

# Upgrade - vSphere login for single cluster
./k8s-cluster-upgrade.sh -c prod-workload-01

# Multi-cluster ops - vSphere login for all clusters
./k8s-ops-cmd.sh "kubectl get nodes"
```

### Console Output 📟

When vSphere login is running, you'll see console messages like:

```
[vSphere Login] Success login to Supervisor prod-1
[vSphere Login] Success login to prod-workload-01
[vSphere Login] Success login to Supervisor uat-2
[vSphere Login] Success login to uat-system-01
```

### Files Modified 📝

- **New**: `lib/vsphere-login.sh` (~180 lines)
- **Modified**: `k8s-health-check.sh` (added module sourcing, restructured run_health_checks)
- **Modified**: `k8s-cluster-upgrade.sh` (added module sourcing, integrated in all 3 modes)
- **Modified**: `k8s-ops-cmd.sh` (added module sourcing, integrated in run_ops_command)
- **Updated**: `CLAUDE.md` (documentation on new module)
- **Updated**: `README.md` (added configuration steps, environment variables)

### Backward Compatibility ✅

- All changes are **backward compatible**
- Existing scripts work unchanged (vSphere login is optional enhancement)
- TMC credential flow unchanged (same single prompt per session)
- No breaking changes to any public functions or flags

### Testing Checklist ✓

- ✓ vSphere login works in parallel mode
- ✓ vSphere login works in sequential mode
- ✓ Non-prod credentials prompted only once per session
- ✓ Supervisor logins deduplicated (only one per suffix)
- ✓ Cross-script guard prevents duplicate login (upgrade→health-check chain)
- ✓ Gracefully skips if kubectl vsphere plugin unavailable
- ✓ Console output visible during background execution
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
