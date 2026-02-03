# Kubernetes Cluster Health Check Tool

**Version 3.5** - Management Cluster Discovery & Dynamic Operations

---

## What's New in v3.5

- **Management Cluster Discovery**: Dynamic cluster discovery for `k8s-ops-cmd.sh`
  - New `-m <environment>` flag to discover clusters from TMC management clusters
  - No need to maintain `clusters.conf` for dynamic environments
  - Automatic environment detection (prod-1, uat-2, system-3, etc.)
  - 12-hour caching for discovered clusters (consistent with v3.5 standards)
  - Full integration with existing parallel/sequential execution modes
- **Simplified Upgrade Script**: Complete rewrite of `k8s-cluster-upgrade.sh` (70% code reduction)
  - Delegates to `k8s-health-check.sh` instead of duplicating health logic
  - 350 lines vs 1200 lines in v3.4 - cleaner, more maintainable
  - Same functionality, less code to maintain
- **Standardized Cache Expiry**: All caches now use consistent 12-hour expiry

## What's New in v3.4

- **Batch Parallel Execution (Default)**: All scripts now run in parallel batches of 6 clusters by default
  - `--batch-size N` option to customize batch size
  - `--sequential` option for one-at-a-time processing
  - TMC contexts prepared sequentially, then clusters processed in parallel batches
- **Automated Cluster Upgrade**: New `k8s-cluster-upgrade.sh` with health-gated upgrades
  - PRE-upgrade health validation (HEALTHY=auto, WARNINGS=prompt, CRITICAL=abort)
  - TMC-based upgrade execution with progress monitoring
  - POST-upgrade health comparison with detailed reports
- **Multi-Cluster Ops Command**: New `k8s-ops-cmd.sh` for running commands across all clusters
  - Parallel batch execution for faster results
  - Formatted output to terminal and file
  - Reuses existing TMC context/kubeconfig caching

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

### Quick Start (v3.4 Unified Script)

```bash
# Make script executable
chmod +x k8s-health-check.sh

# Run PRE-change health check (before maintenance)
./k8s-health-check.sh --mode pre

# Perform your maintenance/upgrade...

# Run POST-change health check (after maintenance)
./k8s-health-check.sh --mode post

# For faster execution with multiple clusters, use parallel mode
./k8s-health-check.sh --mode pre --parallel
./k8s-health-check.sh --mode post --parallel
```

### PRE-Change Health Check

```bash
# Default clusters.conf
./k8s-health-check.sh --mode pre

# Custom config file
./k8s-health-check.sh --mode pre ./my-clusters.conf

# With debug output
DEBUG=on ./k8s-health-check.sh --mode pre

# With credentials in environment (no prompts)
TMC_SELF_MANAGED_USERNAME=myuser \
TMC_SELF_MANAGED_PASSWORD=mypass \
./k8s-health-check.sh --mode pre
```

### POST-Change Health Check (with comparison)

```bash
# Use latest PRE results (default)
./k8s-health-check.sh --mode post

# Custom config file + latest PRE results
./k8s-health-check.sh --mode post ./clusters.conf

# Compare with specific older PRE results
./k8s-health-check.sh --mode post ./health-check-results/pre-20260128_120000

# Both custom config and specific PRE results (either order works)
./k8s-health-check.sh --mode post ./clusters.conf ./health-check-results/pre-20260128_120000
./k8s-health-check.sh --mode post ./health-check-results/pre-20260128_120000 ./clusters.conf

# With debug output
DEBUG=on ./k8s-health-check.sh --mode post
```

### Parallel Execution (Default in v3.4)

All scripts now run in **parallel batches of 6 clusters by default** for faster processing.

```bash
# PRE-check (parallel by default, 6 clusters at a time)
./k8s-health-check.sh --mode pre

# POST-check (parallel by default)
./k8s-health-check.sh --mode post

# Custom batch size (10 clusters at a time)
./k8s-health-check.sh --mode pre --batch-size 10

# Sequential execution (one cluster at a time)
./k8s-health-check.sh --mode pre --sequential
```

**How it works:**
1. TMC contexts are prepared sequentially first (to avoid race conditions)
2. Clusters are processed in batches (default: 6 at a time)
3. Each batch completes before the next batch starts
4. Results are collected and displayed at the end

**When to use sequential (`--sequential`):**
- Debugging issues with specific clusters
- When you want to see detailed progress per cluster
- Single cluster checks

**Customizing batch size (`--batch-size N`):**
- Increase for faster execution on powerful machines
- Decrease if encountering resource constraints

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

---

## Automated Cluster Upgrade (v3.5)

