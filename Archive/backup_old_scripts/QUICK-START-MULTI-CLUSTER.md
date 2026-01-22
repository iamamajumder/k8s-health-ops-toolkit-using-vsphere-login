# Quick Start Guide - Multi-Cluster Health Checks

## Prerequisites

- [ ] Tanzu CLI installed and configured
- [ ] TMC-SM context already created and authenticated
- [ ] SSH access configured from Linux jumphost to Windows machine
- [ ] OpenSSH Server running on Windows machine (optional, for automatic SCP)

## Setup (One-Time)

### 1. Configure Windows OpenSSH Server (Optional)

On your Windows machine, run PowerShell as Administrator:

```powershell
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start and enable service
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Configure firewall
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

# Create target directories
New-Item -Path "C:\HealthCheckReports\pre-change" -ItemType Directory -Force
New-Item -Path "C:\HealthCheckReports\post-change" -ItemType Directory -Force
```

### 2. Setup SSH Key (Recommended for Passwordless Auth)

On Linux jumphost:

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096

# Copy public key to Windows
ssh-copy-id your-windows-username@your-windows-ip

# Test connection
ssh your-windows-username@your-windows-ip
```

### 3. Configure clusters.conf

Edit the configuration file with your cluster details:

```bash
cd /path/to/k8-health-check
vi clusters.conf
```

Update the following sections:

```bash
# Windows SCP Configuration
WINDOWS_SCP_USER=your-windows-username
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change

# Local output directory
LOCAL_OUTPUT_DIR=./k8s-healthcheck

# Add your clusters (Format: cluster-name.management-cluster.provisioner)
prod-workload-01.mgmt-cluster-01.vsphere-tkg
prod-workload-02.mgmt-cluster-01.vsphere-tkg
dev-workload-01.mgmt-cluster-02.vsphere-tkg
```

## Usage Workflow

### Before Making Changes (PRE-CHECK)

```bash
# Run pre-change health checks on all clusters
./multi-cluster-pre-check.sh

