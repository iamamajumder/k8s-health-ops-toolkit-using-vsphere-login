# Kubernetes Cluster Health Check Tool

**Version 3.3** - Unified Script with TMC Auto-Discovery and PRE/POST Comparison

---

## What's New in v3.3

- **Unified Script**: Merged PRE and POST scripts into single `k8s-health-check.sh` with `--mode` flag
- **Centralized Health Logic**: New `lib/health.sh` module for all health calculations
- **Test Suite**: Added `tests/test-grep-patterns.sh` for pattern validation
- **Reduced Code Duplication**: ~500 fewer lines of code to maintain
- **Legacy Scripts**: Old scripts moved to `Archive/v3.2/` for backwards compatibility

---

## Requirements

### Prerequisites

| Requirement | Description | Verification |
|-------------|-------------|--------------|
| **Tanzu CLI** | VMware Tanzu CLI with TMC plugin | `tanzu version` |
| **kubectl** | Kubernetes command-line tool | `kubectl version --client` |
| **jq** | JSON processor for parsing | `jq --version` |
| **Bash** | Bash shell (v4.0+) | `bash --version` |
| **TMC Access** | TMC Self-Managed credentials | Valid username/password |

### Installation

```bash
# Verify all prerequisites
tanzu version
kubectl version --client
jq --version

# Install jq if missing:
# Ubuntu/Debian: sudo apt-get install jq
# RHEL/CentOS:   sudo yum install jq
# macOS:         brew install jq
# Windows:       choco install jq
```

### Cluster Naming Convention (Required)

Your clusters MUST follow these naming patterns:

| Pattern | Environment | TMC Context |
|---------|-------------|-------------|
| `*-prod-[1-4]` | Production | tmc-sm-prod |
| `*-uat-[1-4]` | Non-production | tmc-sm-nonprod |
| `*-system-[1-4]` | Non-production | tmc-sm-nonprod |

**Examples:**
- `workload-prod-01` → Production
- `app-uat-02` → Non-production
- `dev-system-01` → Non-production

### Configuration (One-Time Setup)

**1. Set TMC Endpoints** - Edit `lib/tmc-context.sh`:
```bash
NON_PROD_DNS="your-nonprod-tmc.example.com"  # Line 7
PROD_DNS="your-prod-tmc.example.com"          # Line 8
```

**2. Create clusters.conf** - List your cluster names:
```bash
# clusters.conf
prod-workload-01
prod-workload-02
uat-system-01
dev-system-01
```

---

## Execution

### Quick Start (v3.3 Unified Script)

```bash
# Make script executable
chmod +x k8s-health-check.sh

# Run PRE-change health check (before maintenance)
./k8s-health-check.sh --mode pre

# Perform your maintenance/upgrade...

# Run POST-change health check (after maintenance)
./k8s-health-check.sh --mode post
```

### PRE-Change Health Check

```bash
# Using default ./clusters.conf
./k8s-health-check.sh --mode pre

# Using specific config file
./k8s-health-check.sh --mode pre ./my-clusters.conf

# With debug output
DEBUG=on ./k8s-health-check.sh --mode pre

# With credentials in environment (no prompts)
TMC_SELF_MANAGED_USERNAME=myuser \
TMC_SELF_MANAGED_PASSWORD=mypass \
./k8s-health-check.sh --mode pre
```

### POST-Change Health Check

```bash
# Simplest: Use latest PRE results (recommended for recent PRE runs)
./k8s-health-check.sh --mode post

# Using specific PRE results directory
./k8s-health-check.sh --mode post ./health-check-results/pre-20260128_120000

# Using specific config file and PRE results
./k8s-health-check.sh --mode post ./clusters.conf ./health-check-results/pre-20260128_120000

# With debug output
DEBUG=on ./k8s-health-check.sh --mode post
```

### Cache Management

```bash
# View cache status
./k8s-health-check.sh --cache-status

# Clear all cached data
./k8s-health-check.sh --clear-cache
```

### Running Tests

```bash
# Run grep pattern validation tests
./tests/test-grep-patterns.sh
```

### Legacy Scripts (v3.2 Compatibility)

The old separate PRE/POST scripts are still available for backwards compatibility:

