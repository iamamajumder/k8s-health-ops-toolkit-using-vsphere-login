#!/bin/bash
# Section 1: Cluster Overview

run_section_01_cluster_overview() {
    print_header "SECTION 1: CLUSTER OVERVIEW"

    run_check "Current Date/Time" "date"
    run_check "Cluster Info" "kubectl cluster-info"
    run_check "Kubernetes Version" "kubectl version --short 2>/dev/null || kubectl version"
    run_check "Current Context" "kubectl config current-context"
}

export -f run_section_01_cluster_overview
