#!/bin/bash
# Section 15: External Connectivity Test

run_section_15_connectivity() {
    print_header "SECTION 15: EXTERNAL CONNECTIVITY TEST"

    local httpproxy_fqdn=$(kubectl -n k8s-system get httpproxy k8s-ingress-verify-httpproxy -o jsonpath="{.spec.virtualhost.fqdn}" 2>/dev/null)
    if [ -n "${httpproxy_fqdn}" ]; then
        echo "--- HTTPProxy Ingress Test (${httpproxy_fqdn}) ---"
        echo "Testing URL: https://${httpproxy_fqdn}"
        echo ""

        echo "Attempt 1: With SSL certificate verification"
        local curl_result=$(curl -s --connect-timeout 10 -o /dev/null -w "HTTP_CODE:%{http_code} SSL_VERIFY:OK" "https://${httpproxy_fqdn}" 2>&1)
        if echo "${curl_result}" | grep -q "HTTP_CODE:"; then
            echo "Result: ${curl_result}"
            echo "Response preview:"
            curl -s --connect-timeout 10 "https://${httpproxy_fqdn}" 2>/dev/null | head -20 || echo "Could not fetch content"
        else
            echo "Result: SSL certificate verification failed"
            echo ""
            echo "Attempt 2: Skipping SSL certificate verification (-k flag)"
            local curl_result_insecure=$(curl -sk --connect-timeout 10 -o /dev/null -w "HTTP_CODE:%{http_code}" "https://${httpproxy_fqdn}" 2>&1)
            echo "Result: ${curl_result_insecure} (SSL verification skipped)"
            echo "[WARNING] SSL certificate may be self-signed or invalid"
            echo "Response preview:"
            curl -sk --connect-timeout 10 "https://${httpproxy_fqdn}" 2>/dev/null | head -20 || echo "Could not fetch content"
        fi
        echo ""
    else
        echo "--- HTTPProxy Ingress Test ---"
        echo "HTTPProxy k8s-ingress-verify-httpproxy not found in k8s-system namespace"
        echo ""
    fi
}

export -f run_section_15_connectivity
