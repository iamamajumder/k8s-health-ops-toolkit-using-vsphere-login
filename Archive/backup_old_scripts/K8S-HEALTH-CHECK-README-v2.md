# Kubernetes Cluster Health Check Scripts

## Overview

These scripts provide a comprehensive health check solution for Kubernetes clusters running on **VMware Cloud Foundation 5.2.1** with **vSphere Kubernetes Service (VKS) 3.3.3**. They are specifically designed for **VKR (vSphere Kubernetes Release) upgrades** (Kubernetes versions 1.28.x/1.29.x) and day-to-day operations that trigger rolling updates on workload clusters.

## Environment Details

| Component | Version |
|-----------|---------|
| VMware Cloud Foundation | 5.2.1 |
| vSphere | 8.x (derived from VCF 5.2.1) |
| NSX | 4.x (derived from VCF 5.2.1) |
| vSphere Kubernetes Service (VKS) | 3.3.3 |
| Kubernetes (VKR) | 1.28.x / 1.29.x |

## Scripts

| Script | Purpose |
|--------|---------|
| `k8s-health-check-pre.sh` | Capture cluster state **before** upgrades or changes |
| `k8s-health-check-post.sh` | Capture cluster state **after** changes and compare with pre-change state |

---

## Quick Start

### Step 1: Before Making Changes

```bash
# Make scripts executable (first time only)
chmod +x k8s-health-check-pre.sh k8s-health-check-post.sh

# Run pre-change health check
./k8s-health-check-pre.sh <cluster-name> [output-directory]

# Examples:
./k8s-health-check-pre.sh prod-workload-cluster
./k8s-health-check-pre.sh dev-cluster ./my-healthchecks
```

### Step 2: Perform Your Change

- VKR version upgrade (Kubernetes upgrade)
- Rolling update operations
- Day-to-day maintenance activities

### Step 3: After Making Changes

```bash
# Run post-change health check with comparison
./k8s-health-check-post.sh <cluster-name> [output-directory] [pre-change-file]

# Examples:
./k8s-health-check-post.sh prod-workload-cluster
./k8s-health-check-post.sh dev-cluster ./my-healthchecks
./k8s-health-check-post.sh dev-cluster ./my-healthchecks ./my-healthchecks/dev-cluster_pre_change_20250121_100000.txt
```

---

## Usage Details

### Pre-Change Script

```bash
./k8s-health-check-pre.sh [cluster-name] [output-directory]
```

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `cluster-name` | No | Auto-detected from kubectl context | Identifier for the cluster |
| `output-directory` | No | `./k8s-healthcheck` | Directory to store output files |

**Output Files:**
- `{cluster-name}_pre_change_{YYYYMMDD_HHMMSS}.txt` - Timestamped health check output
- `{cluster-name}_pre_change_latest.txt` - Symlink to the most recent pre-change file

### Post-Change Script

```bash
./k8s-health-check-post.sh [cluster-name] [output-directory] [pre-change-file]
```

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `cluster-name` | No | Auto-detected from kubectl context | Identifier for the cluster |
| `output-directory` | No | `./k8s-healthcheck` | Directory to store output files |
| `pre-change-file` | No | `{output-dir}/{cluster}_pre_change_latest.txt` | Specific pre-change file to compare against |

**Output Files:**
- `{cluster-name}_post_change_{YYYYMMDD_HHMMSS}.txt` - Timestamped health check output
- `{cluster-name}_post_change_latest.txt` - Symlink to the most recent post-change file
- `{cluster-name}_comparison_{YYYYMMDD_HHMMSS}.txt` - Detailed comparison report
- `{cluster-name}_comparison_latest.txt` - Symlink to the most recent comparison

---

## Output Directory Structure

```
./k8s-healthcheck/
├── prod-cluster_pre_change_20250121_100000.txt
├── prod-cluster_pre_change_latest.txt -> prod-cluster_pre_change_20250121_100000.txt
├── prod-cluster_post_change_20250121_113000.txt
├── prod-cluster_post_change_latest.txt -> prod-cluster_post_change_20250121_113000.txt
├── prod-cluster_comparison_20250121_113000.txt
└── prod-cluster_comparison_latest.txt -> prod-cluster_comparison_20250121_113000.txt
```

---

## Health Checks Performed

The scripts perform comprehensive health checks across 18 sections:

