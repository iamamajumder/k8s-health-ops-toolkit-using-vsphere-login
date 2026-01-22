#!/bin/bash
#===============================================================================
# Kubernetes Cluster Health Check - POST-CHANGE Script
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Capture cluster state after upgrades/changes and compare with pre-change
#===============================================================================

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CLUSTER_NAME="${1:-$(kubectl config current-context 2>/dev/null | cut -d'/' -f1 || echo 'unknown-cluster')}"
OUTPUT_DIR="${2:-./k8s-healthcheck}"
PRE_CHANGE_FILE="${3:-${OUTPUT_DIR}/${CLUSTER_NAME}_pre_change_latest.txt}"
OUTPUT_FILE="${OUTPUT_DIR}/${CLUSTER_NAME}_post_change_${TIMESTAMP}.txt"
DIFF_FILE="${OUTPUT_DIR}/${CLUSTER_NAME}_comparison_${TIMESTAMP}.txt"
LATEST_POST_LINK="${OUTPUT_DIR}/${CLUSTER_NAME}_post_change_latest.txt"
LATEST_DIFF_LINK="${OUTPUT_DIR}/${CLUSTER_NAME}_comparison_latest.txt"

# Image exclusion pattern (customize as needed)
IMAGE_EXCLUSION_PATTERN='harbor|localhost:5000|image: sha256|vmware|broadcom|dynatrace|ghcr.io/northerntrust-internal'

# Events to ignore during comparison (expected during upgrades/rolling updates)
EXPECTED_UPGRADE_EVENTS=(
    "Pulling"
    "Pulled"
    "Created"
    "Started"
    "Scheduled"
    "SuccessfulCreate"
    "Killing"
    "Deleted"
    "ScalingReplicaSet"
    "SuccessfulDelete"
    "NodeReady"
    "NodeNotReady"
    "RegisteredNode"
    "RemovingNode"
    "DeletingAllPods"
    "TerminatingEvictedPod"
)

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Function to print section header
print_header() {
    local title="$1"
    echo ""
    echo "================================================================================"
    echo "=== ${title}"
    echo "=== Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================================"
    echo ""
}

# Function to run command and capture output
run_check() {
    local description="$1"
    local cmd="$2"
    
    echo "--- ${description} ---"
    echo "Command: ${cmd}"
    echo "Output:"
    eval "${cmd}" 2>&1 || echo "[WARN] Command returned non-zero exit code"
    echo ""
}

# Function to display progress
progress() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to extract section from health check file
extract_section() {
    local file="$1"
    local section="$2"
    local start_pattern="=== ${section}"
    local end_pattern="^=== SECTION"
    
    sed -n "/${start_pattern}/,/${end_pattern}/p" "${file}" | head -n -3
}

# Function to compare sections
compare_sections() {
    local section_name="$1"
    local pre_file="$2"
    local post_file="$3"
    
    local pre_section=$(mktemp)
    local post_section=$(mktemp)
    
    extract_section "${pre_file}" "${section_name}" > "${pre_section}"
    extract_section "${post_file}" "${section_name}" > "${post_section}"
    
    if ! diff -q "${pre_section}" "${post_section}" > /dev/null 2>&1; then
        echo "CHANGES DETECTED"
        diff --color=never -u "${pre_section}" "${post_section}" | tail -n +3
    else
        echo "NO CHANGES"
    fi
    
    rm -f "${pre_section}" "${post_section}"
}

# Function to filter relevant events
filter_relevant_events() {
    local input="$1"
    local exclude_pattern=$(IFS='|'; echo "${EXPECTED_UPGRADE_EVENTS[*]}")
    
    echo "${input}" | grep -vE "${exclude_pattern}" || true
}

