#!/bin/bash
#===============================================================================
# Kubernetes Cluster Health Check - PRE-CHANGE Script
# Environment: VMware Cloud Foundation 5.2.1 (vSphere 8.x, NSX 4.x)
#              VKS 3.3.3, VKR 1.28.x/1.29.x
# Purpose: Capture cluster state before upgrades or rolling updates
#===============================================================================

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CLUSTER_NAME="${1:-$(kubectl config current-context 2>/dev/null | cut -d'/' -f1 || echo 'unknown-cluster')}"
OUTPUT_DIR="${2:-./k8s-healthcheck}"
OUTPUT_FILE="${OUTPUT_DIR}/${CLUSTER_NAME}_pre_change_${TIMESTAMP}.txt"
LATEST_LINK="${OUTPUT_DIR}/${CLUSTER_NAME}_pre_change_latest.txt"

# Image exclusion pattern (customize as needed)
IMAGE_EXCLUSION_PATTERN='harbor|localhost:5000|image: sha256|vmware|broadcom|dynatrace|ghcr.io/northerntrust-internal'

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

# Start health check
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Kubernetes Pre-Change Health Check${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Cluster: ${YELLOW}${CLUSTER_NAME}${NC}"
echo -e "Output:  ${YELLOW}${OUTPUT_FILE}${NC}"
echo ""

# Verify kubectl connectivity
progress "Verifying cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}[ERROR] Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Begin capturing output
{
    print_header "KUBERNETES CLUSTER HEALTH CHECK - PRE-CHANGE"
    echo "Cluster Context: ${CLUSTER_NAME}"
    echo "Check Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Environment: VMware Cloud Foundation 5.2.1 / VKS 3.3.3"
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
ln -sf "$(basename "${OUTPUT_FILE}")" "${LATEST_LINK}"

# Print completion message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Health Check Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Output saved to: ${YELLOW}${OUTPUT_FILE}${NC}"
echo -e "Latest link: ${YELLOW}${LATEST_LINK}${NC}"
echo ""

# Show quick summary
echo -e "${BLUE}Quick Summary:${NC}"
echo "  Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l) total, $(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready') ready"
echo "  Pods:  $(kubectl get pods -A --no-headers 2>/dev/null | wc -l) total, $(kubectl get pods -A --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l) not running"
echo ""

# Check for critical issues
NON_RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l)
if [ "${NON_RUNNING}" -gt 0 ]; then
    echo -e "${YELLOW}[WARNING] ${NON_RUNNING} pods are not in Running/Completed state${NC}"
fi

NODE_ISSUES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v ' Ready' | wc -l)
if [ "${NODE_ISSUES}" -gt 0 ]; then
    echo -e "${RED}[CRITICAL] ${NODE_ISSUES} nodes are not Ready${NC}"
fi

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Review the output file for any issues before proceeding with changes"
echo "  2. After making changes, run: k8s-health-check-post.sh ${CLUSTER_NAME}"
echo ""
