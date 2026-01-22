# Migration Guide - Version 3.0 (Modular Architecture)

## Overview

Version 3.0 introduces a **modular, library-based architecture** that consolidates single-cluster and multi-cluster functionality into unified scripts.

## What Changed

### Previous Architecture (v2.0)
```
k8-health-check/
├── k8s-health-check-pre.sh          # Single cluster only
├── k8s-health-check-post.sh         # Single cluster only
├── multi-cluster-pre-check.sh       # Multi-cluster only
├── multi-cluster-post-check.sh      # Multi-cluster only
└── clusters.conf
```

### New Architecture (v3.0)
```
k8-health-check/
├── k8s-health-check-pre.sh          # Unified (single + multi)
├── k8s-health-check-post.sh         # Unified (single + multi)
├── lib/                              # Modular libraries
│   ├── common.sh                     # Shared utilities
│   ├── config.sh                     # Configuration parser
│   ├── tmc.sh                        # TMC integration
│   ├── scp.sh                        # Windows file transfer
│   ├── comparison.sh                 # Comparison logic
│   └── sections/                     # 18 health check modules
│       ├── 01-cluster-overview.sh
│       ├── 02-node-status.sh
│       └── ... (16 more)
├── clusters.conf                     # Same as before
└── backup_old_scripts/               # Backup of v2.0 scripts
```

## Key Improvements

### 1. Unified Scripts
- **Single script handles both modes**: `--multi` flag switches to multi-cluster
- **Reduced duplication**: Health check logic shared between single and multi-cluster
- **Consistent behavior**: Same checks regardless of mode

### 2. Modular Architecture
- **Maintainability**: Update one section file, both PRE and POST benefit
- **Extensibility**: Easy to add new health check sections
- **Testability**: Individual modules can be tested in isolation
- **Performance**: No overhead - functions loaded once into memory