# Start health check
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Kubernetes Post-Change Health Check${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Cluster: ${YELLOW}${CLUSTER_NAME}${NC}"
echo -e "Output:  ${YELLOW}${OUTPUT_FILE}${NC}"
echo ""

# Check for pre-change file
if [ ! -f "${PRE_CHANGE_FILE}" ]; then
    # Try to resolve symlink
    if [ -L "${PRE_CHANGE_FILE}" ]; then
        PRE_CHANGE_FILE=$(readlink -f "${PRE_CHANGE_FILE}")
    fi
    
    if [ ! -f "${PRE_CHANGE_FILE}" ]; then
        echo -e "${RED}[ERROR] Pre-change file not found: ${PRE_CHANGE_FILE}${NC}"
        echo -e "${YELLOW}Please run k8s-health-check-pre.sh first or specify the pre-change file path.${NC}"
        echo ""
        echo "Usage: $0 [cluster-name] [output-dir] [pre-change-file]"
        exit 1
    fi
fi

progress "Using pre-change file: ${PRE_CHANGE_FILE}"

# Verify kubectl connectivity
progress "Verifying cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}[ERROR] Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Begin capturing POST-CHANGE output (same checks as pre-change)
progress "Collecting post-change cluster state..."
{
    print_header "KUBERNETES CLUSTER HEALTH CHECK - POST-CHANGE"
    echo "Cluster Context: ${CLUSTER_NAME}"
    echo "Check Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Environment: VMware Cloud Foundation 5.2.1 / VKS 3.3.3"
    echo "Pre-Change Reference: ${PRE_CHANGE_FILE}"
    echo ""

    #---------------------------------------------------------------------------
    # SECTION 1: CLUSTER OVERVIEW
    #---------------------------------------------------------------------------
    print_header "SECTION 1: CLUSTER OVERVIEW"
    
    run_check "Current Date/Time" "date"
    run_check "Cluster Info" "kubectl cluster-info"
    run_check "Kubernetes Version" "kubectl version --short 2>/dev/null || kubectl version"
    run_check "Current Context" "kubectl config current-context"

    #---------------------------------------------------------------------------
    # SECTION 2: NODE STATUS
    #---------------------------------------------------------------------------
    print_header "SECTION 2: NODE STATUS"
    
    run_check "All Nodes" "kubectl get nodes -o wide"
    run_check "Node Conditions (Pressure/Issues)" "kubectl describe nodes | grep -E '(^Name:|Conditions:|MemoryPressure|DiskPressure|PIDPressure|NetworkUnavailable|Ready)' | grep -v 'Conditions:'"
    run_check "Node Resource Allocation" "kubectl describe nodes | grep -A 5 'Allocated resources:'"
    run_check "Node Taints" "kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].effect'"

    #---------------------------------------------------------------------------
    # SECTION 3: POD STATUS
    #---------------------------------------------------------------------------
    print_header "SECTION 3: POD STATUS"
    
    run_check "All Pods (Full List)" "kubectl get pod -A -o wide"
    run_check "Non-Running Pods (CRITICAL)" "kubectl get pod -A | grep -vi running | grep -vi completed || echo 'All pods are Running or Completed'"
    run_check "Pods in CrashLoopBackOff" "kubectl get pod -A | grep -i crashloop || echo 'No CrashLoopBackOff pods found'"
    run_check "Pods in Pending State" "kubectl get pod -A | grep -i pending || echo 'No Pending pods found'"
    run_check "Pods Restarting (>5 restarts)" "kubectl get pod -A -o wide | awk 'NR==1 || \$5 > 5'"
    run_check "Gateway Pods" "kubectl get po -A | grep -i gateway-0"
    run_check "Kubernetes Dashboard Pods" "kubectl get po -A | grep -i kubernetes-dashboard || echo 'Kubernetes Dashboard not found'"

    #---------------------------------------------------------------------------
    # SECTION 4: WORKLOAD STATUS
    #---------------------------------------------------------------------------
    print_header "SECTION 4: WORKLOAD STATUS"
    
    run_check "All Deployments" "kubectl get deploy -A -o wide"
    run_check "Deployments Not Ready" "kubectl get deploy -A | awk 'NR==1 || \$3 != \$4' | grep -v 'READY' || echo 'All deployments are ready'"
    run_check "All DaemonSets" "kubectl get ds -A -o wide"
    run_check "DaemonSets Not Ready" "kubectl get ds -A | awk 'NR==1 || \$4 != \$6'"
    run_check "All StatefulSets" "kubectl get sts -A -o wide 2>/dev/null || echo 'No StatefulSets found'"
    run_check "All ReplicaSets" "kubectl get rs -A 2>/dev/null | awk 'NR==1 || \$3 != \$4'"
    run_check "All Jobs" "kubectl get jobs -A 2>/dev/null || echo 'No Jobs found'"
    run_check "All CronJobs" "kubectl get cronjobs -A 2>/dev/null || echo 'No CronJobs found'"

    #---------------------------------------------------------------------------
    # SECTION 5: STORAGE STATUS
    #---------------------------------------------------------------------------
    print_header "SECTION 5: STORAGE STATUS"
    
    run_check "Persistent Volumes" "kubectl get pv -o wide"
    run_check "PVs Not Bound" "kubectl get pv | grep -v Bound | grep -v NAME || echo 'All PVs are Bound'"
    run_check "Persistent Volume Claims" "kubectl get pvc -A -o wide"
    run_check "PVCs Not Bound" "kubectl get pvc -A | grep -v Bound | grep -v NAME || echo 'All PVCs are Bound'"
    run_check "Storage Classes" "kubectl get sc"

    #---------------------------------------------------------------------------
    # SECTION 6: NETWORKING
    #---------------------------------------------------------------------------
    print_header "SECTION 6: NETWORKING"
    
    run_check "All Services" "kubectl get svc -A"
    run_check "Services in tanzu-system-ingress" "kubectl get svc -n tanzu-system-ingress 2>/dev/null || echo 'Namespace not found'"
    run_check "Pods in tanzu-system-ingress" "kubectl get pod -n tanzu-system-ingress 2>/dev/null || echo 'Namespace not found'"
    run_check "HTTPProxy Resources" "kubectl -n k8s-system get httpproxy 2>/dev/null || echo 'HTTPProxy not found or namespace does not exist'"
    run_check "All Ingresses" "kubectl get ingress -A 2>/dev/null || echo 'No Ingress resources found'"
    run_check "Network Policies" "kubectl get networkpolicy -A 2>/dev/null || echo 'No NetworkPolicies found'"

    #---------------------------------------------------------------------------
    # SECTION 7: ANTREA/CNI STATUS
    #---------------------------------------------------------------------------
    print_header "SECTION 7: ANTREA/CNI STATUS"
    
    run_check "Antrea Controller Tier Count" "kubectl -n kube-system logs -l component=antrea-controller --tail 1000 2>/dev/null | grep -i tier | wc -l || echo '0'"
    run_check "Antrea Pods Status" "kubectl get pods -n kube-system -l app=antrea 2>/dev/null || echo 'Antrea pods not found with label app=antrea'"
    run_check "Antrea Agent Pods" "kubectl get pods -n kube-system | grep antrea || echo 'No Antrea pods found'"

    #---------------------------------------------------------------------------
    # SECTION 8: TANZU/VMware SPECIFIC
    #---------------------------------------------------------------------------
    print_header "SECTION 8: TANZU/VMware SPECIFIC"
    
    run_check "Package Installs (pkgi)" "kubectl get pkgi -A 2>/dev/null || echo 'PackageInstall CRD not found'"
    run_check "Package Install Status" "kubectl get pkgi -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].type,MESSAGE:.status.conditions[0].message' 2>/dev/null || echo 'Could not get pkgi status'"
    run_check "TMC Impersonation Secrets Count" "kubectl -n vmware-system-tmc get secrets 2>/dev/null | grep impersonation | wc -l || echo '0'"
    run_check "TMC Pods" "kubectl get pods -n vmware-system-tmc 2>/dev/null || echo 'TMC namespace not found'"
    run_check "Cluster API Resources" "kubectl get cluster,machine,machinedeployment -A 2>/dev/null || echo 'Cluster API resources not found'"

    #---------------------------------------------------------------------------
    # SECTION 9: SECURITY & RBAC
    #---------------------------------------------------------------------------
    print_header "SECTION 9: SECURITY & RBAC"
    
    run_check "Pod Disruption Budgets" "kubectl get pdb -A"
    run_check "PDB Status Details" "kubectl get pdb -A -o wide 2>/dev/null"
    run_check "Service Accounts (kube-system)" "kubectl get sa -n kube-system"
    run_check "Cluster Role Bindings Count" "kubectl get clusterrolebindings --no-headers 2>/dev/null | wc -l"

    #---------------------------------------------------------------------------
    # SECTION 10: COMPONENT STATUS
    #---------------------------------------------------------------------------
    print_header "SECTION 10: COMPONENT STATUS"
    
    run_check "Component Status (Deprecated but useful)" "kubectl get cs 2>/dev/null || echo 'Component status not available'"
    run_check "Control Plane Pods" "kubectl get pods -n kube-system -l tier=control-plane 2>/dev/null || kubectl get pods -n kube-system | grep -E '(kube-apiserver|kube-controller|kube-scheduler|etcd)'"
    run_check "CoreDNS Status" "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    run_check "Metrics Server" "kubectl get pods -n kube-system | grep metrics-server || echo 'Metrics server not found'"

    #---------------------------------------------------------------------------
    # SECTION 11: HELM RELEASES
    #---------------------------------------------------------------------------
    print_header "SECTION 11: HELM RELEASES"
    
    run_check "Helm Releases (All Namespaces)" "helm list -A 2>/dev/null || echo 'Helm not available or no releases found'"
    run_check "Failed Helm Releases" "helm list -A --failed 2>/dev/null || echo 'No failed releases or Helm not available'"

    #---------------------------------------------------------------------------
    # SECTION 12: NAMESPACES
    #---------------------------------------------------------------------------
    print_header "SECTION 12: NAMESPACES"
    
    run_check "All Namespaces with Labels" "kubectl get ns --show-labels"
    run_check "Namespace Status" "kubectl get ns -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'"

    #---------------------------------------------------------------------------
    # SECTION 13: RESOURCE QUOTAS & LIMITS
    #---------------------------------------------------------------------------
    print_header "SECTION 13: RESOURCE QUOTAS & LIMITS"
    
    run_check "Resource Quotas" "kubectl get resourcequota -A 2>/dev/null || echo 'No ResourceQuotas found'"
    run_check "Limit Ranges" "kubectl get limitrange -A 2>/dev/null || echo 'No LimitRanges found'"

    #---------------------------------------------------------------------------
    # SECTION 14: EVENTS (WARNING/ERROR)
    #---------------------------------------------------------------------------
    print_header "SECTION 14: EVENTS (Non-Normal)"
    
    run_check "Warning/Error Events (Last 1 hour)" "kubectl get events -A --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -100 || echo 'No warning events found'"
    run_check "Events Summary by Reason" "kubectl get events -A --field-selector type!=Normal -o custom-columns='REASON:.reason' --no-headers 2>/dev/null | sort | uniq -c | sort -rn | head -20 || echo 'No events to summarize'"

    #---------------------------------------------------------------------------
    # SECTION 15: EXTERNAL CONNECTIVITY TEST
    #---------------------------------------------------------------------------
    print_header "SECTION 15: EXTERNAL CONNECTIVITY TEST"
    
    HTTPPROXY_FQDN=$(kubectl -n k8s-system get httpproxy k8s-ingress-verify-httpproxy -o jsonpath="{.spec.virtualhost.fqdn}" 2>/dev/null)
    if [ -n "${HTTPPROXY_FQDN}" ]; then
        echo "--- HTTPProxy Ingress Test (${HTTPPROXY_FQDN}) ---"
        echo "Testing URL: https://${HTTPPROXY_FQDN}"
        echo ""
        
        # First try with certificate verification
        echo "Attempt 1: With SSL certificate verification"
        CURL_RESULT=$(curl -s --connect-timeout 10 -o /dev/null -w "HTTP_CODE:%{http_code} SSL_VERIFY:OK" "https://${HTTPPROXY_FQDN}" 2>&1)
        if echo "${CURL_RESULT}" | grep -q "HTTP_CODE:"; then
            echo "Result: ${CURL_RESULT}"
            echo "Response preview:"
            curl -s --connect-timeout 10 "https://${HTTPPROXY_FQDN}" 2>/dev/null | head -20 || echo "Could not fetch content"
        else
            # Certificate verification failed, try with -k flag
            echo "Result: SSL certificate verification failed"
            echo ""
            echo "Attempt 2: Skipping SSL certificate verification (-k flag)"
            CURL_RESULT_INSECURE=$(curl -sk --connect-timeout 10 -o /dev/null -w "HTTP_CODE:%{http_code}" "https://${HTTPPROXY_FQDN}" 2>&1)
            echo "Result: ${CURL_RESULT_INSECURE} (SSL verification skipped)"
            echo "[WARNING] SSL certificate may be self-signed or invalid"
            echo "Response preview:"
            curl -sk --connect-timeout 10 "https://${HTTPPROXY_FQDN}" 2>/dev/null | head -20 || echo "Could not fetch content"
        fi
        echo ""
    else
        echo "--- HTTPProxy Ingress Test ---"
        echo "HTTPProxy k8s-ingress-verify-httpproxy not found in k8s-system namespace"
        echo ""
    fi

    #---------------------------------------------------------------------------
    # SECTION 16: CONTAINER IMAGES AUDIT
    #---------------------------------------------------------------------------
    print_header "SECTION 16: CONTAINER IMAGES AUDIT"
    
    run_check "Non-Standard Images (External Registry)" "kubectl get pod,deploy,sts,ds,job,cronjob -A -o yaml 2>/dev/null | grep -i 'image:' | egrep -vi '${IMAGE_EXCLUSION_PATTERN}' | xargs -L1 2>/dev/null | sort -u || echo 'No external images found'"
    run_check "All Unique Images in Cluster" "kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{\"\\n\"}{end}{end}' 2>/dev/null | sort -u"

    #---------------------------------------------------------------------------
    # SECTION 17: CERTIFICATES & SECRETS SUMMARY
    #---------------------------------------------------------------------------
    print_header "SECTION 17: CERTIFICATES & SECRETS SUMMARY"
    
    run_check "Certificate Resources" "kubectl get certificates -A 2>/dev/null || echo 'Certificate CRD not found (cert-manager may not be installed)'"
    run_check "TLS Secrets Count by Namespace" "kubectl get secrets -A --field-selector type=kubernetes.io/tls --no-headers 2>/dev/null | awk '{print \$1}' | sort | uniq -c | sort -rn || echo 'No TLS secrets found'"

    #---------------------------------------------------------------------------
    # SECTION 18: CLUSTER SUMMARY
    #---------------------------------------------------------------------------
    print_header "SECTION 18: CLUSTER SUMMARY"
    
    echo "--- Quick Health Summary ---"
    echo ""
    echo "Nodes Total: $(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
    echo "Nodes Ready: $(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')"
    echo "Pods Total: $(kubectl get pods -A --no-headers 2>/dev/null | wc -l)"
    echo "Pods Running: $(kubectl get pods -A --no-headers 2>/dev/null | grep -c Running)"
    echo "Pods Not Running: $(kubectl get pods -A --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l)"
    echo "Deployments Total: $(kubectl get deploy -A --no-headers 2>/dev/null | wc -l)"
    echo "DaemonSets Total: $(kubectl get ds -A --no-headers 2>/dev/null | wc -l)"
    echo "Services Total: $(kubectl get svc -A --no-headers 2>/dev/null | wc -l)"
    echo "PVCs Total: $(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)"
    echo "Namespaces: $(kubectl get ns --no-headers 2>/dev/null | wc -l)"
    echo "Helm Releases: $(helm list -A --no-headers 2>/dev/null | wc -l || echo '0')"
    echo ""
    
    print_header "HEALTH CHECK COMPLETED"
    echo "Check Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    
} > "${OUTPUT_FILE}" 2>&1

# Create/update latest symlink
ln -sf "$(basename "${OUTPUT_FILE}")" "${LATEST_POST_LINK}"

progress "Post-change data collected. Starting comparison..."

#===============================================================================
# COMPARISON SECTION
#===============================================================================

{
    echo "================================================================================"
    echo "  KUBERNETES CLUSTER HEALTH CHECK - COMPARISON REPORT"
    echo "================================================================================"
    echo ""
    echo "Cluster:          ${CLUSTER_NAME}"
    echo "Pre-Change File:  ${PRE_CHANGE_FILE}"
    echo "Post-Change File: ${OUTPUT_FILE}"
    echo "Comparison Time:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Environment:      VMware Cloud Foundation 5.2.1 / VKS 3.3.3"
    echo ""
    echo "================================================================================"
    echo ""

    #---------------------------------------------------------------------------
    # CRITICAL CHECKS - Immediate attention needed
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                        CRITICAL HEALTH INDICATORS                        #"
    echo "############################################################################"
    echo ""
    
    # Node status comparison
    echo ">>> NODE STATUS CHANGES <<<"
    echo ""
    PRE_NODES=$(grep -A 100 "^--- All Nodes ---" "${PRE_CHANGE_FILE}" | grep -E "^[a-zA-Z0-9]" | head -20)
    POST_NODES=$(grep -A 100 "^--- All Nodes ---" "${OUTPUT_FILE}" | grep -E "^[a-zA-Z0-9]" | head -20)
    
    PRE_NODE_COUNT=$(echo "${PRE_NODES}" | grep -v "^$" | wc -l)
    POST_NODE_COUNT=$(echo "${POST_NODES}" | grep -v "^$" | wc -l)
    
    echo "Pre-Change Node Count:  ${PRE_NODE_COUNT}"
    echo "Post-Change Node Count: ${POST_NODE_COUNT}"
    
    if [ "${PRE_NODE_COUNT}" != "${POST_NODE_COUNT}" ]; then
        echo "[CHANGE] Node count changed from ${PRE_NODE_COUNT} to ${POST_NODE_COUNT}"
    fi
    
    # Check for NotReady nodes
    POST_NOTREADY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" || true)
    if [ -n "${POST_NOTREADY}" ]; then
        echo ""
        echo "[CRITICAL] Nodes NOT Ready:"
        echo "${POST_NOTREADY}"
    else
        echo "[OK] All nodes are Ready"
    fi
    echo ""
    
    # Pod status comparison
    echo ">>> POD STATUS CHANGES <<<"
    echo ""
    PRE_NONRUNNING=$(grep -A 50 "^--- Non-Running Pods" "${PRE_CHANGE_FILE}" | grep -v "^---" | grep -v "^Command:" | grep -v "^Output:" | grep -v "^$" | head -30)
    POST_NONRUNNING=$(kubectl get pod -A 2>/dev/null | grep -vi running | grep -vi completed || echo "All pods Running/Completed")
    
    echo "Pre-Change Non-Running Pods:"
    echo "${PRE_NONRUNNING:-None}"
    echo ""
    echo "Post-Change Non-Running Pods:"
    echo "${POST_NONRUNNING:-None}"
    echo ""
    
    # Check for new problematic pods
    POST_CRASH=$(kubectl get pod -A 2>/dev/null | grep -i crashloop || true)
    if [ -n "${POST_CRASH}" ]; then
        echo "[CRITICAL] Pods in CrashLoopBackOff:"
        echo "${POST_CRASH}"
    fi
    
    POST_PENDING=$(kubectl get pod -A 2>/dev/null | grep -i pending || true)
    if [ -n "${POST_PENDING}" ]; then
        echo "[WARNING] Pods in Pending state:"
        echo "${POST_PENDING}"
    fi
    echo ""
    
    #---------------------------------------------------------------------------
    # VERSION CHANGES (Expected during VKR upgrades)
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                          VERSION CHANGES                                 #"
    echo "############################################################################"
    echo ""
    
    echo ">>> KUBERNETES VERSION <<<"
    PRE_VERSION=$(grep -A 5 "Kubernetes Version" "${PRE_CHANGE_FILE}" | grep -i "server version" | head -1 || echo "Not found")
    POST_VERSION=$(kubectl version --short 2>/dev/null | grep -i server || kubectl version 2>/dev/null | grep -i "Server Version" | head -1 || echo "Not found")
    echo "Pre-Change:  ${PRE_VERSION}"
    echo "Post-Change: ${POST_VERSION}"
    echo ""
    
    echo ">>> CONTAINER IMAGE CHANGES <<<"
    echo "(Comparing unique images - changes expected during upgrades)"
    echo ""
    
    # Extract unique images from both files
    PRE_IMAGES=$(grep -A 1000 "All Unique Images in Cluster" "${PRE_CHANGE_FILE}" | grep -v "^---" | grep -v "^Command:" | grep -v "^Output:" | grep -v "^$" | grep -v "^===" | head -100 | sort -u)
    POST_IMAGES=$(kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | sort -u)
    
    # Find new images
    NEW_IMAGES=$(comm -13 <(echo "${PRE_IMAGES}" | sort) <(echo "${POST_IMAGES}" | sort) 2>/dev/null || true)
    REMOVED_IMAGES=$(comm -23 <(echo "${PRE_IMAGES}" | sort) <(echo "${POST_IMAGES}" | sort) 2>/dev/null || true)
    
    if [ -n "${NEW_IMAGES}" ]; then
        echo "New Images Added:"
        echo "${NEW_IMAGES}" | sed 's/^/  + /'
    fi
    echo ""
    if [ -n "${REMOVED_IMAGES}" ]; then
        echo "Images Removed:"
        echo "${REMOVED_IMAGES}" | sed 's/^/  - /'
    fi
    echo ""
    
    #---------------------------------------------------------------------------
    # WORKLOAD CHANGES
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                         WORKLOAD CHANGES                                 #"
    echo "############################################################################"
    echo ""
    
    echo ">>> DEPLOYMENT STATUS <<<"
    PRE_DEPLOY_COUNT=$(grep -c "^[a-zA-Z]" <(grep -A 200 "^--- All Deployments ---" "${PRE_CHANGE_FILE}" | grep -v "^---" | grep -v "^Command:" | grep -v "^Output:" | head -100) 2>/dev/null || echo "0")
    POST_DEPLOY_COUNT=$(kubectl get deploy -A --no-headers 2>/dev/null | wc -l)
    echo "Pre-Change Deployments:  ${PRE_DEPLOY_COUNT}"
    echo "Post-Change Deployments: ${POST_DEPLOY_COUNT}"
    
    DEPLOY_NOTREADY=$(kubectl get deploy -A 2>/dev/null | awk 'NR>1 && $3 != $4 {print}')
    if [ -n "${DEPLOY_NOTREADY}" ]; then
        echo ""
        echo "[WARNING] Deployments NOT fully ready:"
        echo "${DEPLOY_NOTREADY}"
    else
        echo "[OK] All deployments are ready"
    fi
    echo ""
    
    echo ">>> DAEMONSET STATUS <<<"
    DS_NOTREADY=$(kubectl get ds -A 2>/dev/null | awk 'NR>1 && $4 != $6 {print}')
    if [ -n "${DS_NOTREADY}" ]; then
        echo "[WARNING] DaemonSets NOT fully ready:"
        echo "${DS_NOTREADY}"
    else
        echo "[OK] All DaemonSets are ready"
    fi
    echo ""
    
    echo ">>> STATEFULSET STATUS <<<"
    STS_NOTREADY=$(kubectl get sts -A 2>/dev/null | awk 'NR>1 && $3 != $4 {print}' 2>/dev/null)
    if [ -n "${STS_NOTREADY}" ]; then
        echo "[WARNING] StatefulSets NOT fully ready:"
        echo "${STS_NOTREADY}"
    else
        echo "[OK] All StatefulSets are ready"
    fi
    echo ""
    
    #---------------------------------------------------------------------------
    # STORAGE CHANGES
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                         STORAGE STATUS                                   #"
    echo "############################################################################"
    echo ""
    
    PV_ISSUES=$(kubectl get pv 2>/dev/null | grep -v Bound | grep -v NAME || true)
    PVC_ISSUES=$(kubectl get pvc -A 2>/dev/null | grep -v Bound | grep -v NAME || true)
    
    if [ -n "${PV_ISSUES}" ]; then
        echo "[WARNING] PVs not in Bound state:"
        echo "${PV_ISSUES}"
    else
        echo "[OK] All PVs are Bound"
    fi
    echo ""
    
    if [ -n "${PVC_ISSUES}" ]; then
        echo "[WARNING] PVCs not in Bound state:"
        echo "${PVC_ISSUES}"
    else
        echo "[OK] All PVCs are Bound"
    fi
    echo ""
    
    #---------------------------------------------------------------------------
    # TANZU PACKAGE CHANGES
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                       TANZU PACKAGE STATUS                               #"
    echo "############################################################################"
    echo ""
    
    echo ">>> PACKAGE INSTALL STATUS <<<"
    PKGI_STATUS=$(kubectl get pkgi -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].type' --no-headers 2>/dev/null || echo "PackageInstall not available")
    
    PKGI_FAILED=$(echo "${PKGI_STATUS}" | grep -vi "Reconcile" | grep -vi "succeeded" || true)
    if [ -n "${PKGI_FAILED}" ] && [ "${PKGI_FAILED}" != "PackageInstall not available" ]; then
        echo "[WARNING] Packages not in healthy state:"
        echo "${PKGI_FAILED}"
    else
        echo "[OK] All packages reconciled successfully"
    fi
    echo ""
    kubectl get pkgi -A 2>/dev/null || echo "PackageInstall CRD not found"
    echo ""
    
    #---------------------------------------------------------------------------
    # HELM RELEASE CHANGES
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                        HELM RELEASE STATUS                               #"
    echo "############################################################################"
    echo ""
    
    HELM_FAILED=$(helm list -A --failed 2>/dev/null || true)
    if [ -n "${HELM_FAILED}" ]; then
        echo "[WARNING] Failed Helm releases:"
        echo "${HELM_FAILED}"
    else
        echo "[OK] No failed Helm releases"
    fi
    echo ""
    helm list -A 2>/dev/null || echo "Helm not available"
    echo ""
    
    #---------------------------------------------------------------------------
    # EVENTS ANALYSIS (Filtered for relevance)
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                    RELEVANT EVENTS (Post-Change)                         #"
    echo "############################################################################"
    echo ""
    echo "Note: Normal upgrade-related events (Pulling, Pulled, Created, Started,"
    echo "      Scheduled, Killing, Deleted, ScalingReplicaSet) are filtered out."
    echo ""
    
    # Get current non-normal events
    ALL_EVENTS=$(kubectl get events -A --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -50 || echo "No events found")
    
    # Filter out expected upgrade events
    RELEVANT_EVENTS=$(echo "${ALL_EVENTS}" | grep -vE "(Pulling|Pulled|Created|Started|Scheduled|SuccessfulCreate|Killing|Deleted|ScalingReplicaSet|SuccessfulDelete|NodeReady|NodeNotReady|RegisteredNode|RemovingNode|DeletingAllPods|TerminatingEvictedPod)" || true)
    
    if [ -n "${RELEVANT_EVENTS}" ]; then
        echo ">>> EVENTS REQUIRING ATTENTION <<<"
        echo ""
        echo "${RELEVANT_EVENTS}"
    else
        echo "[OK] No concerning events found (expected upgrade events filtered)"
    fi
    echo ""
    
    echo ">>> EVENT SUMMARY BY TYPE <<<"
    kubectl get events -A --field-selector type!=Normal -o custom-columns='REASON:.reason' --no-headers 2>/dev/null | sort | uniq -c | sort -rn | head -15 || echo "No events"
    echo ""
    
    #---------------------------------------------------------------------------
    # NETWORK/INGRESS STATUS
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                       NETWORK/INGRESS STATUS                             #"
    echo "############################################################################"
    echo ""
    
    echo ">>> TANZU INGRESS STATUS <<<"
    kubectl get pod -n tanzu-system-ingress 2>/dev/null || echo "tanzu-system-ingress namespace not found"
    echo ""
    kubectl get svc -n tanzu-system-ingress 2>/dev/null || echo "No services in tanzu-system-ingress"
    echo ""
    
    echo ">>> HTTPPROXY STATUS <<<"
    kubectl -n k8s-system get httpproxy 2>/dev/null || echo "HTTPProxy not found"
    echo ""
    
    # Ingress connectivity test
    HTTPPROXY_FQDN=$(kubectl -n k8s-system get httpproxy k8s-ingress-verify-httpproxy -o jsonpath="{.spec.virtualhost.fqdn}" 2>/dev/null)
    if [ -n "${HTTPPROXY_FQDN}" ]; then
        echo ">>> INGRESS CONNECTIVITY TEST <<<"
        echo "HTTPProxy FQDN: ${HTTPPROXY_FQDN}"
        
        # First try with SSL verification
        CURL_RESULT=$(curl -s --connect-timeout 10 -o /dev/null -w "%{http_code}" "https://${HTTPPROXY_FQDN}" 2>/dev/null)
        if [ -n "${CURL_RESULT}" ] && [ "${CURL_RESULT}" != "000" ]; then
            echo "HTTP Response Code: ${CURL_RESULT} (SSL verified)"
            SSL_STATUS="verified"
        else
            # Try without SSL verification
            CURL_RESULT=$(curl -sk --connect-timeout 10 -o /dev/null -w "%{http_code}" "https://${HTTPPROXY_FQDN}" 2>/dev/null || echo "FAILED")
            echo "HTTP Response Code: ${CURL_RESULT} (SSL verification skipped)"
            SSL_STATUS="skipped"
        fi
        
        if [ "${CURL_RESULT}" == "200" ] || [ "${CURL_RESULT}" == "301" ] || [ "${CURL_RESULT}" == "302" ]; then
            echo "[OK] Ingress connectivity verified"
        elif [ "${CURL_RESULT}" == "FAILED" ] || [ "${CURL_RESULT}" == "000" ]; then
            echo "[CRITICAL] Ingress connectivity FAILED - connection refused or timed out"
        else
            echo "[WARNING] Ingress may have issues (HTTP ${CURL_RESULT})"
        fi
        
        if [ "${SSL_STATUS}" == "skipped" ]; then
            echo "[INFO] SSL certificate verification failed - certificate may be self-signed"
        fi
    fi
    echo ""
    
    #---------------------------------------------------------------------------
    # TMC STATUS
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                          TMC STATUS                                      #"
    echo "############################################################################"
    echo ""
    
    TMC_PODS=$(kubectl get pods -n vmware-system-tmc 2>/dev/null || echo "TMC namespace not found")
    echo "TMC Pods:"
    echo "${TMC_PODS}"
    echo ""
    
    TMC_SECRETS=$(kubectl -n vmware-system-tmc get secrets 2>/dev/null | grep impersonation | wc -l || echo "0")
    echo "TMC Impersonation Secrets Count: ${TMC_SECRETS}"
    echo ""
    
    #---------------------------------------------------------------------------
    # SUMMARY
    #---------------------------------------------------------------------------
    echo ""
    echo "############################################################################"
    echo "#                        COMPARISON SUMMARY                                #"
    echo "############################################################################"
    echo ""
    
    # Count issues
    CRITICAL_ISSUES=0
    WARNINGS=0
    
    # Check nodes - ensure we get a clean integer
    NOTREADY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l | tr -d ' ')
    NOTREADY_NODES=${NOTREADY_NODES:-0}
    if [ "${NOTREADY_NODES}" -gt 0 ] 2>/dev/null; then
        echo "[CRITICAL] ${NOTREADY_NODES} node(s) not Ready"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
    fi
    
    # Check pods - use grep -c with proper error handling
    CRASH_PODS=$(kubectl get pod -A --no-headers 2>/dev/null | grep -ic crashloop 2>/dev/null || true)
    CRASH_PODS=${CRASH_PODS:-0}
    CRASH_PODS=$(echo "${CRASH_PODS}" | tr -d ' ')
    if [ -n "${CRASH_PODS}" ] && [ "${CRASH_PODS}" -gt 0 ] 2>/dev/null; then
        echo "[CRITICAL] ${CRASH_PODS} pod(s) in CrashLoopBackOff"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
    fi
    
    PENDING_PODS=$(kubectl get pod -A --no-headers 2>/dev/null | grep -ic pending 2>/dev/null || true)
    PENDING_PODS=${PENDING_PODS:-0}
    PENDING_PODS=$(echo "${PENDING_PODS}" | tr -d ' ')
    if [ -n "${PENDING_PODS}" ] && [ "${PENDING_PODS}" -gt 0 ] 2>/dev/null; then
        echo "[WARNING] ${PENDING_PODS} pod(s) in Pending state"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Check deployments
    NOTREADY_DEPLOYS=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '$3 != $4' | wc -l | tr -d ' ')
    NOTREADY_DEPLOYS=${NOTREADY_DEPLOYS:-0}
    if [ "${NOTREADY_DEPLOYS}" -gt 0 ] 2>/dev/null; then
        echo "[WARNING] ${NOTREADY_DEPLOYS} deployment(s) not fully ready"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Check DaemonSets
    NOTREADY_DS=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$4 != $6' | wc -l | tr -d ' ')
    NOTREADY_DS=${NOTREADY_DS:-0}
    if [ "${NOTREADY_DS}" -gt 0 ] 2>/dev/null; then
        echo "[WARNING] ${NOTREADY_DS} DaemonSet(s) not fully ready"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    echo ""
    echo "================================================================================"
    if [ "${CRITICAL_ISSUES}" -gt 0 ]; then
        echo "  RESULT: ${CRITICAL_ISSUES} CRITICAL issue(s), ${WARNINGS} warning(s) found"
        echo "  ACTION: Please investigate critical issues before proceeding"
    elif [ "${WARNINGS}" -gt 0 ]; then
        echo "  RESULT: ${WARNINGS} warning(s) found (no critical issues)"
        echo "  ACTION: Monitor warnings, may resolve during rolling update completion"
    else
        echo "  RESULT: Cluster health check PASSED"
        echo "  All components appear healthy after the change"
    fi
    echo "================================================================================"
    echo ""
    echo "Comparison completed at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    
} > "${DIFF_FILE}" 2>&1

