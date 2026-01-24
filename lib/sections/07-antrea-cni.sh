#!/bin/bash
# Section 7: Antrea/CNI Status

run_section_07_antrea_cni() {
    print_header "SECTION 7: ANTREA/CNI STATUS"

    run_check "Antrea Controller Tier Count" "kubectl -n kube-system logs -l component=antrea-controller --tail 1000 2>/dev/null | grep -i tier | wc -l || echo '0'"
    run_check "Antrea Pods Status" "kubectl get pods -n kube-system -l app=antrea 2>/dev/null || echo 'Antrea pods not found with label app=antrea'"
}

export -f run_section_07_antrea_cni
