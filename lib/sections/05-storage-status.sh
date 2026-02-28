#!/bin/bash
# Section 5: Storage Status

run_section_05_storage_status() {
    print_header "SECTION 5: STORAGE STATUS"

    # FIX: run_check + || echo pattern replaced with capture-then-check throughout.
    # Previous grep -v NAME approach had header bypass risk without --no-headers.

    # --- Persistent Volumes ---
    echo ""
    echo "--- Persistent Volumes ---"
    echo "Output:"
    local PV_OUTPUT
    PV_OUTPUT=$(kubectl get pv --no-headers 2>/dev/null)
    if [ -z "$PV_OUTPUT" ]; then
        echo "  No PersistentVolumes found"
    else
        local PV_TOTAL PV_NOTBOUND
        PV_TOTAL=$(echo "$PV_OUTPUT" | wc -l | tr -d ' ')
        PV_NOTBOUND=$(echo "$PV_OUTPUT" | grep -v " Bound " || true)
        echo "  Total PVs: ${PV_TOTAL}"
        if [ -n "$PV_NOTBOUND" ]; then
            local NB_COUNT
            NB_COUNT=$(echo "$PV_NOTBOUND" | wc -l | tr -d ' ')
            echo "  [WARN] ${NB_COUNT} PV(s) not Bound:"
            echo "$PV_NOTBOUND"
        else
            echo "  All PVs Bound"
        fi
    fi

    # --- Persistent Volume Claims ---
    echo ""
    echo "--- Persistent Volume Claims ---"
    echo "Output:"
    local PVC_OUTPUT
    PVC_OUTPUT=$(kubectl get pvc -A --no-headers 2>/dev/null)
    if [ -z "$PVC_OUTPUT" ]; then
        echo "  No PersistentVolumeClaims found"
    else
        local PVC_TOTAL PVC_NOTBOUND
        PVC_TOTAL=$(echo "$PVC_OUTPUT" | wc -l | tr -d ' ')
        PVC_NOTBOUND=$(echo "$PVC_OUTPUT" | grep -v " Bound " || true)
        echo "  Total PVCs: ${PVC_TOTAL}"
        if [ -n "$PVC_NOTBOUND" ]; then
            local NB_COUNT
            NB_COUNT=$(echo "$PVC_NOTBOUND" | wc -l | tr -d ' ')
            echo "  [WARN] ${NB_COUNT} PVC(s) not Bound:"
            echo "$PVC_NOTBOUND"
        else
            echo "  All PVCs Bound"
        fi
    fi

    # --- Storage Classes ---
    echo ""
    echo "--- Storage Classes ---"
    echo "Output:"
    local SC_OUTPUT
    SC_OUTPUT=$(kubectl get sc --no-headers 2>/dev/null)
    if [ -z "$SC_OUTPUT" ]; then
        echo "  No StorageClasses found"
    else
        echo "$SC_OUTPUT"
        # Flag missing default StorageClass — dynamic PVC provisioning won't work without one
        if ! echo "$SC_OUTPUT" | grep -q "(default)"; then
            echo ""
            echo "  [WARN] No default StorageClass defined — dynamic PVC provisioning requires one"
        fi
    fi
}

export -f run_section_05_storage_status