# Create/update latest symlink for comparison
ln -sf "$(basename "${DIFF_FILE}")" "${LATEST_DIFF_LINK}"

#===============================================================================
# DISPLAY RESULTS
#===============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Health Check & Comparison Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Files generated:"
echo -e "  Post-Change Output: ${YELLOW}${OUTPUT_FILE}${NC}"
echo -e "  Comparison Report:  ${YELLOW}${DIFF_FILE}${NC}"
echo ""

# Display comparison summary on console
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}         COMPARISON SUMMARY                 ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# Quick status - ensure clean integers with proper error handling
NOTREADY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l | tr -d ' ')
NOTREADY_NODES=${NOTREADY_NODES:-0}

CRASH_PODS=$(kubectl get pod -A --no-headers 2>/dev/null | grep -ic crashloop 2>/dev/null || true)
CRASH_PODS=${CRASH_PODS:-0}
CRASH_PODS=$(echo "${CRASH_PODS}" | tr -d ' ')

PENDING_PODS=$(kubectl get pod -A --no-headers 2>/dev/null | grep -ic pending 2>/dev/null || true)
PENDING_PODS=${PENDING_PODS:-0}
PENDING_PODS=$(echo "${PENDING_PODS}" | tr -d ' ')

NOTREADY_DEPLOYS=$(kubectl get deploy -A --no-headers 2>/dev/null | awk '$3 != $4' | wc -l | tr -d ' ')
NOTREADY_DEPLOYS=${NOTREADY_DEPLOYS:-0}

