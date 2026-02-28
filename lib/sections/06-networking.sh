#!/bin/bash
# Section 6: Networking

run_section_06_networking() {
    print_header "SECTION 6: NETWORKING"

    # FIX: kubectl get svc -A raw dump replaced with summary by type.
    # Large clusters can have 100+ services — full dump is noisy with no health signal.
    # LoadBalancer services are highlighted as the most operationally relevant (externally visible).

    # --- Services Summary ---
    echo ""
    echo "--- Services Summary ---"
    echo "Output:"
    local SVC_OUTPUT
    SVC_OUTPUT=$(kubectl get svc -A --no-headers 2>/dev/null)
    if [ -z "$SVC_OUTPUT" ]; then
        echo "  No Services found"
    else
        local SVC_TOTAL LB_COUNT NODEPORT_COUNT CI_COUNT EXT_COUNT
        SVC_TOTAL=$(echo "$SVC_OUTPUT" | wc -l | tr -d ' ')
        LB_COUNT=$(echo "$SVC_OUTPUT" | grep -c " LoadBalancer " || true)
        NODEPORT_COUNT=$(echo "$SVC_OUTPUT" | grep -c " NodePort " || true)
        CI_COUNT=$(echo "$SVC_OUTPUT" | grep -c " ClusterIP " || true)
        EXT_COUNT=$(echo "$SVC_OUTPUT" | grep -c " ExternalName " || true)
        echo "  Total: ${SVC_TOTAL}  (LoadBalancer: ${LB_COUNT}  NodePort: ${NODEPORT_COUNT}  ClusterIP: ${CI_COUNT}  ExternalName: ${EXT_COUNT})"
        # Show LoadBalancer services — externally visible, most operationally relevant
        # Columns (kubectl get svc -A --no-headers): NAMESPACE(1) NAME(2) TYPE(3) CLUSTER-IP(4) EXTERNAL-IP(5) PORT(S)(6) AGE(7)
        if [ "${LB_COUNT:-0}" -gt 0 ]; then
            echo ""
            echo "  LoadBalancer services:"
            echo "$SVC_OUTPUT" | grep " LoadBalancer " | \
                awk '{printf "    %-30s %-30s ext-ip=%-20s ports=%s\n", $1"/"$2, $3, $5, $6}'
        fi
    fi

    # --- tanzu-system-ingress ---
    echo ""
    echo "--- tanzu-system-ingress Namespace ---"
    echo "Output:"
    local INGRESS_PODS
    INGRESS_PODS=$(kubectl get pods -n tanzu-system-ingress --no-headers 2>/dev/null)
    if [ -z "$INGRESS_PODS" ]; then
        echo "  tanzu-system-ingress: namespace not found or no pods"
    else
        local NOT_RUNNING
        NOT_RUNNING=$(echo "$INGRESS_PODS" | grep -v " Running " || true)
        if [ -z "$NOT_RUNNING" ]; then
            local TOTAL
            TOTAL=$(echo "$INGRESS_PODS" | wc -l | tr -d ' ')
            echo "  All ${TOTAL} ingress pod(s) Running"
        else
            echo "  [WARN] Non-running ingress pods:"
            echo "$NOT_RUNNING"
        fi
    fi

    # --- HTTPProxy Resources ---
    # Checks status across all namespaces (not hardcoded to k8s-system)
    echo ""
    echo "--- HTTPProxy Resources ---"
    echo "Output:"
    local HP_OUTPUT
    HP_OUTPUT=$(kubectl get httpproxy -A --no-headers 2>/dev/null)
    if [ -z "$HP_OUTPUT" ]; then
        echo "  No HTTPProxy resources found"
    else
        local HP_TOTAL HP_INVALID
        HP_TOTAL=$(echo "$HP_OUTPUT" | wc -l | tr -d ' ')
        # Columns (kubectl get httpproxy -A --no-headers): NAMESPACE(1) NAME(2) FQDN(3) TLS-SECRET(4) STATUS(5) ...
        HP_INVALID=$(echo "$HP_OUTPUT" | awk 'tolower($5) != "valid" {print}')
        echo "  Total HTTPProxies: ${HP_TOTAL}"
        if [ -n "$HP_INVALID" ]; then
            local INV_COUNT
            INV_COUNT=$(echo "$HP_INVALID" | wc -l | tr -d ' ')
            echo "  [WARN] ${INV_COUNT} HTTPProxy resource(s) not Valid:"
            echo "$HP_INVALID"
        else
            echo "  All HTTPProxies Valid"
        fi
    fi

    # --- Ingress Resources ---
    echo ""
    echo "--- Ingress Resources ---"
    echo "Output:"
    local ING_OUTPUT
    ING_OUTPUT=$(kubectl get ingress -A --no-headers 2>/dev/null)
    if [ -z "$ING_OUTPUT" ]; then
        echo "  No Ingress resources found"
    else
        local ING_COUNT
        ING_COUNT=$(echo "$ING_OUTPUT" | wc -l | tr -d ' ')
        echo "  Total Ingresses: ${ING_COUNT}"
        echo "$ING_OUTPUT"
    fi

    # --- Network Policies ---
    echo ""
    echo "--- Network Policies ---"
    echo "Output:"
    local NP_OUTPUT
    NP_OUTPUT=$(kubectl get networkpolicy -A --no-headers 2>/dev/null)
    if [ -z "$NP_OUTPUT" ]; then
        echo "  No NetworkPolicies found"
    else
        local NP_COUNT
        NP_COUNT=$(echo "$NP_OUTPUT" | wc -l | tr -d ' ')
        echo "  Total NetworkPolicies: ${NP_COUNT}"
    fi
}

export -f run_section_06_networking