Simple orchestration script that delegates health checks to `k8s-health-check.sh` for clean, maintainable code.

### Upgrade Workflow

```
1. Run PRE-upgrade health check (full output displayed)
                    │
                    ▼
2. Prompt: "Do you want to upgrade [cluster]? (Y/N)"
                    │
                    ▼
3. Execute TMC upgrade command (--latest)
                    │
                    ▼
4. Monitor progress every 2 minutes
   - Display: [elapsed] Phase: X | Version: Y | Health: Z
   - Dynamic timeout: nodes × 5 min/node
                    │
                    ▼
5. Display completion message with new version
                    │
                    ▼
6. Run POST-upgrade health check with PRE vs POST comparison
```

### Key Features

- **No Code Duplication**: Delegates to existing `k8s-health-check.sh` script
- **User Confirmation**: Explicit approval required before each upgrade
- **Dynamic Timeout**: Calculated as number of nodes × 5 minutes per node
- **Real-time Monitoring**: Progress updates every 2 minutes
- **Automatic Comparison**: POST check automatically compares with PRE results

### Timeout Calculation

| Nodes | Default Timeout | Custom (10 min/node) |
|-------|----------------|---------------------|
| 3 nodes | 15 minutes | 30 minutes |
| 5 nodes | 25 minutes | 50 minutes |
| 10 nodes | 50 minutes | 100 minutes |

Formula: `timeout = node_count × timeout_multiplier`

### Usage

```bash
# Make script executable
chmod +x k8s-cluster-upgrade.sh

# Default: Use ./clusters.conf
./k8s-cluster-upgrade.sh

# Single cluster upgrade
./k8s-cluster-upgrade.sh -c prod-workload-01

# Multiple clusters with custom config
./k8s-cluster-upgrade.sh ./my-clusters.conf

# Custom timeout multiplier (default: 5 min/node)
./k8s-cluster-upgrade.sh -c uat-system-01 --timeout-multiplier 10

# Dry run (shows what would be done)
./k8s-cluster-upgrade.sh -c my-cluster --dry-run
```

### Upgrade Output Structure

```
upgrade-results/
└── upgrade-YYYYMMDD_HHMMSS/
    └── cluster-name/
        ├── pre-upgrade-health.txt      # PRE health check report
        ├── upgrade-log.txt             # Upgrade execution and monitoring
        ├── post-upgrade-health.txt     # POST health check report
        └── comparison-report.txt       # PRE vs POST comparison
```

### Example Monitoring Output

```
[  2 min] Phase: UPGRADING    | Version: v1.28.2 | Health: HEALTHY
[  4 min] Phase: UPGRADING    | Version: v1.28.2 | Health: HEALTHY
[  6 min] Phase: UPGRADING    | Version: v1.29.0 | Health: HEALTHY
[  8 min] Phase: READY        | Version: v1.29.0 | Health: HEALTHY

Upgrade completed successfully!
  Cluster: prod-workload-01
  Version: v1.29.0
  Health: HEALTHY
  Duration: 8 minutes
```

---

## Multi-Cluster Ops Command (v3.5)

The `k8s-ops-cmd.sh` script executes commands across all clusters in parallel. Now supports dynamic cluster discovery from TMC management clusters.

### Usage (File-based Mode)

```bash
# Make script executable
chmod +x k8s-ops-cmd.sh

# Get Contour version on all clusters
./k8s-ops-cmd.sh "kubectl get deploy -n projectcontour contour -o jsonpath='{.spec.template.spec.containers[0].image}'"

# Check cert-manager version
./k8s-ops-cmd.sh "helm list -n cert-manager -o json | jq -r '.[0].chart'"

# Get node count per cluster
./k8s-ops-cmd.sh "kubectl get nodes --no-headers | wc -l"

# Check Kubernetes version
./k8s-ops-cmd.sh "kubectl version --short 2>/dev/null | grep Server"

# Get Antrea pod count
./k8s-ops-cmd.sh "kubectl get pods -n kube-system -l app=antrea --no-headers | wc -l"

# With custom config and timeout
./k8s-ops-cmd.sh --timeout 60 "kubectl get pods -A" ./my-clusters.conf

# Sequential execution (one cluster at a time)
./k8s-ops-cmd.sh --sequential "kubectl get nodes"

# Minimal terminal output (results saved to file only)
./k8s-ops-cmd.sh --output-only "kubectl get nodes"
```

### Management Cluster Discovery (Dynamic Cluster Selection - v3.5)

Instead of maintaining `clusters.conf`, you can dynamically discover clusters from a TMC management cluster using the `-m` flag.

