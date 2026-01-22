# Kubernetes Cluster Health Check

**Version 3.1** - Automated Health Check with TMC Auto-Discovery

---

## Overview

Comprehensive automated health check system for Kubernetes clusters running on **VMware Cloud Foundation 5.2.1** with **Tanzu Mission Control (TMC) Self-Managed**. Designed for VKR upgrades and day-to-day cluster operations.

### Key Features

- ✅ **Auto-Discovery**: Automatically discovers cluster metadata from TMC
- ✅ **Auto-Context**: Automatically creates TMC contexts based on naming patterns
- ✅ **18 Health Check Modules**: Comprehensive cluster state assessment
- ✅ **PRE/POST Comparison**: Intelligent comparison with issue classification
- ✅ **Multi-Cluster**: Process multiple clusters sequentially
- ✅ **Error Resilient**: Graceful handling of failures, continues with other clusters

### Environment

| Component | Version |
|-----------|---------|
| VMware Cloud Foundation | 5.2.1 |
| vSphere | 8.x |
| NSX | 4.x |
| vSphere Kubernetes Service (VKS) | 3.3.3 |
| Kubernetes (VKR) | 1.28.x / 1.29.x |

---

## Prerequisites

### Required

1. **Tanzu CLI** installed and available in PATH
   ```bash
   tanzu version
   ```

2. **kubectl** installed and configured
   ```bash
   kubectl version --client
   ```

3. **TMC Self-Managed Access**
   - Production TMC instance FQDN
   - Non-production TMC instance FQDN
   - Valid credentials (username/password)

4. **Cluster Naming Convention**
   Your clusters MUST follow these patterns:
   - `*-prod-[1-4]` → Production (e.g., `workload-prod-01`)
   - `*-uat-[1-4]` → Non-production (e.g., `workload-uat-01`)
   - `*-system-[1-4]` → Non-production (e.g., `dev-system-01`)

### Optional (Recommended)

- **jq** - For faster JSON parsing
  ```bash
  # Ubuntu/Debian
  sudo apt-get install jq

  # RHEL/CentOS
  sudo yum install jq

  # macOS
  brew install jq
  ```

---

## Quick Start

### 1. Configure TMC Endpoints

**CRITICAL:** Edit `lib/tmc-context.sh` and set your TMC FQDNs:

```bash
# Edit lines 7-8 in lib/tmc-context.sh
NON_PROD_DNS="your-nonprod-tmc.example.com"    # ← SET THIS
PROD_DNS="your-prod-tmc.example.com"           # ← SET THIS
```

### 2. Create Cluster Configuration

Create `clusters.conf` with your cluster names (one per line):

```bash
cat > clusters.conf <<EOF
# Production Clusters
prod-workload-01
prod-workload-02

# UAT Clusters
uat-system-01

# Development Clusters
dev-system-01
EOF
```

### 3. Make Scripts Executable

```bash
chmod +x k8s-health-check-pre.sh k8s-health-check-post.sh
```

### 4. Run PRE-Change Health Check

```bash
./k8s-health-check-pre.sh ./clusters.conf
```

**First Run:** You'll be prompted for TMC username/password
**Subsequent Runs:** TMC contexts are reused

### 5. Perform Your Changes

- VKR upgrade
- Configuration changes
- Rolling updates
- etc.

### 6. Run POST-Change Health Check

```bash
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20250122_143000
```

**Result:** Generates comparison reports showing differences

---

## Project Structure

