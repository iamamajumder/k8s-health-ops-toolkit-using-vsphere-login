# Migration Guide: v3.0 → v3.1

## Overview

Version 3.1 introduces significant simplifications to the K8s Health Check project:

- **Unified execution model** - No more `--multi` flag, always uses clusters.conf
- **Auto-discovery** - Automatically discovers management cluster and provisioner from TMC
- **Auto-context creation** - Automatically creates TMC contexts based on cluster naming patterns
- **Simplified configuration** - Just cluster names (one per line)
- **33% code reduction** - From ~1070 to ~720 lines of code

## Breaking Changes

1. **clusters.conf format** - Old three-part format replaced with simple cluster names
2. **Script invocation** - No more single-cluster mode or `--multi` flag
3. **No backward compatibility** - Old v3.0 format not supported

## Migration Steps

### Step 1: Backup Your v3.0 Setup

```bash
cd "d:\Ankur\Projects\k8 Health check"

# Backup entire v3.0 project
mkdir -p ../k8-health-check-v3.0-backup
cp -r . ../k8-health-check-v3.0-backup/

# Verify backup
ls -la ../k8-health-check-v3.0-backup/
```

### Step 2: Update clusters.conf

Convert from old three-part format to new simple format.

**OLD format (v3.0):**
```bash
# clusters.conf
prod-workload-01.mgmt-cluster-01.vsphere-tkg
prod-workload-02.mgmt-cluster-01.vsphere-tkg
dev-workload-01.mgmt-cluster-02.vsphere-tkg
uat-system-01.mgmt-cluster-02.vsphere-tkg
```

**NEW format (v3.1):**
```bash
# clusters.conf
prod-workload-01
prod-workload-02
dev-workload-01
uat-system-01
```

**Automated conversion:**
```bash
# Convert old format to new format
cat clusters.conf | grep -v '^#' | grep -v '^$' | cut -d'.' -f1 > clusters.conf.new
mv clusters.conf clusters.conf.v3.0.backup
mv clusters.conf.new clusters.conf
```

### Step 3: Configure TMC Endpoints

Edit lib/tmc-context.sh and set your actual TMC endpoints:

```bash
# lib/tmc-context.sh
NON_PROD_DNS="your-nonprod-tmc-fqdn"
PROD_DNS="your-prod-tmc-fqdn"
```

Replace the placeholder values with your actual TMC self-managed instance FQDNs.

### Step 4: Verify Cluster Naming Patterns

Ensure your cluster names follow the required naming patterns for auto-context detection:

- Production: `*-prod-[1-4]` (e.g., `prod-workload-01`, `my-prod-2`)
- UAT: `*-uat-[1-4]` (e.g., `uat-system-01`, `my-uat-3`)
- System/Dev: `*-system-[1-4]` (e.g., `dev-system-01`, `test-system-2`)

If your clusters don't follow these patterns, you have two options:

**Option A: Rename clusters in TMC** (if feasible)

**Option B: Modify lib/tmc-context.sh** to match your naming convention:

```bash
# lib/tmc-context.sh - customize the determine_environment function
determine_environment() {
    local cluster_name="$1"

    # Add your custom patterns here
    if [[ "${cluster_name}" =~ -prod-[1-4]$ ]]; then
        echo "prod"
    elif [[ "${cluster_name}" =~ -uat-[1-4]$ ]] || [[ "${cluster_name}" =~ -system-[1-4]$ ]]; then
        echo "nonprod"
    # Add more patterns as needed
    elif [[ "${cluster_name}" =~ ^prod- ]]; then
        echo "prod"
    else
        echo "unknown"
    fi
}
```

### Step 5: Update Script Invocation

**OLD usage (v3.0):**
```bash
# Single cluster mode
./k8s-health-check-pre.sh cluster-name ./output-dir

# Multi-cluster mode
./k8s-health-check-pre.sh --multi ./clusters.conf
```

**NEW usage (v3.1):**
```bash
# Always uses clusters.conf
./k8s-health-check-pre.sh ./clusters.conf

# For POST-change with comparison
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20250122_143000
```