### Section 1: Cluster Overview
- Current date/time
- Cluster info
- Kubernetes version
- Current context

### Section 2: Node Status
- All nodes with details (`kubectl get nodes -o wide`)
- Node conditions (MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable)
- Node resource allocation
- Node taints

### Section 3: Pod Status
- All pods across namespaces
- Non-running pods (Critical)
- CrashLoopBackOff pods
- Pending pods
- Pods with high restart counts (>5)
- Gateway pods (`gateway-0`)
- Kubernetes Dashboard pods

### Section 4: Workload Status
- Deployments (all and not-ready)
- DaemonSets (all and not-ready)
- StatefulSets
- ReplicaSets
- Jobs
- CronJobs

### Section 5: Storage Status
- Persistent Volumes (PVs)
- Persistent Volume Claims (PVCs)
- Unbound PVs/PVCs
- Storage Classes

### Section 6: Networking
- All Services
- Services in `tanzu-system-ingress`
- Pods in `tanzu-system-ingress`
- HTTPProxy resources
- Ingress resources
- Network Policies

### Section 7: Antrea/CNI Status
- Antrea controller tier count
- Antrea pods status
- Antrea agent pods

### Section 8: Tanzu/VMware Specific
- Package Installs (pkgi)
- Package Install status
- TMC impersonation secrets count
- TMC pods
- Cluster API resources (cluster, machine, machinedeployment)

### Section 9: Security & RBAC
- Pod Disruption Budgets (PDBs)
- Service Accounts (kube-system)
- Cluster Role Bindings count

### Section 10: Component Status
- Component status (deprecated but useful)
- Control plane pods
- CoreDNS status
- Metrics server

### Section 11: Helm Releases
- All Helm releases
- Failed Helm releases

### Section 12: Namespaces
- All namespaces with labels
- Namespace status

### Section 13: Resource Quotas & Limits
- Resource Quotas
- Limit Ranges

### Section 14: Events (Non-Normal)
- Warning/Error events (last 100)
- Events summary by reason

### Section 15: External Connectivity Test
- HTTPProxy ingress test with SSL verification
- Fallback to insecure connection if SSL fails
- Response preview

### Section 16: Container Images Audit
- Non-standard images (external registry)
- All unique images in cluster

### Section 17: Certificates & Secrets Summary
- Certificate resources (cert-manager)
- TLS secrets count by namespace

### Section 18: Cluster Summary
- Quick health summary with counts

---

## Comparison Report Features

The post-change script generates a detailed comparison report with:

### Critical Health Indicators
- Node status changes (count, Ready status)
- Pod status changes (non-running, CrashLoopBackOff, Pending)

### Version Changes
- Kubernetes version comparison
- Container image changes (new/removed images)

### Workload Changes
- Deployment status and readiness
- DaemonSet status
- StatefulSet status

### Storage Status
- PV/PVC binding status

### Tanzu Package Status
- Package install reconciliation status

### Helm Release Status
- Failed releases detection

### Event Analysis (Smart Filtering)

**Events FILTERED OUT** (expected during upgrades):
- Pulling, Pulled
- Created, Started
- Scheduled, SuccessfulCreate
- Killing, Deleted
- ScalingReplicaSet, SuccessfulDelete
- NodeReady, NodeNotReady
- RegisteredNode, RemovingNode
- DeletingAllPods, TerminatingEvictedPod

**Events SHOWN** (require attention):
- All other warning/error events that may indicate real issues

### Network/Ingress Status
- Tanzu ingress pod and service status
- HTTPProxy status
- Ingress connectivity test with SSL handling

### TMC Status
- TMC pods health
- Impersonation secrets count

### Summary
- Critical issues count
- Warnings count
- Overall health assessment (PASSED/WARNINGS/CRITICAL)

---

## SSL Certificate Handling

The scripts handle SSL certificates intelligently for the HTTPProxy connectivity test:

1. **First Attempt**: Tries connection with full SSL certificate verification
2. **Fallback**: If SSL verification fails (self-signed/invalid cert), retries with `-k` flag
3. **Reporting**: Clearly indicates which method succeeded and warns if SSL was skipped

```
Attempt 1: With SSL certificate verification
Result: SSL certificate verification failed

Attempt 2: Skipping SSL certificate verification (-k flag)
Result: HTTP_CODE:200 (SSL verification skipped)
[WARNING] SSL certificate may be self-signed or invalid
```

