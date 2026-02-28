#!/bin/bash
# Section 10: Component Status

run_section_10_component_status() {
    print_header "SECTION 10: COMPONENT STATUS"

    # API server health — replaces deprecated/removed `kubectl get cs` (removed in K8s 1.28)
    run_check "API Server Health (/healthz)" \
        "kubectl get --raw /healthz 2>/dev/null || echo '  [WARN] API server /healthz unreachable'"

    # Control plane pods — present on management/supervisor clusters, absent on workload clusters
    local CTRL_PODS
    CTRL_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | \
        grep -E 'etcd|kube-apiserver|kube-controller-manager|kube-scheduler')

    echo ""
    echo "--- Control Plane Pods ---"
    echo "Output:"
    if [ -z "$CTRL_PODS" ]; then
        echo "  Not found in kube-system — workload cluster (control plane managed by supervisor)"
        # Check via CAPI KubeadmControlPlane object instead
        local KCP
        KCP=$(kubectl get kubeadmcontrolplane -A --no-headers 2>/dev/null)
        if [ -n "$KCP" ]; then
            echo "  CAPI KubeadmControlPlane:"
            echo "$KCP" | awk '{printf "    %s/%s: replicas=%s initialized=%s ready=%s\n", $1,$2,$4,$5,$6}'
        else
            echo "  CAPI KubeadmControlPlane: not found"
        fi
    else
        echo "$CTRL_PODS"
    fi

    # CoreDNS
    run_check "CoreDNS Status" \
        "kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null || echo '  [WARN] CoreDNS pods not found in kube-system'"

    # kube-proxy DaemonSet
    run_check "kube-proxy DaemonSet" \
        "kubectl get ds kube-proxy -n kube-system --no-headers 2>/dev/null | awk '{printf \"  kube-proxy: %s/%s ready\n\", \$4, \$2}' || echo '  kube-proxy: not found as DaemonSet in kube-system'"

    # Metrics server — check by deployment name, not by grep
    echo ""
    echo "--- Metrics Server ---"
    echo "Output:"
    if kubectl get deployment metrics-server -n kube-system &>/dev/null 2>&1; then
        kubectl get deployment metrics-server -n kube-system --no-headers 2>/dev/null | \
            awk '{printf "  metrics-server: %s ready\n", $2}'
    else
        echo "  metrics-server: not installed"
    fi
}

export -f run_section_10_component_status
