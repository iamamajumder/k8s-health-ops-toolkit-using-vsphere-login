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

        compare_critical_health
        compare_versions
        compare_workloads
        compare_storage
        compare_tanzu_packages
        compare_helm_releases
        compare_events
        compare_network_ingress
        compare_tmc_status
        generate_summary

    } > "${diff_file}" 2>&1
}

#===============================================================================
# Individual Comparison Functions
#===============================================================================

# Compare critical health indicators
compare_critical_health() {
    echo ""
    echo "############################################################################"
    echo "#                        CRITICAL HEALTH INDICATORS                        #"
    echo "############################################################################"
    echo ""

    echo ">>> NODE STATUS CHANGES <<<"
    echo ""

    local notready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" || true)
    if [ -n "${notready_nodes}" ]; then
        echo "[CRITICAL] Nodes NOT Ready:"
        echo "${notready_nodes}"
    else
        echo "[OK] All nodes are Ready"
    fi
    echo ""

    echo ">>> POD STATUS CHANGES <<<"
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

# Compare Kubernetes versions
compare_versions() {
    echo ""
    echo "############################################################################"
    echo "#                          VERSION CHANGES                                 #"
    echo "############################################################################"
    echo ""

    echo ">>> KUBERNETES VERSION <<<"
    local post_version=$(kubectl version --short 2>/dev/null | grep -i server || kubectl version 2>/dev/null | grep -i "Server Version" | head -1 || echo "Not found")
    echo "Post-Change: ${post_version}"
    echo ""

    echo ">>> CONTAINER IMAGE CHANGES <<<"
    echo "(New/removed images - changes expected during upgrades)"
    echo ""
}

# Compare workload status
compare_workloads() {
    echo ""
    echo "############################################################################"
    echo "#                         WORKLOAD CHANGES                                 #"
    echo "############################################################################"
    echo ""

    echo ">>> DEPLOYMENT STATUS <<<"
    local deploy_notready=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) print}')
    if [ -n "${deploy_notready}" ]; then
        echo "[WARNING] Deployments NOT fully ready:"
        kubectl get deploy -A | head -1
        echo "${deploy_notready}"
    else
        echo "[OK] All deployments are ready"
    fi
    echo ""

    echo ">>> DAEMONSET STATUS <<<"
    local ds_notready=$(kubectl get ds -A 2>/dev/null | awk 'NR>1 && $4 != $6 {print}')
    if [ -n "${ds_notready}" ]; then
        echo "[WARNING] DaemonSets NOT fully ready:"
        echo "${ds_notready}"
    else
        echo "[OK] All DaemonSets are ready"
    fi
    echo ""

    echo ">>> STATEFULSET STATUS <<<"
    local sts_notready=$(kubectl get sts -A 2>/dev/null | awk 'NR>1 && $3 != $4 {print}' 2>/dev/null)
    if [ -n "${sts_notready}" ]; then
        echo "[WARNING] StatefulSets NOT fully ready:"
        echo "${sts_notready}"
    else
        echo "[OK] All StatefulSets are ready"
    fi
    echo ""
}

