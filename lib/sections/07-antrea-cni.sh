#!/bin/bash
# Section 7: Antrea/CNI Status

run_section_07_antrea_cni() {
    print_header "SECTION 7: ANTREA/CNI STATUS"

    # REMOVED: "Antrea Controller Tier Count" — tailed 1000 log lines per run to grep for
    # "tier" occurrences. Slow, fragile (log text changes across versions), and a raw count
    # provides no actionable health signal. Replaced with DS ready check below.

    # --- Antrea Agent DaemonSet ---
    # Checks DESIRED vs READY — the real CNI health signal (is the agent running on all nodes?)
    echo ""
    echo "--- Antrea Agent DaemonSet ---"
    echo "Output:"
    local ANTREA_DS
    ANTREA_DS=$(kubectl get ds antrea-agent -n kube-system --no-headers 2>/dev/null)
    if [ -z "$ANTREA_DS" ]; then
        echo "  antrea-agent DaemonSet not found in kube-system"
    else
        # Columns: NAME(1) DESIRED(2) CURRENT(3) READY(4) UP-TO-DATE(5) AVAILABLE(6) NODE SELECTOR(7) AGE(8)
        # (no-headers on a single-namespace get ds omits the NAMESPACE column)
        echo "$ANTREA_DS" | awk '{
            status = ($2 == $4) ? "[OK]" : "[WARN]"
            printf "  %s antrea-agent: desired=%s ready=%s available=%s\n", status, $2, $4, $6
        }'
    fi

    # --- Antrea Pods Status ---
    echo ""
    echo "--- Antrea Pods Status ---"
    echo "Output:"
    local ANTREA_PODS
    ANTREA_PODS=$(kubectl get pods -n kube-system -l app=antrea --no-headers 2>/dev/null)
    if [ -z "$ANTREA_PODS" ]; then
        echo "  No Antrea pods found (label app=antrea) in kube-system"
    else
        local NOT_READY
        NOT_READY=$(echo "$ANTREA_PODS" | grep -v " Running " || true)
        if [ -z "$NOT_READY" ]; then
            local TOTAL
            TOTAL=$(echo "$ANTREA_PODS" | wc -l | tr -d ' ')
            echo "  All ${TOTAL} Antrea pod(s) Running"
        else
            echo "  [WARN] Non-running Antrea pods:"
            echo "$NOT_READY"
        fi
    fi
}

export -f run_section_07_antrea_cni