```
k8-health-check/
├── k8s-health-check-pre.sh          # PRE-change health check
├── k8s-health-check-post.sh         # POST-change health check with comparison
├── clusters.conf                     # Cluster configuration (simple names)
│
├── lib/                              # Library modules
│   ├── common.sh                     # Shared utilities & logging
│   ├── config.sh                     # Configuration parser
│   ├── tmc-context.sh                # TMC context auto-creation ⭐
│   ├── tmc.sh                        # TMC integration with auto-discovery ⭐
│   ├── scp.sh                        # Optional Windows SCP transfer
│   ├── comparison.sh                 # PRE/POST comparison logic
│   │
│   └── sections/                     # 18 health check modules
│       ├── 01-cluster-overview.sh    # Date, cluster info, K8s version
│       ├── 02-node-status.sh         # Node health, conditions, taints
│       ├── 03-pod-status.sh          # Pod status, failures
│       ├── 04-workload-status.sh     # Deployments, DaemonSets, StatefulSets
│       ├── 05-storage-status.sh      # PVs, PVCs, StorageClasses
│       ├── 06-networking.sh          # Services, Ingress, HTTPProxy
│       ├── 07-antrea-cni.sh          # Antrea CNI pods
│       ├── 08-tanzu-vmware.sh        # Tanzu packages, TMC agents
│       ├── 09-security-rbac.sh       # PDBs, RBAC resources
│       ├── 10-component-status.sh    # Control plane pods
│       ├── 11-helm-releases.sh       # Helm release status
│       ├── 12-namespaces.sh          # Namespace listing
│       ├── 13-resource-quotas.sh     # Quotas and limits
│       ├── 14-events.sh              # Warning/Error events (filtered)
│       ├── 15-connectivity.sh        # HTTPProxy connectivity tests
│       ├── 16-images-audit.sh        # Container image audit
│       ├── 17-certificates.sh        # Certificate resources
│       └── 18-cluster-summary.sh     # Quick health summary
│
└── health-check-results/             # Output directory (auto-created)
    ├── pre-YYYYMMDD_HHMMSS/          # PRE-change results
    │   └── cluster-name/
    │       ├── kubeconfig            # Cluster kubeconfig
    │       └── health-check-report.txt
    │
    └── post-YYYYMMDD_HHMMSS/         # POST-change results
        └── cluster-name/
            ├── kubeconfig
            ├── health-check-report.txt
            └── comparison-report.txt  # ← PRE/POST comparison
```

---

## How It Works

### Architecture Flow

```
User provides: clusters.conf (simple cluster names)
        ↓
1. Script reads clusters.conf
        ↓
2. For each cluster:
   ├─→ Detect environment from name (prod/nonprod)
   ├─→ Create/reuse TMC context automatically
   ├─→ Auto-discover management cluster & provisioner from TMC
   ├─→ Fetch kubeconfig from TMC
   ├─→ Execute 18 health check modules
   └─→ Save report
        ↓
3. POST script additionally:
   ├─→ Compare with PRE results
   └─→ Generate comparison report (PASSED/WARNING/CRITICAL)
```

### Auto-Discovery

You provide only the cluster name:
```
prod-workload-01
```

The script automatically discovers:
- **Environment**: Production (from `-prod-` pattern)
- **TMC Context**: `tmc-sm-prod` (auto-created)
- **Management Cluster**: `mgmt-cluster-01` (from TMC API)
- **Provisioner**: `vsphere-tkg` (from TMC API)

### Auto-Context Creation

Based on cluster naming:
- `*-prod-[1-4]` → Creates/uses `tmc-sm-prod` context
- `*-uat-[1-4]` → Creates/uses `tmc-sm-nonprod` context
- `*-system-[1-4]` → Creates/uses `tmc-sm-nonprod` context

Contexts are reused within and across executions for efficiency.

### Metadata Caching

Discovered cluster metadata is cached during execution:
- **First cluster**: Queries TMC API
- **Same cluster again**: Uses cached data (fast)
- **Cache location**: `/tmp/k8s-health-check-cluster-cache-$$.txt`
- **Cleanup**: Automatic at script end

---

## Usage

### Basic Usage

**PRE-change check:**
```bash
./k8s-health-check-pre.sh ./clusters.conf
```

**POST-change check with comparison:**
```bash
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20250122_143000
```

