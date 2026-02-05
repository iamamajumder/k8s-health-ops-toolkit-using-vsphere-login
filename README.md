# Kubernetes Cluster Health Check & Management Tool

**Version 3.8** | VMware Cloud Foundation 5.2.1 (VKS 3.3.3, VKR 1.28.x/1.29.x)

A suite of three scripts for automated Kubernetes cluster health validation, upgrades, and multi-cluster operations through Tanzu Mission Control (TMC) integration.

---

## Prerequisites

| Requirement | Description | Verification |
|-------------|-------------|--------------|
| **Tanzu CLI** | VMware Tanzu CLI with TMC plugin | `tanzu version` |
| **kubectl** | Kubernetes command-line tool | `kubectl version --client` |
| **jq** | JSON processor for parsing | `jq --version` |
| **Bash 4.0+** | Bash shell with associative arrays | `bash --version` |
| **TMC Access** | TMC Self-Managed credentials | Valid username/password |

---

## Quick Start

```bash
# 1. Edit TMC endpoints (one-time)
vi lib/tmc-context.sh
# Set NON_PROD_DNS and PROD_DNS on lines 7-8

# 2. Create cluster list
cat > clusters.conf << EOF
prod-workload-01
prod-workload-02
uat-system-01
EOF

# 3. Make scripts executable
chmod +x k8s-health-check.sh k8s-cluster-upgrade.sh k8s-ops-cmd.sh

# 4. Run first health check
./k8s-health-check.sh --mode pre
```

---

## Configuration

### TMC Endpoint Setup

Edit `lib/tmc-context.sh` (lines 7-8):

```bash
NON_PROD_DNS="your-nonprod-tmc.example.com"
PROD_DNS="your-prod-tmc.example.com"
```

### Cluster List (`clusters.conf`)

One cluster name per line:

```
prod-workload-01
prod-workload-02
uat-system-01
dev-system-01
```

### Cluster Naming Convention

Cluster names determine the TMC context automatically:

| Pattern | Environment | TMC Context |
|---------|-------------|-------------|
| `*-prod-[1-4]` | Production | tmc-sm-prod |
| `*-uat-[1-4]` | Non-production | tmc-sm-nonprod |
| `*-system-[1-4]` | Non-production | tmc-sm-nonprod |

Examples: `workload-prod-01` (prod), `app-uat-02` (nonprod), `dev-system-01` (nonprod)

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `TMC_SELF_MANAGED_USERNAME` | TMC username | No (prompts if not set) |
| `TMC_SELF_MANAGED_PASSWORD` | TMC password | No (prompts if not set) |
| `DEBUG` | Set to `on` for verbose output | No |

---

## Script 1: Health Check (`k8s-health-check.sh`)

Captures comprehensive cluster state before and after changes. Runs 18 health check modules and produces reports with HEALTHY/WARNINGS/CRITICAL status.

### Usage & Options

```
./k8s-health-check.sh --mode pre|post [options] [clusters.conf] [pre-results-dir]
```

| Option | Description |
|--------|-------------|
| `--mode pre\|post` | Check mode (required) |
| `-c, --cluster NAME` | Single cluster (no clusters.conf needed) |
| `--sequential` | One cluster at a time (default: parallel) |
| `--batch-size N` | Clusters per parallel batch (default: 6) |
| `--cache-status` | Show cache status |
| `--clear-cache` | Clear all cached data |

### Examples

```bash
# PRE-change baseline (parallel, 6 clusters at a time)
./k8s-health-check.sh --mode pre

# Single cluster health check
./k8s-health-check.sh --mode pre -c prod-workload-01

# POST-change with comparison to latest PRE
./k8s-health-check.sh --mode post

# POST-change for single cluster
./k8s-health-check.sh --mode post -c prod-workload-01

# POST with specific PRE results directory
./k8s-health-check.sh --mode post ./clusters.conf ./health-check-results/pre-20260128_120000

# Custom batch size
./k8s-health-check.sh --mode pre --batch-size 10

# Sequential execution
./k8s-health-check.sh --mode pre --sequential

# With debug output
DEBUG=on ./k8s-health-check.sh --mode pre

# With credentials in environment
TMC_SELF_MANAGED_USERNAME=myuser TMC_SELF_MANAGED_PASSWORD=mypass ./k8s-health-check.sh --mode pre
```