---

## Image Exclusion Pattern

The scripts filter out known/approved container images when checking for external images:

```
harbor|localhost:5000|image: sha256|vmware|broadcom|dynatrace|ghcr.io/northerntrust-internal
```

To modify this pattern, edit the `IMAGE_EXCLUSION_PATTERN` variable in both scripts.

---

## Console Output

Both scripts provide color-coded console output:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Success, healthy |
| 🟡 Yellow | Warning, attention needed |
| 🔴 Red | Critical, immediate action required |
| 🔵 Blue | Informational |

---

## Example Workflow

### Scenario: VKR Upgrade from 1.28.x to 1.29.x

```bash
# 1. Before the upgrade
$ ./k8s-health-check-pre.sh prod-cluster-01
========================================
  Kubernetes Pre-Change Health Check
========================================

Cluster: prod-cluster-01
Output:  ./k8s-healthcheck/prod-cluster-01_pre_change_20250121_100000.txt

[INFO] Verifying cluster connectivity...
[INFO] Collecting cluster state...

========================================
  Health Check Complete!
========================================

Output saved to: ./k8s-healthcheck/prod-cluster-01_pre_change_20250121_100000.txt

Quick Summary:
  Nodes: 5 total, 5 ready
  Pods:  142 total, 0 not running

# 2. Perform the VKR upgrade via vSphere/VKS

# 3. After the upgrade completes
$ ./k8s-health-check-post.sh prod-cluster-01
========================================
  Kubernetes Post-Change Health Check
========================================

Cluster: prod-cluster-01
Output:  ./k8s-healthcheck/prod-cluster-01_post_change_20250121_113000.txt

[INFO] Using pre-change file: ./k8s-healthcheck/prod-cluster-01_pre_change_latest.txt
[INFO] Verifying cluster connectivity...
[INFO] Collecting post-change cluster state...
[INFO] Post-change data collected. Starting comparison...

========================================
  Health Check & Comparison Complete!
========================================

Files generated:
  Post-Change Output: ./k8s-healthcheck/prod-cluster-01_post_change_20250121_113000.txt
  Comparison Report:  ./k8s-healthcheck/prod-cluster-01_comparison_20250121_113000.txt

============================================
         COMPARISON SUMMARY
============================================

✓ Cluster health looks good!

To view the full comparison report:
  cat ./k8s-healthcheck/prod-cluster-01_comparison_20250121_113000.txt
```

---

## Viewing Results

### View Full Comparison Report
```bash
cat ./k8s-healthcheck/{cluster}_comparison_latest.txt
```

### View Only Relevant Events
```bash
grep -A 50 'EVENTS REQUIRING ATTENTION' ./k8s-healthcheck/{cluster}_comparison_latest.txt
```

### View Critical Issues Only
```bash
grep -E '\[CRITICAL\]|\[WARNING\]' ./k8s-healthcheck/{cluster}_comparison_latest.txt
```

### View Version Changes
```bash
grep -A 20 'VERSION CHANGES' ./k8s-healthcheck/{cluster}_comparison_latest.txt
```

### View Image Changes
```bash
grep -A 30 'CONTAINER IMAGE CHANGES' ./k8s-healthcheck/{cluster}_comparison_latest.txt
```

---

## Prerequisites

- `kubectl` configured with cluster access
- `helm` (optional, for Helm release checks)
- `curl` (for connectivity tests)
- Bash shell (tested on Linux/macOS)

---

## Troubleshooting

### Script fails with "Cannot connect to Kubernetes cluster"
```bash
# Check your kubeconfig
kubectl cluster-info
kubectl config current-context
```

### Pre-change file not found
```bash
# Specify the exact pre-change file path
./k8s-health-check-post.sh my-cluster ./k8s-healthcheck ./k8s-healthcheck/my-cluster_pre_change_20250121_100000.txt
```

### Permission denied
```bash
chmod +x k8s-health-check-pre.sh k8s-health-check-post.sh
```

---

## Customization

### Modify Image Exclusion Pattern
Edit the `IMAGE_EXCLUSION_PATTERN` variable in both scripts:
```bash
IMAGE_EXCLUSION_PATTERN='harbor|localhost:5000|your-registry.com|vmware|broadcom'
```

