#!/bin/bash
#===============================================================================
# Test Script: Validate Grep Patterns
# Purpose: Ensure grep patterns work correctly and produce valid numeric output
#          Prevents the "0\n0" bug from pipefail + grep -c returning 1 on no match
# Version: 3.3
#===============================================================================

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#===============================================================================
# Test Framework
#===============================================================================

test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓ PASS${NC}: ${test_name}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    echo -e "${RED}✗ FAIL${NC}: ${test_name}"
    echo "    Expected: '${expected}'"
    echo "    Actual:   '${actual}'"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "${actual}" == "${expected}" ]]; then
        test_pass "${test_name}"
    else
        test_fail "${test_name}" "${expected}" "${actual}"
    fi
}

# Check if value is a valid integer
is_valid_integer() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

run_integer_test() {
    local test_name="$1"
    local value="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    if is_valid_integer "${value}"; then
        test_pass "${test_name}: '${value}' is valid integer"
    else
        test_fail "${test_name}" "valid integer" "'${value}'"
    fi
}

# Test arithmetic operation
run_arithmetic_test() {
    local test_name="$1"
    local value="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    # Try to use value in arithmetic
    local result
    if result=$((value + 1)) 2>/dev/null; then
        test_pass "${test_name}: '${value}' works in arithmetic"
    else
        test_fail "${test_name}" "arithmetic success" "arithmetic failed with '${value}'"
    fi
}

#===============================================================================
# Test Cases: Simulate kubectl output scenarios
#===============================================================================

echo "========================================"
echo "Grep Pattern Validation Tests"
echo "========================================"
echo ""

# Create temporary test data
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

#-------------------------------------------------------------------------------
# Test 1: grep -c with matches (normal case)
#-------------------------------------------------------------------------------
echo "--- Test Group 1: grep -c with matches ---"

echo -e "line1 Running\nline2 Running\nline3 Pending" > "${TEMP_DIR}/pods.txt"

# CORRECT pattern (what we use now)
count=$(grep -c Running "${TEMP_DIR}/pods.txt" || true)
count=$(echo "${count}" | tr -d ' \n\r')
count=${count:-0}
run_test "grep -c with 2 matches" "2" "${count}"
run_integer_test "Result is valid integer" "${count}"
run_arithmetic_test "Result works in arithmetic" "${count}"

#-------------------------------------------------------------------------------
# Test 2: grep -c with NO matches (the problematic case)
#-------------------------------------------------------------------------------
echo "--- Test Group 2: grep -c with NO matches ---"

echo -e "line1 Running\nline2 Running" > "${TEMP_DIR}/pods-no-pending.txt"

# CORRECT pattern
count=$(grep -c Pending "${TEMP_DIR}/pods-no-pending.txt" || true)
count=$(echo "${count}" | tr -d ' \n\r')
count=${count:-0}
run_test "grep -c with 0 matches (correct pattern)" "0" "${count}"
run_integer_test "Result is valid integer" "${count}"
run_arithmetic_test "Result works in arithmetic" "${count}"

# INCORRECT pattern (old bug) - demonstrates the problem
echo "--- Test Group 2b: OLD BUGGY pattern (demonstrating the bug) ---"
count_buggy=$(grep -c Pending "${TEMP_DIR}/pods-no-pending.txt" | tr -d ' ' || echo '0')
# This would produce "0\n0" on systems with pipefail
echo "  Buggy pattern output: '${count_buggy}' (may have hidden newline)"
if [[ "${count_buggy}" == "0" ]]; then
    echo -e "  ${YELLOW}Note: Bug not reproduced on this system (pipefail may not be active)${NC}"
else
    echo -e "  ${RED}Bug reproduced: got '${count_buggy}' instead of '0'${NC}"
fi

#-------------------------------------------------------------------------------
# Test 3: grep -ic (case insensitive) with NO matches
#-------------------------------------------------------------------------------
echo ""
echo "--- Test Group 3: grep -ic (case insensitive) ---"

count=$(grep -ic CrashLoopBackOff "${TEMP_DIR}/pods-no-pending.txt" || true)
count=$(echo "${count}" | tr -d ' \n\r')
count=${count:-0}
run_test "grep -ic with 0 matches" "0" "${count}"
run_integer_test "Result is valid integer" "${count}"
run_arithmetic_test "Result works in arithmetic" "${count}"

#-------------------------------------------------------------------------------
# Test 4: wc -l patterns
#-------------------------------------------------------------------------------
echo ""
echo "--- Test Group 4: wc -l patterns ---"

