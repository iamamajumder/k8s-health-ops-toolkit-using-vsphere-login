# Kubernetes Cluster Health Check Scripts

**Version 3.0** - Modular Architecture with Unified Single and Multi-Cluster Support

## Overview

Comprehensive health check solution for Kubernetes clusters running on **VMware Cloud Foundation 5.2.1** with **vSphere Kubernetes Service (VKS) 3.3.3**. Designed for **VKR upgrades** (Kubernetes 1.28.x/1.29.x) and day-to-day operations.

### Environment

| Component | Version |
|-----------|---------|
| VMware Cloud Foundation | 5.2.1 |
| vSphere | 8.x |
| NSX | 4.x |
| vSphere Kubernetes Service (VKS) | 3.3.3 |
| Kubernetes (VKR) | 1.28.x / 1.29.x |

### Architecture

**Modular library-based design** for maintainability and extensibility:

```
k8-health-check/
├── k8s-health-check-pre.sh          # Unified PRE script (single + multi cluster)
├── k8s-health-check-post.sh         # Unified POST script (single + multi cluster)
├── lib/                              # Modular libraries
│   ├── common.sh                     # Shared utilities & logging
│   ├── config.sh                     # Configuration parser
│   ├── tmc.sh                        # TMC integration
│   ├── scp.sh                        # Windows file transfer
│   ├── comparison.sh                 # Comparison logic
│   └── sections/                     # 18 health check modules
│       ├── 01-cluster-overview.sh
│       ├── 02-node-status.sh
│       └── ... (16 more modules)
├── clusters.conf                     # Multi-cluster configuration
└── backup_old_scripts/               # Backup of previous version
```

---

## Quick Start

### Single Cluster Mode

Perfect for individual cluster health checks:

```bash
# 1. Make scripts executable (first time only)
chmod +x k8s-health-check-pre.sh k8s-health-check-post.sh

# 2. Before making changes
./k8s-health-check-pre.sh prod-cluster-01

# 3. Perform your changes (VKR upgrade, rolling updates, etc.)

# 4. After making changes
./k8s-health-check-post.sh prod-cluster-01
```

### Multi-Cluster Mode

Automated health checks across multiple clusters:

```bash
# 1. Configure clusters in clusters.conf
vi clusters.conf

# 2. Run pre-change checks on all clusters
./k8s-health-check-pre.sh --multi ./clusters.conf

# 3. Perform your changes across clusters

# 4. Run post-change checks and comparisons
./k8s-health-check-post.sh --multi ./clusters.conf
```

---

## Single Cluster Usage

### Pre-Change Health Check

```bash
./k8s-health-check-pre.sh [cluster-name] [output-directory]

# Examples:
./k8s-health-check-pre.sh prod-cluster                    # Uses current context
./k8s-health-check-pre.sh dev-cluster ./my-reports        # Custom output dir
```

**Parameters:**
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `cluster-name` | No | Auto-detected from kubectl context | Cluster identifier |
| `output-directory` | No | `./k8s-healthcheck` | Output directory |

**Output Files:**
- `{cluster}_pre_change_{timestamp}.txt` - Full health check report
- `{cluster}_pre_change_latest.txt` - Symlink to latest report

### Post-Change Health Check

```bash
./k8s-health-check-post.sh [cluster-name] [output-directory] [pre-change-file]

# Examples:
./k8s-health-check-post.sh prod-cluster                    # Auto-finds pre-change file
./k8s-health-check-post.sh dev-cluster ./my-reports        # Custom output dir
```

**Output Files:**
- `{cluster}_post_change_{timestamp}.txt` - Full health check report
- `{cluster}_post_change_latest.txt` - Symlink to latest
- `{cluster}_comparison_{timestamp}.txt` - **Comparison report** (Critical!)
- `{cluster}_comparison_latest.txt` - Symlink to latest comparison

---

## Multi-Cluster Usage

### Configuration File Setup

Edit `clusters.conf`:

