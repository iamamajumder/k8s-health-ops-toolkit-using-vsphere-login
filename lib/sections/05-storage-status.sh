#!/bin/bash
# Section 5: Storage Status

run_section_05_storage_status() {
    print_header "SECTION 5: STORAGE STATUS"

    run_check "Persistent Volumes" "kubectl get pv -o wide"
    run_check "PVs Not Bound" "kubectl get pv | grep -v Bound | grep -v NAME || echo 'All PVs are Bound'"
    run_check "Persistent Volume Claims" "kubectl get pvc -A -o wide"
    run_check "PVCs Not Bound" "kubectl get pvc -A | grep -v Bound | grep -v NAME || echo 'All PVCs are Bound'"
    run_check "Storage Classes" "kubectl get sc"
}

export -f run_section_05_storage_status
