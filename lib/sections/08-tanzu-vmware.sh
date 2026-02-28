#!/bin/bash
# Section 8: Tanzu/VMware Specific

run_section_08_tanzu_vmware() {
    print_header "SECTION 8: TANZU/VMware SPECIFIC"

    # --- Package Installs ---
    # FIX: raw dump replaced with summary + [WARN] on packages not in "Reconcile succeeded" state.
    # Exit code distinguishes "CRD not found" (non-zero) from "no packages" (zero, empty output).
    echo ""
    echo "--- Package Installs (kapp-controller PackageInstalls) ---"
    echo "Output:"
    local PKGI_OUTPUT
    PKGI_OUTPUT=$(kubectl get pkgi -A --no-headers 2>/dev/null)
    local PKGI_EXIT=$?
    if [ $PKGI_EXIT -ne 0 ]; then
        echo "  PackageInstall CRD not found (kapp-controller not installed)"
    elif [ -z "$PKGI_OUTPUT" ]; then
        echo "  No packages installed"
    else
        local PKGI_COUNT
        PKGI_COUNT=$(echo "$PKGI_OUTPUT" | wc -l | tr -d ' ')
        local PKGI_FAILED
        PKGI_FAILED=$(echo "$PKGI_OUTPUT" | grep -iv "succeeded" || true)
        echo "  Total packages: ${PKGI_COUNT}"
        if [ -n "$PKGI_FAILED" ]; then
            local FAIL_COUNT
            FAIL_COUNT=$(echo "$PKGI_FAILED" | wc -l | tr -d ' ')
            echo "  [WARN] ${FAIL_COUNT} package(s) not in Reconcile succeeded state:"
            echo "$PKGI_FAILED"
        else
            echo "  All packages: Reconcile succeeded"
        fi
    fi

    # --- TMC Agent ---
    # FIX: raw pod dump replaced with Running/NotRunning health signal.
    echo ""
    echo "--- TMC Agent (vmware-system-tmc) ---"
    echo "Output:"
    local TMC_PODS
    TMC_PODS=$(kubectl get pods -n vmware-system-tmc --no-headers 2>/dev/null)
    if [ -z "$TMC_PODS" ]; then
        echo "  TMC namespace not found or no pods"
    else
        local TMC_TOTAL TMC_NOT_RUNNING
        TMC_TOTAL=$(echo "$TMC_PODS" | wc -l | tr -d ' ')
        TMC_NOT_RUNNING=$(echo "$TMC_PODS" | grep -v " Running " || true)
        if [ -z "$TMC_NOT_RUNNING" ]; then
            echo "  All ${TMC_TOTAL} TMC pod(s) Running"
        else
            echo "  [WARN] TMC pods not Running:"
            echo "$TMC_NOT_RUNNING"
        fi
        local IMPERSONATION_COUNT
        IMPERSONATION_COUNT=$(kubectl get secrets -n vmware-system-tmc --no-headers 2>/dev/null | \
            grep -c impersonation || true)
        echo "  TMC impersonation secrets: ${IMPERSONATION_COUNT:-0}"
    fi

    # --- Cluster API Resources ---
    echo ""
    echo "--- Cluster API Resources ---"
    echo "Output:"
    local CAPI_OUTPUT
    CAPI_OUTPUT=$(kubectl get cluster,machine,machinedeployment -A --no-headers 2>/dev/null)
    if [ -z "$CAPI_OUTPUT" ]; then
        echo "  Cluster API resources not found (not a CAPI-managed cluster)"
    else
        echo "$CAPI_OUTPUT"
    fi
}

export -f run_section_08_tanzu_vmware