```bash
# Windows SCP Configuration (for automatic report copying)
WINDOWS_SCP_USER=your-username
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change

# Local output directory
LOCAL_OUTPUT_DIR=./k8s-healthcheck

# Cluster List (Format: cluster-name.management-cluster.provisioner)
prod-workload-01.mgmt-cluster-01.vsphere-tkg
prod-workload-02.mgmt-cluster-01.vsphere-tkg
dev-workload-01.mgmt-cluster-02.vsphere-tkg
```

### Cluster Name Format

**Format:** `cluster-name.management-cluster.provisioner`

This translates to TMC command:
```bash
tanzu tmc cluster kubeconfig get prod-workload-01 -m mgmt-cluster-01 -p vsphere-tkg
```

### Multi-Cluster Workflow

```bash
# Step 1: Pre-change checks on all clusters
./k8s-health-check-pre.sh --multi ./clusters.conf

# What happens:
# - Reads cluster list from clusters.conf
# - For each cluster:
#   ✓ Fetches kubeconfig via TMC
#   ✓ Runs 18 health check sections
#   ✓ Saves report to ./k8s-healthcheck/
# - Copies all reports to Windows (if configured)

# Step 2: Perform changes
# - VKR upgrades (1.28.x → 1.29.x)
# - Rolling updates
# - Configuration changes

# Step 3: Post-change checks on all clusters
./k8s-health-check-post.sh --multi ./clusters.conf

# What happens:
# - Verifies pre-change files exist
# - For each cluster:
#   ✓ Fetches kubeconfig via TMC
#   ✓ Runs 18 health check sections
#   ✓ Compares with pre-change state
#   ✓ Generates comparison report
#   ✓ Classifies: PASSED / WARNING / CRITICAL
# - Copies all reports to Windows (if configured)
# - Displays comprehensive summary
```

---

## Health Checks Performed

The scripts perform **18 comprehensive sections**:

### Section 1: Cluster Overview
- Current date/time
- Cluster info
- Kubernetes version
- Current context

### Section 2: Node Status
- All nodes with details
- Node conditions (MemoryPressure, DiskPressure, PIDPressure)
- Node resource allocation
- Node taints

### Section 3: Pod Status
- All pods across namespaces
- Non-running pods (Critical)
- CrashLoopBackOff pods
- Pending pods
- Pods with high restart counts (>5)

### Section 4: Workload Status
- Deployments (all and not-ready)
- DaemonSets (all and not-ready)
- StatefulSets
- ReplicaSets, Jobs, CronJobs

### Section 5: Storage Status
- Persistent Volumes (PVs)
- Persistent Volume Claims (PVCs)
- Unbound PVs/PVCs
- Storage Classes

### Section 6: Networking
- All Services
- Tanzu system ingress
- HTTPProxy resources
- Ingress resources
- Network Policies

### Section 7: Antrea/CNI Status
- Antrea controller tier count
- Antrea pods status
- Antrea agent pods

### Section 8: Tanzu/VMware Specific
- Package Installs (pkgi)
- Package install status
- TMC impersonation secrets
- Cluster API resources

### Section 9: Security & RBAC
- Pod Disruption Budgets
- Service Accounts
- Cluster Role Bindings

### Section 10: Component Status
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
- HTTPProxy ingress test
- SSL verification with fallback

### Section 16: Container Images Audit
- Non-standard images (external registry)
- All unique images in cluster

### Section 17: Certificates & Secrets
- Certificate resources
- TLS secrets count by namespace

### Section 18: Cluster Summary
- Quick health summary with counts
- Overall cluster statistics

---

## Comparison Report Features

The post-change script generates intelligent comparison reports:

### Critical Health Indicators
- **Node Status**: Count changes, NotReady detection
- **Pod Status**: CrashLoopBackOff, Pending pods
- **Workload Status**: Deployment/DaemonSet readiness

### Version Changes
- Kubernetes version comparison
- Container image changes (new/removed)

### Smart Event Filtering

**Events FILTERED OUT** (expected during upgrades):
- Pulling, Pulled, Created, Started
- Scheduled, SuccessfulCreate
- Killing, Deleted, ScalingReplicaSet

**Events SHOWN** (require attention):
- All other warning/error events

