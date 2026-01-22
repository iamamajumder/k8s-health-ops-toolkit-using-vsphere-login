#!/bin/bash
# Section 13: Resource Quotas & Limits

run_section_13_resource_quotas() {
    print_header "SECTION 13: RESOURCE QUOTAS & LIMITS"

    run_check "Resource Quotas" "kubectl get resourcequota -A 2>/dev/null || echo 'No ResourceQuotas found'"
    run_check "Limit Ranges" "kubectl get limitrange -A 2>/dev/null || echo 'No LimitRanges found'"
}

export -f run_section_13_resource_quotas
