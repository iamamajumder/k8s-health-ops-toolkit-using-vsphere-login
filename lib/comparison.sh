#!/bin/bash
#===============================================================================
# Comparison Logic Library
# Functions for comparing pre-change and post-change health check results
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
fi

#===============================================================================
# Report Parsing Functions
#===============================================================================

# Parse Section 18 metrics from a health check report file
# Returns metrics in KEY=VALUE format
parse_health_report() {
    local report_file="$1"

    if [[ ! -f "${report_file}" ]]; then
        echo "ERROR: Report file not found: ${report_file}" >&2
        return 1
    fi

    # Extract metrics from Section 18 - Resource Counts
    local nodes_total=$(grep -E "^Nodes Total:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local nodes_ready=$(grep -E "^Nodes Ready:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local pods_total=$(grep -E "^Pods Total:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local pods_running=$(grep -E "^Pods Running:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local deploys_total=$(grep -E "^Deployments Total:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local ds_total=$(grep -E "^DaemonSets Total:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local sts_total=$(grep -E "^StatefulSets Total:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local pvc_total=$(grep -E "^PVCs Total:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')
    local helm_total=$(grep -E "^Helm Releases:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d ' ')

    # Extract health indicators from Section 18
    local nodes_notready=$(grep -E "^Nodes NotReady:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local pods_crashloop=$(grep -E "^Pods CrashLoop:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local pods_pending=$(grep -E "^Pods Pending:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local pods_completed=$(grep -E "^Pods Completed:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local pods_unaccounted=$(grep -E "^Pods Unaccounted:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local deploys_notready=$(grep -E "^Deploys NotReady:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local ds_notready=$(grep -E "^DS NotReady:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local sts_notready=$(grep -E "^STS NotReady:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local pvc_notbound=$(grep -E "^PVCs NotBound:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')
    local helm_failed=$(grep -E "^Helm Failed:" "${report_file}" 2>/dev/null | tail -1 | awk '{print $3}' | tr -d ' ')

    # Output as KEY=VALUE pairs
    echo "NODES_TOTAL=${nodes_total:-0}"
    echo "NODES_READY=${nodes_ready:-0}"
    echo "NODES_NOTREADY=${nodes_notready:-0}"
    echo "PODS_TOTAL=${pods_total:-0}"
    echo "PODS_RUNNING=${pods_running:-0}"
    echo "PODS_CRASHLOOP=${pods_crashloop:-0}"
    echo "PODS_PENDING=${pods_pending:-0}"
    echo "PODS_COMPLETED=${pods_completed:-0}"
    echo "PODS_UNACCOUNTED=${pods_unaccounted:-0}"
    echo "DEPLOYS_TOTAL=${deploys_total:-0}"
    echo "DEPLOYS_NOTREADY=${deploys_notready:-0}"
    echo "DS_TOTAL=${ds_total:-0}"
    echo "DS_NOTREADY=${ds_notready:-0}"
    echo "STS_TOTAL=${sts_total:-0}"
    echo "STS_NOTREADY=${sts_notready:-0}"
    echo "PVC_TOTAL=${pvc_total:-0}"
    echo "PVC_NOTBOUND=${pvc_notbound:-0}"
    echo "HELM_TOTAL=${helm_total:-0}"
    echo "HELM_FAILED=${helm_failed:-0}"
}

# Calculate delta between two values
# Returns "+N", "-N", or "0"
calculate_delta() {
    local pre_val="${1:-0}"
    local post_val="${2:-0}"

    # Clean values to ensure integers
    pre_val=$(echo "$pre_val" | tr -d ' ' | grep -E '^[0-9]+$' || echo "0")
    post_val=$(echo "$post_val" | tr -d ' ' | grep -E '^[0-9]+$' || echo "0")
    pre_val=${pre_val:-0}
    post_val=${post_val:-0}

    local delta=$((post_val - pre_val))

    if [ "$delta" -gt 0 ]; then
        echo "+${delta}"
    elif [ "$delta" -lt 0 ]; then
        echo "${delta}"
    else
        echo "0"
    fi
}

# Determine status for a metric change
# $1 = metric name, $2 = delta, $3 = metric type (higher_is_worse, lower_is_worse, neutral)
get_delta_status() {
    local metric_name="$1"
    local delta="$2"
    local metric_type="${3:-neutral}"

    # Remove + sign for comparison
    local delta_num=$(echo "$delta" | tr -d '+')

    if [ "$delta_num" -eq 0 ]; then
        echo "[OK]"
        return
    fi

    case "$metric_type" in
        higher_is_worse)
            # More NotReady nodes, CrashLoop pods = worse
            if [ "$delta_num" -gt 0 ]; then
                echo "[WORSE]"
            else
                echo "[BETTER]"
            fi
            ;;
        lower_is_worse)
            # Fewer Running pods, Ready nodes = worse
            if [ "$delta_num" -lt 0 ]; then
                echo "[WORSE]"
            else
                echo "[BETTER]"
            fi
            ;;
        neutral)
            # Informational change
            echo "[CHANGED]"
            ;;
    esac
}

#===============================================================================
# Comparison Report Generation
#===============================================================================

# Generate full comparison report
generate_comparison_report() {
    local cluster_name="$1"
    local pre_file="$2"
    local post_file="$3"
    local diff_file="$4"

    {
        echo "================================================================================"
        echo "  KUBERNETES CLUSTER HEALTH CHECK - COMPARISON REPORT"
        echo "================================================================================"
        echo ""
        echo "Cluster:          ${cluster_name}"
        echo "Pre-Change File:  ${pre_file}"
        echo "Post-Change File: ${post_file}"
        echo "Comparison Time:  $(get_formatted_timestamp)"
        echo ""
        echo "================================================================================"
        echo ""

        # Parse both reports
        local pre_metrics=$(parse_health_report "${pre_file}")
        local post_metrics=$(parse_health_report "${post_file}")

        # Load metrics into variables
        eval "$(echo "${pre_metrics}" | sed 's/^/PRE_/')"
        eval "$(echo "${post_metrics}" | sed 's/^/POST_/')"

        # Generate PRE vs POST comparison table
        generate_metrics_comparison

        # Generate layman summary
        generate_layman_summary

        # Also run live cluster checks for additional context
        echo ""
        echo "############################################################################"
        echo "#                    CURRENT CLUSTER STATE (Live)                          #"
        echo "############################################################################"
        echo ""

        compare_critical_health
        compare_workloads
        compare_storage
        compare_tanzu_packages
        compare_helm_releases
        compare_events

        # Final verdict
        generate_final_verdict

    } > "${diff_file}" 2>&1
}

#===============================================================================
# Metrics Comparison Table (Data-Driven)
#===============================================================================

# Generate metrics comparison table using data-driven approach
generate_metrics_comparison() {
    echo ""
    echo "############################################################################"
    echo "#                       PRE vs POST COMPARISON                             #"
    echo "############################################################################"
    echo ""
    printf "%-25s %10s %10s %10s %10s\n" "Metric" "PRE" "POST" "DELTA" "STATUS"
    printf "%-25s %10s %10s %10s %10s\n" "-------------------------" "----------" "----------" "----------" "----------"

    # Metric definitions: "label|var_suffix|metric_type|group"
    # Groups: nodes, pods, deploys, ds, sts, pvc, helm
    local metrics=(
        "Nodes Total|NODES_TOTAL|neutral|nodes"
        "Nodes Ready|NODES_READY|lower_is_worse|nodes"
        "Nodes NotReady|NODES_NOTREADY|higher_is_worse|nodes"
        "Pods Total|PODS_TOTAL|neutral|pods"
        "Pods Running|PODS_RUNNING|lower_is_worse|pods"
        "Pods CrashLoopBackOff|PODS_CRASHLOOP|higher_is_worse|pods"
        "Pods Pending|PODS_PENDING|higher_is_worse|pods"
        "Pods Completed|PODS_COMPLETED|neutral|pods"
        "Pods Unaccounted|PODS_UNACCOUNTED|higher_is_worse|pods"
        "Deployments Total|DEPLOYS_TOTAL|neutral|deploys"
        "Deployments NotReady|DEPLOYS_NOTREADY|higher_is_worse|deploys"
        "DaemonSets Total|DS_TOTAL|neutral|ds"
        "DaemonSets NotReady|DS_NOTREADY|higher_is_worse|ds"
        "StatefulSets Total|STS_TOTAL|neutral|sts"
        "StatefulSets NotReady|STS_NOTREADY|higher_is_worse|sts"
        "PVCs Total|PVC_TOTAL|neutral|pvc"
        "PVCs NotBound|PVC_NOTBOUND|higher_is_worse|pvc"
        "Helm Releases Total|HELM_TOTAL|neutral|helm"
        "Helm Releases Failed|HELM_FAILED|higher_is_worse|helm"
    )

    local last_group=""
    for metric_def in "${metrics[@]}"; do
        IFS='|' read -r label var_suffix metric_type group <<< "${metric_def}"

        # Add blank line between groups
        if [[ -n "${last_group}" && "${group}" != "${last_group}" ]]; then
            echo ""
        fi
        last_group="${group}"

        # Get PRE and POST values using indirect expansion
        local pre_var="PRE_${var_suffix}"
        local post_var="POST_${var_suffix}"
        local pre_val="${!pre_var:-0}"
        local post_val="${!post_var:-0}"

        # Calculate delta and status
        local delta=$(calculate_delta "${pre_val}" "${post_val}")
        local status=$(get_delta_status "${var_suffix}" "${delta}" "${metric_type}")

        printf "%-25s %10s %10s %10s %10s\n" "${label}" "${pre_val}" "${post_val}" "${delta}" "${status}"
    done

    echo ""
}

#===============================================================================
# Plain English Summary (Data-Driven)
#===============================================================================

# Generate plain English summary using data-driven approach
generate_layman_summary() {
    echo ""
    echo "############################################################################"
    echo "#                      PLAIN ENGLISH SUMMARY                               #"
    echo "############################################################################"
    echo ""
    echo "What changed after the maintenance/upgrade:"
    echo ""

    local has_changes=false
    local critical_issues=()
    local warnings=()
    local improvements=()
    local info_changes=()

    # Check definitions: "var_suffix|category|worse_msg|better_msg"
    # Categories: critical, warning, info
    local checks=(
        "NODES_NOTREADY|critical|more node(s) became NotReady|node(s) recovered to Ready state"
        "PODS_CRASHLOOP|critical|more pod(s) are now crashing (CrashLoopBackOff)|pod(s) stopped crashing"
        "PODS_PENDING|warning|more pod(s) are stuck in Pending state|pod(s) moved from Pending to Running"
        "PODS_UNACCOUNTED|warning|more pod(s) in unexpected state (Failed/Unknown/Error)|pod(s) recovered from unexpected state"
        "DEPLOYS_NOTREADY|warning|more deployment(s) are not fully ready|deployment(s) became fully ready"
        "DS_NOTREADY|warning|more DaemonSet(s) are not fully ready|DaemonSet(s) became fully ready"
        "STS_NOTREADY|warning|more StatefulSet(s) are not fully ready|StatefulSet(s) became fully ready"
        "PVC_NOTBOUND|warning|more PVC(s) are not bound|PVC(s) became bound"
        "HELM_FAILED|warning|more Helm release(s) failed|Helm release(s) recovered"
    )

    for check_def in "${checks[@]}"; do
        IFS='|' read -r var_suffix category worse_msg better_msg <<< "${check_def}"

        local pre_var="PRE_${var_suffix}"
        local post_var="POST_${var_suffix}"
        local delta=$((${!post_var:-0} - ${!pre_var:-0}))

        if [ "$delta" -gt 0 ]; then
            if [[ "${category}" == "critical" ]]; then
                critical_issues+=("${delta} ${worse_msg}")
            else
                warnings+=("${delta} ${worse_msg}")
            fi
            has_changes=true
        elif [ "$delta" -lt 0 ]; then
            improvements+=("$((-delta)) ${better_msg}")
            has_changes=true
        fi
    done

    # Check pod count changes (info only)
    local pods_delta=$((${POST_PODS_TOTAL:-0} - ${PRE_PODS_TOTAL:-0}))
    if [ "$pods_delta" -ne 0 ]; then
        if [ "$pods_delta" -gt 0 ]; then
            info_changes+=("${pods_delta} new pod(s) added")
        else
            info_changes+=("$((-pods_delta)) pod(s) removed")
        fi
        has_changes=true
    fi

    # Print results by category
    for issue in "${critical_issues[@]}"; do
        echo "  * CRITICAL: ${issue}"
    done

    for warning in "${warnings[@]}"; do
        echo "  * WARNING: ${warning}"
    done

    for improvement in "${improvements[@]}"; do
        echo "  * IMPROVED: ${improvement}"
    done

    for info in "${info_changes[@]}"; do
        echo "  * INFO: ${info}"
    done

    if [ "$has_changes" = false ]; then
        echo "  No significant changes detected between PRE and POST states."
    fi

    echo ""
}

# Generate final verdict
generate_final_verdict() {
    echo ""
    echo "############################################################################"
    echo "#                         FINAL VERDICT                                    #"
    echo "############################################################################"
    echo ""

    local critical_count=0
    local warning_count=0

    # Count critical issues (from POST state)
    [ "${POST_NODES_NOTREADY:-0}" -gt 0 ] && critical_count=$((critical_count + 1))
    [ "${POST_PODS_CRASHLOOP:-0}" -gt 0 ] && critical_count=$((critical_count + 1))

    # Count warnings (from POST state)
    [ "${POST_PODS_PENDING:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${POST_PODS_UNACCOUNTED:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${POST_DEPLOYS_NOTREADY:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${POST_DS_NOTREADY:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${POST_STS_NOTREADY:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${POST_PVC_NOTBOUND:-0}" -gt 0 ] && warning_count=$((warning_count + 1))
    [ "${POST_HELM_FAILED:-0}" -gt 0 ] && warning_count=$((warning_count + 1))

    echo "================================================================================"
    if [ "$critical_count" -gt 0 ]; then
        echo "  RESULT: FAILED - ${critical_count} CRITICAL issue(s), ${warning_count} warning(s)"
        echo "  ACTION: Investigate critical issues immediately before proceeding"
    elif [ "$warning_count" -gt 0 ]; then
        echo "  RESULT: WARNINGS - ${warning_count} warning(s) found (no critical issues)"
        echo "  ACTION: Monitor warnings, may resolve during rolling update completion"
    else
        echo "  RESULT: PASSED - Cluster health check successful"
        echo "  All components appear healthy after the change"
    fi
    echo "================================================================================"
    echo ""
    echo "Comparison completed at: $(get_formatted_timestamp)"
    echo ""
}

#===============================================================================
# Individual Comparison Functions (Live Cluster State)
#===============================================================================

# Compare critical health indicators (live state)
compare_critical_health() {
    echo ""
    echo ">>> NODE STATUS (Live) <<<"
    echo ""

    local notready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" || true)
    if [ -n "${notready_nodes}" ]; then
        echo "[CRITICAL] Nodes NOT Ready:"
        echo "${notready_nodes}"
    else
        echo "[OK] All nodes are Ready"
    fi
    echo ""

    echo ">>> POD STATUS (Live) <<<"
    echo ""

    local crash_pods=$(kubectl get pod -A 2>/dev/null | grep -i crashloop || true)
    if [ -n "${crash_pods}" ]; then
        echo "[CRITICAL] Pods in CrashLoopBackOff:"
        echo "${crash_pods}"
    fi

    local pending_pods=$(kubectl get pod -A 2>/dev/null | grep -i pending || true)
    if [ -n "${pending_pods}" ]; then
        echo "[WARNING] Pods in Pending state:"
        echo "${pending_pods}"
    fi

    if [ -z "${crash_pods}" ] && [ -z "${pending_pods}" ]; then
        echo "[OK] All pods are Running or Completed"
    fi
    echo ""
}

# Compare workload status (live state)
compare_workloads() {
    echo ""
    echo ">>> WORKLOAD STATUS (Live) <<<"
    echo ""

    echo "Deployments:"
    local deploy_notready=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) print}')
    if [ -n "${deploy_notready}" ]; then
        echo "[WARNING] Deployments NOT fully ready:"
        kubectl get deploy -A | head -1
        echo "${deploy_notready}"
    else
        echo "[OK] All deployments are ready"
    fi
    echo ""

    echo "DaemonSets:"
    local ds_notready=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$3 != $5 {print}')
    if [ -n "${ds_notready}" ]; then
        echo "[WARNING] DaemonSets NOT fully ready:"
        echo "${ds_notready}"
    else
        echo "[OK] All DaemonSets are ready"
    fi
    echo ""

    echo "StatefulSets:"
    local sts_notready=$(kubectl get sts -A 2>/dev/null | awk 'NR>1 {split($3,a,"/"); if(a[1]!=a[2]) print}' 2>/dev/null)
    if [ -n "${sts_notready}" ]; then
        echo "[WARNING] StatefulSets NOT fully ready:"
        echo "${sts_notready}"
    else
        echo "[OK] All StatefulSets are ready"
    fi
    echo ""
}

# Compare storage status (live state)
compare_storage() {
    echo ""
    echo ">>> STORAGE STATUS (Live) <<<"
    echo ""

    local pv_issues=$(kubectl get pv 2>/dev/null | grep -v Bound | grep -v NAME || true)
    local pvc_issues=$(kubectl get pvc -A 2>/dev/null | grep -v Bound | grep -v NAME || true)

    if [ -n "${pv_issues}" ]; then
        echo "[WARNING] PVs not in Bound state:"
        echo "${pv_issues}"
    else
        echo "[OK] All PVs are Bound"
    fi
    echo ""

    if [ -n "${pvc_issues}" ]; then
        echo "[WARNING] PVCs not in Bound state:"
        echo "${pvc_issues}"
    else
        echo "[OK] All PVCs are Bound"
    fi
    echo ""
}

# Compare Tanzu packages (live state)
compare_tanzu_packages() {
    echo ""
    echo ">>> TANZU PACKAGE STATUS (Live) <<<"
    echo ""

    local pkgi_status=$(kubectl get pkgi -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].type' --no-headers 2>/dev/null || echo "PackageInstall not available")

    local pkgi_failed=$(echo "${pkgi_status}" | grep -vi "Reconcile" | grep -vi "succeeded" || true)
    if [ -n "${pkgi_failed}" ] && [ "${pkgi_failed}" != "PackageInstall not available" ]; then
        echo "[WARNING] Packages not in healthy state:"
        echo "${pkgi_failed}"
    else
        echo "[OK] All packages reconciled successfully"
    fi
    echo ""
}

# Compare Helm releases (live state)
compare_helm_releases() {
    echo ""
    echo ">>> HELM RELEASE STATUS (Live) <<<"
    echo ""

    local helm_failed=$(helm list -A --failed 2>/dev/null || true)
    if [ -n "${helm_failed}" ]; then
        echo "[WARNING] Failed Helm releases:"
        echo "${helm_failed}"
    else
        echo "[OK] No failed Helm releases"
    fi
    echo ""
}

# Compare events (live state)
compare_events() {
    echo ""
    echo ">>> RELEVANT EVENTS (Live - Post-Change) <<<"
    echo ""
    echo "Note: Normal upgrade-related events are filtered out."
    echo ""

    local all_events=$(kubectl get events -A --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -50 || echo "No events found")
    local relevant_events=$(echo "${all_events}" | grep -vE "(Pulling|Pulled|Created|Started|Scheduled|SuccessfulCreate|Killing|Deleted|ScalingReplicaSet|SuccessfulDelete|NodeReady|NodeNotReady|RegisteredNode|RemovingNode|DeletingAllPods|TerminatingEvictedPod)" || true)

    if [ -n "${relevant_events}" ]; then
        echo "Events requiring attention:"
        echo ""
        echo "${relevant_events}"
    else
        echo "[OK] No concerning events found"
    fi
    echo ""
}

#===============================================================================
# Export Functions
#===============================================================================

export -f parse_health_report
export -f calculate_delta
export -f get_delta_status
export -f generate_comparison_report
export -f generate_metrics_comparison
export -f generate_layman_summary
export -f generate_final_verdict
export -f compare_critical_health
export -f compare_workloads
export -f compare_storage
export -f compare_tanzu_packages
export -f compare_helm_releases
export -f compare_events