### 3. Clean Separation of Concerns
- **lib/common.sh**: Logging, display, validation functions
- **lib/config.sh**: Configuration file parsing
- **lib/tmc.sh**: TMC cluster management
- **lib/scp.sh**: Windows file transfer
- **lib/comparison.sh**: Pre/post comparison logic
- **lib/sections/**: 18 independent health check modules

## Migration Steps

### Automatic Migration (Already Done)

The old scripts have been backed up to `backup_old_scripts/`:
- k8s-health-check-pre.sh (v2.0) → backup_old_scripts/
- k8s-health-check-post.sh (v2.0) → backup_old_scripts/
- multi-cluster-pre-check.sh → backup_old_scripts/
- multi-cluster-post-check.sh → backup_old_scripts/

New unified scripts are now in place.

### Usage Changes

#### Single Cluster Mode (No Change)

**Before (v2.0):**
```bash
./k8s-health-check-pre.sh my-cluster ./output
./k8s-health-check-post.sh my-cluster ./output
```

**After (v3.0):**
```bash
./k8s-health-check-pre.sh my-cluster ./output
./k8s-health-check-post.sh my-cluster ./output
```
✅ **No changes required!**

#### Multi-Cluster Mode (Syntax Change)

**Before (v2.0):**
```bash
./multi-cluster-pre-check.sh ./clusters.conf
./multi-cluster-post-check.sh ./clusters.conf
```

**After (v3.0):**
```bash
./k8s-health-check-pre.sh --multi ./clusters.conf
./k8s-health-check-post.sh --multi ./clusters.conf
```
⚠️ **Use `--multi` flag with unified scripts**

#### Quick Migration Commands

```bash
# Old multi-cluster commands
./multi-cluster-pre-check.sh ./clusters.conf
./multi-cluster-post-check.sh ./clusters.conf

# New unified commands (use these instead)
./k8s-health-check-pre.sh --multi ./clusters.conf
./k8s-health-check-post.sh --multi ./clusters.conf
```

## Configuration File

**No changes required** - `clusters.conf` format remains the same:

```bash
# Windows SCP Configuration
WINDOWS_SCP_USER=yourusername
WINDOWS_SCP_HOST=192.168.1.100
WINDOWS_PRE_PATH=C:\\HealthCheckReports\\pre-change
WINDOWS_POST_PATH=C:\\HealthCheckReports\\post-change

# Local output directory
LOCAL_OUTPUT_DIR=./k8s-healthcheck

# Cluster List (Format: cluster-name.management-cluster.provisioner)
prod-workload-01.mgmt-cluster-01.vsphere-tkg
prod-workload-02.mgmt-cluster-01.vsphere-tkg
```

## Output Files

**No changes** - Output file naming and structure remain identical:

```
./k8s-healthcheck/
├── cluster-name_pre_change_TIMESTAMP.txt
├── cluster-name_pre_change_latest.txt
├── cluster-name_post_change_TIMESTAMP.txt
├── cluster-name_post_change_latest.txt
├── cluster-name_comparison_TIMESTAMP.txt
└── cluster-name_comparison_latest.txt
```

## Help and Documentation

Get help on the unified scripts:

```bash
./k8s-health-check-pre.sh --help
./k8s-health-check-post.sh --help
```

## Rollback (If Needed)

If you need to rollback to v2.0 scripts:

```bash
cd "k8 Health check"

# Restore old scripts
cp backup_old_scripts/k8s-health-check-pre.sh .
cp backup_old_scripts/k8s-health-check-post.sh .
cp backup_old_scripts/multi-cluster-pre-check.sh .
cp backup_old_scripts/multi-cluster-post-check.sh .

# Make executable
chmod +x *.sh
```

## Testing the Migration

### Test Single Cluster Mode

```bash
# Should work exactly as before
./k8s-health-check-pre.sh test-cluster ./test-output
./k8s-health-check-post.sh test-cluster ./test-output
```

### Test Multi-Cluster Mode

```bash
# New syntax with --multi flag
./k8s-health-check-pre.sh --multi ./clusters.conf
./k8s-health-check-post.sh --multi ./clusters.conf
```

## Benefits of v3.0

### For Users
- ✅ **Simpler**: Single script for all modes
- ✅ **Consistent**: Same behavior in single and multi-cluster
- ✅ **Faster**: No process spawning overhead
- ✅ **Reliable**: Better error handling and validation

### For Maintainers
- ✅ **Modular**: Easy to update individual sections
- ✅ **DRY Principle**: No code duplication
- ✅ **Testable**: Individual modules can be tested
- ✅ **Extensible**: Simple to add new features

## Adding Custom Health Checks

With the modular architecture, adding custom health checks is easy:

### Create a New Section Module

```bash
# Create new section file
cat > lib/sections/19-custom-check.sh << 'EOF'
#!/bin/bash
# Section 19: Custom Health Check

run_section_19_custom_check() {
    print_header "SECTION 19: CUSTOM HEALTH CHECK"

    run_check "My Custom Check" "kubectl get customresource -A"
    run_check "Another Check" "custom-command"
}

export -f run_section_19_custom_check
EOF

chmod +x lib/sections/19-custom-check.sh
```

### Update Main Scripts

Add the function call to both PRE and POST scripts:

```bash
# In k8s-health-check-pre.sh and k8s-health-check-post.sh
# Add after run_section_18_cluster_summary:

run_section_19_custom_check
```

That's it! The new section will be included in all future health checks.

## Troubleshooting

### Issue: "Source file not found"

```bash
# Ensure you're running from the correct directory
cd "k8 Health check"
./k8s-health-check-pre.sh --help
```

### Issue: "Function not defined"

```bash
# Ensure all library files are sourced
ls -la lib/*.sh
ls -la lib/sections/*.sh
```

### Issue: Multi-cluster commands not working

```bash
# Old syntax (won't work anymore)
./multi-cluster-pre-check.sh ./clusters.conf  ❌

# New syntax (use this)
./k8s-health-check-pre.sh --multi ./clusters.conf  ✅
```

## Version Comparison

| Feature | v2.0 | v3.0 |
|---------|------|------|
| Single Cluster Support | ✅ Separate script | ✅ Unified script |
| Multi-Cluster Support | ✅ Separate script | ✅ Unified script (--multi) |
| Modular Architecture | ❌ Monolithic | ✅ Library-based |
| Code Duplication | ❌ High | ✅ Minimal |
| Maintainability | ⚠️ Moderate | ✅ Excellent |
| Performance | ✅ Good | ✅ Better (no overhead) |
| Extensibility | ⚠️ Difficult | ✅ Easy |

## Support

For issues or questions:
- Check the main README: `K8S-HEALTH-CHECK-README.md`
- Review this migration guide
- Check backup scripts in `backup_old_scripts/`

## Version History

| Version | Date | Major Changes |
|---------|------|---------------|
| 1.0.0 | 2025-01-21 | Initial single-cluster scripts |
| 2.0.0 | 2025-01-21 | Added multi-cluster orchestration |
| 3.0.0 | 2025-01-22 | Unified scripts with modular architecture |
