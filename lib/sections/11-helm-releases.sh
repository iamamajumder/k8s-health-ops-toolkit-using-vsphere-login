#!/bin/bash
# Section 11: Helm Releases

run_section_11_helm_releases() {
    print_header "SECTION 11: HELM RELEASES"

    run_check "Helm Releases (All Namespaces)" "helm list -A 2>/dev/null || echo 'Helm not available or no releases found'"
    run_check "Failed Helm Releases" "helm list -A --failed 2>/dev/null || echo 'No failed releases or Helm not available'"
}

export -f run_section_11_helm_releases