### Health Classification

Each cluster receives a status:
- **PASSED** 🟢 - All checks successful, no issues
- **WARNING** 🟡 - Minor issues, may resolve during rolling update
- **CRITICAL** 🔴 - Immediate action required

---

## Windows SCP Integration

Automatically copy health check reports to your Windows machine.

### Prerequisites

1. **Windows**: OpenSSH Server installed and running
2. **Linux Jumphost**: SSH key configured (passwordless auth recommended)
3. **Network**: Linux jumphost can reach Windows machine

### Setup OpenSSH on Windows

```powershell
# Run in PowerShell as Administrator
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Configure firewall
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

# Create target directories
New-Item -Path "C:\HealthCheckReports\pre-change" -ItemType Directory -Force
New-Item -Path "C:\HealthCheckReports\post-change" -ItemType Directory -Force
```

### Setup SSH Key (Recommended)

```bash
# On Linux jumphost
ssh-keygen -t rsa -b 4096
ssh-copy-id username@windows-host

# Test connection
ssh username@windows-host
```

### Configure in clusters.conf

```bash
WINDOWS_SCP_USER=your-windows-username
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change
```

**Note:** Use double backslashes for Windows paths!

---

## Output Directory Structure

### On Linux Jumphost

```
./k8s-healthcheck/
├── prod-cluster-01_pre_change_20250122_100000.txt
├── prod-cluster-01_pre_change_latest.txt -> prod-cluster-01_pre_change_20250122_100000.txt
├── prod-cluster-01_post_change_20250122_150000.txt
├── prod-cluster-01_post_change_latest.txt -> prod-cluster-01_post_change_20250122_150000.txt
├── prod-cluster-01_comparison_20250122_150000.txt
├── prod-cluster-01_comparison_latest.txt -> prod-cluster-01_comparison_20250122_150000.txt
├── prod-cluster-02_pre_change_20250122_101000.txt
└── ... (similar structure for other clusters)
```

### On Windows (After SCP)

```
C:\HealthCheckReports\
├── pre-change\
│   ├── cluster1_pre_change_20250122_100000.txt
│   ├── cluster2_pre_change_20250122_101000.txt
│   └── ...
└── post-change\
    ├── cluster1_post_change_20250122_150000.txt
    ├── cluster1_comparison_20250122_150000.txt
    └── ...
```

---

## Viewing Results

### View Comparison Report

```bash
# View latest comparison for a cluster
cat ./k8s-healthcheck/prod-cluster-01_comparison_latest.txt

# View only relevant events
grep -A 50 'EVENTS REQUIRING ATTENTION' ./k8s-healthcheck/*_comparison_latest.txt

# View critical issues only
grep -E '\[CRITICAL\]|\[WARNING\]' ./k8s-healthcheck/*_comparison_latest.txt
```

### Multi-Cluster Summary

```bash
# Quick summary of all clusters
grep "RESULT:" ./k8s-healthcheck/*_comparison_latest.txt

# Find all critical issues across all clusters
grep '\[CRITICAL\]' ./k8s-healthcheck/*_comparison_latest.txt

# Find all warnings across all clusters
grep '\[WARNING\]' ./k8s-healthcheck/*_comparison_latest.txt
```

---

## Troubleshooting

### Single Cluster Issues

**Cannot connect to cluster:**
```bash
# Check kubeconfig
kubectl cluster-info
kubectl config current-context
```

**Pre-change file not found:**
```bash
# List all pre-change files
ls -la ./k8s-healthcheck/*_pre_change_*.txt

# Run pre-check first
./k8s-health-check-pre.sh my-cluster
```

### Multi-Cluster Issues

**TMC Authentication:**
```bash
# Verify TMC login
tanzu tmc login

# Test cluster access
tanzu tmc cluster list

# Manual kubeconfig fetch test
tanzu tmc cluster kubeconfig get <cluster-name> -m <mgmt-cluster> -p <provisioner>
```

**SCP Copy Fails:**
```bash
# Test SSH connectivity
ssh username@windows-host

# Verify OpenSSH Server (on Windows)
Get-Service sshd

# Manual SCP test
scp test.txt username@windows-host:C:/HealthCheckReports/
```

