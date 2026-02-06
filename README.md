<div align="center">

# Kubernetes Health & Ops Toolkit

**Health Check, Upgrade & Multi-Cluster Operations for VMware Tanzu**

[![VMware Kubernetes Service](https://img.shields.io/badge/VKS-3.3.3-blue?style=flat-square)]()
[![Kubernetes](https://img.shields.io/badge/K8s-1.28--1.32-326CE5?style=flat-square&logo=kubernetes&logoColor=white)]()
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)]()
[![TMC](https://img.shields.io/badge/TMC-Self--Managed-orange?style=flat-square)]()

</div>

---

## Table of Contents

- [What is This?](#what-is-this)
- [When Should I Use This?](#when-should-i-use-this)
- [Quick Start](#quick-start)
- [The Three Scripts](#the-three-scripts)
  - [Health Check](#1-health-check-k8s-health-checksh)
  - [Cluster Upgrade](#2-cluster-upgrade-k8s-cluster-upgradesh)
  - [Multi-Cluster Operations](#3-multi-cluster-operations-k8s-ops-cmdsh)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Output & Reports](#output--reports)
- [Health Check Sections](#health-check-sections)
- [Troubleshooting](#troubleshooting)
- [Version History](#version-history)
- [License](#license)

---

## What is This?

A production-ready toolkit for managing Kubernetes clusters in VMware Kubernetes Service environments. Three scripts that automate health validation, orchestrate upgrades, and execute commands across multiple clusters through Tanzu Mission Control integration.

**Built for**: Platform engineers and SREs managing VKS clusters who need reliable pre/post change validation, automated upgrades with rollback safety, and efficient multi-cluster operations.

---

## When Should I Use This?

| Scenario | Script | Example |
|----------|--------|---------|
| Before/after Kubernetes upgrades | `k8s-health-check.sh` | PRE/POST validation with comparison reports |
| Automated cluster upgrades | `k8s-cluster-upgrade.sh` | Upgrade with health gates and monitoring |
| Audit multiple clusters | `k8s-ops-cmd.sh` | Check versions, node counts across all clusters |
| Change management validation | `k8s-health-check.sh` | Generate comparison reports for change tickets |
| Troubleshooting cluster issues | `k8s-health-check.sh` | 18-section diagnostic report |

---

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/your-org/kubernetes-health-ops-toolkit.git
cd kubernetes-health-ops-toolkit

# 2. Edit TMC endpoints (one-time setup)
vi lib/tmc-context.sh
# Set NON_PROD_DNS and PROD_DNS on lines 7-8

# 3. Create cluster list
cat > clusters.conf << EOF
prod-workload-01
prod-workload-02
uat-system-01
EOF

# 4. Make scripts executable
chmod +x k8s-health-check.sh k8s-cluster-upgrade.sh k8s-ops-cmd.sh

# 5. Run your first health check
./k8s-health-check.sh --mode pre
```

---

## The Three Scripts

### 1. Health Check (`k8s-health-check.sh`)

Captures comprehensive cluster state before and after changes. Runs 18 health check modules and produces reports with **HEALTHY** / **WARNINGS** / **CRITICAL** status.

```bash
# PRE-change baseline (parallel, 6 clusters at a time)
./k8s-health-check.sh --mode pre

# Single cluster health check
./k8s-health-check.sh --mode pre -c prod-workload-01

# POST-change with comparison to latest PRE
./k8s-health-check.sh --mode post

# POST with specific PRE results directory
./k8s-health-check.sh --mode post ./clusters.conf ./health-check-results/pre-20260128_120000
```

| Option | Description |
|--------|-------------|
| `--mode pre\|post` | Check mode (required) |
| `-c, --cluster NAME` | Single cluster (no clusters.conf needed) |
| `--sequential` | One cluster at a time (default: parallel) |
| `--batch-size N` | Clusters per parallel batch (default: 6) |
| `--cache-status` | Show cache status |
| `--clear-cache` | Clear all cached data |

**Health Status Classification:**

| Status | Criteria |
|--------|----------|
| **CRITICAL** | Nodes NotReady > 0 OR Pods CrashLoopBackOff > 0 |
| **WARNINGS** | Pods Pending > 0, Unaccounted > 0, Deployments/DaemonSets/StatefulSets NotReady > 0, PVCs NotBound > 0, Helm Failed > 0 |
| **HEALTHY** | None of the above |

---

### 2. Cluster Upgrade (`k8s-cluster-upgrade.sh`)

Orchestrates cluster upgrades with PRE/POST health checks and progress monitoring.

```bash
# Default: Use ./clusters.conf (sequential)
./k8s-cluster-upgrade.sh

# Single cluster upgrade
./k8s-cluster-upgrade.sh -c prod-workload-01

# Parallel batch upgrades (6 at a time)
./k8s-cluster-upgrade.sh --parallel

# Parallel with custom batch size
./k8s-cluster-upgrade.sh --parallel --batch-size 3

# Dry run
./k8s-cluster-upgrade.sh -c prod-workload-01 --dry-run
```

| Option | Description |
|--------|-------------|
| `-c CLUSTER` | Upgrade a single cluster |
| `--parallel` | Run upgrades in parallel batches |
| `--batch-size N` | Clusters per batch in parallel mode (default: 6) |
| `--timeout-multiplier N` | Minutes per node for timeout (default: 5) |
| `--dry-run` | Show what would be done without executing |

---

### 3. Multi-Cluster Operations (`k8s-ops-cmd.sh`)

Executes commands across multiple clusters with parallel batch execution.

```bash
# Single cluster
./k8s-ops-cmd.sh -c prod-workload-01 "kubectl get nodes"

# All clusters from config
./k8s-ops-cmd.sh "kubectl get nodes --no-headers | wc -l"

# Discovery from TMC management cluster
./k8s-ops-cmd.sh -m prod-1 "kubectl get nodes"

# Check Kubernetes version across clusters
./k8s-ops-cmd.sh "kubectl version --short 2>/dev/null | grep Server"
```

| Option | Description |
|--------|-------------|
| `-c, --cluster NAME` | Run on a single cluster |
| `-m, --management-cluster ENV` | Discover clusters from TMC management cluster |
| `--timeout SEC` | Command timeout in seconds (default: 30) |
| `--sequential` | One cluster at a time (default: parallel) |
| `--batch-size N` | Clusters per batch (default: 6) |

---

## Architecture

### Upgrade Workflow

![Upgrade Workflow](gif/upgrade_workflow.gif)

**Workflow Steps:**
1. **PRE-Change**: Run comprehensive health check and generate baseline metrics
2. **Change Window**: Execute cluster upgrade with monitoring
3. **POST-Change**: Run health check and compare with PRE baseline
4. **Verdict**: Automatic classification (PASSED ✓ / WARNINGS ⚠ / FAILED ✗)

---

### Script Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   🎯 MAIN SCRIPTS                                        │
├─────────────────────────────┬─────────────────────────────┬─────────────────────────────┤
│                             │                             │                             │
│  📊 k8s-health-check.sh    │  ⬆️ k8s-cluster-upgrade.sh  │  🔧 k8s-ops-cmd.sh          │
│  ─────────────────────      │  ────────────────────────   │  ───────────────            │
│  • PRE/POST validation      │  • Upgrade orchestration    │  • Multi-cluster ops        │
│  • 18 health modules        │  • Health gates             │  • Parallel execution       │
│  • Comparison reports       │  • Progress monitoring      │  • TMC discovery            │
│                             │                             │                             │
└──────────────┬──────────────┴──────────────┬──────────────┴──────────────┬──────────────┘
               │                             │                             │
               │                             │ delegates                   │
               ▼                             ▼                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              📦 LIBRARY MODULES (lib/)                                   │
├─────────────────────────────┬─────────────────────────────┬─────────────────────────────┤
│                             │                             │                             │
│  common.sh    - Utilities   │  tmc-context.sh - Contexts  │  health.sh     - Metrics    │
│  config.sh    - Parsing     │  tmc.sh         - TMC API   │  comparison.sh - PRE/POST   │
│                             │                             │                             │
└─────────────────────────────┴──────────────┬──────────────┴─────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        📋 18 HEALTH CHECK SECTIONS (lib/sections/)                       │
├─────────────────────────────┬─────────────────────────────┬─────────────────────────────┤
│  01-cluster-overview        │  07-antrea-cni              │  13-resource-quotas         │
│  02-node-status             │  08-tanzu-vmware            │  14-events                  │
│  03-pod-status              │  09-security-rbac           │  15-connectivity            │
│  04-workload-status         │  10-component-status        │  16-images-audit            │
│  05-storage-status          │  11-helm-releases           │  17-certificates            │
│  06-networking              │  12-namespaces              │  18-cluster-summary         │
└─────────────────────────────┴──────────────┬──────────────┴─────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                               🌐 EXTERNAL TOOLS                                          │
├─────────────────────────────┬─────────────────────────────┬─────────────────────────────┤
│        tanzu CLI            │          kubectl            │            jq               │
└─────────────────────────────┴─────────────────────────────┴─────────────────────────────┘
```

---

### Health Status Decision Tree

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 🔍 COLLECT METRICS                                       │
│                                                                                         │
│                    Nodes, Pods, Workloads, Storage, Helm Releases                       │
└─────────────────────────────────────────┬───────────────────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              ❓ Nodes NotReady > 0?                                      │
└───────────────┬─────────────────────────────────────────────────────────┬───────────────┘
                │                                                         │
                │ YES                                                     │ NO
                ▼                                                         ▼
┌───────────────────────────────┐                     ┌───────────────────────────────────┐
│        🔴 CRITICAL            │                     │    ❓ Pods CrashLoopBackOff > 0?  │
│        ───────────            │                     └─────────────────┬─────────────────┘
│                               │                                       │
│  • Abort upgrade              │◄──────────── YES ─────────────────────┤
│  • Investigate immediately    │                                       │ NO
│  • Alert team                 │                                       ▼
│                               │                     ┌───────────────────────────────────┐
└───────────────────────────────┘                     │  ❓ Pending/NotReady/Unaccounted? │
                                                      └─────────────────┬─────────────────┘
                                                                        │
                                          ┌─────────────────────────────┼─────────────────┐
                                          │ YES                                           │ NO
                                          ▼                                               ▼
                          ┌───────────────────────────────┐       ┌───────────────────────────────┐
                          │        🟡 WARNINGS            │       │        🟢 HEALTHY             │
                          │        ───────────            │       │        ─────────              │
                          │                               │       │                               │
                          │  • Prompt user for decision   │       │  • Auto-proceed with upgrade  │
                          │  • Monitor closely            │       │  • All systems nominal        │
                          │  • Proceed with caution       │       │  • Safe to continue           │
                          │                               │       │                               │
                          └───────────────────────────────┘       └───────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   HEALTH STATUS SUMMARY                                  │
├─────────────────────────────┬─────────────────────────────┬─────────────────────────────┤
│        🔴 CRITICAL          │        🟡 WARNINGS          │        🟢 HEALTHY           │
├─────────────────────────────┼─────────────────────────────┼─────────────────────────────┤
│                             │                             │                             │
│  Criteria:                  │  Criteria:                  │  Criteria:                  │
│  • Nodes NotReady > 0       │  • Pods Pending > 0         │  • None of the above        │
│  • Pods CrashLoop > 0       │  • Pods Unaccounted > 0     │                             │
│                             │  • Workloads NotReady > 0   │                             │
│                             │  • PVCs NotBound > 0        │                             │
│                             │  • Helm Failed > 0          │                             │
│                             │                             │                             │
│  Action: ❌ Abort           │  Action: ⚠️ Prompt User     │  Action: ✅ Auto-proceed    │
│                             │                             │                             │
└─────────────────────────────┴─────────────────────────────┴─────────────────────────────┘
```

### Library Modules

| Module | Purpose |
|--------|---------|
| `common.sh` | Logging, colors, utilities, `cleanup_old_files()` |
| `config.sh` | Cluster list parsing, configuration validation |
| `tmc-context.sh` | TMC context auto-creation based on cluster naming |
| `tmc.sh` | TMC integration, metadata discovery, kubeconfig fetching |
| `health.sh` | Health metrics collection and status calculation |
| `comparison.sh` | PRE/POST comparison logic and report generation |

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
```

### Cluster Naming Convention

Cluster names determine the TMC context automatically:

| Pattern | Environment | TMC Context |
|---------|-------------|-------------|
| `*-prod-[1-4]` | Production | tmc-sm-prod |
| `*-uat-[1-4]` | Non-production | tmc-sm-nonprod |
| `*-system-[1-4]` | Non-production | tmc-sm-nonprod |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TMC_SELF_MANAGED_USERNAME` | TMC username (prompts if not set) |
| `TMC_SELF_MANAGED_PASSWORD` | TMC password (prompts if not set) |
| `DEBUG` | Set to `on` for verbose output |

---

## Output & Reports

All reports are saved to `~/k8s-health-check/output/<cluster-name>/`:

| Directory | Contents |
|-----------|----------|
| `h-c-r/` | Health check reports (`pre-hcr-*.txt`, `post-hcr-*.txt`, `comparison-*.txt`) |
| `h-c-r/latest/` | Most recent PRE report (for automatic POST comparison) |
| `ops/` | Operations command output (`ops-*.txt`) |
| `upgrade/` | Upgrade logs and health reports |
| `kubeconfig` | Cached cluster credentials (12-hour expiry) |

**Aggregated results** for multi-cluster operations: `~/k8s-health-check/output/ops-aggregated/`

### PRE vs POST Comparison Example

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

## Health Check Sections

The toolkit runs 18 comprehensive health check modules:

| # | Section | What It Checks |
|---|---------|----------------|
| 1 | Cluster Overview | Date, cluster info, Kubernetes version |
| 2 | Node Status | Node health, conditions, taints, capacity |
| 3 | Pod Status | Pod states, CrashLoopBackOff, Pending |
| 4 | Workload Status | Deployments, DaemonSets, StatefulSets |
| 5 | Storage Status | PersistentVolumes, PVCs, StorageClasses |
| 6 | Networking | Services, Ingress, HTTPProxy |
| 7 | Antrea CNI | CNI pods and agent status |
| 8 | Tanzu/VMware | Tanzu packages, TMC agent pods |
| 9 | Security/RBAC | PodDisruptionBudgets, RBAC resources |
| 10 | Component Status | Control plane pods (apiserver, etcd) |
| 11 | Helm Releases | Release status and versions |
| 12 | Namespaces | Namespace listing and status |
| 13 | Resource Quotas | ResourceQuotas, LimitRanges |
| 14 | Events | Warning/Error events (filtered) |
| 15 | Connectivity | HTTPProxy connectivity tests |
| 16 | Images Audit | Container images in use |
| 17 | Certificates | Certificate resources and expiration |
| 18 | Cluster Summary | Quick health summary with indicators |

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Cannot determine environment" | Cluster name doesn't match pattern | Check naming convention (must match `*-prod-*`, `*-uat-*`, or `*-system-*`) |
| "Cluster not found in TMC" | Not registered or wrong name | Verify with `tanzu tmc cluster list` |
| "Failed to create TMC context" | Wrong endpoint or credentials | Check `lib/tmc-context.sh` lines 7-8 |
| "Context expired" | TMC context older than 12 hours | Auto-recreated on next run |
| "Mode not specified" | Missing `--mode` flag | Use `--mode pre` or `--mode post` |
| Script hangs at prompt | Credentials not provided | Set `TMC_SELF_MANAGED_USERNAME/PASSWORD` env vars |

### Debug Mode

```bash
DEBUG=on ./k8s-health-check.sh --mode pre 2>&1 | tee debug.log
```

### Cache Management

```bash
# View cache status
./k8s-health-check.sh --cache-status

# Clear all cached data
./k8s-health-check.sh --clear-cache
```

---

## Version History

See [RELEASE.md](RELEASE.md) for detailed release notes.

| Version | Highlights |
|---------|------------|
| **3.8** | Codebase refactoring (~455 lines removed), shared functions, data-driven comparison |
| **3.7** | Parallel upgrades, `-c` flag for health-check/ops-cmd, file retention fixes |
| **3.6** | Per-cluster output structure, consolidated kubeconfig, automatic cleanup |
| **3.5** | Management cluster discovery, simplified upgrade script, standardized caching |
| **3.4** | Parallel batch execution, automated upgrades, multi-cluster ops command |
| **3.3** | Unified script with `--mode` flag, centralized health module, test suite |

---

## Prerequisites

| Requirement | Verification |
|-------------|--------------|
| Tanzu CLI with TMC plugin | `tanzu version` |
| kubectl | `kubectl version --client` |
| jq | `jq --version` |
| Bash 4.0+ | `bash --version` |
| TMC Self-Managed credentials | Valid username/password |

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
