#!/bin/bash
# Section 10: Component Status

run_section_10_component_status() {
    print_header "SECTION 10: COMPONENT STATUS"

    run_check "Component Status (Deprecated but useful)" "kubectl get cs 2>/dev/null || echo 'Component status not available'"
    run_check "Control Plane Pods" "kubectl get pods -n kube-system -l tier=control-plane 2>/dev/null || kubectl get pods -n kube-system | grep -E '(kube-apiserver|kube-controller|kube-scheduler|etcd)'"
    run_check "CoreDNS Status" "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    run_check "Metrics Server" "kubectl get pods -n kube-system | grep metrics-server || echo 'Metrics server not found'"
}

export -f run_section_10_component_status
