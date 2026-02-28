#!/bin/bash
#===============================================================================
# Health Calculation Module
# Centralized health metrics and status calculation
# Version: 3.3
#===============================================================================

#===============================================================================
# Health Metrics Collection
#===============================================================================

# Collect all health metrics from cluster
# Returns metrics as exported variables
collect_health_metrics() {
    # Node metrics
    HEALTH_NODES_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    HEALTH_NODES_TOTAL=${HEALTH_NODES_TOTAL:-0}

    HEALTH_NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
    HEALTH_NODES_READY=$(echo "${HEALTH_NODES_READY}" | tr -d ' \n\r')
    HEALTH_NODES_READY=${HEALTH_NODES_READY:-0}

    HEALTH_NODES_NOTREADY=$((HEALTH_NODES_TOTAL - HEALTH_NODES_READY))

    # Pod metrics
    HEALTH_PODS_TOTAL=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    HEALTH_PODS_TOTAL=${HEALTH_PODS_TOTAL:-0}

    HEALTH_PODS_RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running || true)
    HEALTH_PODS_RUNNING=$(echo "${HEALTH_PODS_RUNNING}" | tr -d ' \n\r')
    HEALTH_PODS_RUNNING=${HEALTH_PODS_RUNNING:-0}

    HEALTH_PODS_CRASHLOOP=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic CrashLoopBackOff || true)
    HEALTH_PODS_CRASHLOOP=$(echo "${HEALTH_PODS_CRASHLOOP}" | tr -d ' \n\r')
    HEALTH_PODS_CRASHLOOP=${HEALTH_PODS_CRASHLOOP:-0}

    HEALTH_PODS_PENDING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic Pending || true)
    HEALTH_PODS_PENDING=$(echo "${HEALTH_PODS_PENDING}" | tr -d ' \n\r')
    HEALTH_PODS_PENDING=${HEALTH_PODS_PENDING:-0}

    HEALTH_PODS_COMPLETED=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic Completed || true)
    HEALTH_PODS_COMPLETED=$(echo "${HEALTH_PODS_COMPLETED}" | tr -d ' \n\r')
    HEALTH_PODS_COMPLETED=${HEALTH_PODS_COMPLETED:-0}

    # Calculate unaccounted pods (not Running, Completed, CrashLoop, or Pending)
    HEALTH_PODS_UNACCOUNTED=$((HEALTH_PODS_TOTAL - HEALTH_PODS_RUNNING - HEALTH_PODS_COMPLETED - HEALTH_PODS_CRASHLOOP - HEALTH_PODS_PENDING))
    [ "${HEALTH_PODS_UNACCOUNTED}" -lt 0 ] && HEALTH_PODS_UNACCOUNTED=0

    # Deployment metrics
    HEALTH_DEPLOYS_TOTAL=$(kubectl get deploy -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    HEALTH_DEPLOYS_TOTAL=${HEALTH_DEPLOYS_TOTAL:-0}

    HEALTH_DEPLOYS_NOTREADY=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')
    HEALTH_DEPLOYS_NOTREADY=${HEALTH_DEPLOYS_NOTREADY:-0}

    HEALTH_DEPLOYS_READY=$((HEALTH_DEPLOYS_TOTAL - HEALTH_DEPLOYS_NOTREADY))

    # DaemonSet metrics
    HEALTH_DS_TOTAL=$(kubectl get ds -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    HEALTH_DS_TOTAL=${HEALTH_DS_TOTAL:-0}

    # FIX: was $4!=$6 (CURRENT vs UP-TO-DATE) — wrong columns. Correct: $3!=$5 (DESIRED vs READY).
    # kubectl get ds -A --no-headers columns: NAMESPACE(1) NAME(2) DESIRED(3) CURRENT(4) READY(5) UP-TO-DATE(6) AVAILABLE(7)
    HEALTH_DS_NOTREADY=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$3 != $5 {count++} END{print count+0}' | tr -d ' ')
    HEALTH_DS_NOTREADY=${HEALTH_DS_NOTREADY:-0}

    HEALTH_DS_READY=$((HEALTH_DS_TOTAL - HEALTH_DS_NOTREADY))

    # StatefulSet metrics
    HEALTH_STS_TOTAL=$(kubectl get sts -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    HEALTH_STS_TOTAL=${HEALTH_STS_TOTAL:-0}

    HEALTH_STS_NOTREADY=$(kubectl get sts -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')
    HEALTH_STS_NOTREADY=${HEALTH_STS_NOTREADY:-0}

    HEALTH_STS_READY=$((HEALTH_STS_TOTAL - HEALTH_STS_NOTREADY))

    # PVC metrics
    HEALTH_PVC_TOTAL=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    HEALTH_PVC_TOTAL=${HEALTH_PVC_TOTAL:-0}

    HEALTH_PVC_NOTBOUND=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -v Bound | wc -l | tr -d ' ')
    HEALTH_PVC_NOTBOUND=${HEALTH_PVC_NOTBOUND:-0}

    HEALTH_PVC_BOUND=$((HEALTH_PVC_TOTAL - HEALTH_PVC_NOTBOUND))

    # Helm metrics
    HEALTH_HELM_TOTAL=$(helm list -A --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo '0')
    HEALTH_HELM_TOTAL=${HEALTH_HELM_TOTAL:-0}

    HEALTH_HELM_FAILED=$(helm list -A --failed --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo '0')
    HEALTH_HELM_FAILED=${HEALTH_HELM_FAILED:-0}

    HEALTH_HELM_DEPLOYED=$((HEALTH_HELM_TOTAL - HEALTH_HELM_FAILED))
}

#===============================================================================
# Health Status Calculation
#===============================================================================

# Calculate health status based on collected metrics
# Sets HEALTH_STATUS to HEALTHY, WARNINGS, or CRITICAL
calculate_health_status() {
    local critical_count=0
    local warning_count=0

    # Critical conditions
    [ "${HEALTH_NODES_NOTREADY:-0}" -gt 0 ] && critical_count=$((critical_count + 1))
    [ "${HEALTH_PODS_CRASHLOOP:-0}" -gt 0 ] && critical_count=$((critical_count + 1))

    # Warning conditions
    [ "${HEALTH_PODS_PENDING:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${HEALTH_PODS_UNACCOUNTED:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${HEALTH_DEPLOYS_NOTREADY:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${HEALTH_DS_NOTREADY:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${HEALTH_STS_NOTREADY:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${HEALTH_PVC_NOTBOUND:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${HEALTH_HELM_FAILED:-0}" -gt 0 ] && warning_count=$((warning_count + 1))

    # Determine status
    HEALTH_STATUS="HEALTHY"
    HEALTH_CRITICAL_COUNT=${critical_count}
    HEALTH_WARNING_COUNT=${warning_count}

    [ "$critical_count" -gt 0 ] && HEALTH_STATUS="CRITICAL"
    [ "$critical_count" -eq 0 ] && [ "$warning_count" -gt 0 ] && HEALTH_STATUS="WARNINGS"
}

#===============================================================================
# Health Summary Generation
#===============================================================================

# Generate cluster health summary string
# Usage: generate_health_summary "cluster-name"
generate_health_summary() {
    local cluster_name="$1"

    cat << EOSUMMARY
CLUSTER: ${cluster_name}
  Nodes: ${HEALTH_NODES_READY}/${HEALTH_NODES_TOTAL} Ready
  Pods: ${HEALTH_PODS_RUNNING}/${HEALTH_PODS_TOTAL} Running
  Deployments: ${HEALTH_DEPLOYS_READY}/${HEALTH_DEPLOYS_TOTAL} Ready
  DaemonSets: ${HEALTH_DS_READY}/${HEALTH_DS_TOTAL} Ready
  StatefulSets: ${HEALTH_STS_READY}/${HEALTH_STS_TOTAL} Ready
  PVCs: ${HEALTH_PVC_BOUND}/${HEALTH_PVC_TOTAL} Bound
  Helm: ${HEALTH_HELM_DEPLOYED}/${HEALTH_HELM_TOTAL} Deployed
  ---
  Health Indicators:
    Nodes NotReady: ${HEALTH_NODES_NOTREADY:-0}
    Pods CrashLoop: ${HEALTH_PODS_CRASHLOOP:-0}
    Pods Pending: ${HEALTH_PODS_PENDING:-0}
    Pods Completed: ${HEALTH_PODS_COMPLETED:-0}
    Pods Unaccounted: ${HEALTH_PODS_UNACCOUNTED:-0}
  ---
  HEALTH STATUS: ${HEALTH_STATUS}
EOSUMMARY
}

#===============================================================================
# All-in-One Health Check
#===============================================================================

# Collect metrics, calculate status, and generate summary
# Usage: run_health_check "cluster-name"
# Returns: summary string via stdout, sets HEALTH_* variables
run_health_check() {
    local cluster_name="$1"

    # Collect all metrics
    collect_health_metrics

    # Calculate health status
    calculate_health_status

    # Generate and return summary
    generate_health_summary "${cluster_name}"
}

export -f collect_health_metrics
export -f calculate_health_status
export -f generate_health_summary
export -f run_health_check
