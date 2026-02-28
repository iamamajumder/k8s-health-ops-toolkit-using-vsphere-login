#!/bin/bash
# Section 18: Cluster Summary with Health Indicators
#
# FORMAT CONTRACT — DO NOT CHANGE label text without updating lib/comparison.sh
# parse_health_report() uses these exact grep patterns to extract metrics for PRE/POST comparison:
#   grep -E "^Nodes NotReady:"   | awk '{print $3}'
#   grep -E "^Pods CrashLoop:"   | awk '{print $3}'
#   grep -E "^Pods Pending:"     | awk '{print $3}'
#   grep -E "^Pods Unaccounted:" | awk '{print $3}'
#   grep -E "^Deploys NotReady:" | awk '{print $3}'
#   grep -E "^DS NotReady:"      | awk '{print $3}'
#   grep -E "^STS NotReady:"     | awk '{print $3}'
#   grep -E "^PVCs NotBound:"    | awk '{print $3}'
#   grep -E "^Helm Failed:"      | awk '{print $3}'

run_section_18_cluster_summary() {
    # Format version — lets comparison.sh detect incompatible format changes
    echo "# Section18-Format-Version: 4.3"

    print_header "SECTION 18: CLUSTER SUMMARY"

    # METRICS NOTE: collect_health_metrics() and calculate_health_status() are called
    # in process_cluster() BEFORE run_all_health_sections(), so HEALTH_* variables are
    # already populated here. Do NOT call collect_health_metrics() again — it would
    # duplicate ~22 kubectl API calls per cluster with no benefit.

    # Defensive: ensure required metric keys have defaults to prevent arithmetic errors
    HEALTH_NODES_TOTAL=${HEALTH_NODES_TOTAL:-0}
    HEALTH_NODES_READY=${HEALTH_NODES_READY:-0}
    HEALTH_NODES_NOTREADY=${HEALTH_NODES_NOTREADY:-0}
    HEALTH_PODS_TOTAL=${HEALTH_PODS_TOTAL:-0}
    HEALTH_PODS_RUNNING=${HEALTH_PODS_RUNNING:-0}
    HEALTH_PODS_COMPLETED=${HEALTH_PODS_COMPLETED:-0}
    HEALTH_PODS_CRASHLOOP=${HEALTH_PODS_CRASHLOOP:-0}
    HEALTH_PODS_PENDING=${HEALTH_PODS_PENDING:-0}
    HEALTH_PODS_UNACCOUNTED=${HEALTH_PODS_UNACCOUNTED:-0}
    HEALTH_DEPLOYS_TOTAL=${HEALTH_DEPLOYS_TOTAL:-0}
    HEALTH_DEPLOYS_NOTREADY=${HEALTH_DEPLOYS_NOTREADY:-0}
    HEALTH_DS_TOTAL=${HEALTH_DS_TOTAL:-0}
    HEALTH_DS_NOTREADY=${HEALTH_DS_NOTREADY:-0}
    HEALTH_STS_TOTAL=${HEALTH_STS_TOTAL:-0}
    HEALTH_STS_NOTREADY=${HEALTH_STS_NOTREADY:-0}
    HEALTH_PVC_TOTAL=${HEALTH_PVC_TOTAL:-0}
    HEALTH_PVC_NOTBOUND=${HEALTH_PVC_NOTBOUND:-0}
    HEALTH_HELM_TOTAL=${HEALTH_HELM_TOTAL:-0}
    HEALTH_HELM_FAILED=${HEALTH_HELM_FAILED:-0}
    HEALTH_STATUS=${HEALTH_STATUS:-UNKNOWN}
    HEALTH_CRITICAL_COUNT=${HEALTH_CRITICAL_COUNT:-0}
    HEALTH_WARNING_COUNT=${HEALTH_WARNING_COUNT:-0}

    echo "--- Resource Counts ---"
    echo ""

    # Collect display-only metrics not in health.sh
    local svc_total ns_total pods_notrunning
    svc_total=$(kubectl get svc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ns_total=$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
    pods_notrunning=$((HEALTH_PODS_TOTAL - HEALTH_PODS_RUNNING - HEALTH_PODS_COMPLETED))
    [ "${pods_notrunning}" -lt 0 ] && pods_notrunning=0

    # Resource counts (format must match parse_health_report() grep patterns in comparison.sh)
    echo "Nodes Total: ${HEALTH_NODES_TOTAL}"
    echo "Nodes Ready: ${HEALTH_NODES_READY}"
    echo "Pods Total: ${HEALTH_PODS_TOTAL}"
    echo "Pods Running: ${HEALTH_PODS_RUNNING}"
    echo "Pods Not Running: ${pods_notrunning}"
    echo "Deployments Total: ${HEALTH_DEPLOYS_TOTAL}"
    echo "DaemonSets Total: ${HEALTH_DS_TOTAL}"
    echo "StatefulSets Total: ${HEALTH_STS_TOTAL}"
    echo "Services Total: ${svc_total:-0}"
    echo "PVCs Total: ${HEALTH_PVC_TOTAL}"
    echo "Namespaces: ${ns_total:-0}"
    echo "Helm Releases: ${HEALTH_HELM_TOTAL}"
    echo ""

    echo "--- Health Indicators ---"
    echo ""

    # Health indicators — label text is a FORMAT CONTRACT with comparison.sh (see header comment)
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

    # Overall health status
    echo "=================================================================================="
    echo "CLUSTER HEALTH: ${HEALTH_STATUS}"
    if [ "${HEALTH_CRITICAL_COUNT}" -gt 0 ] || [ "${HEALTH_WARNING_COUNT}" -gt 0 ]; then
        echo "  Critical Issues: ${HEALTH_CRITICAL_COUNT}"
        echo "  Warnings: ${HEALTH_WARNING_COUNT}"
    fi
    echo "=================================================================================="
    echo ""

    echo "Check Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

export -f run_section_18_cluster_summary