### Health Status Classification

| Status | Criteria | Action |
|--------|----------|--------|
| **CRITICAL** | Nodes NotReady > 0 OR Pods CrashLoopBackOff > 0 | Investigate immediately |
| **WARNINGS** | Pods Pending > 0, Pods Unaccounted > 0, Deployments/DaemonSets/StatefulSets NotReady > 0, PVCs NotBound > 0, Helm Failed > 0 | Monitor, may resolve |
| **HEALTHY** | None of the above | No action needed |

**Pods Unaccounted** = Total - Running - Completed - CrashLoop - Pending. Catches pods in unexpected states (Failed, Unknown, ImagePullBackOff).

### PRE vs POST Comparison

POST mode compares current state with PRE baseline:

1. Parses PRE report metrics
2. Collects current POST metrics
3. Calculates deltas for health indicators
4. Generates comparison table with `[OK]`, `[WORSE]`, `[BETTER]` status
5. Produces plain-English summary
6. Final verdict: **PASSED** / **WARNINGS** / **FAILED**

```
Metric                    PRE      POST     DELTA    STATUS
------------------------- -------- -------- -------- --------
Nodes Total                      5        5        0     [OK]
Nodes NotReady                   0        1       +1  [WORSE]
Pods Running                   145      140       -5  [WORSE]
Pods CrashLoopBackOff            0        2       +2  [WORSE]

RESULT: FAILED - 2 CRITICAL issue(s), 1 warning(s)
```

---

## Script 2: Cluster Upgrade (`k8s-cluster-upgrade.sh`)

Orchestrates cluster upgrades with PRE/POST health checks and progress monitoring. Delegates health check logic to `k8s-health-check.sh`.

### Usage & Options

```
./k8s-cluster-upgrade.sh [options] [clusters.conf]
```

| Option | Description |
|--------|-------------|
| `-c CLUSTER` | Upgrade a single cluster |
| `--parallel` | Run upgrades in parallel batches |
| `--batch-size N` | Clusters per batch in parallel mode (default: 6) |
| `--timeout-multiplier N` | Minutes per node for timeout (default: 5) |
| `--dry-run` | Show what would be done without executing |

### Examples

```bash
# Default: Use ./clusters.conf (sequential)
./k8s-cluster-upgrade.sh

# Single cluster upgrade
./k8s-cluster-upgrade.sh -c prod-workload-01

# Multiple clusters with custom config
./k8s-cluster-upgrade.sh ./my-clusters.conf

# Parallel batch upgrades (6 at a time)
./k8s-cluster-upgrade.sh --parallel

# Parallel with custom batch size
./k8s-cluster-upgrade.sh --parallel --batch-size 3

# Custom timeout (10 minutes per node)
./k8s-cluster-upgrade.sh -c uat-system-01 --timeout-multiplier 10

# Dry run
./k8s-cluster-upgrade.sh -c prod-workload-01 --dry-run
```

### Upgrade Workflow

**Sequential (default):**

```
For each cluster:
  1. PRE health check (full output) → 2. User prompt (Y/N) → 3. Upgrade
  → 4. Monitor every 2 min → 5. POST health check with comparison
```

**Parallel (`--parallel` flag):**

```
For each batch of N clusters:
  1. PRE health check + prompt per cluster (sequential within batch)
  2. Trigger upgrades for confirmed clusters
  3. Monitor all in parallel (logs to files, no terminal output)
  4. POST health check runs per-cluster as each completes
  5. Batch summary displayed on terminal
```

### Monitoring

Two monitoring methods:

- **kubectl-based** (preferred): Direct cluster access, per-node kubelet version verification, real-time. Success requires: API version changed AND all nodes Ready AND all nodes upgraded.
- **TMC-based** (fallback): Via TMC API when kubeconfig unavailable, cluster-level phase/version only.

### Timeout Calculation

| Nodes | Default (5 min/node) | Custom (10 min/node) |
|-------|---------------------|---------------------|
| 3 | 15 minutes | 30 minutes |
| 5 | 25 minutes | 50 minutes |
| 10 | 50 minutes | 100 minutes |

