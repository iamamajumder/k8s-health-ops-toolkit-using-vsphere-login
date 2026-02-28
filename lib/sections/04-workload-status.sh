#!/bin/bash
# Section 4: Workload Status

run_section_04_workload_status() {
    print_header "SECTION 4: WORKLOAD STATUS"

    # --- Deployments ---
    echo ""
    echo "--- Deployments ---"
    echo "Output:"
    local NOT_READY_DEPLOY
    NOT_READY_DEPLOY=$(kubectl get deploy -A --no-headers 2>/dev/null | \
        awk '{split($3,a,"/"); if(a[1]!=a[2]) print}')
    if [ -z "$NOT_READY_DEPLOY" ]; then
        DEPLOY_TOTAL=$(kubectl get deploy -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        echo "  All Deployments are Ready (${DEPLOY_TOTAL} total)"
    else
        echo "  [WARN] Deployments Not Ready:"
        kubectl get deploy -A --no-headers 2>/dev/null | \
            awk 'BEGIN{printf "  %-30s %-40s %s\n","NAMESPACE","NAME","READY"} \
                 {split($3,a,"/"); if(a[1]!=a[2]) printf "  %-30s %-40s %s\n",$1,$2,$3}'
    fi

    # --- DaemonSets ---
    # FIX: previous code used $4!=$6 (CURRENT vs UP-TO-DATE) — WRONG
    #      correct comparison is $3!=$5 (DESIRED vs READY)
    # kubectl get ds -A --no-headers columns:
    #   NAMESPACE(1) NAME(2) DESIRED(3) CURRENT(4) READY(5) UP-TO-DATE(6) AVAILABLE(7)
    echo ""
    echo "--- DaemonSets ---"
    echo "Output:"
    local NOT_READY_DS
    NOT_READY_DS=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$3 != $5 {print}')
    if [ -z "$NOT_READY_DS" ]; then
        DS_TOTAL=$(kubectl get ds -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
        echo "  All DaemonSets are Ready (${DS_TOTAL} total)"
    else
        echo "  [WARN] DaemonSets Not Ready (DESIRED vs READY):"
        printf "  %-30s %-40s %-8s %-8s %s\n" "NAMESPACE" "NAME" "DESIRED" "READY" "AVAILABLE"
        echo "$NOT_READY_DS" | awk '{printf "  %-30s %-40s %-8s %-8s %s\n",$1,$2,$3,$5,$7}'
    fi

    # --- StatefulSets ---
    echo ""
    echo "--- StatefulSets ---"
    echo "Output:"
    local STS_OUTPUT
    STS_OUTPUT=$(kubectl get sts -A --no-headers 2>/dev/null)
    if [ -z "$STS_OUTPUT" ]; then
        echo "  No StatefulSets found"
    else
        local NOT_READY_STS
        NOT_READY_STS=$(echo "$STS_OUTPUT" | awk '{split($3,a,"/"); if(a[1]!=a[2]) print}')
        if [ -z "$NOT_READY_STS" ]; then
            STS_TOTAL=$(echo "$STS_OUTPUT" | wc -l | tr -d ' ')
            echo "  All StatefulSets are Ready (${STS_TOTAL} total)"
        else
            echo "  [WARN] StatefulSets Not Ready:"
            printf "  %-30s %-40s %s\n" "NAMESPACE" "NAME" "READY"
            echo "$NOT_READY_STS" | awk '{printf "  %-30s %-40s %s\n",$1,$2,$3}'
        fi
    fi

    # --- ReplicaSets ---
    # FIX: previous code used $3!=$4 (DESIRED vs CURRENT) — WRONG
    #      correct comparison is $3!=$5 (DESIRED vs READY)
    # kubectl get rs -A --no-headers columns:
    #   NAMESPACE(1) NAME(2) DESIRED(3) CURRENT(4) READY(5) AGE(6)
    # Note: skip RS with DESIRED=0 (scaled-down orphaned RS is expected)
    echo ""
    echo "--- ReplicaSets ---"
    echo "Output:"
    local NOT_READY_RS
    NOT_READY_RS=$(kubectl get rs -A --no-headers 2>/dev/null | awk '$3 != 0 && $3 != $5 {print}')
    if [ -z "$NOT_READY_RS" ]; then
        echo "  All ReplicaSets have expected replicas"
    else
        echo "  [WARN] ReplicaSets Not Ready (DESIRED vs READY):"
        printf "  %-30s %-50s %-8s %-8s %s\n" "NAMESPACE" "NAME" "DESIRED" "CURRENT" "READY"
        echo "$NOT_READY_RS" | awk '{printf "  %-30s %-50s %-8s %-8s %s\n",$1,$2,$3,$4,$5}'
    fi

    # --- Jobs ---
    echo ""
    echo "--- Jobs ---"
    echo "Output:"
    local JOBS_OUTPUT
    JOBS_OUTPUT=$(kubectl get jobs -A --no-headers 2>/dev/null)
    if [ -z "$JOBS_OUTPUT" ]; then
        echo "  No Jobs found"
    else
        # Flag Failed jobs explicitly via jq
        local FAILED_JOBS
        FAILED_JOBS=$(kubectl get jobs -A -o json 2>/dev/null | \
            jq -r '.items[] |
                select(.status.conditions[]?.type == "Failed") |
                "  [WARN] FAILED: " + .metadata.namespace + "/" + .metadata.name' 2>/dev/null)
        if [ -n "$FAILED_JOBS" ]; then
            echo "$FAILED_JOBS"
        else
            echo "  No Failed Jobs"
        fi
        echo ""
        echo "  All Jobs:"
        echo "$JOBS_OUTPUT"
    fi

    # --- CronJobs ---
    echo ""
    echo "--- CronJobs ---"
    echo "Output:"
    local CRONJOB_OUTPUT
    CRONJOB_OUTPUT=$(kubectl get cronjobs -A --no-headers 2>/dev/null)
    if [ -z "$CRONJOB_OUTPUT" ]; then
        echo "  No CronJobs found"
    else
        echo "$CRONJOB_OUTPUT"
    fi

    # --- HorizontalPodAutoscalers ---
    # Flag HPAs at max replicas — may indicate the workload is starved and cannot scale further.
    # Columns (kubectl get hpa -A --no-headers):
    #   NAMESPACE(1) NAME(2) REFERENCE(3) TARGETS(4) MINPODS(5) MAXPODS(6) REPLICAS(7) AGE(8)
    echo ""
    echo "--- HorizontalPodAutoscalers ---"
    echo "Output:"
    local HPA_OUTPUT
    HPA_OUTPUT=$(kubectl get hpa -A --no-headers 2>/dev/null)
    if [ -z "$HPA_OUTPUT" ]; then
        echo "  No HorizontalPodAutoscalers found"
    else
        local HPA_COUNT HPA_AT_MAX
        HPA_COUNT=$(echo "$HPA_OUTPUT" | wc -l | tr -d ' ')
        # Flag HPAs where REPLICAS >= MAXPODS (at ceiling — cannot scale further)
        HPA_AT_MAX=$(echo "$HPA_OUTPUT" | awk '$7 != "0" && $7 >= $6 {
            print "  [WARN] " $1 "/" $2 ": at max replicas (" $7 "/" $6 ") targets=" $4
        }')
        echo "  Total HPAs: ${HPA_COUNT}"
        if [ -n "$HPA_AT_MAX" ]; then
            echo "$HPA_AT_MAX"
        else
            echo "  All HPAs below max replicas"
        fi
        echo ""
        echo "$HPA_OUTPUT"
    fi
}

export -f run_section_04_workload_status