### With Environment Variables

Avoid interactive prompts by setting credentials:

```bash
export TMC_SELF_MANAGED_USERNAME="your-username@example.com"
export TMC_SELF_MANAGED_PASSWORD="your-password"

./k8s-health-check-pre.sh ./clusters.conf
```

### With Debug Output

Enable verbose logging:

```bash
DEBUG=on ./k8s-health-check-pre.sh ./clusters.conf
```

### Single Cluster Check

Create config with one cluster:

```bash
echo "prod-workload-01" > single-cluster.conf
./k8s-health-check-pre.sh single-cluster.conf
```

### Windows SCP Transfer (Optional)

Automatically copy reports to Windows machine:

```bash
export WINDOWS_SCP_ENABLED="true"
export WINDOWS_SCP_USER="windowsuser"
export WINDOWS_SCP_HOST="192.168.1.100"
export WINDOWS_PRE_PATH="C:\\HealthCheckReports\\pre"
export WINDOWS_POST_PATH="C:\\HealthCheckReports\\post"

./k8s-health-check-pre.sh ./clusters.conf
```

---

## Configuration

### clusters.conf Format

Simple format - one cluster name per line:

```bash
# Comments start with #
# Empty lines are ignored

# Production Clusters (naming pattern: *-prod-[1-4])
prod-workload-01
prod-workload-02

# UAT Clusters (naming pattern: *-uat-[1-4])
uat-system-01
uat-system-02

# Development Clusters (naming pattern: *-system-[1-4])
dev-system-01
```

### TMC Endpoint Configuration

Edit `lib/tmc-context.sh`:

```bash
# Lines 7-10
NON_PROD_DNS="nonprod-tmc.example.com"
PROD_DNS="prod-tmc.example.com"
TMC_SM_CONTEXT_PROD="tmc-sm-prod"
TMC_SM_CONTEXT_NONPROD="tmc-sm-nonprod"
```

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `TMC_SELF_MANAGED_USERNAME` | TMC username | No (prompts if not set) |
| `TMC_SELF_MANAGED_PASSWORD` | TMC password | No (prompts if not set) |
| `DEBUG` | Verbose output (`on`/`off`) | No |
| `WINDOWS_SCP_ENABLED` | Enable Windows SCP (`true`/`false`) | No |
| `WINDOWS_SCP_USER` | Windows username | If SCP enabled |
| `WINDOWS_SCP_HOST` | Windows hostname/IP | If SCP enabled |
| `WINDOWS_PRE_PATH` | Windows PRE reports path | If SCP enabled |
| `WINDOWS_POST_PATH` | Windows POST reports path | If SCP enabled |

---

## Health Check Modules

### 18 Comprehensive Checks

| # | Module | What It Checks |
|---|--------|----------------|
| 1 | cluster-overview | Date, cluster info, Kubernetes version |
| 2 | node-status | Node health, conditions, taints, capacity |
| 3 | pod-status | Pod status, CrashLoopBackOff, Pending pods |
| 4 | workload-status | Deployments, DaemonSets, StatefulSets availability |
| 5 | storage-status | PersistentVolumes, PVCs, StorageClasses |
| 6 | networking | Services, Ingress, HTTPProxy resources |
| 7 | antrea-cni | Antrea CNI pods and agent status |
| 8 | tanzu-vmware | Tanzu package installs, TMC agent pods |
| 9 | security-rbac | PodDisruptionBudgets, RBAC resources |
| 10 | component-status | Control plane pods (apiserver, etcd, etc.) |
| 11 | helm-releases | Helm release status and versions |
| 12 | namespaces | Namespace listing and status |
| 13 | resource-quotas | ResourceQuotas and LimitRanges |
| 14 | events | Warning/Error events (intelligently filtered) |
| 15 | connectivity | HTTPProxy connectivity tests |
| 16 | images-audit | Container images in use (external registries) |
| 17 | certificates | Certificate resources and expiration |
| 18 | cluster-summary | Quick health summary with metrics |