count=$(wc -l < "${TEMP_DIR}/pods.txt" | tr -d ' ')
count=${count:-0}
run_test "wc -l line count" "3" "${count}"
run_integer_test "Result is valid integer" "${count}"

# Empty file
echo -n "" > "${TEMP_DIR}/empty.txt"
count=$(wc -l < "${TEMP_DIR}/empty.txt" | tr -d ' ')
count=${count:-0}
run_test "wc -l empty file" "0" "${count}"
run_integer_test "Empty file result is valid integer" "${count}"

#-------------------------------------------------------------------------------
# Test 5: awk patterns (for deployments)
#-------------------------------------------------------------------------------
echo ""
echo "--- Test Group 5: awk patterns ---"

# Simulate deploy output: NAMESPACE NAME READY UP-TO-DATE AVAILABLE
echo -e "ns1 deploy1 3/3 3 3\nns2 deploy2 2/3 3 2\nns3 deploy3 1/1 1 1" > "${TEMP_DIR}/deploys.txt"

count=$(awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' "${TEMP_DIR}/deploys.txt" | tr -d ' ')
count=${count:-0}
run_test "awk not-ready deployments" "1" "${count}"
run_integer_test "Result is valid integer" "${count}"

# All ready
echo -e "ns1 deploy1 3/3 3 3\nns2 deploy2 2/2 2 2" > "${TEMP_DIR}/deploys-ready.txt"
count=$(awk '{split($3,a,"/"); if(a[1]!=a[2]) count++} END{print count+0}' "${TEMP_DIR}/deploys-ready.txt" | tr -d ' ')
count=${count:-0}
run_test "awk all deployments ready" "0" "${count}"
run_integer_test "Result is valid integer" "${count}"

#-------------------------------------------------------------------------------
# Test 6: Arithmetic with collected values
#-------------------------------------------------------------------------------
echo ""
echo "--- Test Group 6: Arithmetic operations ---"

total=100
running=95
completed=3
crashloop=1
pending=1

unaccounted=$((total - running - completed - crashloop - pending))
run_test "Unaccounted calculation" "0" "${unaccounted}"

# Test with zeros
total=0
running=0
completed=0
crashloop=0
pending=0
unaccounted=$((total - running - completed - crashloop - pending))
[ "${unaccounted}" -lt 0 ] && unaccounted=0
run_test "Unaccounted with all zeros" "0" "${unaccounted}"

#-------------------------------------------------------------------------------
# Test 7: Health module patterns (simulated)
#-------------------------------------------------------------------------------
echo ""
echo "--- Test Group 7: Health module simulation ---"

# Simulate the exact patterns from lib/health.sh

# Node ready count pattern
echo -e "node1   Ready   control-plane\nnode2   Ready   worker\nnode3   NotReady   worker" > "${TEMP_DIR}/nodes.txt"
nodes_ready=$(grep -c ' Ready' "${TEMP_DIR}/nodes.txt" || true)
nodes_ready=$(echo "${nodes_ready}" | tr -d ' \n\r')
nodes_ready=${nodes_ready:-0}
run_test "Nodes Ready pattern" "2" "${nodes_ready}"
run_arithmetic_test "Nodes Ready in arithmetic" "${nodes_ready}"

# Pod Running pattern
echo -e "ns1 pod1 Running\nns2 pod2 Running\nns3 pod3 Completed" > "${TEMP_DIR}/pod-status.txt"
pods_running=$(grep -c Running "${TEMP_DIR}/pod-status.txt" || true)
pods_running=$(echo "${pods_running}" | tr -d ' \n\r')
pods_running=${pods_running:-0}
run_test "Pods Running pattern" "2" "${pods_running}"

# CrashLoopBackOff pattern (case insensitive)
echo -e "ns1 pod1 CrashLoopBackOff\nns2 pod2 Running" > "${TEMP_DIR}/pod-crashloop.txt"
pods_crashloop=$(grep -ic CrashLoopBackOff "${TEMP_DIR}/pod-crashloop.txt" || true)
pods_crashloop=$(echo "${pods_crashloop}" | tr -d ' \n\r')
pods_crashloop=${pods_crashloop:-0}
run_test "Pods CrashLoopBackOff pattern" "1" "${pods_crashloop}"

#===============================================================================
# Summary
#===============================================================================

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Tests Run:    ${TESTS_RUN}"
echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ ${TESTS_FAILED} -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the patterns.${NC}"
    exit 1
fi
