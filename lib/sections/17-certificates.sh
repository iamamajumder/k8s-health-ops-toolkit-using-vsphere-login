#!/bin/bash
# Section 17: Certificates & Secrets Summary

run_section_17_certificates() {
    print_header "SECTION 17: CERTIFICATES & SECRETS SUMMARY"

    run_check "Certificate Resources" "kubectl get certificates -A 2>/dev/null || echo 'Certificate CRD not found (cert-manager may not be installed)'"
    run_check "TLS Secrets Count by Namespace" "kubectl get secrets -A --field-selector type=kubernetes.io/tls --no-headers 2>/dev/null | awk '{print \$1}' | sort | uniq -c | sort -rn || echo 'No TLS secrets found'"
}

export -f run_section_17_certificates