# Review the output
ls -la ./k8s-healthcheck/*_pre_change_*.txt

# Files are automatically copied to:
# Windows: C:\HealthCheckReports\pre-change\
```

**Expected Output:**
- ✓ Kubeconfig fetched for each cluster via TMC
- ✓ Pre-change health check completed for each cluster
- ✓ Reports saved to `./k8s-healthcheck/`
- ✓ Files copied to Windows machine (if SCP configured)

### Perform Your Changes

- VKR version upgrades (Kubernetes 1.28.x → 1.29.x)
- Rolling updates
- Configuration changes
- Day-to-day maintenance

### After Making Changes (POST-CHECK)

```bash
# Run post-change health checks and comparison
./multi-cluster-post-check.sh

# Review the comparison reports
cat ./k8s-healthcheck/*_comparison_latest.txt

# Files are automatically copied to:
# Windows: C:\HealthCheckReports\post-change\
```

**Expected Output:**
- ✓ Kubeconfig fetched for each cluster via TMC
- ✓ Post-change health check completed for each cluster
- ✓ Comparison reports generated
- ✓ Summary showing: PASSED / WARNING / CRITICAL status per cluster
- ✓ Files copied to Windows machine (if SCP configured)

## Quick Commands

### View All Cluster Statuses

```bash
# Quick summary of all clusters
grep "RESULT:" ./k8s-healthcheck/*_comparison_latest.txt

# Find all critical issues
grep '\[CRITICAL\]' ./k8s-healthcheck/*_comparison_latest.txt

# Find all warnings
grep '\[WARNING\]' ./k8s-healthcheck/*_comparison_latest.txt
```

### Process Specific Clusters Only

```bash
# Create temporary config with specific clusters
cat > temp-clusters.conf << 'EOF'
WINDOWS_SCP_USER=admin
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change
LOCAL_OUTPUT_DIR=./k8s-healthcheck

prod-cluster-01.mgmt-01.vsphere-tkg
prod-cluster-02.mgmt-01.vsphere-tkg
EOF

# Run with custom config
./multi-cluster-pre-check.sh temp-clusters.conf
./multi-cluster-post-check.sh temp-clusters.conf
```

### Manual File Copy (If SCP Fails)

```bash
# Copy files to Windows manually
scp ./k8s-healthcheck/*_pre_change_*.txt your-username@windows-ip:C:/HealthCheckReports/pre-change/
scp ./k8s-healthcheck/*_post_change_*.txt ./k8s-healthcheck/*_comparison_*.txt your-username@windows-ip:C:/HealthCheckReports/post-change/
```

## Cluster Name Format

**Format:** `cluster-name.management-cluster.provisioner`

**Example:** `prod-workload-01.mgmt-cluster-01.vsphere-tkg`

This translates to the TMC command:
```bash
tanzu tmc cluster kubeconfig get prod-workload-01 -m mgmt-cluster-01 -p vsphere-tkg
```

## Troubleshooting

### Issue: "Cannot connect to cluster"

```bash
# Verify TMC authentication
tanzu tmc login

# Test cluster access
tanzu tmc cluster list

# Manually fetch kubeconfig
tanzu tmc cluster kubeconfig get <cluster-name> -m <mgmt-cluster> -p <provisioner>

# Verify kubectl connectivity
kubectl cluster-info
```

### Issue: "Pre-change file not found"

```bash
# Check if pre-change files exist
ls -la ./k8s-healthcheck/*_pre_change_*.txt

# Re-run pre-check if missing
./multi-cluster-pre-check.sh
```

### Issue: "SCP copy failed"

```bash
# Test SSH connectivity
ssh your-username@windows-ip

# Verify OpenSSH Server is running (on Windows)
Get-Service sshd

# Test manual SCP
echo "test" > test.txt
scp test.txt your-username@windows-ip:C:/HealthCheckReports/

# If SCP is not configured, files are still saved locally in:
# ./k8s-healthcheck/
```

### Issue: "Cluster not found in TMC"

```bash
# List all available clusters
tanzu tmc cluster list

# Verify cluster name format in clusters.conf
# Correct: cluster-name.management-cluster.provisioner
# Incorrect: cluster-name (missing management cluster and provisioner)
```

## File Locations

### On Linux Jumphost

```
./k8s-healthcheck/
├── {cluster}_pre_change_{timestamp}.txt
├── {cluster}_pre_change_latest.txt (symlink)
├── {cluster}_post_change_{timestamp}.txt
├── {cluster}_post_change_latest.txt (symlink)
├── {cluster}_comparison_{timestamp}.txt
└── {cluster}_comparison_latest.txt (symlink)
```

### On Windows Machine (After SCP)

```
C:\HealthCheckReports\
├── pre-change\
│   └── {cluster}_pre_change_{timestamp}.txt
└── post-change\
    ├── {cluster}_post_change_{timestamp}.txt
    └── {cluster}_comparison_{timestamp}.txt
```

## Status Indicators

### Health Check Status

- **PASSED** 🟢 - All checks successful, no issues detected
- **WARNING** 🟡 - Minor issues detected, may resolve during rolling update
- **CRITICAL** 🔴 - Critical issues detected, immediate action required

### Exit Codes

- `0` - Success (all clusters passed or warnings only)
- `1` - Failure (critical issues or execution errors)

## Tips

1. **Always run pre-checks before making changes** - This creates the baseline for comparison
2. **Review comparison reports** - Don't just rely on the summary, check detailed reports
3. **Wait for rolling updates to complete** - Some warnings are expected during updates
4. **Keep reports for audit trail** - Store reports for compliance and troubleshooting
5. **Use custom configs for different environments** - Create separate configs for prod/dev/staging

## Support

For issues or questions:
1. Check the full README: `K8S-HEALTH-CHECK-README.md`
2. Review error messages in console output
3. Check individual cluster logs in `./k8s-healthcheck/`

## Environment Details

| Component | Version |
|-----------|---------|
| VMware Cloud Foundation | 5.2.1 |
| vSphere | 8.x |
| NSX | 4.x |
| VKS (vSphere Kubernetes Service) | 3.3.3 |
| VKR (Kubernetes) | 1.28.x / 1.29.x |
