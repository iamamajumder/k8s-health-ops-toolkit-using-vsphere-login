#!/bin/bash
# Section 8: Tanzu/VMware Specific

run_section_08_tanzu_vmware() {
    print_header "SECTION 8: TANZU/VMware SPECIFIC"

    run_check "Package Installs (pkgi)" "kubectl get pkgi -A 2>/dev/null || echo 'PackageInstall CRD not found'"
    run_check "TMC Impersonation Secrets Count" "kubectl -n vmware-system-tmc get secrets 2>/dev/null | grep impersonation | wc -l || echo '0'"
    run_check "TMC Pods" "kubectl get pods -n vmware-system-tmc 2>/dev/null || echo 'TMC namespace not found'"
    run_check "Cluster API Resources" "kubectl get cluster,machine,machinedeployment -A 2>/dev/null || echo 'Cluster API resources not found'"
}

export -f run_section_08_tanzu_vmware