### Add Custom Health Checks
Add new checks using the `run_check` function:
```bash
run_check "My Custom Check" "kubectl get customresource -A"
```

### Modify Event Filtering
Edit the `EXPECTED_UPGRADE_EVENTS` array in the post-change script to adjust which events are filtered during comparison.

---

## Multi-Cluster Mode

### Overview

The multi-cluster orchestrator scripts enable automated health checks across multiple Kubernetes clusters with TMC-SM integration and automatic file transfer to Windows machines.

**New Scripts:**
- `multi-cluster-pre-check.sh` - Run pre-change checks on all clusters
- `multi-cluster-post-check.sh` - Run post-change checks and comparisons on all clusters
- `clusters.conf` - Configuration file for cluster list and Windows SCP settings

### Configuration File Setup

Edit `clusters.conf` to configure your environment:

```bash
# Windows SCP Target Configuration
WINDOWS_SCP_USER=yourusername
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change

# Local output directory on Linux jumphost
LOCAL_OUTPUT_DIR=./k8s-healthcheck

# Cluster List (Format: cluster-name.management-cluster.provisioner)
prod-workload-01.mgmt-cluster-01.vsphere-tkg
prod-workload-02.mgmt-cluster-01.vsphere-tkg
dev-workload-01.mgmt-cluster-02.vsphere-tkg
```

### Cluster Name Format

Clusters are defined using the format: `cluster-name.management-cluster.provisioner`

This format is used to construct the TMC command:
```bash
tanzu tmc cluster kubeconfig get <cluster-name> -m <management-cluster> -p <provisioner>
```

**Example:**
```
prod-workload-01.mgmt-cluster-01.vsphere-tkg
```
Translates to:
```bash
tanzu tmc cluster kubeconfig get prod-workload-01 -m mgmt-cluster-01 -p vsphere-tkg
```

### Quick Start - Multi-Cluster Mode

#### Step 1: Configure Clusters

```bash
# Edit the configuration file
vi clusters.conf

# Add your clusters in the format: cluster-name.management-cluster.provisioner
prod-cluster-01.mgmt-01.vsphere-tkg
prod-cluster-02.mgmt-01.vsphere-tkg
dev-cluster-01.mgmt-02.vsphere-tkg
```

#### Step 2: Make Scripts Executable (First Time Only)

```bash
chmod +x multi-cluster-pre-check.sh multi-cluster-post-check.sh
```

#### Step 3: Run Pre-Change Checks on All Clusters

```bash
./multi-cluster-pre-check.sh

# Or specify a different config file:
./multi-cluster-pre-check.sh ./my-clusters.conf
```

**What happens:**
1. Reads cluster list from `clusters.conf`
2. For each cluster:
   - Fetches kubeconfig via `tanzu tmc cluster kubeconfig get`
   - Runs `k8s-health-check-pre.sh`
   - Saves output to `./k8s-healthcheck/`
3. Copies all pre-change reports to Windows machine via SCP

#### Step 4: Perform Your Changes

- VKR version upgrades
- Rolling updates
- Day-to-day maintenance

#### Step 5: Run Post-Change Checks on All Clusters

```bash
./multi-cluster-post-check.sh

# Or specify a different config file:
./multi-cluster-post-check.sh ./my-clusters.conf
```

**What happens:**
1. Verifies pre-change files exist for all clusters
2. For each cluster:
   - Fetches kubeconfig via TMC
   - Runs `k8s-health-check-post.sh`
   - Generates comparison report
   - Saves output to `./k8s-healthcheck/`
3. Copies all post-change and comparison reports to Windows machine via SCP
4. Displays summary with health status for each cluster

### Multi-Cluster Execution Flow

```
┌─────────────────────────────────────────────────────┐
│  Step 1: Configure clusters.conf                    │
│  - Add cluster list                                 │
│  - Configure Windows SCP settings                   │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  Step 2: Run multi-cluster-pre-check.sh            │
│  - Fetch kubeconfig for each cluster (TMC)         │
│  - Execute pre-change health checks                │
│  - Copy results to Windows machine                 │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  Step 3: Perform Changes on Clusters               │
│  - VKR upgrades                                     │
│  - Rolling updates                                  │
│  - Configuration changes                            │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  Step 4: Run multi-cluster-post-check.sh           │
│  - Fetch kubeconfig for each cluster (TMC)         │
│  - Execute post-change health checks               │
│  - Generate comparison reports                     │
│  - Copy results to Windows machine                 │
│  - Display health summary                          │
└─────────────────────────────────────────────────────┘
```

