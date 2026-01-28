# TO-DO List - Future Enhancements

**Project:** K8s Health Check Tool
**Last Updated:** 2026-01-28

---

## Deferred Tasks

### 1. Add Cluster Upgrade Module via TMC
**Status:** DEFERRED

Implement automated cluster upgrade functionality through TMC API.

**Scope:**
- Trigger VKR upgrades via TMC
- Monitor upgrade progress
- Rollback capability
- Pre-upgrade validation

---

### 2. Multi-Cluster Command Execution Tool
**Status:** DEFERRED

Create a tool to execute arbitrary commands across multiple clusters.

**Scope:**
- Execute kubectl commands on multiple clusters
- Parallel execution option
- Output aggregation
- Error handling per cluster

---

## Potential Future Enhancements

- [ ] HTML report generation
- [ ] Email notifications for critical issues
- [ ] Integration with monitoring systems (Prometheus/Grafana)
- [ ] Scheduled health checks (cron integration)
- [ ] Custom health check plugins
- [ ] Report archival and retention policies
- [ ] Dashboard for viewing historical health trends

---

## Completed (v3.2)

See [RELEASE.md](RELEASE.md) for completed items and changelog.