if [ -n "${NOTREADY_NODES}" ] && [ "${NOTREADY_NODES}" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}[CRITICAL] ${NOTREADY_NODES} node(s) NOT Ready${NC}"
fi

if [ -n "${CRASH_PODS}" ] && [ "${CRASH_PODS}" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}[CRITICAL] ${CRASH_PODS} pod(s) in CrashLoopBackOff${NC}"
fi

if [ -n "${PENDING_PODS}" ] && [ "${PENDING_PODS}" -gt 0 ] 2>/dev/null; then
    echo -e "${YELLOW}[WARNING] ${PENDING_PODS} pod(s) in Pending state${NC}"
fi

if [ -n "${NOTREADY_DEPLOYS}" ] && [ "${NOTREADY_DEPLOYS}" -gt 0 ] 2>/dev/null; then
    echo -e "${YELLOW}[WARNING] ${NOTREADY_DEPLOYS} deployment(s) not fully ready${NC}"
fi

# Overall status - with safe integer comparison
NODES_OK=true
PODS_OK=true

if [ -n "${NOTREADY_NODES}" ] && [ "${NOTREADY_NODES}" -gt 0 ] 2>/dev/null; then
    NODES_OK=false
fi
if [ -n "${CRASH_PODS}" ] && [ "${CRASH_PODS}" -gt 0 ] 2>/dev/null; then
    PODS_OK=false
fi

if [ "${NODES_OK}" = true ] && [ "${PODS_OK}" = true ]; then
    PENDING_OK=true
    DEPLOY_OK=true
    
    if [ -n "${PENDING_PODS}" ] && [ "${PENDING_PODS}" -gt 0 ] 2>/dev/null; then
        PENDING_OK=false
    fi
    if [ -n "${NOTREADY_DEPLOYS}" ] && [ "${NOTREADY_DEPLOYS}" -gt 0 ] 2>/dev/null; then
        DEPLOY_OK=false
    fi
    
    if [ "${PENDING_OK}" = true ] && [ "${DEPLOY_OK}" = true ]; then
        echo -e "${GREEN}✓ Cluster health looks good!${NC}"
    else
        echo -e "${YELLOW}⚠ Minor issues detected - may resolve during rolling update${NC}"
    fi
else
    echo -e "${RED}✗ Critical issues detected - please investigate${NC}"
fi

echo ""
echo -e "${BLUE}To view the full comparison report:${NC}"
echo -e "  cat ${DIFF_FILE}"
echo ""
echo -e "${BLUE}To view relevant events only:${NC}"
echo -e "  grep -A 50 'EVENTS REQUIRING ATTENTION' ${DIFF_FILE}"
echo ""
