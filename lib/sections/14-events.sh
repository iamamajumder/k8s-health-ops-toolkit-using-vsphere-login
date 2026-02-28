#!/bin/bash
# Section 14: Events (Warning/Error)

run_section_14_events() {
    print_header "SECTION 14: EVENTS (Non-Normal)"

    # Single JSON fetch — avoids double API hit on the events API.
    # FIX: || echo fallbacks never fire when kubectl exits 0 with empty output.
    # Fix: capture EVENT_COUNT from jq; empty-state handled explicitly.
    local EVENTS_JSON
    EVENTS_JSON=$(kubectl get events -A --field-selector type!=Normal \
        --sort-by='.metadata.creationTimestamp' -o json 2>/dev/null)

    local EVENT_COUNT
    EVENT_COUNT=$(echo "$EVENTS_JSON" | jq '.items | length' 2>/dev/null || echo 0)

    echo ""
    echo "--- Warning/Error Events (last 100 shown) ---"
    echo "Output:"
    if [ "${EVENT_COUNT:-0}" -eq 0 ]; then
        echo "  No warning events found"
    else
        echo "  Total: ${EVENT_COUNT} non-normal event(s)"
        echo ""
        echo "$EVENTS_JSON" | jq -r '
            .items[-100:] | .[] |
            "  \(.metadata.namespace)  \((.lastTimestamp // .eventTime // .metadata.creationTimestamp // "-")[0:19])  \(.type)  \(.reason)  \((.involvedObject // .regarding | .kind + "/" + .name))  \((.message // .note // "") | gsub("[\n\r]"; " "))"
        ' 2>/dev/null
    fi

    echo ""
    echo "--- Events Summary by Reason ---"
    echo "Output:"
    if [ "${EVENT_COUNT:-0}" -eq 0 ]; then
        echo "  No events to summarize"
    else
        echo "$EVENTS_JSON" | jq -r '.items[].reason' 2>/dev/null | \
            sort | uniq -c | sort -rn | head -20
    fi
}

export -f run_section_14_events
