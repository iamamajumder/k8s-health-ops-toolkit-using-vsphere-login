#!/bin/bash
# Section 14: Events (Warning/Error)

run_section_14_events() {
    print_header "SECTION 14: EVENTS (Non-Normal)"

    run_check "Warning/Error Events (Last 1 hour)" "kubectl get events -A --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -100 || echo 'No warning events found'"
    run_check "Events Summary by Reason" "kubectl get events -A --field-selector type!=Normal -o custom-columns='REASON:.reason' --no-headers 2>/dev/null | sort | uniq -c | sort -rn | head -20 || echo 'No events to summarize'"
}

export -f run_section_14_events
