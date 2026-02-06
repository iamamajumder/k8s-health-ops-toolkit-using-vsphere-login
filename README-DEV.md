# Kubernetes Health & Ops Toolkit

**Health Check, Upgrade & Multi-Cluster Operations**

VKS 3.3.3 | Kubernetes 1.28-1.32 | Bash 4.0+ | TMC Self-Managed

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [The Three Scripts](#2-the-three-scripts)
3. [Architecture](#3-architecture)
   - [Upgrade Workflow](#upgrade-workflow)
   - [Script Architecture](#script-architecture)
   - [Health Status Decision Tree](#health-status-decision-tree)
4. [Configuration](#4-configuration)
5. [Output Structure](#5-output-structure)
6. [Health Check Sections (18)](#6-health-check-sections-18)
7. [Troubleshooting](#7-troubleshooting)
8. [Quick Reference](#8-quick-reference)

---

## 1. Quick Start

```bash
# 1. Edit TMC endpoints (one-time setup)
vi lib/tmc-context.sh
# Set NON_PROD_DNS and PROD_DNS on lines 7-8

# 2. Create cluster list
echo "prod-workload-01" > clusters.conf
echo "prod-workload-02" >> clusters.conf

# 3. Make scripts executable
chmod +x k8s-health-check.sh k8s-cluster-upgrade.sh k8s-ops-cmd.sh

# 4. Run your first health check
./k8s-health-check.sh --mode pre
```

---

## 2. The Three Scripts

| Script | Purpose |
|--------|---------|
| `k8s-health-check.sh` | PRE/POST health validation, 18-section audit |
| `k8s-cluster-upgrade.sh` | Orchestrated upgrades with health gates |
| `k8s-ops-cmd.sh` | Execute commands across multiple clusters |

**Health Check:**
```bash
./k8s-health-check.sh --mode pre                    # PRE baseline
./k8s-health-check.sh --mode pre -c <cluster>       # Single cluster
./k8s-health-check.sh --mode post                   # POST with comparison
```

**Cluster Upgrade:**
```bash
./k8s-cluster-upgrade.sh                            # Sequential upgrade
./k8s-cluster-upgrade.sh -c <cluster>               # Single cluster
./k8s-cluster-upgrade.sh --parallel                 # Parallel batch
```

**Multi-Cluster Ops:**
```bash
./k8s-ops-cmd.sh "kubectl get nodes"                # All clusters
./k8s-ops-cmd.sh -c <cluster> "kubectl get nodes"   # Single cluster
./k8s-ops-cmd.sh -m prod-1 "kubectl get nodes"      # TMC discovery
```

---

## 3. Architecture

### Upgrade Workflow

```
    +-----------------+     +------------------+     +------------------+
    |   PRE-Change    |     |  Change Window   |     |   POST-Change    |
    +-----------------+     +------------------+     +------------------+
    |                 |     |                  |     |                  |
    | +-------------+ |     | +--------------+ |     | +--------------+ |
    | | Run PRE     | |     | |   Execute    | |     | | Run POST     | |
    | | Health Check|------->|   Upgrade    |------->| | Health Check | |
    | +-------------+ |     | +--------------+ |     | +--------------+ |
    |       |         |     |                  |     |       |          |
    |       v         |     |                  |     |       v          |
    | +-------------+ |     |                  |     | +--------------+ |
    | |  Generate   | |     |                  |     | | Compare with | |
    | |  Baseline   | |     |                  |     | |     PRE      | |
    | +-------------+ |     |                  |     | +--------------+ |
    |                 |     |                  |     |       |          |
    +-----------------+     +------------------+     +-------+----------+
                                                           |
                                                           v
                                                   +---------------+
                                                   |    Verdict    |
                                                   +-------+-------+
                                                           |
                           +-------------------------------+-------------------------------+
                           |                               |                               |
                           v                               v                               v
                   +---------------+               +---------------+               +---------------+
                   |    PASSED     |               |   WARNINGS    |               |    FAILED     |
                   |   (Success)   |               |   (Review)    |               | (Investigate) |
                   +---------------+               +---------------+               +---------------+
```

### Script Architecture

```
    +===========================================================================+
    |                            MAIN SCRIPTS                                    |
    +===========================================================================+
    |                                                                            |
    |   +------------------------+  +------------------------+  +-------------+  |
    |   | k8s-health-check.sh    |  | k8s-cluster-upgrade.sh |  | k8s-ops-    |  |
    |   |------------------------|  |------------------------|  | cmd.sh      |  |
    |   | - PRE/POST validation  |  | - Orchestration        |  |-------------|  |
    |   | - 18 health modules    |  | - Health gates         |  | - Parallel  |  |
    |   | - Comparison reports   |  | - Progress monitoring  |  | - Any cmd   |  |
    |   +------------------------+  +------------------------+  +-------------+  |
    |            |                            |                       |          |
    +============|============================|=======================|==========+
                 |                            |                       |
                 |      +---------delegates---+                       |
                 |      |                                             |
                 v      v                                             v
    +===========================================================================+
    |                          LIBRARY MODULES (lib/)                            |
    +===========================================================================+
    |                                                                            |
    |   +---------------+  +---------------+  +---------------+                  |
    |   | common.sh     |  | config.sh     |  | tmc-context.sh|                  |
    |   |---------------|  |---------------|  |---------------|                  |
    |   | Logging       |  | Config parse  |  | TMC context   |                  |
    |   | Colors        |  | Cluster list  |  | Auto-create   |                  |
    |   | Utilities     |  | Validation    |  | Caching       |                  |
    |   +---------------+  +---------------+  +---------------+                  |
    |                                                                            |
    |   +---------------+  +---------------+  +---------------+                  |
    |   | tmc.sh        |  | health.sh     |  | comparison.sh |                  |
    |   |---------------|  |---------------|  |---------------|                  |
    |   | TMC API       |  | Metrics       |  | PRE/POST      |                  |
    |   | Metadata      |  | Status calc   |  | Delta calc    |                  |
    |   | Kubeconfig    |  | Health check  |  | Reports       |                  |
    |   +---------------+  +---------------+  +---------------+                  |
    |                                                                            |
    +===========================================================================+
                 |
                 v
    +===========================================================================+
    |                     HEALTH CHECK SECTIONS (lib/sections/)                  |
    +===========================================================================+
    |                                                                            |
    |   01-cluster-overview    07-antrea-cni        13-resource-quotas           |
    |   02-node-status         08-tanzu-vmware      14-events                    |
    |   03-pod-status          09-security-rbac     15-connectivity              |
    |   04-workload-status     10-component-status  16-images-audit              |
    |   05-storage-status      11-helm-releases     17-certificates              |
    |   06-networking          12-namespaces        18-cluster-summary           |
    |                                                                            |
    +===========================================================================+
                 |
                 v
    +===========================================================================+
    |                          EXTERNAL TOOLS                                    |
    +===========================================================================+
    |   tanzu CLI (TMC)    |    kubectl    |    jq                               |
    +===========================================================================+
```

### Health Status Decision Tree

```
                            +-------------------+
                            |  Collect Metrics  |
                            |                   |
                            | - Nodes status    |
                            | - Pods status     |
                            | - Workloads       |
                            | - Storage         |
                            +--------+----------+
                                     |
                                     v
                         +-----------+-----------+
                         |   Nodes NotReady?     |
                         +-----------+-----------+
                                     |
                    +----------------+----------------+
                    |                                 |
                    v                                 v
                  [YES]                             [NO]
                    |                                 |
                    v                                 v
          +-----------------+             +-----------+-----------+
          |    CRITICAL     |             | Pods CrashLoopBackOff?|
          |-----------------|             +-----------+-----------+
          | - Abort upgrade |                         |
          | - Investigate   |            +------------+------------+
          | - Alert team    |            |                         |
          +-----------------+            v                         v
                                       [YES]                     [NO]
                                         |                         |
                                         v                         v
                               +-----------------+     +-----------+-----------+
                               |    CRITICAL     |     | Pending/NotReady/     |
                               +-----------------+     | Unaccounted Pods?     |
                                                       +-----------+-----------+
                                                                   |
                                                      +------------+------------+
                                                      |                         |
                                                      v                         v
                                                    [YES]                     [NO]
                                                      |                         |
                                                      v                         v
                                            +-----------------+       +-----------------+
                                            |    WARNINGS     |       |     HEALTHY     |
                                            |-----------------|       |-----------------|
                                            | - Prompt user   |       | - Auto-proceed  |
                                            | - Monitor       |       | - Safe to       |
                                            | - Proceed w/    |       |   upgrade       |
                                            |   caution       |       +-----------------+
                                            +-----------------+
```

**Health Status Summary:**

| Status | Criteria | Action |
|--------|----------|--------|
| **CRITICAL** | Nodes NotReady > 0 OR Pods CrashLoopBackOff > 0 | Abort, investigate |
| **WARNINGS** | Pods Pending > 0 OR Pods Unaccounted > 0 OR Deployments NotReady > 0 OR DaemonSets NotReady > 0 OR StatefulSets NotReady > 0 OR PVCs NotBound > 0 OR Helm Failed > 0 | Prompt user, proceed with caution |
| **HEALTHY** | None of the above | Auto-proceed |

---

## 4. Configuration

### TMC Endpoints

Edit `lib/tmc-context.sh` (lines 7-8):

```bash
NON_PROD_DNS="your-nonprod-tmc.example.com"
PROD_DNS="your-prod-tmc.example.com"
```

### Cluster Naming Convention

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

## 5. Output Structure

```
~/k8s-health-check/output/
|
+-- cluster-name/
|   +-- kubeconfig                         # Cached credentials (12h expiry)
|   +-- h-c-r/                             # Health Check Reports
|   |   +-- pre-hcr-YYYYMMDD_HHMMSS.txt
|   |   +-- post-hcr-YYYYMMDD_HHMMSS.txt
|   |   +-- comparison-hcr-YYYYMMDD_HHMMSS.txt
|   |   +-- latest/
|   |       +-- pre-hcr-YYYYMMDD_HHMMSS.txt
|   +-- ops/                               # Operations results
|   |   +-- ops-YYYYMMDD_HHMMSS.txt
|   +-- upgrade/                           # Upgrade logs
|       +-- pre-hcr-YYYYMMDD_HHMMSS.txt
|       +-- post-hcr-YYYYMMDD_HHMMSS.txt
|       +-- upgrade-log-YYYYMMDD_HHMMSS.txt
|
+-- ops-aggregated/                        # Multi-cluster aggregated results
    +-- ops-YYYYMMDD_HHMMSS.txt
```

**PRE vs POST Comparison Output:**

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

## 6. Health Check Sections (18)

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

## 7. Troubleshooting

| Issue | Solution |
|-------|----------|
| "Cannot determine environment" | Cluster name must match `*-prod-*`, `*-uat-*`, or `*-system-*` |
| "Cluster not found in TMC" | Verify: `tanzu tmc cluster list` |
| "Failed to create TMC context" | Check `lib/tmc-context.sh` lines 7-8 |
| Script hangs at prompt | Set `TMC_SELF_MANAGED_USERNAME`/`PASSWORD` |

**Debug Mode:**
```bash
DEBUG=on ./k8s-health-check.sh --mode pre 2>&1 | tee debug.log
```

**Cache Management:**
```bash
./k8s-health-check.sh --cache-status     # View cache status
./k8s-health-check.sh --clear-cache      # Clear all cached data
```

---

## 8. Quick Reference

### Health Check

| Flag | Description |
|------|-------------|
| `--mode pre\|post` | Required: Check mode |
| `-c, --cluster` | Single cluster (no clusters.conf needed) |
| `--sequential` | One at a time (default: parallel) |
| `--batch-size N` | Clusters per batch (default: 6) |
| `--cache-status` | Show cache status |
| `--clear-cache` | Clear all cached data |

### Cluster Upgrade

| Flag | Description |
|------|-------------|
| `-c CLUSTER` | Single cluster upgrade |
| `--parallel` | Parallel batch upgrades |
| `--batch-size N` | Clusters per batch (default: 6) |
| `--timeout-mult N` | Minutes per node (default: 5) |
| `--dry-run` | Preview without executing |

### Multi-Cluster Ops

| Flag | Description |
|------|-------------|
| `-c, --cluster` | Single cluster |
| `-m, --mgmt-cluster` | TMC management cluster discovery |
| `--timeout SEC` | Command timeout (default: 30) |
| `--sequential` | One at a time (default: parallel) |
| `--batch-size N` | Clusters per batch (default: 6) |

---

**Kubernetes Health & Ops Toolkit** | MIT License
