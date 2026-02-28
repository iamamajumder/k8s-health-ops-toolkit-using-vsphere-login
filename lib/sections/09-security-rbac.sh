#!/bin/bash
# Section 9: Security & RBAC

run_section_09_security_rbac() {
    print_header "SECTION 9: SECURITY & RBAC"

    # --- Pod Disruption Budgets ---
    # Key health signal: ALLOWED DISRUPTIONS = 0 blocks kubectl drain during maintenance/upgrades.
    # REMOVED: "Service Accounts (kube-system)" — always-present list with no health signal.
    echo ""
    echo "--- Pod Disruption Budgets ---"
    echo "Output:"
    local PDB_OUTPUT
    PDB_OUTPUT=$(kubectl get pdb -A --no-headers 2>/dev/null)
    if [ -z "$PDB_OUTPUT" ]; then
        echo "  No PodDisruptionBudgets found"
    else
        local PDB_COUNT
        PDB_COUNT=$(echo "$PDB_OUTPUT" | wc -l | tr -d ' ')
        echo "  Total PDBs: ${PDB_COUNT}"
        # Flag PDBs where ALLOWED DISRUPTIONS = 0 — these block drain/eviction.
        # Columns (kubectl get pdb -A --no-headers):
        #   NAMESPACE(1) NAME(2) MIN AVAILABLE(3) MAX UNAVAILABLE(4) ALLOWED DISRUPTIONS(5) AGE(6)
        local BLOCKING
        BLOCKING=$(echo "$PDB_OUTPUT" | awk '$5 == "0" {print "  [WARN] " $1 "/" $2 ": disruptionsAllowed=0 (blocks drain/eviction)"}')
        if [ -n "$BLOCKING" ]; then
            echo "$BLOCKING"
        else
            echo "  All PDBs allow disruptions"
        fi
        echo ""
        echo "$PDB_OUTPUT"
    fi

    # --- Cluster Role Bindings ---
    echo ""
    echo "--- Cluster Role Bindings ---"
    echo "Output:"
    local CRB_COUNT
    CRB_COUNT=$(kubectl get clusterrolebindings --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "  ClusterRoleBindings total: ${CRB_COUNT:-0}"
}

export -f run_section_09_security_rbac
