#!/bin/bash
# Section 4: Workload Status

run_section_04_workload_status() {
    print_header "SECTION 4: WORKLOAD STATUS"

    run_check "All Deployments" "kubectl get deploy -A -o wide"
    run_check "Deployments Not Ready" "kubectl get deploy -A | awk 'NR==1 || \$3 != \$4' | grep -v 'READY' || echo 'All deployments are ready'"
    run_check "All DaemonSets" "kubectl get ds -A -o wide"
    run_check "DaemonSets Not Ready" "kubectl get ds -A | awk 'NR==1 || \$4 != \$6'"
    run_check "All StatefulSets" "kubectl get sts -A -o wide 2>/dev/null || echo 'No StatefulSets found'"
    run_check "All ReplicaSets" "kubectl get rs -A 2>/dev/null | awk 'NR==1 || \$3 != \$4'"
    run_check "All Jobs" "kubectl get jobs -A 2>/dev/null || echo 'No Jobs found'"
    run_check "All CronJobs" "kubectl get cronjobs -A 2>/dev/null || echo 'No CronJobs found'"
}

export -f run_section_04_workload_status
