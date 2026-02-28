#!/bin/bash
# Section 2: Node Status

run_section_02_node_status() {
    print_header "SECTION 2: NODE STATUS"

    # FIX: kubectl describe nodes fetches full describe for ALL nodes — two separate calls
    # (conditions + resource allocation) meant two full describe-all-nodes round-trips.
    # Fix: kubectl get nodes -o wide for display + single kubectl get nodes -o json for
    # conditions and taints. Saves significant API load on large clusters.

    # --- Node Overview ---
    echo ""
    echo "--- Node Overview ---"
    echo "Output:"
    local NODE_OUTPUT
    NODE_OUTPUT=$(kubectl get nodes -o wide 2>/dev/null)
    if [ -z "$NODE_OUTPUT" ]; then
        echo "  No nodes found"
    else
        echo "$NODE_OUTPUT"
    fi

    # Single JSON fetch — reused for both conditions and taints checks below
    local NODE_JSON
    NODE_JSON=$(kubectl get nodes -o json 2>/dev/null)

    # --- Node Conditions ---
    echo ""
    echo "--- Node Conditions (Pressure/Issues) ---"
    echo "Output:"
    local CONDITIONS
    CONDITIONS=$(echo "$NODE_JSON" | jq -r '
        .items[] |
        . as $node |
        .status.conditions[] |
        select(
            (.type == "MemoryPressure"    and .status == "True") or
            (.type == "DiskPressure"      and .status == "True") or
            (.type == "PIDPressure"       and .status == "True") or
            (.type == "NetworkUnavailable" and .status == "True") or
            (.type == "Ready"             and .status != "True")
        ) |
        "  [WARN] " + $node.metadata.name + ": " + .type + "=" + .status
    ' 2>/dev/null)
    if [ -z "$CONDITIONS" ]; then
        echo "  All nodes: no pressure or readiness conditions"
    else
        echo "$CONDITIONS"
    fi

    # --- Node Taints ---
    echo ""
    echo "--- Node Taints ---"
    echo "Output:"
    local TAINTS
    TAINTS=$(echo "$NODE_JSON" | jq -r '
        .items[] |
        select(.spec.taints != null and (.spec.taints | length) > 0) |
        .metadata.name as $name |
        .spec.taints[] |
        "  " + $name + ": " + .key + "=" + (.value // "") + ":" + .effect
    ' 2>/dev/null)
    if [ -z "$TAINTS" ]; then
        echo "  No node taints found"
    else
        echo "$TAINTS"
    fi

    # --- Node Resource Usage ---
    echo ""
    echo "--- Node Resource Usage (kubectl top) ---"
    echo "Output:"
    if kubectl top nodes 2>/dev/null; then
        : # kubectl top nodes prints directly
    else
        echo "  kubectl top nodes unavailable (metrics-server not installed or insufficient permissions)"
    fi
}

export -f run_section_02_node_status