---

## Script 3: Multi-Cluster Operations (`k8s-ops-cmd.sh`)

Executes commands across multiple clusters with parallel batch execution.

### Usage & Options

```
./k8s-ops-cmd.sh [options] "<command>" [clusters.conf]
```

| Option | Description |
|--------|-------------|
| `-c, --cluster NAME` | Run on a single cluster |
| `-m, --management-cluster ENV` | Discover clusters from TMC management cluster |
| `--timeout SEC` | Command timeout in seconds (default: 30) |
| `--sequential` | One cluster at a time (default: parallel) |
| `--batch-size N` | Clusters per batch (default: 6) |
| `--output-only` | Minimal terminal output, save to file |

`-c`, `-m`, and config file are mutually exclusive.

### Examples

```bash
# Single cluster
./k8s-ops-cmd.sh -c prod-workload-01 "kubectl get nodes"

# Run on all workload cluster under mentioned Management cluster by discovery
./k8s-ops-cmd.sh -m prod-1 "kubectl get nodes"

# Custom config and timeout
./k8s-ops-cmd.sh --timeout 60 "kubectl get pods -A" ./my-clusters.conf

# Sequential execution
./k8s-ops-cmd.sh --sequential "kubectl get nodes"

# Custom batch size
./k8s-ops-cmd.sh --batch-size 10 "kubectl get nodes"

# Get node count across all clusters
./k8s-ops-cmd.sh "kubectl get nodes --no-headers | wc -l"

# Check Kubernetes version
./k8s-ops-cmd.sh "kubectl version --short 2>/dev/null | grep Server"
```

### Management Cluster Discovery (`-m` flag)

Dynamically discovers clusters from TMC management cluster instead of using `clusters.conf`.

Supported environments: `prod-1`, `prod-2`, `prod-3`, `prod-4`, `uat-2`, `uat-4`, `system-1`, `system-3`

```bash
./k8s-ops-cmd.sh -m prod-1 "kubectl get nodes --no-headers | wc -l"
```

---

## Architecture

### Script Architecture

```
┌─────────────────────┐  ┌──────────────────────┐  ┌─────────────────┐
│ k8s-health-check.sh │  │ k8s-cluster-upgrade. │  │ k8s-ops-cmd.sh  │
│                     │  │ sh                   │  │                 │
│ - PRE/POST modes    │  │ - Orchestrates       │  │ - Parallel exec │
│ - 18 health modules │  │   upgrade workflow   │  │ - Any kubectl   │
│ - Parallel batches  │  │ - Calls health-check │  │   command       │
│ - Comparison report │  │ - Monitor progress   │  │ - Mgmt discovery│
└────────┬────────────┘  └──────────┬───────────┘  └────────┬────────┘
         │                          │                        │
         └──────────────┬───────────┘────────────────────────┘
                        │
              ┌─────────┴─────────┐
              │    lib/ modules   │
              ├───────────────────┤
              │ common.sh         │  Logging, colors, utilities
              │ config.sh         │  Cluster list parsing, validation
              │ tmc-context.sh    │  TMC context auto-creation
              │ tmc.sh            │  TMC API, metadata, kubeconfig
              │ health.sh         │  Health metrics & status calc
              │ comparison.sh     │  PRE/POST comparison logic
              │ sections/*.sh     │  18 health check modules
              └───────────────────┘
                        │
              ┌─────────┴─────────┐
              │  External Tools   │
              ├───────────────────┤
              │ tanzu CLI (TMC)   │
              │ kubectl           │
              │ jq                │
              └───────────────────┘
```

### Execution Flow

1. **Initialize**: Parse arguments, check prerequisites
2. **TMC Context**: Auto-detect environment from cluster name, create/reuse TMC context
3. **Kubeconfig**: Fetch from TMC (cached for 12 hours)
4. **Execute**: Run health checks / upgrade / command
5. **Report**: Generate output files, display summary

### Caching System

All caches stored in `~/.k8s-health-check/` with consistent 12-hour expiry.

