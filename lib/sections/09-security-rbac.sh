#!/bin/bash
# Section 9: Security & RBAC

run_section_09_security_rbac() {
    print_header "SECTION 9: SECURITY & RBAC"

    run_check "Pod Disruption Budgets" "kubectl get pdb -A"
    run_check "PDB Status Details" "kubectl get pdb -A -o wide 2>/dev/null"
    run_check "Service Accounts (kube-system)" "kubectl get sa -n kube-system"
    run_check "Cluster Role Bindings Count" "kubectl get clusterrolebindings --no-headers 2>/dev/null | wc -l"
}

export -f run_section_09_security_rbac