### Windows SCP Configuration

The scripts use SCP to copy health check reports to your Windows machine.

**Prerequisites:**
1. **Windows Machine:** OpenSSH Server installed and running
2. **Linux Jumphost:** SSH key configured for passwordless authentication (recommended)
3. **Network:** Linux jumphost can reach Windows machine on network

**Enable OpenSSH Server on Windows:**

```powershell
# Run in PowerShell as Administrator
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Configure firewall
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

**Setup SSH Key (Passwordless Authentication):**

```bash
# On Linux jumphost, generate SSH key if not exists
ssh-keygen -t rsa -b 4096

# Copy public key to Windows
ssh-copy-id username@windows-host

# Test connection
ssh username@windows-host
```

**Windows Path Format in Config:**

```bash
# Use double backslashes for Windows paths
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change
```

### Multi-Cluster Output

#### Directory Structure

```
./k8s-healthcheck/
├── prod-cluster-01_pre_change_20250121_100000.txt
├── prod-cluster-01_pre_change_latest.txt -> prod-cluster-01_pre_change_20250121_100000.txt
├── prod-cluster-01_post_change_20250121_150000.txt
├── prod-cluster-01_post_change_latest.txt -> prod-cluster-01_post_change_20250121_150000.txt
├── prod-cluster-01_comparison_20250121_150000.txt
├── prod-cluster-01_comparison_latest.txt -> prod-cluster-01_comparison_20250121_150000.txt
├── prod-cluster-02_pre_change_20250121_101000.txt
├── prod-cluster-02_pre_change_latest.txt -> prod-cluster-02_pre_change_20250121_101000.txt
├── prod-cluster-02_post_change_20250121_151000.txt
├── prod-cluster-02_post_change_latest.txt -> prod-cluster-02_post_change_20250121_151000.txt
├── prod-cluster-02_comparison_20250121_151000.txt
└── prod-cluster-02_comparison_latest.txt -> prod-cluster-02_comparison_20250121_151000.txt
```

#### Console Output Example

```bash
$ ./multi-cluster-pre-check.sh

================================================================================
Multi-Cluster Pre-Change Health Check Orchestrator
================================================================================

Configuration File: ./clusters.conf
Script Directory: /home/admin/k8s-healthcheck
Started: 2025-01-21 10:00:00 IST

[INFO] Reading configuration file...
[INFO] Local output directory: ./k8s-healthcheck
[INFO] Windows SCP target: admin@192.168.1.100:C:\HealthCheckReports\pre-change
[INFO] Found 3 cluster(s) in configuration

Clusters to process:
 1. prod-workload-01.mgmt-cluster-01.vsphere-tkg
 2. prod-workload-02.mgmt-cluster-01.vsphere-tkg
 3. dev-workload-01.mgmt-cluster-02.vsphere-tkg

Continue with pre-change health checks? [y/N]: y

[1/3] Processing: prod-workload-01.mgmt-cluster-01.vsphere-tkg

================================================================================
Processing Cluster: prod-workload-01
================================================================================

[INFO] Management Cluster: mgmt-cluster-01
[INFO] Provisioner: vsphere-tkg
[INFO] Fetching kubeconfig for cluster: prod-workload-01
[SUCCESS] Kubeconfig fetched successfully for prod-workload-01
[INFO] Verifying connectivity to prod-workload-01...
[SUCCESS] Connected to cluster prod-workload-01
[INFO] Running pre-change health check for prod-workload-01...
[SUCCESS] Pre-change health check completed for prod-workload-01

───────────────────────────────────────────────────────────────────────────────

[2/3] Processing: prod-workload-02.mgmt-cluster-01.vsphere-tkg
...

================================================================================
Execution Summary
================================================================================

Total Clusters:    3
Successful:        3
Failed:            0
Completed:         2025-01-21 10:15:00 IST

[SUCCESS] All pre-change health checks completed successfully!

Next Steps:
  1. Review health check reports in: ./k8s-healthcheck
  2. Perform your cluster changes/upgrades
  3. Run post-change checks: ./multi-cluster-post-check.sh
