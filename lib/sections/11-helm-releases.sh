#!/bin/bash
# Section 11: Helm Releases

run_section_11_helm_releases() {
    print_header "SECTION 11: HELM RELEASES"

    echo ""
    echo "--- All Helm Releases ---"
    echo "Output:"
    local HELM_ALL
    HELM_ALL=$(helm list -A 2>/dev/null)
    if [ -z "$HELM_ALL" ]; then
        echo "  No Helm releases found (or Helm not available)"
    else
        echo "$HELM_ALL"
    fi

    # FIX: helm list --failed exits 0 with empty output when no failures exist.
    # The || echo fallback never fires in the healthy case — leaves blank output.
    # Fix: capture-then-check so empty output is always handled explicitly.
    echo ""
    echo "--- Failed Helm Releases ---"
    echo "Output:"
    local HELM_FAILED
    HELM_FAILED=$(helm list -A --failed --no-headers 2>/dev/null)
    if [ -z "$HELM_FAILED" ]; then
        echo "  No failed Helm releases"
    else
        local FAIL_COUNT
        FAIL_COUNT=$(echo "$HELM_FAILED" | wc -l | tr -d ' ')
        echo "  [WARN] ${FAIL_COUNT} failed Helm release(s):"
        echo "$HELM_FAILED"
    fi
}

export -f run_section_11_helm_releases
