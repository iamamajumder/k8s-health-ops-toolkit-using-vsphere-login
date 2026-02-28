#!/bin/bash
# Section 12: Namespaces

run_section_12_namespaces() {
    print_header "SECTION 12: NAMESPACES"

    # FIX: replaced two redundant raw dumps (with-labels + custom-columns) with
    # a single fetch that gives count + Terminating detection (the real health signal).
    # Terminating namespaces block namespace deletion and indicate stuck finalizers.

    local NS_OUTPUT
    NS_OUTPUT=$(kubectl get ns --no-headers 2>/dev/null)

    echo ""
    echo "--- Namespace Summary ---"
    echo "Output:"
    if [ -z "$NS_OUTPUT" ]; then
        echo "  No namespaces found"
    else
        local NS_TOTAL
        NS_TOTAL=$(echo "$NS_OUTPUT" | wc -l | tr -d ' ')
        echo "  Total namespaces: ${NS_TOTAL}"

        # Terminating namespaces — stuck finalizers block deletion
        local TERMINATING
        TERMINATING=$(echo "$NS_OUTPUT" | awk '$2 == "Terminating" {print "  [WARN] " $1 ": stuck in Terminating state (check finalizers)"}')
        if [ -n "$TERMINATING" ]; then
            echo "$TERMINATING"
        else
            echo "  All namespaces Active"
        fi
    fi

    echo ""
    echo "--- All Namespaces ---"
    echo "Output:"
    if [ -n "$NS_OUTPUT" ]; then
        echo "$NS_OUTPUT"
    fi
}

export -f run_section_12_namespaces
