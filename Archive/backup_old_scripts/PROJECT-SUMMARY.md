# K8s Health Check Project - Enhancement Summary

## Project Overview

Enhanced the Kubernetes cluster health check system to support **automated multi-cluster operations** with TMC-SM integration and Windows file transfer capabilities.

**Environment:**
- VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
- VKS (vSphere Kubernetes Service) 3.3.3
- VKR (Kubernetes) 1.28.x / 1.29.x

## What Was Built

### Core Files Created

| File | Purpose | Size |
|------|---------|------|
| `clusters.conf` | Configuration file for cluster list and Windows SCP settings | 1.6K |
| `multi-cluster-pre-check.sh` | Orchestrator for running pre-change checks on all clusters | 11K |
| `multi-cluster-post-check.sh` | Orchestrator for running post-change checks and comparisons | 16K |
| `example-workflow.sh` | Interactive workflow guide demonstrating complete process | 12K |
| `QUICK-START-MULTI-CLUSTER.md` | Quick reference guide for multi-cluster mode | 7.6K |
| Enhanced `K8S-HEALTH-CHECK-README.md` | Updated with comprehensive multi-cluster documentation | 27K |

### Existing Files (Original Implementation)

| File | Purpose |
|------|---------|
| `k8s-health-check-pre.sh` | Single cluster pre-change health check (18 sections) |
| `k8s-health-check-post.sh` | Single cluster post-change health check with comparison |

## Key Features

### 1. Multi-Cluster Orchestration

- **Automated execution** across multiple clusters from a single command
- **Sequential processing** with progress tracking and status reporting
- **Error handling** with detailed logging and per-cluster success/failure tracking
- **Interactive prompts** for user confirmation before execution

### 2. TMC-SM Integration

- **Automatic kubeconfig fetching** using Tanzu CLI
- **Dynamic cluster connection** using format: `cluster-name.management-cluster.provisioner`
- **Command construction**: `tanzu tmc cluster kubeconfig get <cluster> -m <mgmt> -p <provisioner>`
- **Cluster validation** before health check execution

### 3. Windows SCP Integration

- **Automatic file transfer** to Windows machine after health checks
- **Configurable paths** via `clusters.conf`
- **Support for OpenSSH Server** on Windows (native Windows 10/11 feature)
- **Passwordless authentication** via SSH keys
- **Fallback to manual copy** if SCP fails

### 4. Comprehensive Reporting

- **Per-cluster status tracking**: PASSED / WARNING / CRITICAL
- **Execution summary** with counts and statistics
- **Health status aggregation** across all clusters
- **Detailed comparison reports** for each cluster
- **Console output** with color-coded status indicators

### 5. Configuration Management

- **Centralized configuration** in `clusters.conf`
- **Support for multiple config files** (prod, dev, staging)
- **Cluster list format**: One line per cluster with dot-separated components
- **Windows path configuration** with proper escaping

## Workflow

### Pre-Change Phase

```
1. Configure clusters.conf with cluster list
2. Run: ./multi-cluster-pre-check.sh
3. For each cluster:
   - Fetch kubeconfig from TMC
   - Run health check (18 sections)
   - Save report to ./k8s-healthcheck/
4. Copy all reports to Windows machine
5. Display execution summary
```

### Change Phase

```
Perform cluster changes:
- VKR version upgrades
- Rolling updates
- Configuration changes
- Day-to-day maintenance
```

### Post-Change Phase

```
1. Run: ./multi-cluster-post-check.sh
2. Verify pre-change files exist
3. For each cluster:
   - Fetch kubeconfig from TMC
   - Run health check (18 sections)
   - Compare with pre-change baseline
   - Generate comparison report
   - Categorize: PASSED / WARNING / CRITICAL
4. Copy all reports to Windows machine
5. Display detailed summary with per-cluster status
```

## Technical Implementation Details

### Cluster Name Format

**Format:** `cluster-name.management-cluster.provisioner`

**Example:** `prod-workload-01.mgmt-cluster-01.vsphere-tkg`

**Parsing:**
```bash
cluster_name=$(echo "${cluster_full_name}" | cut -d'.' -f1)
mgmt_cluster=$(echo "${cluster_full_name}" | cut -d'.' -f2)
provisioner=$(echo "${cluster_full_name}" | cut -d'.' -f3)
```

### Configuration File Structure

