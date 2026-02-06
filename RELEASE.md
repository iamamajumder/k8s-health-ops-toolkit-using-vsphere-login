# Release Notes

## Quick Navigation

| Version | Date | Summary |
|---------|------|---------|
| [v4.0](#version-40-2026-02-06) | 2026-02-06 | Documentation overhaul - README-DEV.md beautification |
| [v3.8](#version-38-2026-02-05) | 2026-02-05 | Codebase refactoring (~455 lines removed) |
| [v3.7](#version-37-2026-02-05) | 2026-02-05 | Parallel upgrades, `-c` flag for health-check/ops-cmd |
| [v3.6](#version-36-2026-02-04) | 2026-02-04 | Per-cluster output structure, automatic cleanup |
| [v3.5](#version-35-2026-02-03) | 2026-02-03 | Management cluster discovery, upgrade script rewrite |
| [v3.4](#version-34-2026-01-29) | 2026-01-29 | Parallel batch execution, new upgrade/ops scripts |
| [v3.3](#version-33-2026-01-29) | 2026-01-29 | Unified script with `--mode` flag, health module |
| [v3.2.x](#version-326-2026-01-29) | 2026-01-29 | Bug fixes for grep patterns and health metrics |
| [v3.2](#version-32-2026-01-28) | 2026-01-28 | Enhanced health summary, PRE vs POST comparison |
| [v3.1](#version-31-2025-01-22) | 2025-01-22 | Auto-discovery, auto-context, unified execution |
| [v3.0](#version-30-initial-release) | Initial | Basic health check functionality |

---

## Version 4.0 (2026-02-06)

**Summary:** Documentation overhaul - README-DEV.md converted from plain text to proper markdown for improved VSCode readability.

### Changes

#### README-DEV.md Beautification
- Converted ASCII box headers (`================`) to proper markdown `##` headers
- Converted ASCII tables (`+---+---+`) to markdown tables (`| --- |`)
- Wrapped all command examples in ```bash code blocks with syntax highlighting
- Wrapped ASCII diagrams in code blocks to preserve alignment
- Added `---` horizontal rules between major sections
- Added clickable Table of Contents with anchor links
- Removed excessive 2-space indentation throughout

#### Architecture Section Simplification
- Replaced complex ASCII box diagrams with simple tree format using `|` and `+--`
- Upgrade Workflow: Now shows linear flow with bullet points
- Script Architecture: Tree structure (main scripts → library modules → sections → external tools)
- Health Status Decision Tree: Simple decision tree with `+-- YES/NO` branches

#### "The Three Scripts" Section Enhancement
- Added three numbered subsections (2.1, 2.2, 2.3) with proper headers
- Included full descriptions for each script
- Added comprehensive code examples from README.md:
  - Health Check: 4 examples
  - Cluster Upgrade: 5 examples
  - Multi-Cluster Ops: 4 examples
- Added options tables for each script
- Included Health Status Classification table

### Breaking Changes

**None** - Documentation only, no code changes.

---

## Version 3.8 (2026-02-05)

**Summary:** Major internal refactoring to eliminate duplicated code, consolidate shared logic, and clean up dead code. **~455 lines removed** with zero functional changes.

### Changes

#### Shared Functions & Constants
- Extracted `prepare_tmc_contexts()` to `lib/tmc.sh` (was duplicated in health-check and upgrade scripts)
- Added `DEFAULT_BATCH_SIZE=6` constant to `lib/common.sh` (was hardcoded in 3 scripts)
- Standardized timestamp usage via `get_timestamp()` function

#### Code Consolidation
- Section 18 now reuses `collect_health_metrics()` and `calculate_health_status()` from `lib/health.sh` (-100 lines)
- Consolidated TMC context functions into single `_setup_tmc_context()` core (-105 lines)
- Data-driven `generate_metrics_comparison()` and `generate_layman_summary()` in `lib/comparison.sh` (-195 lines)
- Added generic `safe_compare()` function, simplified existing comparison wrappers

#### Cleanup
- Removed empty `get_environment_info()` function
- Removed deprecated `display_comparison_summary()` function

### Bug Fixes

| Component | Issue | Fix |
|-----------|-------|-----|
| `k8s-ops-cmd.sh` | Credentials not prompted in single cluster mode | Sequential context prep before parallel execution |
| `k8s-ops-cmd.sh` | Old output directory structure | Per-cluster v3.8 structure |
| `k8s-ops-cmd.sh` | Redundant output files | Consolidated to single `ops-*.txt` per cluster |
| `k8s-ops-cmd.sh` | Aggregated results in per-cluster dirs | New `/ops-aggregated/` directory |
| `k8s-cluster-upgrade.sh` | POST skipped in parallel mode | File logging instead of `/dev/null` |
| `k8s-cluster-upgrade.sh` | VMware version suffix mismatch | Base version extraction before comparison |
| `k8s-health-check.sh` | Redundant header in POST output | Removed wrapper section |

### Breaking Changes

**None** - All functionality preserved, all command-line options unchanged.

---

## Version 3.7 (2026-02-05)

**Summary:** Parallel upgrade mode, single cluster flag for all scripts, and file retention bug fixes.

### Changes

#### Parallel Upgrade Mode
- Added `--parallel` flag to `k8s-cluster-upgrade.sh` for batch parallel cluster upgrades
- Customizable batch size with `--batch-size N` (default: 6)
- PRE health checks and prompts run sequentially, monitoring runs in parallel
- Per-cluster POST health check runs automatically when each upgrade completes

#### Single Cluster Flag (`-c`)
- Added `-c`/`--cluster` flag to `k8s-health-check.sh` and `k8s-ops-cmd.sh`
- Run against a single cluster without requiring `clusters.conf`
- Mutually exclusive with config file argument

### Bug Fixes

| Issue | Fix |
|-------|-----|
| `latest/` directory accumulates files unbounded | Clear before copy, keep only 1 file |
| Sequential mode never updates `latest/` | Added fallback for non-parallel mode |
| `cleanup_old_files()` doesn't clean `latest/` subdirectory | Added nested cleanup loop |
| Upgrade scripts don't always run cleanup | Added cleanup to parallel and sequential multi-cluster functions |

### Breaking Changes

**None** - Default behavior unchanged.

---

## Version 3.6 (2026-02-04)

**Summary:** Complete reorganization of output structure from timestamp-based directories to per-cluster directories with timestamped files.

### Changes

#### Output Folder Restructuring
- Per-cluster organization: `~/k8s-health-check/output/<cluster>/`
- Consolidated kubeconfig: Single cached file per cluster (12-hour expiry)
- Timestamped files: `pre-hcr-YYYYMMDD_HHMMSS.txt`, `post-hcr-*.txt`, etc.
- Automatic cleanup: Keeps 5 most recent files per type

**New Structure:**
```
~/k8s-health-check/output/
└── cluster-name/
    ├── kubeconfig
    ├── h-c-r/
    │   ├── pre-hcr-YYYYMMDD_HHMMSS.txt
    │   ├── post-hcr-YYYYMMDD_HHMMSS.txt
    │   └── latest/
    ├── ops/
    └── upgrade/
```

### Bug Fixes

| Issue | Fix |
|-------|-----|
| TMC authentication prompt hanging | Removed `2>&1` from TMC function calls |
| `BOLD: unbound variable` | Added `BOLD`/`RESET` variables to `lib/common.sh` |

### Breaking Changes

**None** - Old directories preserved for backward compatibility.

---

## Version 3.5 (2026-02-03)

**Summary:** Cluster upgrade script rewrite (70% code reduction), management cluster discovery, and standardized caching.

### Changes

#### Cluster Upgrade Script Rewrite
- **70% code reduction**: 1200 lines to 350 lines
- Delegates health checks to `k8s-health-check.sh` instead of duplicating logic
- User confirmation prompt before each upgrade
- Dynamic timeout calculation (nodes x 5 minutes)
- Real-time monitoring with 2-minute progress updates

#### Management Cluster Discovery
- Added `-m <environment>` flag to `k8s-ops-cmd.sh`
- Dynamically discovers clusters from TMC management cluster
- Supports: `prod-1`, `prod-2`, `prod-3`, `prod-4`, `uat-2`, `uat-4`, `system-1`, `system-3`
- Results cached for 12 hours

#### Standardized Cache Expiry
- All caches now use consistent 12-hour expiry
- Metadata cache changed from 7 days to 12 hours

### Breaking Changes

**None** - All existing functionality preserved.

---

## Version 3.4 (2026-01-29)

**Summary:** Parallel batch execution as default, new upgrade and ops scripts.

### Changes

#### Batch Parallel Execution (Default)
- All scripts now run 6 clusters in parallel by default
- Use `--sequential` to process one at a time
- Use `--batch-size N` to customize batch size

#### New Scripts
- **`k8s-cluster-upgrade.sh`**: Health-gated cluster upgrades with monitoring
- **`k8s-ops-cmd.sh`**: Multi-cluster command execution

### Breaking Changes

**None** - Parallel execution improves performance without changing output format.

---

## Version 3.3 (2026-01-29)

**Summary:** Unified PRE/POST scripts into single script with `--mode` flag.

### Changes

- Merged `k8s-health-check-pre.sh` and `k8s-health-check-post.sh` into `k8s-health-check.sh`
- New `lib/health.sh` module with centralized health calculations
- Added test suite (`tests/test-grep-patterns.sh`)

### Usage Change
```bash
# Old (v3.2)
./k8s-health-check-pre.sh
./k8s-health-check-post.sh

# New (v3.3+)
./k8s-health-check.sh --mode pre
./k8s-health-check.sh --mode post
```

### Breaking Changes

Old scripts archived to `Archive/v3.2/` for backward compatibility.

---

## Version 3.2.6 (2026-01-29)

**Summary:** Bug fix for "0\n0" syntax error in arithmetic expressions.

### Bug Fixes

| Issue | Fix |
|-------|-----|
| `syntax error in expression (error token is "0")` | Changed `grep -c ... \|\| echo '0'` pattern to use `\|\| true` with separate sanitization |

---

## Version 3.2.3 (2026-01-29)

**Summary:** Bug fix for script exiting silently during health check.

### Bug Fixes

| Issue | Fix |
|-------|-----|
| Script exits abruptly without error | Added `set +e`, `\|\| true` to all `grep -c` commands, proper variable sanitization |

---

## Version 3.2.2 (2026-01-29)

**Summary:** Added "Pods Unaccounted" health metric.

### Changes

- **New metric**: `Pods Unaccounted = Total - Running - Completed - CrashLoop - Pending`
- Catches pods in unexpected states (Failed, Unknown, ImagePullBackOff)
- `Pods Unaccounted > 0` triggers a WARNING

---

## Version 3.2.1 (2026-01-29)

**Summary:** Multiple bug fixes for integer expressions, TMC context, and output formatting.

### Bug Fixes

| Issue | Fix |
|-------|-----|
| `integer expression expected` error | Changed `\|\| echo '0'` to `\|\| true` with sanitization |
| "0\n0" display in Health Indicators | Proper sanitization with `tr -d ' \n\r'` |
| POST recreated context even when PRE just created it | Fixed `save_context_timestamp()` edge case |
| Excessive console output | Removed verbose directory/info messages |
| Multi-line spacing | Reduced blank lines between sections |

---

## Version 3.2 (2026-01-28)

**Summary:** Enhanced cluster health summary and improved PRE vs POST comparison.

### Changes

#### Latest Directory
- PRE script creates/updates `./health-check-results/latest/`
- POST script defaults to using `latest` directory

#### Enhanced Health Summary
- Health indicators in Section 18 with HEALTHY/WARNINGS/CRITICAL status
- New metrics: Nodes NotReady, Pods CrashLoopBackOff, Pending, etc.

#### PRE vs POST Comparison
- Actual comparison of PRE and POST report files
- Delta calculation showing OK/WORSE/BETTER/CHANGED
- Plain English summary of what changed

### Breaking Changes

**None**

---

## Version 3.1 (2025-01-22)

**Summary:** Simplified configuration with auto-discovery and auto-context creation.

### Changes

- Simplified configuration (just cluster names)
- Auto-discovery of cluster metadata from TMC
- Auto-creation of TMC contexts based on naming patterns
- Unified execution (removed `--multi` flag)
- 18 comprehensive health check modules
- Persistent caching for metadata and kubeconfig

### Cluster Naming Convention
| Pattern | Environment | TMC Context |
|---------|-------------|-------------|
| `*-prod-[1-4]` | Production | tmc-sm-prod |
| `*-uat-[1-4]` | Non-production | tmc-sm-nonprod |
| `*-system-[1-4]` | Non-production | tmc-sm-nonprod |

---

## Version 3.0 (Initial Release)

**Summary:** Basic health check functionality.

### Features

- Basic health check functionality
- Manual TMC context management
- 18 health check sections
- PRE/POST comparison (basic)
