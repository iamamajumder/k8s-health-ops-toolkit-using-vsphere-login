#!/bin/bash
# Section 16: Container Images Audit

run_section_16_images_audit() {
    print_header "SECTION 16: CONTAINER IMAGES AUDIT"

    run_check "Non-Standard Images (External Registry)" "kubectl get pod,deploy,sts,ds,job,cronjob -A -o yaml 2>/dev/null | grep -i 'image:' | egrep -vi '${IMAGE_EXCLUSION_PATTERN}' | xargs -L1 2>/dev/null | sort -u || echo 'No external images found'"
    run_check "All Unique Images in Cluster" "kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{\"\n\"}{end}{end}' 2>/dev/null | sort -u"
}

export -f run_section_16_images_audit