```bash
# Windows SCP Configuration
WINDOWS_SCP_USER=username
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change

# Local output directory
LOCAL_OUTPUT_DIR=./k8s-healthcheck

# Cluster list (one per line)
prod-cluster-01.mgmt-01.vsphere-tkg
prod-cluster-02.mgmt-01.vsphere-tkg
```

### TMC Command Construction

```bash
tanzu tmc cluster get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}"
tanzu tmc cluster kubeconfig get "${cluster_name}" -m "${mgmt_cluster}" -p "${provisioner}"
```

### SCP File Transfer

```bash
# Pre-change reports
scp -r "${output_dir}"/*_pre_change_*.txt "${user}@${host}:${windows_path}/"

# Post-change reports and comparisons
scp -r "${output_dir}"/*_post_change_*.txt "${output_dir}"/*_comparison_*.txt "${user}@${host}:${windows_path}/"
```

### Health Status Classification

```bash
# Extraction from comparison reports
critical=$(grep -c "\[CRITICAL\]" "${comparison_file}")
warnings=$(grep -c "\[WARNING\]" "${comparison_file}")

if [ "${critical}" -gt 0 ]; then
    STATUS="CRITICAL"
elif [ "${warnings}" -gt 0 ]; then
    STATUS="WARNING"
else
    STATUS="PASSED"
fi
```

## File Organization

### Directory Structure

```
k8-health-check/
├── k8s-health-check-pre.sh          # Single cluster pre-check
├── k8s-health-check-post.sh         # Single cluster post-check
├── multi-cluster-pre-check.sh       # Multi-cluster pre-check orchestrator
├── multi-cluster-post-check.sh      # Multi-cluster post-check orchestrator
├── clusters.conf                     # Configuration file
├── example-workflow.sh               # Interactive workflow guide
├── K8S-HEALTH-CHECK-README.md       # Comprehensive documentation
├── QUICK-START-MULTI-CLUSTER.md     # Quick reference guide
├── PROJECT-SUMMARY.md                # This file
└── k8s-healthcheck/                  # Output directory (created at runtime)
    ├── {cluster}_pre_change_{timestamp}.txt
    ├── {cluster}_pre_change_latest.txt
    ├── {cluster}_post_change_{timestamp}.txt
    ├── {cluster}_post_change_latest.txt
    ├── {cluster}_comparison_{timestamp}.txt
    └── {cluster}_comparison_latest.txt
```

### Windows Directory Structure (After SCP)

```
C:\HealthCheckReports\
├── pre-change\
│   ├── cluster1_pre_change_20250121_100000.txt
│   ├── cluster2_pre_change_20250121_101000.txt
│   └── ...
└── post-change\
    ├── cluster1_post_change_20250121_150000.txt
    ├── cluster1_comparison_20250121_150000.txt
    ├── cluster2_post_change_20250121_151000.txt
    ├── cluster2_comparison_20250121_151000.txt
    └── ...
```

## Usage Examples

### Basic Usage

```bash
# Configure clusters
vi clusters.conf

# Run pre-change checks
./multi-cluster-pre-check.sh

# Perform changes...

# Run post-change checks
./multi-cluster-post-check.sh
```

### Custom Configuration

```bash
# Use different config file
./multi-cluster-pre-check.sh ./prod-clusters.conf
./multi-cluster-post-check.sh ./prod-clusters.conf
```

### Interactive Workflow

```bash
# Run interactive workflow guide
./example-workflow.sh
```

### Manual Single Cluster

```bash
# Run single cluster (existing functionality)
./k8s-health-check-pre.sh cluster-name
./k8s-health-check-post.sh cluster-name
```

## Benefits

### For DevOps Admins

1. **Time Savings**: Automate health checks across multiple clusters
2. **Consistency**: Same checks applied to all clusters
3. **Traceability**: Detailed reports for audit and compliance
4. **Risk Reduction**: Detect issues before and after changes
5. **Simplified Workflow**: Single command for all clusters

### For Operations

1. **Centralized Reporting**: All reports in one location
2. **Status Overview**: Quick summary of all cluster health
3. **Windows Integration**: Easy access to reports on Windows machines
4. **Historical Records**: Timestamped reports for comparison

### For Compliance

1. **Audit Trail**: Complete record of pre/post change state
2. **Automated Documentation**: Health checks generate detailed reports
3. **Comparison Reports**: Easy to verify change impact
4. **Structured Output**: Consistent format across all clusters

