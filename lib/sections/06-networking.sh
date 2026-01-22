#!/bin/bash
# Section 6: Networking

run_section_06_networking() {
    print_header "SECTION 6: NETWORKING"

    run_check "All Services" "kubectl get svc -A"
    run_check "Services in tanzu-system-ingress" "kubectl get svc -n tanzu-system-ingress 2>/dev/null || echo 'Namespace not found'"
    run_check "Pods in tanzu-system-ingress" "kubectl get pod -n tanzu-system-ingress 2>/dev/null || echo 'Namespace not found'"
    run_check "HTTPProxy Resources" "kubectl -n k8s-system get httpproxy 2>/dev/null || echo 'HTTPProxy not found or namespace does not exist'"
    run_check "All Ingresses" "kubectl get ingress -A 2>/dev/null || echo 'No Ingress resources found'"
    run_check "Network Policies" "kubectl get networkpolicy -A 2>/dev/null || echo 'No NetworkPolicies found'"
}

export -f run_section_06_networking
