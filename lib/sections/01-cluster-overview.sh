#!/bin/bash
# Section 1: Cluster Overview

run_section_01_cluster_overview() {
    print_header "SECTION 1: CLUSTER OVERVIEW"

    run_check "Cluster Info" "kubectl cluster-info"
    run_check "Kubernetes Version" \
        "kubectl version -o json 2>/dev/null | jq -r '\"Client: \" + .clientVersion.gitVersion + \"\nServer: \" + .serverVersion.gitVersion' || kubectl version"
    run_check "Current Context" "kubectl config current-context"
}

export -f run_section_01_cluster_overview