## Troubleshooting Support

### Built-in Error Handling

- TMC authentication verification
- Cluster connectivity validation
- Pre-change file existence checks
- SCP failure graceful degradation
- Per-cluster error isolation (one failure doesn't stop others)

### Debug Information

- Detailed console output with color-coded status
- Per-cluster success/failure tracking
- Comprehensive error messages
- Execution summary with counts

### Common Issues Addressed

1. **TMC Authentication**: Automatic detection and clear error messages
2. **Missing Pre-change Files**: Validation before post-checks
3. **SCP Failures**: Graceful fallback with manual copy instructions
4. **Cluster Connectivity**: Per-cluster validation with skip on failure
5. **Configuration Errors**: Validation of config file format

## Security Considerations

### SSH Key Authentication

- Passwordless authentication recommended
- SSH keys stored securely on Linux jumphost
- No passwords stored in scripts or config files

### Network Access

- Linux jumphost → TMC (HTTPS)
- Linux jumphost → Kubernetes clusters (kubectl)
- Linux jumphost → Windows machine (SSH/SCP)

### File Permissions

- Scripts: `755` (executable by owner, readable by all)
- Config: `644` (readable by owner and group)
- Reports: `644` (readable, not executable)

## Future Enhancements (Potential)

1. **Parallel Execution**: Run health checks on multiple clusters simultaneously
2. **Email Notifications**: Send reports via email after completion
3. **Slack Integration**: Post status updates to Slack channels
4. **HTML Reports**: Generate HTML versions of comparison reports
5. **Dashboard**: Web-based dashboard for visualizing cluster health
6. **Scheduled Execution**: Cron job support for periodic health checks
7. **Diff Viewer**: Interactive diff viewer for comparison reports
8. **Metrics Export**: Export health metrics to monitoring systems

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-01-21 | Original single-cluster health check scripts |
| 2.0.0 | 2025-01-21 | Multi-cluster orchestration with TMC-SM and Windows SCP |

## Dependencies

### Required

- `bash` (v4.0+)
- `kubectl` (configured with cluster access)
- `tanzu` CLI (TMC-SM authenticated)
- `grep`, `awk`, `sed` (standard Unix tools)

### Optional

- `helm` (for Helm release checks)
- `curl` (for connectivity tests)
- `scp` / `ssh` (for Windows file transfer)
- OpenSSH Server on Windows (for automatic file transfer)

## Documentation Files

| File | Purpose | Audience |
|------|---------|----------|
| `K8S-HEALTH-CHECK-README.md` | Comprehensive documentation | All users |
| `QUICK-START-MULTI-CLUSTER.md` | Quick reference guide | Operations/DevOps |
| `PROJECT-SUMMARY.md` | Technical overview (this file) | Developers/Architects |
| `example-workflow.sh` | Interactive tutorial | New users |

## Support and Maintenance

### Getting Help

1. Read `QUICK-START-MULTI-CLUSTER.md` for quick reference
2. Check `K8S-HEALTH-CHECK-README.md` for detailed documentation
3. Run `example-workflow.sh` for interactive guidance
4. Review error messages and logs in console output

### Maintenance Tasks

1. **Update cluster list**: Edit `clusters.conf`
2. **Update Windows paths**: Edit `clusters.conf`
3. **Update TMC credentials**: Run `tanzu tmc login`
4. **Clean old reports**: Archive/delete old files in `./k8s-healthcheck/`

## Testing Checklist

- [ ] TMC authentication works
- [ ] Cluster list is correct in `clusters.conf`
- [ ] Windows SCP configuration is correct
- [ ] SSH key authentication to Windows works
- [ ] Pre-change health checks run successfully
- [ ] Post-change health checks run successfully
- [ ] Reports are generated correctly
- [ ] Files are copied to Windows successfully
- [ ] Comparison reports show expected results
- [ ] Status summary is accurate

## Summary

Successfully enhanced the K8s health check system from single-cluster to multi-cluster operation with:

✅ Automated TMC-SM integration for kubeconfig management
✅ Multi-cluster orchestration with sequential execution
✅ Windows SCP integration for report delivery
✅ Comprehensive error handling and status reporting
✅ Detailed documentation and quick-start guides
✅ Interactive workflow example for easy adoption

The system now supports enterprise-scale operations across multiple Kubernetes clusters with minimal manual intervention.
