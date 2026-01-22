#!/bin/bash
# Section 2: Node Status

run_section_02_node_status() {
    print_header "SECTION 2: NODE STATUS"

    run_check "All Nodes" "kubectl get nodes -o wide"
    run_check "Node Conditions (Pressure/Issues)" "kubectl describe nodes | grep -E '(^Name:|Conditions:|MemoryPressure|DiskPressure|PIDPressure|NetworkUnavailable|Ready)' | grep -v 'Conditions:'"
    run_check "Node Resource Allocation" "kubectl describe nodes | grep -A 5 'Allocated resources:'"
    run_check "Node Taints" "kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].effect'"
}

export -f run_section_02_node_status