| Cache Type | File | Purpose |
|------------|------|---------|
| Metadata | `metadata.cache` | Cluster management info from TMC |
| Kubeconfig | `~/k8s-health-check/output/<cluster>/kubeconfig` | Cluster access credentials |
| TMC Context | `context-timestamps.cache` | Context validity tracking |
| Management Clusters | `management-clusters.cache` | TMC management cluster list |
| Discovered Clusters | `mgmt-<name>-clusters.cache` | Clusters per management cluster |

Cache flow: Check if valid (< 12 hours old) -> Reuse if valid -> Refresh from TMC if expired.

Manage with: `./k8s-health-check.sh --cache-status` and `./k8s-health-check.sh --clear-cache`

### TMC Context Management

- Auto-detects environment from cluster naming pattern (e.g., `*-prod-*` -> production)
- Creates TMC context with `tanzu context create` targeting the correct endpoint
- Reuses existing contexts within 12-hour validity window
- In parallel mode, contexts are prepared sequentially first to avoid race conditions

### Parallel Batch Execution

Default for health checks and ops commands. Opt-in for upgrades (`--parallel`).

1. TMC contexts prepared sequentially (avoids race conditions)
2. Clusters processed in batches (default: 6)
3. Each batch launches background processes with PID tracking
4. Batch completes (all PIDs waited) before next batch starts
5. Results collected via marker-based format (`===CLUSTER_START===` / `===CLUSTER_END===`)

---

## Directory Structure

### Script Files

```
k8-health-check/
├── k8s-health-check.sh          # Health check script (PRE/POST modes)
├── k8s-cluster-upgrade.sh       # Upgrade orchestration (sequential/parallel)
├── k8s-ops-cmd.sh               # Multi-cluster command execution
├── clusters.conf                # Cluster configuration (one per line)
├── README.md                    # This documentation
├── RELEASE.md                   # Release notes and changelog
├── CLAUDE.md                    # AI assistant instructions
│
├── lib/                         # Library modules
│   ├── common.sh                # Logging, colors, utilities
│   ├── config.sh                # Config parsing, cluster list functions
│   ├── tmc-context.sh           # TMC context auto-creation
│   ├── tmc.sh                   # TMC integration, metadata, kubeconfig
│   ├── health.sh                # Health metrics collection & status
│   ├── comparison.sh            # PRE/POST comparison logic
│   └── sections/                # 18 health check modules
│       ├── 01-cluster-overview.sh
│       ├── 02-node-status.sh
│       ├── ...
│       └── 18-cluster-summary.sh
│
├── tests/                       # Test scripts
│   └── test-grep-patterns.sh    # Pattern validation
│
└── Archive/                     # Archived versions
    └── v3.2/                    # Legacy PRE/POST scripts
```

### Output Structure (`~/k8s-health-check/output/`)

Per-cluster organization with timestamped files:

```
~/k8s-health-check/output/
└── cluster-name/
    ├── kubeconfig                              # Cached credentials (12-hour expiry)
    ├── h-c-r/                                  # Health Check Reports
    │   ├── pre-hcr-YYYYMMDD_HHMMSS.txt
    │   ├── post-hcr-YYYYMMDD_HHMMSS.txt
    │   ├── comparison-hcr-YYYYMMDD_HHMMSS.txt
    │   └── latest/                             # Latest PRE copy for POST comparison
    │       └── pre-hcr-YYYYMMDD_HHMMSS.txt
    ├── ops/                                    # Operations Command Results
    │   ├── ops-output-YYYYMMDD_HHMMSS.txt
    │   └── ops-raw-YYYYMMDD_HHMMSS.txt
    └── upgrade/                                # Upgrade Results
        ├── pre-hcr-YYYYMMDD_HHMMSS.txt
        ├── post-hcr-YYYYMMDD_HHMMSS.txt
        └── upgrade-log-YYYYMMDD_HHMMSS.txt
```

Automatic cleanup keeps 5 most recent files per type per directory. The `latest/` subdirectory keeps only 1 file (the most recent PRE report for POST comparison). Cleanup runs at the end of every script execution regardless of success/failure.

---

