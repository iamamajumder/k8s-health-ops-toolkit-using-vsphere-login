#!/bin/bash
# Section 12: Namespaces

run_section_12_namespaces() {
    print_header "SECTION 12: NAMESPACES"

    run_check "All Namespaces with Labels" "kubectl get ns --show-labels"
    run_check "Namespace Status" "kubectl get ns -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'"
}

export -f run_section_12_namespaces
