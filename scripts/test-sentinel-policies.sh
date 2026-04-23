#!/bin/bash
# test-sentinel-policies.sh
# Tests Sentinel policy enforcement with various test cases
#
# Usage: ./test-sentinel-policies.sh <TEAM_ID> <TOKEN>
# Example: ./test-sentinel-policies.sh AIT-001 abcdef12-3456-7890-abcd-ef1234567890

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Team ID and token are required${NC}"
    echo "Usage: $0 <TEAM_ID> <TOKEN>"
    echo "Example: $0 AIT-001 abcdef12-3456-7890-abcd-ef1234567890"
    exit 1
fi

TEAM_ID="$1"
TOKEN="$2"

# Check prerequisites
if ! command -v consul &> /dev/null; then
    echo -e "${RED}Error: consul CLI not found${NC}"
    exit 1
fi

if [ -z "$CONSUL_HTTP_ADDR" ]; then
    echo -e "${RED}Error: CONSUL_HTTP_ADDR environment variable not set${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Sentinel Policies${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

PASSED=0
FAILED=0

# Helper function to test sensitive data blocking
test_sensitive_data() {
    local test_name="$1"
    local key="$2"
    local value="$3"
    local should_block="$4"  # "yes" or "no"

    echo -e "${YELLOW}Testing: $test_name${NC}"

    if consul kv put \
        -token="$TOKEN" \
        -namespace="$TEAM_ID" \
        "$key" \
        "$value" > /dev/null 2>&1; then

        # Write succeeded
        if [ "$should_block" = "yes" ]; then
            echo -e "${RED}✗ FAILED: Should have been blocked but was allowed${NC}"
            ((FAILED++))
            # Cleanup
            consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$key" > /dev/null 2>&1
        else
            echo -e "${GREEN}✓ PASSED: Correctly allowed${NC}"
            ((PASSED++))
            # Cleanup
            consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$key" > /dev/null 2>&1
        fi
    else
        # Write failed
        if [ "$should_block" = "yes" ]; then
            echo -e "${GREEN}✓ PASSED: Correctly blocked${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ FAILED: Should have been allowed but was blocked${NC}"
            ((FAILED++))
        fi
    fi
    echo ""
}

echo -e "${BLUE}=== Testing Sensitive Data Blocker ===${NC}"
echo ""

# AWS Credentials
test_sensitive_data \
    "AWS Access Key" \
    "${TEAM_ID}/test/aws-1" \
    '{"aws_access_key":"AKIAIOSFODNN7EXAMPLE"}' \
    "yes"

test_sensitive_data \
    "AWS Secret Key" \
    "${TEAM_ID}/test/aws-2" \
    '{"aws_secret_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}' \
    "yes"

# GitHub Tokens
test_sensitive_data \
    "GitHub Personal Access Token" \
    "${TEAM_ID}/test/github-1" \
    '{"token":"ghp_1234567890abcdefghijklmnopqrstuv"}' \
    "yes"

# SSH Keys
test_sensitive_data \
    "SSH Private Key" \
    "${TEAM_ID}/test/ssh-1" \
    '-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdef
-----END RSA PRIVATE KEY-----' \
    "yes"

# Database Connection Strings
test_sensitive_data \
    "PostgreSQL Connection String" \
    "${TEAM_ID}/test/db-1" \
    'postgresql://user:password@localhost:5432/db' \
    "yes"

test_sensitive_data \
    "MySQL Connection String" \
    "${TEAM_ID}/test/db-2" \
    'mysql://admin:secret@db.example.com:3306/mydb' \
    "yes"

# JWT Tokens
test_sensitive_data \
    "JWT Token" \
    "${TEAM_ID}/test/jwt-1" \
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U' \
    "yes"

# API Keys
test_sensitive_data \
    "Generic API Key" \
    "${TEAM_ID}/test/api-1" \
    '{"api_key":"stripe_test_xxxxxxxxx"}' \
    "yes"

# Passwords
test_sensitive_data \
    "Password Field" \
    "${TEAM_ID}/test/pwd-1" \
    '{"password":"MySecretPassword123!"}' \
    "yes"

# PII
test_sensitive_data \
    "Social Security Number" \
    "${TEAM_ID}/test/pii-1" \
    '{"ssn":"123-45-6789"}' \
    "yes"

test_sensitive_data \
    "Credit Card Number" \
    "${TEAM_ID}/test/pii-2" \
    '{"card":"4532-1234-5678-9010"}' \
    "yes"

# Valid data (should NOT be blocked)
test_sensitive_data \
    "Valid Configuration" \
    "${TEAM_ID}/test/valid-1" \
    '{"environment":"production","port":8080,"debug":false}' \
    "no"

test_sensitive_data \
    "Valid Application Data" \
    "${TEAM_ID}/test/valid-2" \
    '{"app_name":"my-service","version":"1.0.0","replicas":3}' \
    "no"

echo -e "${BLUE}=== Testing Size Limit Policy ===${NC}"
echo ""

# Test small value (should pass)
echo -e "${YELLOW}Testing: Small value (< 512 KB)${NC}"
SMALL_VALUE='{"data":"This is a small value that should be allowed"}'
if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "${TEAM_ID}/test/size-small" \
    "$SMALL_VALUE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASSED: Small value allowed${NC}"
    ((PASSED++))
    consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/test/size-small" > /dev/null 2>&1
else
    echo -e "${RED}✗ FAILED: Small value blocked${NC}"
    ((FAILED++))
fi
echo ""

# Test medium value (should pass with warning)
echo -e "${YELLOW}Testing: Medium value (~400 KB, should warn)${NC}"
MEDIUM_VALUE=$(dd if=/dev/zero bs=1024 count=400 2>/dev/null | base64)
if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "${TEAM_ID}/test/size-medium" \
    "$MEDIUM_VALUE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASSED: Medium value allowed (may have warning)${NC}"
    ((PASSED++))
    consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/test/size-medium" > /dev/null 2>&1
else
    echo -e "${RED}✗ FAILED: Medium value blocked${NC}"
    ((FAILED++))
fi
echo ""

# Test large value (should fail)
echo -e "${YELLOW}Testing: Large value (> 512 KB)${NC}"
LARGE_VALUE=$(dd if=/dev/zero bs=1024 count=600 2>/dev/null | base64)
if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "${TEAM_ID}/test/size-large" \
    "$LARGE_VALUE" > /dev/null 2>&1; then
    echo -e "${RED}✗ FAILED: Large value allowed${NC}"
    ((FAILED++))
    consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/test/size-large" > /dev/null 2>&1
else
    echo -e "${GREEN}✓ PASSED: Large value blocked${NC}"
    ((PASSED++))
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Total Tests:   $((PASSED + FAILED))"
echo -e "${GREEN}Passed:        $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed:        $FAILED${NC}"
else
    echo -e "${GREEN}Failed:        $FAILED${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All Sentinel policy tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some Sentinel policy tests failed${NC}"
    echo -e "${YELLOW}Review the Sentinel policies and ensure they are deployed correctly${NC}"
    exit 1
fi

# Made with Bob
