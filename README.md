# Kubernetes Cluster Health Check Tool

**Version 3.2** - Automated Health Check with TMC Auto-Discovery and PRE/POST Comparison

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

### Quick Start

```bash
# Make scripts executable
chmod +x k8s-health-check-pre.sh k8s-health-check-post.sh

# Run PRE-change health check (before maintenance)
./k8s-health-check-pre.sh              # Creates latest/ directory automatically

# Perform your maintenance/upgrade...

# Run POST-change health check (after maintenance)
./k8s-health-check-post.sh             # Automatically uses latest PRE results
```

### PRE-Change Health Check

```bash
# Using default ./clusters.conf
./k8s-health-check-pre.sh

# Using specific config file
./k8s-health-check-pre.sh ./my-clusters.conf

# With debug output
DEBUG=on ./k8s-health-check-pre.sh

# With credentials in environment (no prompts)
TMC_SELF_MANAGED_USERNAME=myuser \
TMC_SELF_MANAGED_PASSWORD=mypass \
./k8s-health-check-pre.sh
```

### POST-Change Health Check

```bash
# Simplest: Use latest PRE results (recommended for recent PRE runs)
./k8s-health-check-post.sh

# Using specific PRE results directory (for older comparisons)
./k8s-health-check-post.sh ./health-check-results/pre-20260128_120000

# Using specific config file
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20260128_120000

# Reverse argument order (auto-detected)
./k8s-health-check-post.sh ./health-check-results/pre-20260128_120000 ./clusters.conf

# With debug output
DEBUG=on ./k8s-health-check-post.sh
```

### Cache Management

```bash
# View cache status (metadata, kubeconfigs, context timestamps)
./k8s-health-check-pre.sh --cache-status

# Clear all cached data
./k8s-health-check-pre.sh --clear-cache
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

### What the Scripts Do

#### PRE-Change Health Check (`k8s-health-check-pre.sh`)

1. **Reads cluster configuration** from `clusters.conf`
2. **Auto-detects environment** (prod/nonprod) from cluster naming pattern
3. **Creates/reuses TMC context** for the appropriate environment
4. **Auto-discovers cluster metadata** (management cluster, provisioner) from TMC
5. **Fetches kubeconfig** from TMC for each cluster
6. **Executes 18 health check modules** covering all aspects of cluster health
7. **Generates health report** with status indicators (HEALTHY/WARNINGS/CRITICAL)
8. **Saves results** to `health-check-results/pre-YYYYMMDD_HHMMSS/`
9. **Updates "latest" directory** to point to most recent PRE results

#### POST-Change Health Check (`k8s-health-check-post.sh`)

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

| Status | Condition | Action |
|--------|-----------|--------|
| **CRITICAL** | Nodes NotReady OR Pods CrashLoopBackOff | Investigate immediately |
| **WARNINGS** | Pending pods, workloads not ready, PVCs not bound, Helm failed | Monitor, may resolve |
| **HEALTHY** | All checks passed | No action needed |

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
├── k8s-health-check-pre.sh      # PRE-change health check script
├── k8s-health-check-post.sh     # POST-change health check script
├── clusters.conf                 # Cluster configuration file
├── README.md                     # This documentation
├── RELEASE.md                    # Release notes and changelog
├── TO-DO.md                      # Future enhancements
│
├── lib/                          # Library modules
│   ├── common.sh                 # Shared utilities & logging
│   ├── config.sh                 # Configuration parser
│   ├── tmc-context.sh            # TMC context auto-creation
│   ├── tmc.sh                    # TMC integration & auto-discovery
│   ├── scp.sh                    # Optional Windows SCP transfer
│   ├── comparison.sh             # PRE/POST comparison logic
│   │
│   └── sections/                 # Health check modules (18 sections)
│       ├── 01-cluster-overview.sh
│       ├── 02-node-status.sh
│       ├── ...
│       └── 18-cluster-summary.sh
│
├── health-check-results/         # Output directory (auto-created)
│
└── Archive/                      # Archived versions and documentation
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

### Debug Mode

```bash
DEBUG=on ./k8s-health-check-pre.sh ./clusters.conf 2>&1 | tee debug.log
```

---

## Version History

See [RELEASE.md](RELEASE.md) for detailed release notes.

| Version | Date | Highlights |
|---------|------|------------|
| 3.2 | 2026-01-28 | Enhanced health summary, PRE vs POST comparison, optional clusters.conf |
| 3.1.1 | 2026-01-27 | 12-hour context validity, removed prompts, cluster summaries |
| 3.1 | 2025-01-22 | Auto-discovery, auto-context, unified execution |
| 3.0 | Initial | Basic health check functionality |

---

## Support

1. Review this README and [RELEASE.md](RELEASE.md)
2. Enable DEBUG mode for verbose output
3. Check error messages in script output
4. Verify prerequisites are met
5. Test with single cluster first
