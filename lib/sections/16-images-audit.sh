#!/bin/bash
# Section 16: Container Images Audit

run_section_16_images_audit() {
    print_header "SECTION 16: CONTAINER IMAGES AUDIT"

    # FIX: IMAGE_EXCLUSION_PATTERN was undefined — grep -vi '' (empty pattern) matched every
    # line, filtering out ALL images and always producing zero results.
    # Fix: default exclusion pattern for standard VMware/Tanzu/k8s registries; env var override.
    #
    # FIX: previous code parsed YAML with grep -i 'image:' which also matched:
    #   imagePullPolicy, imageID, clusterImage, etc. — unreliable false matches.
    # Fix: jq with explicit .spec.containers[].image path for accurate extraction.
    local EXCLUSION_PATTERN="${IMAGE_EXCLUSION_PATTERN:-registry\.vmware\.com|projects\.registry\.vmware\.com|harbor|gcr\.io|k8s\.gcr\.io|registry\.k8s\.io|quay\.io/jetstack}"

    # Single JSON fetch — reused for both checks below
    echo ""
    echo "--- All Unique Images in Cluster ---"
    echo "Output:"
    local ALL_IMAGES
    ALL_IMAGES=$(kubectl get pods -A -o json 2>/dev/null | \
        jq -r '.items[] |
            (.spec.initContainers // [])[] .image,
            (.spec.containers // [])[] .image' 2>/dev/null | \
        sort -u)

    if [ -z "$ALL_IMAGES" ]; then
        echo "  No pods found or unable to retrieve images"
    else
        local IMAGE_COUNT
        IMAGE_COUNT=$(echo "$ALL_IMAGES" | wc -l | tr -d ' ')
        echo "  Total unique images: ${IMAGE_COUNT}"
        echo "$ALL_IMAGES" | awk '{print "  " $0}'
    fi

    echo ""
    echo "--- Non-Standard Registry Images ---"
    echo "Output:"
    if [ -z "$ALL_IMAGES" ]; then
        echo "  No images to audit"
    else
        local EXTERNAL_IMAGES
        EXTERNAL_IMAGES=$(echo "$ALL_IMAGES" | grep -viE "${EXCLUSION_PATTERN}" || true)
        if [ -z "$EXTERNAL_IMAGES" ]; then
            echo "  All images from standard/known registries"
            echo "  (Exclusion pattern: ${EXCLUSION_PATTERN})"
        else
            local EXT_COUNT
            EXT_COUNT=$(echo "$EXTERNAL_IMAGES" | wc -l | tr -d ' ')
            echo "  [INFO] ${EXT_COUNT} image(s) from non-standard registries:"
            echo "$EXTERNAL_IMAGES" | awk '{print "    " $0}'
            echo ""
            echo "  (Exclusion pattern: ${EXCLUSION_PATTERN})"
        fi
    fi
}

export -f run_section_16_images_audit