### Intelligent Event Filtering

Module 14 filters out expected upgrade events, focusing on real issues:

**Excluded (expected during upgrades):**
- Pulling, Pulled, Created, Started
- Scheduled, Killing, SuccessfulCreate
- ScalingReplicaSet, etc.

**Included (real issues):**
- FailedScheduling, BackOff, Unhealthy
- FailedMount, FailedAttachVolume
- NetworkNotReady, CNINotReady

---

## Comparison Report

### POST-Change Comparison

The POST script generates detailed comparison reports:

```
================================================================================
  KUBERNETES CLUSTER HEALTH CHECK - COMPARISON REPORT
================================================================================

Cluster:          prod-workload-01
Pre-Change:       2025-01-22 14:00:00
Post-Change:      2025-01-22 16:00:00

[PASSED] CRITICAL HEALTH CHECK
  Nodes: 5 ready (no change)
  Pods: 0 not running (no change)

[INFO] VERSION CHANGES
  Kubernetes Version:
    Before: v1.28.8+vmware.1
    After:  v1.29.2+vmware.1

[PASSED] WORKLOAD STATUS
  All deployments ready and available
  All DaemonSets running on all nodes
  All StatefulSets ready

[WARNING] EVENTS
  New warning events detected:
    - Pod 'my-app-123' FailedScheduling (Insufficient memory)

================================================================================
OVERALL STATUS: WARNING
================================================================================
Review new events in the Events section above.
```

### Status Classifications

- **PASSED** - No issues detected, all good
- **WARNING** - Non-critical changes detected, review recommended
- **CRITICAL** - Critical issues detected (nodes down, pods failing)
- **INFO** - Informational changes (expected, like version changes)

---

## Common Scenarios

### Scenario 1: VKR Upgrade (Kubernetes 1.28 → 1.29)

```bash
# 1. Before upgrade
./k8s-health-check-pre.sh ./clusters.conf
# Saves to: health-check-results/pre-20250122_140000/

# 2. Perform VKR upgrade using TMC or kubectl
# ...

# 3. After upgrade
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20250122_140000
# Saves to: health-check-results/post-20250122_160000/

# 4. Review comparison reports
cat health-check-results/post-20250122_160000/*/comparison-report.txt

# Expected: Version change INFO, everything else PASSED
```

### Scenario 2: Configuration Change

```bash
# 1. Capture current state
./k8s-health-check-pre.sh ./clusters.conf

# 2. Apply configuration changes
kubectl apply -f new-config.yaml

# 3. Check impact
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-*

# 4. Review what changed
grep -E "WARNING|CRITICAL" health-check-results/post-*/*/comparison-report.txt
```

### Scenario 3: Routine Health Check

```bash
# Weekly cluster health check (no changes)
./k8s-health-check-pre.sh ./clusters.conf

# Review the summary section
grep -A 20 "CLUSTER SUMMARY" health-check-results/pre-*/*/health-check-report.txt
```

---

## Troubleshooting

### Issue: "Cannot determine environment for cluster"

**Cause:** Cluster name doesn't match required patterns

**Solution:**
```bash
# Your cluster: my-cluster
# Expected: *-prod-[1-4], *-uat-[1-4], or *-system-[1-4]

# Option A: Rename cluster (if possible)
# my-cluster → prod-cluster-01

# Option B: Customize naming pattern in lib/tmc-context.sh
# Edit the determine_environment() function
```

### Issue: "Cluster not found in TMC or missing metadata"

**Cause:** Cluster doesn't exist in TMC or name is incorrect

**Diagnosis:**
```bash
# Verify cluster exists in TMC
tanzu tmc cluster list | grep your-cluster-name

# Check current TMC context
tanzu context current

# List all accessible clusters
tanzu tmc cluster list
```

