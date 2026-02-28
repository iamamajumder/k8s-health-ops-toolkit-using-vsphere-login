#!/bin/bash
# Section 17: Certificates & Secrets Summary

run_section_17_certificates() {
    print_header "SECTION 17: CERTIFICATES & SECRETS SUMMARY"

    # --- TLS Secrets Summary ---
    # Count is context only — expiry check below is the real health signal.
    echo ""
    echo "--- TLS Secrets Summary ---"
    echo "Output:"
    local TLS_COUNT
    TLS_COUNT=$(kubectl get secrets -A --field-selector type=kubernetes.io/tls \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "  TLS Secrets total: ${TLS_COUNT:-0}"

    # --- Certificate Expiry Check ---
    # Decodes each TLS secret with openssl and calculates days until expiry.
    # Thresholds: CRITICAL < 7 days, WARN < 30 days, OK >= 30 days.
    # Capped at first 50 TLS secrets for performance (serial kubectl calls per secret).
    echo ""
    echo "--- Certificate Expiry Check ---"
    echo "Output:"

    if ! command -v openssl &>/dev/null; then
        echo "  openssl not available — skipping certificate expiry check"
    elif [ "${TLS_COUNT:-0}" -eq 0 ]; then
        echo "  No TLS secrets found — skipping expiry check"
    else
        local WARN_DAYS=30
        local CRITICAL_DAYS=7
        local EXPIRY_ISSUES=0

        echo "  Thresholds: WARN < ${WARN_DAYS} days | CRITICAL < ${CRITICAL_DAYS} days"
        echo ""

        while read -r NS NAME REST; do
            local CERT_DATA
            CERT_DATA=$(kubectl get secret "${NAME}" -n "${NS}" \
                -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
            [ -z "$CERT_DATA" ] && continue

            local EXPIRY
            EXPIRY=$(echo "$CERT_DATA" | base64 -d 2>/dev/null | \
                openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
            [ -z "$EXPIRY" ] && continue

            # Cross-platform date epoch parsing:
            #   GNU/Linux:  date -d "$EXPIRY" +%s
            #   BSD/macOS:  date -jf "%b %d %T %Y %Z" "$EXPIRY" +%s
            local EXPIRY_EPOCH
            EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || \
                date -jf "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null)
            [ -z "$EXPIRY_EPOCH" ] && continue

            local DAYS
            DAYS=$(( (EXPIRY_EPOCH - $(date +%s)) / 86400 ))

            if [ "$DAYS" -lt 0 ]; then
                echo "  [CRITICAL] EXPIRED:             ${NS}/${NAME}"
                echo "             Expired:             ${EXPIRY}"
                EXPIRY_ISSUES=$((EXPIRY_ISSUES + 1))
            elif [ "$DAYS" -lt "$CRITICAL_DAYS" ]; then
                echo "  [CRITICAL] ${NS}/${NAME}"
                echo "             Expires in ${DAYS} days (${EXPIRY})"
                EXPIRY_ISSUES=$((EXPIRY_ISSUES + 1))
            elif [ "$DAYS" -lt "$WARN_DAYS" ]; then
                echo "  [WARN]     ${NS}/${NAME}"
                echo "             Expires in ${DAYS} days (${EXPIRY})"
                EXPIRY_ISSUES=$((EXPIRY_ISSUES + 1))
            fi
        done < <(kubectl get secrets -A --field-selector type=kubernetes.io/tls \
            --no-headers 2>/dev/null | head -50)

        if [ "$EXPIRY_ISSUES" -eq 0 ]; then
            echo "  All certificates valid — none expiring within ${WARN_DAYS} days"
        else
            echo ""
            echo "  Total certificates with expiry issues: ${EXPIRY_ISSUES}"
        fi
        echo "  (Checked up to 50 TLS secrets)"
    fi

    # --- cert-manager Certificates ---
    # Checks cert-manager Certificate CRD resources (if cert-manager is installed).
    # READY column ($3) = True when cert is valid and up-to-date.
    echo ""
    echo "--- cert-manager Certificates ---"
    echo "Output:"
    local CERT_OUTPUT
    CERT_OUTPUT=$(kubectl get certificates -A --no-headers 2>/dev/null)
    if [ -z "$CERT_OUTPUT" ]; then
        echo "  cert-manager: not installed (no Certificate resources found)"
    else
        local CERT_TOTAL
        CERT_TOTAL=$(echo "$CERT_OUTPUT" | wc -l | tr -d ' ')
        local NOT_READY_CERTS
        NOT_READY_CERTS=$(echo "$CERT_OUTPUT" | \
            awk '$3 != "True" {print "  [WARN] " $1 "/" $2 ": NOT READY (status: " $6 ")"}')
        if [ -n "$NOT_READY_CERTS" ]; then
            echo "  [WARN] cert-manager certificates not Ready:"
            echo "$NOT_READY_CERTS"
        else
            echo "  cert-manager: ${CERT_TOTAL} certificates, all Ready"
        fi
    fi
}

export -f run_section_17_certificates