```bash
# Located in Archive/v3.2/
./Archive/v3.2/k8s-health-check-pre.sh
./Archive/v3.2/k8s-health-check-post.sh
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `TMC_SELF_MANAGED_USERNAME` | TMC username | No (prompts if not set) |
| `TMC_SELF_MANAGED_PASSWORD` | TMC password | No (prompts if not set) |
| `DEBUG` | Enable verbose output (`on`/`off`) | No |
| `WINDOWS_SCP_ENABLED` | Enable Windows SCP transfer (`true`/`false`) | No |
| `WINDOWS_SCP_USER` | Windows username for SCP | If SCP enabled |
| `WINDOWS_SCP_HOST` | Windows hostname/IP | If SCP enabled |
| `WINDOWS_PRE_PATH` | Windows PRE reports path | If SCP enabled |
| `WINDOWS_POST_PATH` | Windows POST reports path | If SCP enabled |

---

## Explanation

### What the Script Does

#### PRE-Change Mode (`--mode pre`)

1. **Reads cluster configuration** from `clusters.conf`
2. **Auto-detects environment** (prod/nonprod) from cluster naming pattern
3. **Creates/reuses TMC context** for the appropriate environment
4. **Auto-discovers cluster metadata** (management cluster, provisioner) from TMC
5. **Fetches kubeconfig** from TMC for each cluster
6. **Executes 18 health check modules** covering all aspects of cluster health
7. **Generates health report** with status indicators (HEALTHY/WARNINGS/CRITICAL)
8. **Saves results** to `health-check-results/pre-YYYYMMDD_HHMMSS/`
9. **Updates "latest" directory** to point to most recent PRE results

#### POST-Change Mode (`--mode post`)

All steps from PRE-check, plus:

10. **Locates PRE-change results** (uses "latest" directory by default, or specified path)
11. **Parses PRE-change report** to extract baseline metrics
12. **Compares PRE vs POST metrics** and calculates deltas
13. **Generates comparison table** showing what changed
14. **Creates plain English summary** explaining changes in layman's terms
15. **Produces final verdict** (PASSED/WARNINGS/FAILED)

### Health Check Modules (18 Sections)

| # | Module | What It Checks |
|---|--------|----------------|
| 1 | Cluster Overview | Date, cluster info, Kubernetes version |
| 2 | Node Status | Node health, conditions, taints, capacity |
| 3 | Pod Status | Pod states, CrashLoopBackOff, Pending pods |
| 4 | Workload Status | Deployments, DaemonSets, StatefulSets readiness |
| 5 | Storage Status | PersistentVolumes, PVCs, StorageClasses |
| 6 | Networking | Services, Ingress, HTTPProxy resources |
| 7 | Antrea CNI | Antrea CNI pods and agent status |
| 8 | Tanzu/VMware | Tanzu package installs, TMC agent pods |
| 9 | Security/RBAC | PodDisruptionBudgets, RBAC resources |
| 10 | Component Status | Control plane pods (apiserver, etcd, etc.) |
| 11 | Helm Releases | Helm release status and versions |
| 12 | Namespaces | Namespace listing and status |
| 13 | Resource Quotas | ResourceQuotas and LimitRanges |
| 14 | Events | Warning/Error events (filtered) |
| 15 | Connectivity | HTTPProxy connectivity tests |
| 16 | Images Audit | Container images in use |
| 17 | Certificates | Certificate resources and expiration |
| 18 | Cluster Summary | Quick health summary with indicators |

### Health Status Classification

| Status | Criteria | Action |
|--------|----------|--------|
| **CRITICAL** | Any of: Nodes NotReady > 0, Pods CrashLoopBackOff > 0 | Investigate immediately |
| **WARNINGS** | Any of: Pods Pending > 0, Pods Unaccounted > 0, Deployments NotReady > 0, DaemonSets NotReady > 0, StatefulSets NotReady > 0, PVCs NotBound > 0, Helm Failed > 0 | Monitor, may resolve |
| **HEALTHY** | None of the above conditions | No action needed |

**Note on "Pods Unaccounted"**: Calculated as `Pods Total - Running - Completed - CrashLoop - Pending`. Catches pods in unexpected states (Failed, Unknown, ImagePullBackOff, etc.). If a pod is Completed (e.g., finished Job), it's accounted for and won't affect health status.

### PRE vs POST Comparison Output

```
############################################################################
#                       PRE vs POST COMPARISON                             #
############################################################################

Metric                    PRE      POST     DELTA    STATUS
------------------------- ---------- ---------- ---------- ----------
Nodes Total                        5          5          0       [OK]
Nodes NotReady                     0          1         +1    [WORSE]
Pods Running                     145        140         -5    [WORSE]
Pods CrashLoopBackOff              0          2         +2    [WORSE]
DaemonSets NotReady                0          0          0       [OK]
StatefulSets NotReady              0          0          0       [OK]
PVCs NotBound                      0          0          0       [OK]
Helm Releases Failed               0          0          0       [OK]

############################################################################
#                      PLAIN ENGLISH SUMMARY                               #
############################################################################

What changed after the maintenance/upgrade:

  * CRITICAL: 2 more pod(s) are now crashing (CrashLoopBackOff)
  * WARNING: 1 node became NotReady
  * INFO: 5 pods removed

================================================================================
  RESULT: FAILED - 2 CRITICAL issue(s), 1 warning(s)
  ACTION: Investigate critical issues immediately before proceeding
