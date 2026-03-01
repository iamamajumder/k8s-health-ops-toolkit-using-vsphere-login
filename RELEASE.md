# Release Notes

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