### Step 6: Set Environment Variables (Optional)

To avoid entering credentials each time:

```bash
# Set TMC credentials
export TMC_SELF_MANAGED_USERNAME="your-ao-username"
export TMC_SELF_MANAGED_PASSWORD="your-password"

# Enable Windows SCP (optional)
export WINDOWS_SCP_ENABLED="true"
export WINDOWS_SCP_USER="windowsuser"
export WINDOWS_SCP_HOST="192.168.1.100"
export WINDOWS_PRE_PATH="C:\\HealthCheckReports\\pre"
export WINDOWS_POST_PATH="C:\\HealthCheckReports\\post"

# Run scripts
./k8s-health-check-pre.sh ./clusters.conf
```

### Step 7: Test with Single Cluster First

Before running on all clusters, test with a single cluster:

```bash
# Create test config with one cluster
echo "prod-workload-01" > test-cluster.conf

# Run PRE-change check
./k8s-health-check-pre.sh test-cluster.conf

# Verify output
ls -la health-check-results/pre-*/prod-workload-01/
cat health-check-results/pre-*/prod-workload-01/health-check-report.txt
```

### Step 8: Run Full Migration

Once testing is successful:

```bash
# Run PRE-change check on all clusters
./k8s-health-check-pre.sh ./clusters.conf

# Perform your cluster changes (upgrades, configuration changes, etc.)
# ...

# Run POST-change check and comparison
./k8s-health-check-post.sh ./clusters.conf ./health-check-results/pre-20250122_143000
```

## What's Changed Under the Hood

### New Library Modules

1. **lib/tmc-context.sh** - New module for TMC context management
   - Auto-detects environment (prod/nonprod) from cluster name
   - Creates TMC contexts automatically
   - Reuses existing contexts

2. **lib/tmc.sh** - Enhanced with auto-discovery
   - `discover_cluster_metadata()` - Fetches management/provisioner from TMC
   - `fetch_kubeconfig_auto()` - Fetches kubeconfig using auto-discovered metadata
   - Caches metadata in temp file for performance

3. **lib/config.sh** - Simplified configuration parsing
   - Removed `parse_cluster_name()` function (no longer needed)
   - Simplified `get_cluster_list()` to handle simple format
   - Updated `validate_cluster_format()` for new format

### Modified Main Scripts

1. **k8s-health-check-pre.sh**
   - Removed `--multi` flag and single/multi mode distinction
   - Integrated TMC context creation
   - Uses auto-discovery for kubeconfig fetching
   - 36% code reduction (280 → 180 lines)

2. **k8s-health-check-post.sh**
   - Removed `--multi` flag and single/multi mode distinction
   - Integrated TMC context creation
   - Uses auto-discovery for kubeconfig fetching
   - Maintains comparison functionality
   - 37% code reduction (350 → 220 lines)

## Troubleshooting

### Issue: "Cannot determine environment for cluster"

**Problem:** Your cluster name doesn't match expected naming patterns.

**Solution:** Either rename your cluster or modify `lib/tmc-context.sh` to match your naming convention (see Step 4).

### Issue: "Cluster not found in TMC or missing metadata"

**Problem:** Auto-discovery failed to find the cluster in TMC.

**Possible Causes:**
1. Cluster name misspelled in clusters.conf
2. Cluster not accessible in current TMC context
3. TMC authentication expired

**Solution:**
```bash
# Verify cluster exists in TMC
tanzu tmc cluster list | grep your-cluster-name

# Check current TMC context
tanzu context current

# Re-authenticate if needed
tanzu tmc context create tmc-sm --endpoint your-tmc-endpoint -i pinniped --basic-auth
```

### Issue: "Failed to create TMC context"

**Problem:** TMC context creation failed.

**Possible Causes:**
1. Incorrect TMC endpoint in lib/tmc-context.sh
2. Wrong credentials
3. Network connectivity issues

