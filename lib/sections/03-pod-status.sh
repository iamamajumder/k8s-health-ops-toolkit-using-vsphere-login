#!/bin/bash
# Section 3: Pod Status

run_section_03_pod_status() {
    print_header "SECTION 3: POD STATUS"

    # --- Pod Count Summary ---
    # Replaces the noisy full pod dump (kubectl get pod -A -o wide) with a concise summary line.
    echo ""
    echo "--- Pod Count Summary ---"
    echo "Output:"
    local ALL_PODS
    ALL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null)
    local TOTAL RUNNING COMPLETED CRASHLOOP PENDING
    TOTAL=$(echo "$ALL_PODS" | grep -c . || true)
    RUNNING=$(echo "$ALL_PODS" | grep -c " Running " || true)
    COMPLETED=$(echo "$ALL_PODS" | grep -c "Completed" || true)
    CRASHLOOP=$(echo "$ALL_PODS" | grep -c "CrashLoopBackOff" || true)
    PENDING=$(echo "$ALL_PODS" | grep -c " Pending " || true)
    echo "  Total: ${TOTAL} | Running: ${RUNNING} | Completed: ${COMPLETED} | Pending: ${PENDING} | CrashLoop: ${CRASHLOOP}"

    # --- Non-Running Pods ---
    # BUG FIX: original used `kubectl get pod -A | grep -vi running | grep -vi completed`
    # WITHOUT --no-headers, so the kubectl column header line ("NAMESPACE NAME READY STATUS...")
    # always passed through (it contains neither "running" nor "completed"), meaning the
    # `|| echo 'All pods are Running or Completed'` fallback NEVER fired on healthy clusters.
    # Fix: --no-headers eliminates the header; capture-then-check gives the correct empty-state.
    echo ""
    echo "--- Non-Running Pods ---"
    echo "Output:"
    local NON_RUNNING
    NON_RUNNING=$(echo "$ALL_PODS" | grep -viE 'running|completed')
    if [ -z "$NON_RUNNING" ]; then
        echo "  All pods are Running or Completed"
    else
        echo "  [WARN] Non-Running pods:"
        echo "$NON_RUNNING"
    fi

    # --- CrashLoopBackOff Pods ---
    echo ""
    echo "--- CrashLoopBackOff Pods ---"
    echo "Output:"
    local CRASH_PODS
    CRASH_PODS=$(echo "$ALL_PODS" | grep -i crashloop)
    if [ -z "$CRASH_PODS" ]; then
        echo "  No CrashLoopBackOff pods"
    else
        echo "  [WARN] CrashLoopBackOff pods:"
        echo "$CRASH_PODS"
    fi

    # --- Pending Pods ---
    echo ""
    echo "--- Pending Pods ---"
    echo "Output:"
    local PENDING_PODS
    PENDING_PODS=$(echo "$ALL_PODS" | grep " Pending ")
    if [ -z "$PENDING_PODS" ]; then
        echo "  No Pending pods"
    else
        echo "  [WARN] Pending pods:"
        echo "$PENDING_PODS"
    fi

    # --- High Restart Count Pods (>5) ---
    # BUG FIX: K8s 1.28+ changed restart count display from integer "3" to "3 (1h ago)".
    # The original `awk '$5 > 5'` integer comparison silently fails because $5 is no longer
    # a pure integer. Fix: gsub strips the "(Xh ago)" suffix before the comparison.
    # Column positions for `kubectl get pods -A --no-headers`:
    #   NAMESPACE(1) NAME(2) READY(3) STATUS(4) RESTARTS(5) AGE(6)
    echo ""
    echo "--- High Restart Count Pods (>5 restarts) ---"
    echo "Output:"
    local HIGH_RESTART
    HIGH_RESTART=$(echo "$ALL_PODS" | awk '{gsub(/\(.*\)/,"",$5); if($5+0 > 5) print}')
    if [ -z "$HIGH_RESTART" ]; then
        echo "  No pods with restart count > 5"
    else
        echo "  [WARN] Pods with >5 restarts:"
        echo "$HIGH_RESTART"
    fi

    # --- OOMKilled Detection ---
    # New check — OOMKilled was completely absent from the original section.
    # Checks lastState.terminated.reason on all container statuses.
    echo ""
    echo "--- OOMKilled Containers (last state) ---"
    echo "Output:"
    local OOMKILLED
    OOMKILLED=$(kubectl get pods -A -o json 2>/dev/null | \
        jq '[.items[] | .status.containerStatuses[]? |
            select(.lastState.terminated.reason == "OOMKilled")] | length' 2>/dev/null)
    if [ "${OOMKILLED:-0}" -gt 0 ]; then
        echo "  [WARN] ${OOMKILLED} container(s) have OOMKilled in last state:"
        kubectl get pods -A -o json 2>/dev/null | \
            jq -r '.items[] |
                select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") |
                "    " + .metadata.namespace + "/" + .metadata.name' 2>/dev/null
    else
        echo "  No OOMKilled containers detected"
    fi

    # NOTE: Removed hardcoded "gateway-0" check — not present on all clusters, caused
    #       misleading [WARN] noise when the pod did not exist.
    # NOTE: Removed hardcoded "kubernetes-dashboard" check — not present on all clusters.
}

export -f run_section_03_pod_status
