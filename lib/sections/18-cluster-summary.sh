#!/bin/bash
# Section 18: Cluster Summary with Health Indicators

run_section_18_cluster_summary() {
    print_header "SECTION 18: CLUSTER SUMMARY"

    echo "--- Resource Counts ---"
    echo ""

    # Basic counts
    local nodes_total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' | tr -d ' ')
    local pods_total=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local pods_running=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running | tr -d ' ')
    local pods_notrunning=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l | tr -d ' ')
    local deploys_total=$(kubectl get deploy -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local ds_total=$(kubectl get ds -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local sts_total=$(kubectl get sts -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local svc_total=$(kubectl get svc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local pvc_total=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local ns_total=$(kubectl get ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local helm_total=$(helm list -A --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo '0')

    echo "Nodes Total: ${nodes_total}"
    echo "Nodes Ready: ${nodes_ready}"
    echo "Pods Total: ${pods_total}"
    echo "Pods Running: ${pods_running}"
    echo "Pods Not Running: ${pods_notrunning}"
    echo "Deployments Total: ${deploys_total}"
    echo "DaemonSets Total: ${ds_total}"
    echo "StatefulSets Total: ${sts_total}"
    echo "Services Total: ${svc_total}"
    echo "PVCs Total: ${pvc_total}"
    echo "Namespaces: ${ns_total}"
    echo "Helm Releases: ${helm_total}"
    echo ""

    echo "--- Health Indicators ---"
    echo ""

    # Health indicator calculations
    local nodes_notready=$((nodes_total - nodes_ready))
    local pods_crashloop=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic CrashLoopBackOff | tr -d ' ' || echo '0')
    local pods_pending=$(kubectl get pods -A --no-headers 2>/dev/null | grep -ic Pending | tr -d ' ' || echo '0')

    # Deployments not ready (READY column shows X/Y where X != Y)
    local deploys_notready=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')

    # DaemonSets not ready (DESIRED != READY)
    local ds_notready=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$4 != $6 {count++} END{print count+0}' | tr -d ' ')

    # StatefulSets not ready (READY column shows X/Y where X != Y)
    local sts_notready=$(kubectl get sts -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')

    # PVCs not bound
    local pvc_notbound=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -v Bound | wc -l | tr -d ' ')

    # Helm releases failed
    local helm_failed=$(helm list -A --failed --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo '0')

    # Clean up values (ensure integers)
    nodes_notready=${nodes_notready:-0}
    pods_crashloop=${pods_crashloop:-0}
    pods_pending=${pods_pending:-0}
    deploys_notready=${deploys_notready:-0}
    ds_notready=${ds_notready:-0}
    sts_notready=${sts_notready:-0}
    pvc_notbound=${pvc_notbound:-0}
    helm_failed=${helm_failed:-0}

    # Display health indicators with status
    if [ "$nodes_notready" -gt 0 ]; then
        echo "Nodes NotReady: ${nodes_notready}      [CRITICAL]"
    else
        echo "Nodes NotReady: ${nodes_notready}      [OK]"
    fi

    if [ "$pods_crashloop" -gt 0 ]; then
        echo "Pods CrashLoop: ${pods_crashloop}      [CRITICAL]"
    else
        echo "Pods CrashLoop: ${pods_crashloop}      [OK]"
    fi

    if [ "$pods_pending" -gt 0 ]; then
        echo "Pods Pending: ${pods_pending}      [WARNING]"
    else
        echo "Pods Pending: ${pods_pending}      [OK]"
    fi

    if [ "$deploys_notready" -gt 0 ]; then
        echo "Deploys NotReady: ${deploys_notready}      [WARNING]"
    else
        echo "Deploys NotReady: ${deploys_notready}      [OK]"
    fi

    if [ "$ds_notready" -gt 0 ]; then
        echo "DS NotReady: ${ds_notready}      [WARNING]"
    else
        echo "DS NotReady: ${ds_notready}      [OK]"
    fi

    if [ "$sts_notready" -gt 0 ]; then
        echo "STS NotReady: ${sts_notready}      [WARNING]"
    else
        echo "STS NotReady: ${sts_notready}      [OK]"
    fi

    if [ "$pvc_notbound" -gt 0 ]; then
        echo "PVCs NotBound: ${pvc_notbound}      [WARNING]"
    else
        echo "PVCs NotBound: ${pvc_notbound}      [OK]"
    fi

    if [ "$helm_failed" -gt 0 ]; then
        echo "Helm Failed: ${helm_failed}      [WARNING]"
    else
        echo "Helm Failed: ${helm_failed}      [OK]"
    fi

    echo ""

    # Determine overall health status
    local health_status="HEALTHY"
    local critical_count=0
    local warning_count=0

    # Critical conditions
    if [ "$nodes_notready" -gt 0 ]; then
        critical_count=$((critical_count + 1))
    fi
    if [ "$pods_crashloop" -gt 0 ]; then
        critical_count=$((critical_count + 1))
    fi

    # Warning conditions
    if [ "$pods_pending" -gt 0 ]; then
        warning_count=$((warning_count + 1))
    fi
    if [ "$deploys_notready" -gt 0 ]; then
        warning_count=$((warning_count + 1))
    fi
    if [ "$ds_notready" -gt 0 ]; then
        warning_count=$((warning_count + 1))
    fi
    if [ "$sts_notready" -gt 0 ]; then
        warning_count=$((warning_count + 1))
    fi
    if [ "$pvc_notbound" -gt 0 ]; then
        warning_count=$((warning_count + 1))
    fi
    if [ "$helm_failed" -gt 0 ]; then
        warning_count=$((warning_count + 1))
    fi

    # Set health status
    if [ "$critical_count" -gt 0 ]; then
        health_status="CRITICAL"
    elif [ "$warning_count" -gt 0 ]; then
        health_status="WARNINGS"
    fi

    echo "=================================================================================="
    echo "CLUSTER HEALTH: ${health_status}"
    if [ "$critical_count" -gt 0 ] || [ "$warning_count" -gt 0 ]; then
        echo "  Critical Issues: ${critical_count}"
        echo "  Warnings: ${warning_count}"
    fi
    echo "=================================================================================="
    echo ""

    print_header "HEALTH CHECK COMPLETED"
    echo "Check Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

export -f run_section_18_cluster_summary