**Solution:**
- Verify cluster name spelling in clusters.conf
- Ensure cluster is registered in TMC
- Check TMC authentication

### Issue: "Failed to create TMC context"

**Cause:** Incorrect TMC endpoint or credentials

**Diagnosis:**
```bash
# Check endpoint configuration
grep -E "(NON_PROD_DNS|PROD_DNS)" lib/tmc-context.sh

# Test connectivity
ping prod-tmc.example.com

# Test manual context creation
tanzu tmc context create test --endpoint prod-tmc.example.com -i pinniped --basic-auth
```

**Solution:**
- Verify TMC FQDN is correct in lib/tmc-context.sh
- Check network connectivity to TMC
- Verify credentials are correct

### Issue: "jq not found" warning

**Cause:** jq command not installed (non-critical)

**Impact:** Slower JSON parsing, but still works

**Solution (optional):**
```bash
# Install jq for better performance
# Ubuntu/Debian: sudo apt-get install jq
# RHEL/CentOS: sudo yum install jq
# macOS: brew install jq
```

### Issue: Failed to connect to cluster

**Cause:** Kubeconfig fetch succeeded but cluster unreachable

**Diagnosis:**
```bash
# Check kubeconfig file
ls -la health-check-results/pre-*/cluster-name/kubeconfig

# Test manually
export KUBECONFIG=health-check-results/pre-*/cluster-name/kubeconfig
kubectl cluster-info
```

**Solution:**
- Verify cluster is running
- Check network connectivity to cluster API server
- Verify TMC agent is healthy on cluster

---

## Performance

### Execution Time

**Per Cluster:**
- TMC context creation (first time): 5-10 seconds
- TMC context reuse: < 1 second
- Metadata discovery (first time): 2-3 seconds
- Metadata cache hit: < 0.1 seconds
- Kubeconfig fetch: 2-5 seconds
- Health checks execution: 30-60 seconds
- Comparison report: 5-10 seconds

**Example: 10 Clusters**
- PRE-change: ~6-10 minutes
- POST-change: ~7-12 minutes

### Optimization

1. **Install jq** - Faster JSON parsing
2. **Set env vars** - Avoid credential prompts
3. **Caching** - Automatic metadata caching
4. **Context reuse** - Automatic TMC context reuse

---

## Security

### Best Practices

1. **Credentials Management**
   ```bash
   # Use environment variables
   export TMC_SELF_MANAGED_USERNAME="user"
   export TMC_SELF_MANAGED_PASSWORD="$(vault read -field=password secret/tmc)"
   ```

2. **Protect Output**
   ```bash
   # Kubeconfig files contain cluster access
   chmod 700 health-check-results/

   # Clean up old reports regularly
   find health-check-results/ -mtime +30 -delete
   ```

3. **Separate Contexts**
   - Production: `tmc-sm-prod`
   - Non-production: `tmc-sm-nonprod`
   - Different credentials recommended

4. **Archive Securely**
   ```bash
   # Encrypt before archiving
   tar czf reports.tar.gz health-check-results/
   gpg -c reports.tar.gz
   rm reports.tar.gz
   ```

---

## Tips & Best Practices

### 1. Always Run PRE-Change Checks

Never skip PRE-change checks, even for "minor" changes:

```bash
# ✅ GOOD
./k8s-health-check-pre.sh ./clusters.conf
# ... make changes ...
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-*

# ❌ BAD
# ... make changes ...
./k8s-health-check-post.sh ./clusters.conf  # No PRE to compare!
```

### 2. Review Comparison Reports

Don't just run the scripts - review the output:

```bash
# Quick check for issues
grep -E "CRITICAL|WARNING" health-check-results/post-*/*/comparison-report.txt

# Detailed review
less health-check-results/post-*/prod-workload-01/comparison-report.txt
```

### 3. Test on Non-Production First

