#!/bin/bash
# Section 18: Cluster Summary with Health Indicators
# Refactored to use centralized health.sh functions

run_section_18_cluster_summary() {
    print_header "SECTION 18: CLUSTER SUMMARY"

    echo "--- Resource Counts ---"
    echo ""

    # Collect all health metrics using centralized module
    collect_health_metrics
    calculate_health_status

    # Collect display-only metrics not in health.sh
    local svc_total=$(kubectl get svc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local ns_total=$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local pods_notrunning=$((HEALTH_PODS_TOTAL - HEALTH_PODS_RUNNING - HEALTH_PODS_COMPLETED))
    [ "${pods_notrunning}" -lt 0 ] && pods_notrunning=0

    # Display resource counts (format must match parse_health_report() grep patterns)
    echo "Nodes Total: ${HEALTH_NODES_TOTAL}"
    echo "Nodes Ready: ${HEALTH_NODES_READY}"
    echo "Pods Total: ${HEALTH_PODS_TOTAL}"
    echo "Pods Running: ${HEALTH_PODS_RUNNING}"
    echo "Pods Not Running: ${pods_notrunning}"
    echo "Deployments Total: ${HEALTH_DEPLOYS_TOTAL}"
    echo "DaemonSets Total: ${HEALTH_DS_TOTAL}"
    echo "StatefulSets Total: ${HEALTH_STS_TOTAL}"
    echo "Services Total: ${svc_total}"
    echo "PVCs Total: ${HEALTH_PVC_TOTAL}"
    echo "Namespaces: ${ns_total}"
    echo "Helm Releases: ${HEALTH_HELM_TOTAL}"
    echo ""

    echo "--- Health Indicators ---"
    echo ""

    # Display health indicators with status (format must match parse_health_report() grep patterns)
    if [ "${HEALTH_NODES_NOTREADY}" -gt 0 ]; then
        echo "Nodes NotReady: ${HEALTH_NODES_NOTREADY}      [CRITICAL]"
    else
        echo "Nodes NotReady: ${HEALTH_NODES_NOTREADY}      [OK]"
    fi

    if [ "${HEALTH_PODS_CRASHLOOP}" -gt 0 ]; then
        echo "Pods CrashLoop: ${HEALTH_PODS_CRASHLOOP}      [CRITICAL]"
    else
        echo "Pods CrashLoop: ${HEALTH_PODS_CRASHLOOP}      [OK]"
    fi

    if [ "${HEALTH_PODS_PENDING}" -gt 0 ]; then
        echo "Pods Pending: ${HEALTH_PODS_PENDING}      [WARNING]"
    else
        echo "Pods Pending: ${HEALTH_PODS_PENDING}      [OK]"
    fi

    if [ "${HEALTH_DEPLOYS_NOTREADY}" -gt 0 ]; then
        echo "Deploys NotReady: ${HEALTH_DEPLOYS_NOTREADY}      [WARNING]"
    else
        echo "Deploys NotReady: ${HEALTH_DEPLOYS_NOTREADY}      [OK]"
    fi

    if [ "${HEALTH_DS_NOTREADY}" -gt 0 ]; then
        echo "DS NotReady: ${HEALTH_DS_NOTREADY}      [WARNING]"
    else
        echo "DS NotReady: ${HEALTH_DS_NOTREADY}      [OK]"
    fi

    if [ "${HEALTH_STS_NOTREADY}" -gt 0 ]; then
        echo "STS NotReady: ${HEALTH_STS_NOTREADY}      [WARNING]"
    else
        echo "STS NotReady: ${HEALTH_STS_NOTREADY}      [OK]"
    fi

    if [ "${HEALTH_PVC_NOTBOUND}" -gt 0 ]; then
        echo "PVCs NotBound: ${HEALTH_PVC_NOTBOUND}      [WARNING]"
    else
        echo "PVCs NotBound: ${HEALTH_PVC_NOTBOUND}      [OK]"
    fi

    if [ "${HEALTH_HELM_FAILED}" -gt 0 ]; then
        echo "Helm Failed: ${HEALTH_HELM_FAILED}      [WARNING]"
    else
        echo "Helm Failed: ${HEALTH_HELM_FAILED}      [OK]"
    fi

    echo "Pods Completed: ${HEALTH_PODS_COMPLETED}      [INFO]"

    if [ "${HEALTH_PODS_UNACCOUNTED}" -gt 0 ]; then
        echo "Pods Unaccounted: ${HEALTH_PODS_UNACCOUNTED}      [WARNING]"
    else
        echo "Pods Unaccounted: ${HEALTH_PODS_UNACCOUNTED}      [OK]"
    fi

    echo ""

    # Display overall health status (already calculated by calculate_health_status)
    echo "=================================================================================="
    echo "CLUSTER HEALTH: ${HEALTH_STATUS}"
    if [ "${HEALTH_CRITICAL_COUNT}" -gt 0 ] || [ "${HEALTH_WARNING_COUNT}" -gt 0 ]; then
        echo "  Critical Issues: ${HEALTH_CRITICAL_COUNT}"
        echo "  Warnings: ${HEALTH_WARNING_COUNT}"
    fi
    echo "=================================================================================="
    echo ""

    print_header "HEALTH CHECK COMPLETED"
    echo "Check Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

export -f run_section_18_cluster_summary