```

### Multi-Cluster Post-Check Summary

After running `multi-cluster-post-check.sh`, you'll see a comprehensive summary:

```bash
================================================================================
Execution Summary
================================================================================

Total Clusters:    3
Checks Completed:  3
Checks Failed:     0

Health Status:
  Passed:          2
  Warnings:        1
  Critical:        0

Completed:         2025-01-21 15:30:00 IST

================================================================================
Cluster Status Summary
================================================================================

Cluster: prod-workload-01
  Status: PASSED
  Report: ./k8s-healthcheck/prod-workload-01_comparison_latest.txt

Cluster: prod-workload-02
  Status: WARNING (2 warning(s))
  Report: ./k8s-healthcheck/prod-workload-02_comparison_latest.txt

Cluster: dev-workload-01
  Status: PASSED
  Report: ./k8s-healthcheck/dev-workload-01_comparison_latest.txt

[WARNING] 1 cluster(s) have warnings

Recommended Actions:
  1. Review comparison reports for clusters with WARNING status
  2. Monitor warnings - they may resolve during rolling update completion
  3. Check logs: grep '[WARNING]' ./k8s-healthcheck/*_comparison_latest.txt
```

### Troubleshooting Multi-Cluster Mode

#### TMC Authentication Issues

```bash
# Verify TMC login
tanzu tmc login

# Test cluster access
tanzu tmc cluster list

# Manually test kubeconfig fetch
tanzu tmc cluster kubeconfig get <cluster-name> -m <mgmt-cluster> -p <provisioner>
```

#### SCP Copy Fails

```bash
# Test SSH connectivity to Windows
ssh username@windows-host

# Verify OpenSSH Server is running on Windows (PowerShell)
Get-Service sshd

# Check if target directory exists on Windows
ssh username@windows-host "dir C:\HealthCheckReports"

# Manual SCP test
scp test.txt username@windows-host:C:/HealthCheckReports/
```

#### Pre-Change File Not Found

```bash
# List all pre-change files
ls -la ./k8s-healthcheck/*_pre_change_*.txt

# Re-run pre-check for specific cluster
./k8s-health-check-pre.sh cluster-name ./k8s-healthcheck
```

#### Cluster Not Found in TMC

```bash
# List all clusters in TMC
tanzu tmc cluster list

# Verify cluster name format in clusters.conf
# Format: cluster-name.management-cluster.provisioner
```

### Advanced Usage

#### Custom Configuration File

```bash
# Create separate config for production clusters
cp clusters.conf prod-clusters.conf
vi prod-clusters.conf

# Run with custom config
./multi-cluster-pre-check.sh prod-clusters.conf
./multi-cluster-post-check.sh prod-clusters.conf
```

#### Processing Subset of Clusters

```bash
# Create temporary config with specific clusters
cat > temp-clusters.conf << 'EOF'
WINDOWS_SCP_USER=admin
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change
LOCAL_OUTPUT_DIR=./k8s-healthcheck

# Only process these clusters
prod-cluster-01.mgmt-01.vsphere-tkg
prod-cluster-02.mgmt-01.vsphere-tkg
EOF

./multi-cluster-pre-check.sh temp-clusters.conf
```

#### Viewing Results Across All Clusters

```bash
# View all comparison summaries
for file in ./k8s-healthcheck/*_comparison_latest.txt; do
    echo "=== $(basename $file) ==="
    grep -E '\[CRITICAL\]|\[WARNING\]|RESULT:' "$file"
    echo ""
done

# Find all critical issues
grep -r '\[CRITICAL\]' ./k8s-healthcheck/*_comparison_latest.txt

# Find all warnings
grep -r '\[WARNING\]' ./k8s-healthcheck/*_comparison_latest.txt

# Get quick summary for all clusters
for file in ./k8s-healthcheck/*_comparison_latest.txt; do
    cluster=$(basename "$file" | cut -d'_' -f1-3)
    result=$(grep "RESULT:" "$file" | tail -1)
    echo "${cluster}: ${result}"
done
```

---

## License

Internal use only. Designed for VMware Cloud Foundation / Tanzu Kubernetes environments.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-01-21 | Initial release with full health check and comparison features |
| 2.0.0 | 2025-01-21 | Added multi-cluster orchestration with TMC-SM integration and Windows SCP support |
