#!/bin/bash
# Section 3: Pod Status

run_section_03_pod_status() {
    print_header "SECTION 3: POD STATUS"

    run_check "All Pods (Full List)" "kubectl get pod -A -o wide"
    run_check "Non-Running Pods (CRITICAL)" "kubectl get pod -A | grep -vi running | grep -vi completed || echo 'All pods are Running or Completed'"
    run_check "Pods in CrashLoopBackOff" "kubectl get pod -A | grep -i crashloop || echo 'No CrashLoopBackOff pods found'"
    run_check "Pods in Pending State" "kubectl get pod -A | grep -i pending || echo 'No Pending pods found'"
    run_check "Pods Restarting (>5 restarts)" "kubectl get pod -A -o wide | awk 'NR==1 || \$5 > 5'"
    run_check "Gateway Pods" "kubectl get po -A | grep -i gateway-0"
    run_check "Kubernetes Dashboard Pods" "kubectl get po -A | grep -i kubernetes-dashboard || echo 'Kubernetes Dashboard not found'"
}

export -f run_section_03_pod_status