# Compare storage status
compare_storage() {
    echo ""
    echo "############################################################################"
    echo "#                         STORAGE STATUS                                   #"
    echo "############################################################################"
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

# Compare Tanzu packages
compare_tanzu_packages() {
    echo ""
    echo "############################################################################"
    echo "#                       TANZU PACKAGE STATUS                               #"
    echo "############################################################################"
    echo ""

    echo ">>> PACKAGE INSTALL STATUS <<<"
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

# Compare Helm releases
compare_helm_releases() {
    echo ""
    echo "############################################################################"
    echo "#                        HELM RELEASE STATUS                               #"
    echo "############################################################################"
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

# Compare events
compare_events() {
    echo ""
    echo "############################################################################"
    echo "#                    RELEVANT EVENTS (Post-Change)                         #"
    echo "############################################################################"
    echo ""
    echo "Note: Normal upgrade-related events are filtered out."
    echo ""

    local all_events=$(kubectl get events -A --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -50 || echo "No events found")
    local relevant_events=$(echo "${all_events}" | grep -vE "(Pulling|Pulled|Created|Started|Scheduled|SuccessfulCreate|Killing|Deleted|ScalingReplicaSet|SuccessfulDelete|NodeReady|NodeNotReady|RegisteredNode|RemovingNode|DeletingAllPods|TerminatingEvictedPod)" || true)

    if [ -n "${relevant_events}" ]; then
        echo ">>> EVENTS REQUIRING ATTENTION <<<"
        echo ""
        echo "${relevant_events}"
    else
        echo "[OK] No concerning events found"
    fi
    echo ""
}

# Compare network and ingress
compare_network_ingress() {
    echo ""
    echo "############################################################################"
    echo "#                       NETWORK/INGRESS STATUS                             #"
    echo "############################################################################"
    echo ""

    echo ">>> TANZU INGRESS STATUS <<<"
    kubectl get pod -n tanzu-system-ingress 2>/dev/null || echo "tanzu-system-ingress namespace not found"
    echo ""
}

# Compare TMC status
compare_tmc_status() {
    echo ""
    echo "############################################################################"
    echo "#                          TMC STATUS                                      #"
    echo "############################################################################"
    echo ""

    kubectl get pods -n vmware-system-tmc 2>/dev/null || echo "TMC namespace not found"
    echo ""
}

# Generate summary
generate_summary() {
    echo ""
    echo "############################################################################"
    echo "#                        COMPARISON SUMMARY                                #"
    echo "############################################################################"
    echo ""

    local critical_issues=0
    local warnings=0

    # Check nodes
    local notready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l | tr -d ' ')
    notready_nodes=$(clean_integer "${notready_nodes}")
    if safe_gt "${notready_nodes}" "0"; then
        echo "[CRITICAL] ${notready_nodes} node(s) not Ready"
        critical_issues=$((critical_issues + 1))
    fi

    # Check pods
    local crash_pods=$(kubectl get pod -A --no-headers 2>/dev/null | grep -ic crashloop 2>/dev/null || echo "0")
    crash_pods=$(clean_integer "${crash_pods}")
    if safe_gt "${crash_pods}" "0"; then
        echo "[CRITICAL] ${crash_pods} pod(s) in CrashLoopBackOff"
        critical_issues=$((critical_issues + 1))
    fi

    local pending_pods=$(kubectl get pod -A --no-headers 2>/dev/null | grep -ic pending 2>/dev/null || echo "0")
    pending_pods=$(clean_integer "${pending_pods}")
    if safe_gt "${pending_pods}" "0"; then
        echo "[WARNING] ${pending_pods} pod(s) in Pending state"
        warnings=$((warnings + 1))
    fi

    # Check deployments
    local notready_deploys=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' | tr -d ' ')
    notready_deploys=$(clean_integer "${notready_deploys}")
    if safe_gt "${notready_deploys}" "0"; then
        echo "[WARNING] ${notready_deploys} deployment(s) not fully ready"
        warnings=$((warnings + 1))
    fi

    # Check DaemonSets
    local notready_ds=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$4 != $6' | wc -l | tr -d ' ')
    notready_ds=$(clean_integer "${notready_ds}")
    if safe_gt "${notready_ds}" "0"; then
        echo "[WARNING] ${notready_ds} DaemonSet(s) not fully ready"
        warnings=$((warnings + 1))
    fi

    echo ""
    echo "================================================================================"
    if safe_gt "${critical_issues}" "0"; then
        echo "  RESULT: ${critical_issues} CRITICAL issue(s), ${warnings} warning(s) found"
        echo "  ACTION: Please investigate critical issues before proceeding"
    elif safe_gt "${warnings}" "0"; then
        echo "  RESULT: ${warnings} warning(s) found (no critical issues)"
        echo "  ACTION: Monitor warnings, may resolve during rolling update completion"
    else
        echo "  RESULT: Cluster health check PASSED"
        echo "  All components appear healthy after the change"
    fi
    echo "================================================================================"
    echo ""
    echo "Comparison completed at: $(get_formatted_timestamp)"
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
    local passed_count=$(grep -c "PASSED" "${diff_file}" 2>/dev/null | tr -d ' \n' || echo "0")

    # Ensure they're valid integers
    critical_count=${critical_count:-0}
    warning_count=${warning_count:-0}
    passed_count=${passed_count:-0}

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

    # Show warnings if any
    if [ "$warning_count" -gt 0 ] && [ "$critical_count" -eq 0 ]; then
        echo "--- WARNING ITEMS ---"
        echo ""
        grep "\[WARNING\]" "${diff_file}" 2>/dev/null | head -10 | while read -r line; do
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
    elif [ "$warning_count" -gt 0 ]; then
        echo -e "  ${YELLOW}RESULT: WARNINGS - Some warnings detected${NC}"
        echo -e "  ${YELLOW}ACTION: Monitor warnings, may resolve during rollout completion${NC}"
    else
        echo -e "  ${GREEN}RESULT: PASSED - All health checks successful${NC}"
        echo -e "  ${GREEN}Cluster is healthy after the change${NC}"
    fi

    echo ""
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${CYAN}║${NC} ${BLUE}Full detailed report saved to:${NC}                                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} ${diff_file}  ${CYAN}║${NC}"
    echo -e "${BLUE}Full report:${NC} ${diff_file}"
    echo ""
}

#===============================================================================
# Export Functions
#===============================================================================

export -f generate_comparison_report
export -f display_comparison_summary
export -f compare_critical_health
export -f compare_versions
export -f compare_workloads
export -f compare_storage
export -f compare_tanzu_packages
export -f compare_helm_releases
export -f compare_events
export -f compare_network_ingress
export -f compare_tmc_status
export -f generate_summary
