#!/bin/bash
# Section 18: Cluster Summary

run_section_18_cluster_summary() {
    print_header "SECTION 18: CLUSTER SUMMARY"

    echo "--- Quick Health Summary ---"
    echo ""
    echo "Nodes Total: $(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
    echo "Nodes Ready: $(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')"
    echo "Pods Total: $(kubectl get pods -A --no-headers 2>/dev/null | wc -l)"
    echo "Pods Running: $(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running)"
    echo "Pods Not Running: $(kubectl get pods -A --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l)"
    echo "Deployments Total: $(kubectl get deploy -A --no-headers 2>/dev/null | wc -l)"
    echo "DaemonSets Total: $(kubectl get ds -A --no-headers 2>/dev/null | wc -l)"
    echo "Services Total: $(kubectl get svc -A --no-headers 2>/dev/null | wc -l)"
    echo "PVCs Total: $(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)"
    echo "Namespaces: $(kubectl get ns --no-headers 2>/dev/null | wc -l)"
    echo "Helm Releases: $(helm list -A --no-headers 2>/dev/null | wc -l || echo '0')"
    echo ""

    print_header "HEALTH CHECK COMPLETED"
    echo "Check Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

export -f run_section_18_cluster_summary