**Solution:**
```bash
# Test TMC endpoint manually
tanzu tmc context create test-context --endpoint your-tmc-endpoint -i pinniped --basic-auth

# Check lib/tmc-context.sh has correct endpoints
grep -E "(NON_PROD_DNS|PROD_DNS)" lib/tmc-context.sh
```

### Issue: "jq not found" warning

**Problem:** jq command-line JSON processor not installed.

**Impact:** Auto-discovery will use fallback basic JSON parsing (slower but functional).

**Solution (optional):**
```bash
# Install jq for better performance
# Ubuntu/Debian
sudo apt-get install jq

# RHEL/CentOS
sudo yum install jq

# macOS
brew install jq
```

## Rollback to v3.0

If you need to rollback to v3.0:

```bash
# Restore from backup
cd "d:\Ankur\Projects"
rm -rf "k8 Health check"
cp -r k8-health-check-v3.0-backup "k8 Health check"

# Verify v3.0 is restored
cd "k8 Health check"
head -5 k8s-health-check-pre.sh | grep "v3.0\|Unified"
```

## Benefits of v3.1

1. **Simplified Configuration**
   - 60% less configuration effort
   - No need to know management cluster or provisioner
   - Less prone to typos

2. **Automatic TMC Management**
   - No manual context creation required
   - Smart environment detection
   - Context reuse for efficiency

3. **Better Error Handling**
   - Clear error messages for common issues
   - Graceful cluster skip on failures
   - Comprehensive execution summary

4. **Improved Performance**
   - Metadata caching reduces API calls
   - Context reuse eliminates redundant authentication

5. **Maintainability**
   - 33% less code to maintain
   - Single execution path (no single vs multi distinction)
   - Modular TMC logic for future flexibility

## Next Steps

1. **Test thoroughly** - Run on non-production clusters first
2. **Document your patterns** - If you customized naming patterns, document them
3. **Update runbooks** - Update operational runbooks with new v3.1 commands
4. **Train team** - Ensure team members understand new simplified workflow

## Support

If you encounter issues during migration:

1. Check this migration guide thoroughly
2. Review the troubleshooting section
3. Check the main [K8S-HEALTH-CHECK-README.md](K8S-HEALTH-CHECK-README.md) for detailed usage
4. Review the [OPTIMIZATION-PLAN-V3.1.md](OPTIMIZATION-PLAN-V3.1.md) for technical details

## Appendix: Quick Reference

### Command Comparison

| Operation | v3.0 Command | v3.1 Command |
|-----------|-------------|-------------|
| Single cluster PRE | `./k8s-health-check-pre.sh cluster-01 ./out` | N/A (use clusters.conf with single entry) |
| Multi cluster PRE | `./k8s-health-check-pre.sh --multi ./clusters.conf` | `./k8s-health-check-pre.sh ./clusters.conf` |
| Single cluster POST | `./k8s-health-check-post.sh cluster-01 ./out` | N/A (use clusters.conf with single entry) |
| Multi cluster POST | `./k8s-health-check-post.sh --multi ./clusters.conf` | `./k8s-health-check-post.sh ./clusters.conf ./pre-results` |

### File Changes

| File | Status | Changes |
|------|--------|---------|
| lib/tmc-context.sh | NEW | TMC context management |
| lib/tmc.sh | MODIFIED | Added auto-discovery |
| lib/config.sh | MODIFIED | Simplified parsing |
| k8s-health-check-pre.sh | REPLACED | Unified execution |
| k8s-health-check-post.sh | REPLACED | Unified execution |
| clusters.conf | MODIFIED | Simple format |
| lib/common.sh | UNCHANGED | No changes |
| lib/comparison.sh | UNCHANGED | No changes |
| lib/scp.sh | UNCHANGED | No changes |
| lib/sections/*.sh | UNCHANGED | No changes |

### Version History

- **v3.1** (2025-01-22) - Simplified execution, auto-discovery, auto-context creation
- **v3.0** (2025-01-21) - Modular architecture, unified scripts with --multi flag
- **v2.0** (Earlier) - Separate scripts for single and multi-cluster
- **v1.0** (Earlier) - Initial implementation
