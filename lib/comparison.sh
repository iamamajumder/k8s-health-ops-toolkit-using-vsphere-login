#!/bin/bash
#===============================================================================
# Comparison Logic Library
# Functions for comparing pre-change and post-change health check results
#===============================================================================

# Source common functions if not already loaded
if [ -z "${COMMON_LIB_LOADED}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/lib/common.sh"
    export COMMON_LIB_LOADED=1
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

# Generate metrics comparison table
generate_metrics_comparison() {
    echo ""
    echo "############################################################################"
    echo "#                       PRE vs POST COMPARISON                             #"
    echo "############################################################################"
    echo ""
    printf "%-25s %10s %10s %10s %10s\n" "Metric" "PRE" "POST" "DELTA" "STATUS"
    printf "%-25s %10s %10s %10s %10s\n" "-------------------------" "----------" "----------" "----------" "----------"

    # Nodes
    local delta=$(calculate_delta "${PRE_NODES_TOTAL}" "${POST_NODES_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "Nodes Total" "${PRE_NODES_TOTAL:-0}" "${POST_NODES_TOTAL:-0}" "$delta" "$(get_delta_status 'nodes_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_NODES_READY}" "${POST_NODES_READY}")
    printf "%-25s %10s %10s %10s %10s\n" "Nodes Ready" "${PRE_NODES_READY:-0}" "${POST_NODES_READY:-0}" "$delta" "$(get_delta_status 'nodes_ready' "$delta" 'lower_is_worse')"

    delta=$(calculate_delta "${PRE_NODES_NOTREADY}" "${POST_NODES_NOTREADY}")
    printf "%-25s %10s %10s %10s %10s\n" "Nodes NotReady" "${PRE_NODES_NOTREADY:-0}" "${POST_NODES_NOTREADY:-0}" "$delta" "$(get_delta_status 'nodes_notready' "$delta" 'higher_is_worse')"

    echo ""

    # Pods
    delta=$(calculate_delta "${PRE_PODS_TOTAL}" "${POST_PODS_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "Pods Total" "${PRE_PODS_TOTAL:-0}" "${POST_PODS_TOTAL:-0}" "$delta" "$(get_delta_status 'pods_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_PODS_RUNNING}" "${POST_PODS_RUNNING}")
    printf "%-25s %10s %10s %10s %10s\n" "Pods Running" "${PRE_PODS_RUNNING:-0}" "${POST_PODS_RUNNING:-0}" "$delta" "$(get_delta_status 'pods_running' "$delta" 'lower_is_worse')"

    delta=$(calculate_delta "${PRE_PODS_CRASHLOOP}" "${POST_PODS_CRASHLOOP}")
    printf "%-25s %10s %10s %10s %10s\n" "Pods CrashLoopBackOff" "${PRE_PODS_CRASHLOOP:-0}" "${POST_PODS_CRASHLOOP:-0}" "$delta" "$(get_delta_status 'pods_crashloop' "$delta" 'higher_is_worse')"

    delta=$(calculate_delta "${PRE_PODS_PENDING}" "${POST_PODS_PENDING}")
    printf "%-25s %10s %10s %10s %10s\n" "Pods Pending" "${PRE_PODS_PENDING:-0}" "${POST_PODS_PENDING:-0}" "$delta" "$(get_delta_status 'pods_pending' "$delta" 'higher_is_worse')"

    delta=$(calculate_delta "${PRE_PODS_COMPLETED}" "${POST_PODS_COMPLETED}")
    printf "%-25s %10s %10s %10s %10s\n" "Pods Completed" "${PRE_PODS_COMPLETED:-0}" "${POST_PODS_COMPLETED:-0}" "$delta" "$(get_delta_status 'pods_completed' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_PODS_UNACCOUNTED}" "${POST_PODS_UNACCOUNTED}")
    printf "%-25s %10s %10s %10s %10s\n" "Pods Unaccounted" "${PRE_PODS_UNACCOUNTED:-0}" "${POST_PODS_UNACCOUNTED:-0}" "$delta" "$(get_delta_status 'pods_unaccounted' "$delta" 'higher_is_worse')"

    echo ""

    # Deployments
    delta=$(calculate_delta "${PRE_DEPLOYS_TOTAL}" "${POST_DEPLOYS_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "Deployments Total" "${PRE_DEPLOYS_TOTAL:-0}" "${POST_DEPLOYS_TOTAL:-0}" "$delta" "$(get_delta_status 'deploys_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_DEPLOYS_NOTREADY}" "${POST_DEPLOYS_NOTREADY}")
    printf "%-25s %10s %10s %10s %10s\n" "Deployments NotReady" "${PRE_DEPLOYS_NOTREADY:-0}" "${POST_DEPLOYS_NOTREADY:-0}" "$delta" "$(get_delta_status 'deploys_notready' "$delta" 'higher_is_worse')"

    echo ""

    # DaemonSets
    delta=$(calculate_delta "${PRE_DS_TOTAL}" "${POST_DS_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "DaemonSets Total" "${PRE_DS_TOTAL:-0}" "${POST_DS_TOTAL:-0}" "$delta" "$(get_delta_status 'ds_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_DS_NOTREADY}" "${POST_DS_NOTREADY}")
    printf "%-25s %10s %10s %10s %10s\n" "DaemonSets NotReady" "${PRE_DS_NOTREADY:-0}" "${POST_DS_NOTREADY:-0}" "$delta" "$(get_delta_status 'ds_notready' "$delta" 'higher_is_worse')"

    echo ""

    # StatefulSets
    delta=$(calculate_delta "${PRE_STS_TOTAL}" "${POST_STS_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "StatefulSets Total" "${PRE_STS_TOTAL:-0}" "${POST_STS_TOTAL:-0}" "$delta" "$(get_delta_status 'sts_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_STS_NOTREADY}" "${POST_STS_NOTREADY}")
    printf "%-25s %10s %10s %10s %10s\n" "StatefulSets NotReady" "${PRE_STS_NOTREADY:-0}" "${POST_STS_NOTREADY:-0}" "$delta" "$(get_delta_status 'sts_notready' "$delta" 'higher_is_worse')"

    echo ""

    # PVCs
    delta=$(calculate_delta "${PRE_PVC_TOTAL}" "${POST_PVC_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "PVCs Total" "${PRE_PVC_TOTAL:-0}" "${POST_PVC_TOTAL:-0}" "$delta" "$(get_delta_status 'pvc_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_PVC_NOTBOUND}" "${POST_PVC_NOTBOUND}")
    printf "%-25s %10s %10s %10s %10s\n" "PVCs NotBound" "${PRE_PVC_NOTBOUND:-0}" "${POST_PVC_NOTBOUND:-0}" "$delta" "$(get_delta_status 'pvc_notbound' "$delta" 'higher_is_worse')"

    echo ""

    # Helm
    delta=$(calculate_delta "${PRE_HELM_TOTAL}" "${POST_HELM_TOTAL}")
    printf "%-25s %10s %10s %10s %10s\n" "Helm Releases Total" "${PRE_HELM_TOTAL:-0}" "${POST_HELM_TOTAL:-0}" "$delta" "$(get_delta_status 'helm_total' "$delta" 'neutral')"

    delta=$(calculate_delta "${PRE_HELM_FAILED}" "${POST_HELM_FAILED}")
    printf "%-25s %10s %10s %10s %10s\n" "Helm Releases Failed" "${PRE_HELM_FAILED:-0}" "${POST_HELM_FAILED:-0}" "$delta" "$(get_delta_status 'helm_failed' "$delta" 'higher_is_worse')"

    echo ""
}

# Generate plain English summary
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

    # Check nodes
    local nodes_notready_delta=$((${POST_NODES_NOTREADY:-0} - ${PRE_NODES_NOTREADY:-0}))
    if [ "$nodes_notready_delta" -gt 0 ]; then
        critical_issues+=("${nodes_notready_delta} more node(s) became NotReady")
        has_changes=true
    elif [ "$nodes_notready_delta" -lt 0 ]; then
        improvements+=("$((-nodes_notready_delta)) node(s) recovered to Ready state")
        has_changes=true
    fi

    # Check pods crashloop
    local crashloop_delta=$((${POST_PODS_CRASHLOOP:-0} - ${PRE_PODS_CRASHLOOP:-0}))
    if [ "$crashloop_delta" -gt 0 ]; then
        critical_issues+=("${crashloop_delta} more pod(s) are now crashing (CrashLoopBackOff)")
        has_changes=true
    elif [ "$crashloop_delta" -lt 0 ]; then
        improvements+=("$((-crashloop_delta)) pod(s) stopped crashing")
        has_changes=true
    fi

    # Check pods pending
    local pending_delta=$((${POST_PODS_PENDING:-0} - ${PRE_PODS_PENDING:-0}))
    if [ "$pending_delta" -gt 0 ]; then
        warnings+=("${pending_delta} more pod(s) are stuck in Pending state")
        has_changes=true
    elif [ "$pending_delta" -lt 0 ]; then
        improvements+=("$((-pending_delta)) pod(s) moved from Pending to Running")
        has_changes=true
    fi

    # Check pods unaccounted
    local unaccounted_delta=$((${POST_PODS_UNACCOUNTED:-0} - ${PRE_PODS_UNACCOUNTED:-0}))
    if [ "$unaccounted_delta" -gt 0 ]; then
        warnings+=("${unaccounted_delta} more pod(s) in unexpected state (Failed/Unknown/Error)")
        has_changes=true
    elif [ "$unaccounted_delta" -lt 0 ]; then
        improvements+=("$((-unaccounted_delta)) pod(s) recovered from unexpected state")
        has_changes=true
    fi

    # Check deployments
    local deploys_notready_delta=$((${POST_DEPLOYS_NOTREADY:-0} - ${PRE_DEPLOYS_NOTREADY:-0}))
    if [ "$deploys_notready_delta" -gt 0 ]; then
        warnings+=("${deploys_notready_delta} more deployment(s) are not fully ready")
        has_changes=true
    elif [ "$deploys_notready_delta" -lt 0 ]; then
        improvements+=("$((-deploys_notready_delta)) deployment(s) became fully ready")
        has_changes=true
    fi

    # Check DaemonSets
    local ds_notready_delta=$((${POST_DS_NOTREADY:-0} - ${PRE_DS_NOTREADY:-0}))
    if [ "$ds_notready_delta" -gt 0 ]; then
        warnings+=("${ds_notready_delta} more DaemonSet(s) are not fully ready")
        has_changes=true
    elif [ "$ds_notready_delta" -lt 0 ]; then
        improvements+=("$((-ds_notready_delta)) DaemonSet(s) became fully ready")
        has_changes=true
    fi

    # Check StatefulSets
    local sts_notready_delta=$((${POST_STS_NOTREADY:-0} - ${PRE_STS_NOTREADY:-0}))
    if [ "$sts_notready_delta" -gt 0 ]; then
        warnings+=("${sts_notready_delta} more StatefulSet(s) are not fully ready")
        has_changes=true
    elif [ "$sts_notready_delta" -lt 0 ]; then
        improvements+=("$((-sts_notready_delta)) StatefulSet(s) became fully ready")
        has_changes=true
    fi

    # Check PVCs
    local pvc_notbound_delta=$((${POST_PVC_NOTBOUND:-0} - ${PRE_PVC_NOTBOUND:-0}))
    if [ "$pvc_notbound_delta" -gt 0 ]; then
        warnings+=("${pvc_notbound_delta} more PVC(s) are not bound")
        has_changes=true
    elif [ "$pvc_notbound_delta" -lt 0 ]; then
        improvements+=("$((-pvc_notbound_delta)) PVC(s) became bound")
        has_changes=true
    fi

    # Check Helm
    local helm_failed_delta=$((${POST_HELM_FAILED:-0} - ${PRE_HELM_FAILED:-0}))
    if [ "$helm_failed_delta" -gt 0 ]; then
        warnings+=("${helm_failed_delta} more Helm release(s) failed")
        has_changes=true
    elif [ "$helm_failed_delta" -lt 0 ]; then
        improvements+=("$((-helm_failed_delta)) Helm release(s) recovered")
        has_changes=true
    fi

    # Check pod count changes
    local pods_delta=$((${POST_PODS_TOTAL:-0} - ${PRE_PODS_TOTAL:-0}))
    if [ "$pods_delta" -ne 0 ]; then
        if [ "$pods_delta" -gt 0 ]; then
            info_changes+=("${pods_delta} new pod(s) added")
        else
            info_changes+=("$((-pods_delta)) pod(s) removed")
        fi
        has_changes=true
    fi

    # Print critical issues
    if [ ${#critical_issues[@]} -gt 0 ]; then
        for issue in "${critical_issues[@]}"; do
            echo "  * CRITICAL: ${issue}"
        done
    fi

    # Print warnings
    if [ ${#warnings[@]} -gt 0 ]; then
        for warning in "${warnings[@]}"; do
            echo "  * WARNING: ${warning}"
        done
    fi

    # Print improvements
    if [ ${#improvements[@]} -gt 0 ]; then
        for improvement in "${improvements[@]}"; do
            echo "  * IMPROVED: ${improvement}"
        done
    fi

    # Print info changes
    if [ ${#info_changes[@]} -gt 0 ]; then
        for info in "${info_changes[@]}"; do
            echo "  * INFO: ${info}"
        done
    fi

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
    local ds_notready=$(kubectl get ds -A 2>/dev/null | awk 'NR>1 && $4 != $6 {print}')
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

# Display comparison summary to CLI
display_comparison_summary() {
    local diff_file="$1"
    local cluster_name="$2"

    echo ""
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${CYAN}                    COMPARISON REPORT SUMMARY${NC}"
    echo -e "${CYAN}================================================================================${NC}"
    echo ""
    echo -e "${BLUE}Cluster:${NC} ${cluster_name}"
    echo -e "${BLUE}Report:${NC}  ${diff_file}"
    echo ""

    # Parse the diff file for critical metrics
    local critical_count=$(grep -c "\[CRITICAL\]" "${diff_file}" 2>/dev/null | tr -d ' \n' || echo "0")
    local warning_count=$(grep -c "\[WARNING\]" "${diff_file}" 2>/dev/null | tr -d ' \n' || echo "0")
    local worse_count=$(grep -c "\[WORSE\]" "${diff_file}" 2>/dev/null | tr -d ' \n' || echo "0")
    local better_count=$(grep -c "\[BETTER\]" "${diff_file}" 2>/dev/null | tr -d ' \n' || echo "0")

    # Ensure they're valid integers
    critical_count=${critical_count:-0}
    warning_count=${warning_count:-0}
    worse_count=${worse_count:-0}
    better_count=${better_count:-0}

    echo "--- STATUS OVERVIEW ---"
    echo ""

    if [ "$critical_count" -gt 0 ]; then
        echo -e "  ${RED}[X] CRITICAL Issues: ${critical_count}${NC}"
    else
        echo -e "  ${GREEN}[OK] CRITICAL Issues: 0${NC}"
    fi

    if [ "$warning_count" -gt 0 ]; then
        echo -e "  ${YELLOW}[!] Warnings: ${warning_count}${NC}"
    else
        echo -e "  ${GREEN}[OK] Warnings: 0${NC}"
    fi

    if [ "$worse_count" -gt 0 ]; then
        echo -e "  ${RED}[!] Metrics Worsened: ${worse_count}${NC}"
    fi

    if [ "$better_count" -gt 0 ]; then
        echo -e "  ${GREEN}[+] Metrics Improved: ${better_count}${NC}"
    fi

    echo ""

    # Show critical items if any
    if [ "$critical_count" -gt 0 ]; then
        echo "--- CRITICAL ITEMS ---"
        echo ""
        grep "\[CRITICAL\]" "${diff_file}" 2>/dev/null | head -10 | while read -r line; do
            echo -e "  ${RED}${line}${NC}"
        done
        echo ""
    fi

    # Show what worsened if any
    if [ "$worse_count" -gt 0 ]; then
        echo "--- ITEMS THAT WORSENED ---"
        echo ""
        grep "\[WORSE\]" "${diff_file}" 2>/dev/null | head -10 | while read -r line; do
            echo -e "  ${YELLOW}${line}${NC}"
        done
        echo ""
    fi

    # Overall status
    echo "--- OVERALL STATUS ---"
    echo ""

    if [ "$critical_count" -gt 0 ]; then
        echo -e "  ${RED}RESULT: FAILED - Critical issues detected${NC}"
        echo -e "  ${RED}ACTION: Investigate and resolve critical issues before proceeding${NC}"
    elif [ "$warning_count" -gt 0 ] || [ "$worse_count" -gt 0 ]; then
        echo -e "  ${YELLOW}RESULT: WARNINGS - Some warnings or degraded metrics detected${NC}"
        echo -e "  ${YELLOW}ACTION: Monitor warnings, may resolve during rollout completion${NC}"
    else
        echo -e "  ${GREEN}RESULT: PASSED - All health checks successful${NC}"
        echo -e "  ${GREEN}Cluster is healthy after the change${NC}"
    fi

    echo ""
    echo -e "${CYAN}================================================================================${NC}"
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
export -f display_comparison_summary
export -f compare_critical_health
export -f compare_workloads
export -f compare_storage
export -f compare_tanzu_packages
export -f compare_helm_releases
export -f compare_events