================================================================================
```

### Output Structure

```
health-check-results/
├── latest/                        # Symlink/copy to most recent PRE results
│   └── (same structure as pre-YYYYMMDD_HHMMSS/)
│
├── pre-YYYYMMDD_HHMMSS/           # PRE-change results
│   ├── cluster-name-1/
│   │   ├── kubeconfig             # Cluster kubeconfig
│   │   └── health-check-report.txt
│   └── cluster-name-2/
│       ├── kubeconfig
│       └── health-check-report.txt
│
└── post-YYYYMMDD_HHMMSS/          # POST-change results
    ├── cluster-name-1/
    │   ├── kubeconfig
    │   ├── health-check-report.txt
    │   └── comparison-report.txt  # PRE vs POST comparison
    └── cluster-name-2/
        ├── kubeconfig
        ├── health-check-report.txt
        └── comparison-report.txt
```

### Caching

| Cache Type | Location | Expiry |
|------------|----------|--------|
| Metadata | `~/.k8s-health-check/metadata.cache` | 7 days |
| Kubeconfig | `~/.k8s-health-check/kubeconfigs/` | 24 hours |
| TMC Context | `~/.k8s-health-check/context-timestamps.cache` | 12 hours |

---

## Project Structure

```
k8-health-check/
├── k8s-health-check.sh           # Unified health check script (v3.3)
├── clusters.conf                  # Cluster configuration file
├── README.md                      # This documentation
├── RELEASE.md                     # Release notes and changelog
├── TO-DO.md                       # Future enhancements
│
├── lib/                           # Library modules
│   ├── common.sh                  # Shared utilities & logging
│   ├── config.sh                  # Configuration parser
│   ├── health.sh                  # Health calculations (NEW in v3.3)
│   ├── tmc-context.sh             # TMC context auto-creation
│   ├── tmc.sh                     # TMC integration & auto-discovery
│   ├── scp.sh                     # Optional Windows SCP transfer
│   ├── comparison.sh              # PRE/POST comparison logic
│   │
│   └── sections/                  # Health check modules (18 sections)
│       ├── 01-cluster-overview.sh
│       ├── 02-node-status.sh
│       ├── ...
│       └── 18-cluster-summary.sh
│
├── tests/                         # Test scripts (NEW in v3.3)
│   └── test-grep-patterns.sh      # Pattern validation tests
│
├── health-check-results/          # Output directory (auto-created)
│
└── Archive/                       # Archived versions
    ├── v3.2/                      # Legacy PRE/POST scripts
    │   ├── k8s-health-check-pre.sh
    │   └── k8s-health-check-post.sh
    └── ...
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Cannot determine environment" | Cluster name doesn't match pattern | Rename cluster or edit `determine_environment()` |
| "Cluster not found in TMC" | Cluster not registered or wrong name | Verify with `tanzu tmc cluster list` |
| "Failed to create TMC context" | Wrong endpoint or credentials | Check `lib/tmc-context.sh` settings |
| "Context expired" | TMC context older than 12 hours | Script auto-recreates, just re-run |
| "Mode not specified" | Missing `--mode` flag | Use `--mode pre` or `--mode post` |

### Debug Mode

```bash
DEBUG=on ./k8s-health-check.sh --mode pre 2>&1 | tee debug.log
```

### Running Tests

```bash
# Validate grep patterns work correctly
./tests/test-grep-patterns.sh

# Expected output: "All tests passed!"
```

---

## Migration from v3.2

If upgrading from v3.2 (separate PRE/POST scripts):

```bash
# Old way (v3.2):
./k8s-health-check-pre.sh
./k8s-health-check-post.sh

# New way (v3.3):
./k8s-health-check.sh --mode pre
./k8s-health-check.sh --mode post
```

The old scripts remain available in `Archive/v3.2/` for backwards compatibility.

---

## Version History

See [RELEASE.md](RELEASE.md) for detailed release notes.

| Version | Date | Highlights |
|---------|------|------------|
| 3.3 | 2026-01-29 | Unified script with --mode flag, lib/health.sh module, test suite |
| 3.2.6 | 2026-01-29 | Fixed grep -c pattern bug causing "0\n0" arithmetic errors |
| 3.2 | 2026-01-28 | Enhanced health summary, PRE vs POST comparison |
| 3.1.1 | 2026-01-27 | 12-hour context validity, removed prompts |
| 3.1 | 2025-01-22 | Auto-discovery, auto-context, unified execution |
| 3.0 | Initial | Basic health check functionality |

---

## Support

1. Review this README and [RELEASE.md](RELEASE.md)
2. Enable DEBUG mode for verbose output
3. Run `./tests/test-grep-patterns.sh` to validate patterns
4. Check error messages in script output
5. Verify prerequisites are met
6. Test with single cluster first
