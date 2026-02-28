#!/bin/bash
# Section 15: External Connectivity Test

run_section_15_connectivity() {
    print_header "SECTION 15: EXTERNAL CONNECTIVITY TEST"

    # FIX: previous code used -w "HTTP_CODE:%{http_code} SSL_VERIFY:OK" where SSL_VERIFY:OK
    # is hardcoded literal text in the format string — NOT the actual SSL verification result.
    # This meant Attempt 1 always reported "SSL_VERIFY:OK" even when SSL failed, and the
    # if-check `grep -q "HTTP_CODE:"` always matched (hardcoded in format string), so
    # Attempt 2 (insecure fallback) NEVER ran.
    # Fix: check curl exit code + HTTP code for actual connectivity determination.

    local httpproxy_fqdn
    httpproxy_fqdn=$(kubectl -n k8s-system get httpproxy k8s-ingress-verify-httpproxy \
        -o jsonpath="{.spec.virtualhost.fqdn}" 2>/dev/null)

    echo ""
    echo "--- HTTPProxy Ingress Test ---"
    echo "Output:"
    if [ -z "${httpproxy_fqdn}" ]; then
        echo "  HTTPProxy 'k8s-ingress-verify-httpproxy' not found in k8s-system"
        echo "  (skipping connectivity test — no test endpoint configured)"
    else
        echo "  Testing: https://${httpproxy_fqdn}"
        echo ""

        # Attempt 1: with SSL certificate verification
        local HTTP_CODE SSL_EXIT
        HTTP_CODE=$(curl -s --connect-timeout 10 -o /dev/null \
            -w "%{http_code}" "https://${httpproxy_fqdn}" 2>/dev/null)
        SSL_EXIT=$?

        if [ "$SSL_EXIT" -eq 0 ] && [ "${HTTP_CODE:-0}" -gt 0 ]; then
            echo "  [OK] Attempt 1 (SSL verify enabled): HTTP ${HTTP_CODE}"
        else
            echo "  Attempt 1 (SSL verify enabled): failed (curl_exit=${SSL_EXIT} http=${HTTP_CODE:-0})"
            echo "  [WARN] SSL certificate may be self-signed, expired, or hostname mismatch"
            echo ""

            # Attempt 2: skip SSL verification
            local HTTP_CODE_INSECURE INSECURE_EXIT
            HTTP_CODE_INSECURE=$(curl -sk --connect-timeout 10 -o /dev/null \
                -w "%{http_code}" "https://${httpproxy_fqdn}" 2>/dev/null)
            INSECURE_EXIT=$?

            if [ "$INSECURE_EXIT" -eq 0 ] && [ "${HTTP_CODE_INSECURE:-0}" -gt 0 ]; then
                echo "  [OK] Attempt 2 (SSL verify skipped): HTTP ${HTTP_CODE_INSECURE} — endpoint reachable but certificate has issues"
            else
                echo "  [WARN] Attempt 2 (SSL verify skipped): unreachable (curl_exit=${INSECURE_EXIT} http=${HTTP_CODE_INSECURE:-0})"
            fi
        fi
        echo ""
    fi
}

export -f run_section_15_connectivity