**Usage:**
```bash
# Execute command on all clusters in prod-1 management cluster
./k8s-ops-cmd.sh -m prod-1 "kubectl get nodes --no-headers | wc -l"

# Check Kubernetes version across uat-2 clusters
./k8s-ops-cmd.sh -m uat-2 "kubectl version --short 2>/dev/null | grep Server"

# Discovery with sequential execution
./k8s-ops-cmd.sh -m system-3 --sequential "kubectl get nodes"

# Custom batch size with discovery
./k8s-ops-cmd.sh -m prod-1 --batch-size 10 "kubectl get pods -A"

# Discovery with custom timeout
./k8s-ops-cmd.sh -m prod-1 --timeout 60 "helm list -A"
```

**Supported Environments:**
- `prod-1`, `prod-2`, `prod-3`, `prod-4` (Production)
- `uat-2`, `uat-4` (UAT)
- `system-1`, `system-3` (System)

**How it works:**
1. Script queries TMC for management cluster matching the environment
2. Lists all clusters within that management cluster
3. Executes your command on all discovered clusters
4. Uses same parallel batch execution as file-based mode

**Benefits:**
- No need to maintain clusters.conf file
- Always up-to-date with TMC cluster list
- Ideal for dynamic environments where clusters are added/removed frequently
- 12-hour caching for fast repeated execution

### Sample Output

```
================================================================================
  MULTI-CLUSTER OPS COMMAND
================================================================================
Command: kubectl get nodes --no-headers | wc -l
Clusters: 5
================================================================================

[SUCCESS] svcs-k8s-1-prod-1
────────────────────────────────────────
5

[SUCCESS] svcs-k8s-2-prod-2
────────────────────────────────────────
5

[SUCCESS] app-k8s-1-uat-1
────────────────────────────────────────
3

================================================================================
  SUMMARY
================================================================================
Total Clusters: 5
Successful: 5
Failed: 0

Results saved to: ops-results/ops-20260129_143000/output.txt
================================================================================
```

### Ops Output Structure

```
ops-results/
└── ops-YYYYMMDD_HHMMSS/
    └── output.txt     # Full results with cluster headers
```

---

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
| Metadata | `~/.k8s-health-check/metadata.cache` | 12 hours |
| Kubeconfig | `~/.k8s-health-check/kubeconfigs/` | 12 hours |
| TMC Context | `~/.k8s-health-check/context-timestamps.cache` | 12 hours |
| Management Clusters | `~/.k8s-health-check/management-clusters.cache` | 12 hours |
| Discovered Clusters | `~/.k8s-health-check/mgmt-<name>-clusters.cache` | 12 hours |

**Cache Benefits:**
- Reduces TMC API calls for better performance
- 12-hour expiry ensures fresh data during upgrades (v3.5 standard)
- Automatic refresh when cache expires
- Can be manually cleared with `--clear-cache` flag
- Management discovery results cached for fast repeated execution

---

## Project Structure

```
k8-health-check/
├── k8s-health-check.sh           # Unified health check script (v3.3)
├── k8s-cluster-upgrade.sh        # Automated cluster upgrade (v3.5 - simplified)
├── k8s-ops-cmd.sh                # Multi-cluster ops command (v3.5 - discovery support)
├── clusters.conf                  # Cluster configuration file
├── README.md                      # This documentation
├── RELEASE.md                     # Release notes and changelog
├── TO-DO.md                       # Future enhancements
│
├── lib/                           # Library modules
│   ├── common.sh                  # Shared utilities & logging
│   ├── config.sh                  # Configuration parser (v3.5 - discovery functions)
│   ├── health.sh                  # Health calculations (v3.3)
│   ├── tmc-context.sh             # TMC context auto-creation (v3.5 - env flags)
│   ├── tmc.sh                     # TMC integration & auto-discovery (v3.5 - mgmt clusters)
│   ├── comparison.sh              # PRE/POST comparison logic
│   │
│   └── sections/                  # Health check modules (18 sections)
│       ├── 01-cluster-overview.sh
│       ├── 02-node-status.sh
│       ├── ...
│       └── 18-cluster-summary.sh
│
├── tests/                         # Test scripts (v3.3)
│   └── test-grep-patterns.sh      # Pattern validation tests
│
├── health-check-results/          # Health check output (auto-created)
├── upgrade-results/               # Upgrade results output (auto-created)
├── ops-results/                   # Ops command output (auto-created)
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
| 3.5 | 2026-02-03 | Management cluster discovery, simplified upgrade script, standardized caching |
| 3.4 | 2026-01-29 | Automated cluster upgrade, multi-cluster ops command |
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
