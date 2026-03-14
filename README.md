# Kubernetes Health & Ops Toolkit (v1.0)

vSphere-only toolkit for:
- PRE/POST health checks
- workload cluster upgrades
- multi-cluster ops command execution

Runs fully through Supervisor/vSphere workflows.

## Scripts

### 1) `k8s-health-check.sh`
Runs PRE/POST health reports for clusters listed in `input.conf` (or a single cluster with `-c`).

Key flags:
- `--mode pre|post`
- `-c, --cluster <name>`
- `--sequential`
- `--batch-size N`
- `--cache-status`
- `--clear-cache`

### 2) `k8s-cluster-upgrade.sh`
Upgrades workload clusters via Supervisor object patching:
- Cluster API path: `cluster.spec.topology.version`
- TKC path: `tanzukubernetescluster.spec.distribution.version`

If TKC retirement is required, the script prompts:
`Do you want to enable Auto-retire the workload cluster from tkc to cluster api? (Y/N)`

Key flags:
- `-c, --cluster <name>`
- `--parallel`
- `--batch-size N`
- `--timeout-multiplier N`
- `--dry-run`

### 3) `k8s-ops-cmd.sh`
Runs one command across many clusters.

Discovery modes:
- Config file list (`input.conf`)
- Environment discovery (`-m prod-1|prod-2|uat-2|system-3`) from Supervisor mappings

Key flags:
- `-c, --cluster <name>`
- `-m, --management-cluster <env>`
- `--timeout <sec>`
- `--sequential`
- `--batch-size N`
- `--output-only`

## Prerequisites

- `kubectl`
- `kubectl vsphere` plugin
- `jq`
- Bash 4+

## Configuration (`input.conf`)

`input.conf` supports:
- optional credentials block
- supervisor suffix to endpoint mapping
- cluster names

Credential behavior:
- `AO_ACCOUNT_*` is used for all Supervisor logins and for production workload logins.
- `NONAO_ACCOUNT_*` is used only for non-production workload logins.

Example:

```ini
# ===CREDENTIALS===
# AO_ACCOUNT_USERNAME=supervisor-and-prod-user
# AO_ACCOUNT_PASSWORD=supervisor-and-prod-pass
# NONAO_ACCOUNT_USERNAME=nonprod-workload-user
# NONAO_ACCOUNT_PASSWORD=nonprod-workload-pass
# ===END_CREDENTIALS===

# ===SUPERVISORS===
prod-1=supvr-prod-1.example.com
prod-2=supvr-prod-2.example.com
system-3=supvr-system-3.example.com
uat-2=supvr-uat-2.example.com
# ===END_SUPERVISORS===

svcs-k8s-1-prod-1
svcs-k8s-2-prod-2
```

## Output Layout

All outputs are under:
`<repo>/output/<cluster>/`

Subpaths:
- `kubeconfig`
- `h-c-r/`
- `ops/`
- `upgrade/`

Aggregated ops output:
- `<repo>/output/ops-aggregated/`

## Quick Start

```bash
chmod +x k8s-health-check.sh k8s-cluster-upgrade.sh k8s-ops-cmd.sh

# PRE health check
./k8s-health-check.sh --mode pre

# Single cluster upgrade
./k8s-cluster-upgrade.sh -c svcs-k8s-1-prod-1

# Multi-cluster ops
./k8s-ops-cmd.sh "kubectl get nodes --no-headers | wc -l"
```



