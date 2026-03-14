# Release Notes

## [1.1] - 2026-03-14

### Summary

- Renamed credential variables for clearer AO vs non-AO account handling:
  - `AO_ACCOUNT_USERNAME`
  - `AO_ACCOUNT_PASSWORD`
  - `NONAO_ACCOUNT_USERNAME`
  - `NONAO_ACCOUNT_PASSWORD`
- Updated credential flow semantics:
  - Supervisor login for prod and non-prod uses `AO_ACCOUNT_*`
  - Production workload login uses `AO_ACCOUNT_*`
  - Non-production workload login uses `NONAO_ACCOUNT_*`
- Added supervisor-only mode to `k8s-ops-cmd.sh`:
  - `-s, --supervisor <env>`
  - Example: `./k8s-ops-cmd.sh -s uat-2 "kubectl get cluster -A"`
- Added `supervisor-ops/` output path for supervisor-only command results.

## [1.0] - 2026-03-01

### Summary

- Refactored toolkit to vSphere-only runtime flow.
- Removed legacy external runtime dependencies from:
  - `k8s-health-check.sh`
  - `k8s-ops-cmd.sh`
  - `k8s-cluster-upgrade.sh`
- Replaced upgrade path with Supervisor object patch workflow:
  - Cluster API: `cluster.spec.topology.version`
  - TKC: `tanzukubernetescluster.spec.distribution.version`
- Added interactive TKC retirement prompt when required:
  - `Do you want to enable Auto-retire the workload cluster from tkc to cluster api? (Y/N)`
- Rebuilt ops `-m` discovery to Supervisor-based discovery.
- Consolidated repository for production use:
  - removed `Archive/`
  - removed `README-DEV.md`