## Library Modules (`lib/`)

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `common.sh` | Shared utilities | `error()`, `success()`, `warning()`, `progress()`, `cleanup_old_files()`, `safe_compare()`, `DEFAULT_BATCH_SIZE` |
| `config.sh` | Configuration | `get_cluster_list()`, `count_clusters()`, `load_configuration()` |
| `tmc-context.sh` | TMC contexts | `ensure_tmc_context()`, `ensure_tmc_context_for_environment()`, `_setup_tmc_context()` |
| `tmc.sh` | TMC integration | `discover_cluster_metadata()`, `fetch_kubeconfig_auto()`, `prepare_tmc_contexts()` |
| `health.sh` | Health metrics | `collect_health_metrics()`, `calculate_health_status()`, `generate_health_summary()` |
| `comparison.sh` | PRE/POST | `generate_comparison_report()`, `parse_health_report()`, `generate_metrics_comparison()` |

## Health Check Sections (`lib/sections/`)

| # | File | What It Checks |
|---|------|----------------|
| 1 | `01-cluster-overview.sh` | Date, cluster info, Kubernetes version |
| 2 | `02-node-status.sh` | Node health, conditions, taints, capacity |
| 3 | `03-pod-status.sh` | Pod states, CrashLoopBackOff, Pending |
| 4 | `04-workload-status.sh` | Deployments, DaemonSets, StatefulSets |
| 5 | `05-storage-status.sh` | PersistentVolumes, PVCs, StorageClasses |
| 6 | `06-networking.sh` | Services, Ingress, HTTPProxy |
| 7 | `07-antrea-cni.sh` | Antrea CNI pods and agent status |
| 8 | `08-tanzu-vmware.sh` | Tanzu packages, TMC agent pods |
| 9 | `09-security-rbac.sh` | PodDisruptionBudgets, RBAC resources |
| 10 | `10-component-status.sh` | Control plane pods (apiserver, etcd) |
| 11 | `11-helm-releases.sh` | Helm release status and versions |
| 12 | `12-namespaces.sh` | Namespace listing and status |
| 13 | `13-resource-quotas.sh` | ResourceQuotas, LimitRanges |
| 14 | `14-events.sh` | Warning/Error events (filtered) |
| 15 | `15-connectivity.sh` | HTTPProxy connectivity tests |
| 16 | `16-images-audit.sh` | Container images in use |
| 17 | `17-certificates.sh` | Certificate resources and expiration |
| 18 | `18-cluster-summary.sh` | Quick health summary with indicators |

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Cannot determine environment" | Cluster name doesn't match pattern | Check naming convention above |
| "Cluster not found in TMC" | Not registered or wrong name | Verify: `tanzu tmc cluster list` |
| "Failed to create TMC context" | Wrong endpoint or credentials | Check `lib/tmc-context.sh` lines 7-8 |
| "Context expired" | TMC context older than 12 hours | Auto-recreated on next run |
| "Mode not specified" | Missing `--mode` flag | Use `--mode pre` or `--mode post` |
| Script hangs at prompt | Credentials not provided | Set `TMC_SELF_MANAGED_USERNAME/PASSWORD` env vars |

### Debug Mode

```bash
DEBUG=on ./k8s-health-check.sh --mode pre 2>&1 | tee debug.log
```

### Running Tests

```bash
./tests/test-grep-patterns.sh
# Expected: "All tests passed!"
```

---

## Version History

See [RELEASE.md](RELEASE.md) for detailed release notes.

| Version | Date | Highlights |
|---------|------|------------|
| 3.8 | 2026-02-05 | Codebase refactoring (~455 lines removed), shared `prepare_tmc_contexts()`, data-driven comparison, consolidated TMC context setup |
| 3.7 | 2026-02-05 | Parallel upgrades, `-c` flag for health-check/ops-cmd, file retention fixes, documentation overhaul |
| 3.6 | 2026-02-04 | Per-cluster output structure, consolidated kubeconfig, automatic cleanup |
| 3.5 | 2026-02-03 | Management cluster discovery, simplified upgrade script, standardized caching |
| 3.4 | 2026-01-29 | Parallel batch execution, automated upgrades, multi-cluster ops command |
| 3.3 | 2026-01-29 | Unified script with `--mode` flag, `lib/health.sh`, test suite |
| 3.2 | 2026-01-28 | Enhanced health summary, PRE vs POST comparison |
| 3.1 | 2025-01-22 | Auto-discovery, auto-context, unified execution |
| 3.0 | Initial | Basic health check functionality |
