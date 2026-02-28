#!/bin/bash
# Section 13: Resource Quotas & Limits

run_section_13_resource_quotas() {
    print_header "SECTION 13: RESOURCE QUOTAS & LIMITS"

    # FIX: kubectl get resourcequota -A exits 0 with empty output when no quotas exist.
    # The || echo fallback never fires. Fix: capture-then-check pattern.

    # --- Resource Quotas ---
    echo ""
    echo "--- Resource Quotas ---"
    echo "Output:"
    local RQ_OUTPUT
    RQ_OUTPUT=$(kubectl get resourcequota -A --no-headers 2>/dev/null)
    if [ -z "$RQ_OUTPUT" ]; then
        echo "  No ResourceQuotas configured"
    else
        local RQ_COUNT
        RQ_COUNT=$(echo "$RQ_OUTPUT" | wc -l | tr -d ' ')
        echo "  Total ResourceQuotas: ${RQ_COUNT}"
        echo ""
        kubectl get resourcequota -A 2>/dev/null
    fi

    # --- Limit Ranges ---
    echo ""
    echo "--- Limit Ranges ---"
    echo "Output:"
    local LR_OUTPUT
    LR_OUTPUT=$(kubectl get limitrange -A --no-headers 2>/dev/null)
    if [ -z "$LR_OUTPUT" ]; then
        echo "  No LimitRanges configured"
    else
        local LR_COUNT
        LR_COUNT=$(echo "$LR_OUTPUT" | wc -l | tr -d ' ')
        echo "  Total LimitRanges: ${LR_COUNT}"
        echo ""
        kubectl get limitrange -A 2>/dev/null
    fi
}

export -f run_section_13_resource_quotas