**Cluster Not Found:**
```bash
# Verify cluster name format in clusters.conf
# Correct: cluster-name.management-cluster.provisioner
# Incorrect: cluster-name (missing components)
```

---

## Customization

### Add Custom Health Check Section

```bash
# 1. Create new section file
cat > lib/sections/19-custom-check.sh << 'EOF'
#!/bin/bash
run_section_19_custom_check() {
    print_header "SECTION 19: CUSTOM HEALTH CHECK"
    run_check "My Custom Check" "kubectl get customresource -A"
    run_check "Another Check" "my-custom-command"
}
export -f run_section_19_custom_check
EOF

# 2. Make executable
chmod +x lib/sections/19-custom-check.sh

# 3. Add to both PRE and POST scripts
# In k8s-health-check-pre.sh and k8s-health-check-post.sh:
# Add after run_section_18_cluster_summary:
#   run_section_19_custom_check
```

### Modify Image Exclusion Pattern

Edit the `IMAGE_EXCLUSION_PATTERN` variable in `lib/common.sh`:

```bash
export IMAGE_EXCLUSION_PATTERN='harbor|localhost:5000|your-registry.com|vmware|broadcom'
```

### Modify Event Filtering

Edit the `EXPECTED_UPGRADE_EVENTS` array in `lib/common.sh`:

```bash
export EXPECTED_UPGRADE_EVENTS=(
    "Pulling"
    "Pulled"
    # Add your patterns here
)
```

---

## Prerequisites

- `kubectl` configured with cluster access
- `tanzu` CLI (for multi-cluster mode with TMC)
- `helm` (optional, for Helm release checks)
- `curl` (for connectivity tests)
- `scp`/`ssh` (optional, for Windows file transfer)
- Bash shell (tested on Linux/WSL)

---

## Version History

| Version | Date | Changes |
|---------|------|---------------|
| 1.0.0 | 2025-01-21 | Initial single-cluster scripts |
| 2.0.0 | 2025-01-21 | Added multi-cluster orchestration |
| 3.0.0 | 2025-01-22 | **Unified scripts with modular architecture** |

### What's New in v3.0

- ✅ **Unified Scripts**: Single script handles both single and multi-cluster modes
- ✅ **Modular Architecture**: 18 independent health check sections
- ✅ **Library-Based**: Shared utilities across all modes
- ✅ **Better Maintainability**: Update once, benefit everywhere
- ✅ **No Performance Penalty**: Function-based, not process-based
- ✅ **Backward Compatible**: Single cluster mode unchanged

See [MIGRATION-GUIDE-V3.md](MIGRATION-GUIDE-V3.md) for migration details from v2.0.

---

## Help and Support

### Get Help

```bash
./k8s-health-check-pre.sh --help
./k8s-health-check-post.sh --help
```

### Common Commands

```bash
# Single cluster pre-check
./k8s-health-check-pre.sh my-cluster

# Single cluster post-check
./k8s-health-check-post.sh my-cluster

# Multi-cluster pre-check
./k8s-health-check-pre.sh --multi ./clusters.conf

# Multi-cluster post-check
./k8s-health-check-post.sh --multi ./clusters.conf

# View help
./k8s-health-check-pre.sh --help
```

---

## License

Internal use only. Designed for VMware Cloud Foundation / Tanzu Kubernetes environments.

---

## Summary

These health check scripts provide:

- ✅ **Comprehensive**: 18 health check sections covering all critical areas
- ✅ **Intelligent Comparison**: Smart diff with event filtering
- ✅ **Multi-Cluster**: Automated checks across multiple clusters
- ✅ **TMC Integration**: Automatic kubeconfig management
- ✅ **Windows Integration**: Automatic report transfer via SCP
- ✅ **Modular**: Easy to extend with custom checks
- ✅ **Production Ready**: Battle-tested for VKR upgrades and day-to-day ops

Perfect for DevOps teams managing VMware Tanzu Kubernetes clusters!