```bash
# Create nonprod config
grep -E "(uat|dev|system)" clusters.conf > clusters-nonprod.conf

# Test on nonprod first
./k8s-health-check-pre.sh clusters-nonprod.conf
# ... make changes on nonprod ...
./k8s-health-check-post.sh clusters-nonprod.conf health-check-results/pre-*

# Review results before proceeding to production
```

### 4. Archive Reports

```bash
# Archive after each major change
tar -czf health-check-$(date +%Y%m%d).tar.gz health-check-results/
mv health-check-*.tar.gz /archive/health-checks/
```

### 5. Automate with Scripts

```bash
#!/bin/bash
# automated-check.sh

export TMC_SELF_MANAGED_USERNAME="svc-account"
export TMC_SELF_MANAGED_PASSWORD="$(vault read -field=password secret/tmc)"

./k8s-health-check-pre.sh ./clusters.conf 2>&1 | tee check-$(date +%Y%m%d).log

# Check for failures
if grep -q "Failed:" check-*.log; then
    echo "Some clusters failed - review log"
    exit 1
fi
```

---

## Support

### Getting Help

1. Review this README thoroughly
2. Check error messages in script output
3. Enable DEBUG mode: `DEBUG=on ./k8s-health-check-pre.sh ./clusters.conf`
4. Verify prerequisites are met
5. Test with single cluster first

### Common Questions

**Q: Can I use different cluster naming patterns?**
A: Yes, edit `lib/tmc-context.sh` and modify the `determine_environment()` function.

**Q: Do I need to create TMC contexts manually?**
A: No, the scripts create them automatically based on cluster names.

**Q: Can I run multiple clusters in parallel?**
A: Scripts process clusters sequentially for better observability. Parallel processing not recommended due to TMC rate limits.

**Q: How long are reports kept?**
A: Scripts don't auto-delete. Implement your own retention policy (e.g., delete reports older than 30 days).

**Q: Can I use this without TMC?**
A: No, this version requires TMC. The TMC logic is isolated in `lib/tmc.sh` and `lib/tmc-context.sh` for future flexibility.

---

## Version Information

**Current Version:** 3.1
**Release Date:** 2025-01-22

### Key Features in v3.1

- ✅ Simplified configuration (just cluster names)
- ✅ Auto-discovery of cluster metadata from TMC
- ✅ Auto-creation of TMC contexts
- ✅ Metadata caching for performance
- ✅ Unified execution (no --multi flag)
- ✅ 33% code reduction for better maintainability

### Tested Environment

- VMware Cloud Foundation 5.2.1
- vSphere 8.x
- NSX 4.x
- VKS 3.3.3
- VKR 1.28.x / 1.29.x
- TMC Self-Managed

---

## Quick Reference

### Required Configuration

```bash
# 1. Edit lib/tmc-context.sh
NON_PROD_DNS="your-nonprod-tmc.example.com"
PROD_DNS="your-prod-tmc.example.com"

# 2. Create clusters.conf
cat > clusters.conf <<EOF
prod-workload-01
prod-workload-02
uat-system-01
EOF

# 3. Run PRE check
./k8s-health-check-pre.sh ./clusters.conf

# 4. Make changes
# ...

# 5. Run POST check
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-*
```

### Cluster Naming Patterns

| Pattern | Environment | Example |
|---------|-------------|---------|
| `*-prod-[1-4]` | Production | `workload-prod-01` |
| `*-uat-[1-4]` | Non-production | `test-uat-01` |
| `*-system-[1-4]` | Non-production | `dev-system-01` |

### Output Structure

```
health-check-results/
├── pre-YYYYMMDD_HHMMSS/
│   └── cluster-name/
│       ├── kubeconfig
│       └── health-check-report.txt
└── post-YYYYMMDD_HHMMSS/
    └── cluster-name/
        ├── kubeconfig
        ├── health-check-report.txt
        └── comparison-report.txt
```

---

**Ready to use after configuring TMC endpoints in lib/tmc-context.sh**
