#!/bin/bash
# test-kv-access.sh
# Tests KV access permissions for a team token
#
# Usage: ./test-kv-access.sh <TEAM_ID> <TOKEN>
# Example: ./test-kv-access.sh AIT-001 abcdef12-3456-7890-abcd-ef1234567890

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
echo -e "${BLUE}Testing KV Access for Team ${TEAM_ID}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test 1: Token validity
echo -e "${YELLOW}Test 1: Verifying token validity...${NC}"
if consul acl token read -id "$TOKEN" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Token is valid${NC}"
else
    echo -e "${RED}✗ Token is invalid or expired${NC}"
    exit 1
fi
echo ""

# Test 2: Write access to team's KV prefix
echo -e "${YELLOW}Test 2: Testing write access to ${TEAM_ID}/ prefix...${NC}"
TEST_KEY="${TEAM_ID}/test/access-test"
TEST_VALUE="test-$(date +%s)"

if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "$TEST_KEY" \
    "$TEST_VALUE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Write access: OK${NC}"
else
    echo -e "${RED}✗ Write access: FAILED${NC}"
    echo -e "${RED}  Cannot write to ${TEST_KEY}${NC}"
fi
echo ""

# Test 3: Read access to team's KV prefix
echo -e "${YELLOW}Test 3: Testing read access to ${TEAM_ID}/ prefix...${NC}"
if RESULT=$(consul kv get \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "$TEST_KEY" 2>&1); then
    if [ "$RESULT" = "$TEST_VALUE" ]; then
        echo -e "${GREEN}✓ Read access: OK${NC}"
        echo -e "${GREEN}  Value matches: $RESULT${NC}"
    else
        echo -e "${YELLOW}⚠ Read access: OK but value mismatch${NC}"
        echo -e "${YELLOW}  Expected: $TEST_VALUE${NC}"
        echo -e "${YELLOW}  Got: $RESULT${NC}"
    fi
else
    echo -e "${RED}✗ Read access: FAILED${NC}"
    echo -e "${RED}  Cannot read from ${TEST_KEY}${NC}"
fi
echo ""

# Test 4: List access to team's KV prefix
echo -e "${YELLOW}Test 4: Testing list access to ${TEAM_ID}/ prefix...${NC}"
if consul kv get \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    -keys \
    "${TEAM_ID}/" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ List access: OK${NC}"
    KEY_COUNT=$(consul kv get -token="$TOKEN" -namespace="$TEAM_ID" -keys "${TEAM_ID}/" | wc -l)
    echo -e "${GREEN}  Found $KEY_COUNT keys${NC}"
else
    echo -e "${RED}✗ List access: FAILED${NC}"
fi
echo ""

# Test 5: Cross-namespace access (should fail)
echo -e "${YELLOW}Test 5: Testing cross-namespace isolation...${NC}"
OTHER_NAMESPACE="default"
if [ "$TEAM_ID" = "default" ]; then
    OTHER_NAMESPACE="AIT-001"
fi

if consul kv put \
    -token="$TOKEN" \
    -namespace="$OTHER_NAMESPACE" \
    "test/should-fail" \
    "test" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cross-namespace isolation: FAILED${NC}"
    echo -e "${RED}  Token can write to other namespaces (security issue!)${NC}"
else
    echo -e "${GREEN}✓ Cross-namespace isolation: OK${NC}"
    echo -e "${GREEN}  Token correctly denied access to namespace: $OTHER_NAMESPACE${NC}"
fi
echo ""

# Test 6: Write to other team's prefix (should fail)
echo -e "${YELLOW}Test 6: Testing cross-team prefix isolation...${NC}"
OTHER_TEAM="AIT-999"
if [ "$TEAM_ID" = "AIT-999" ]; then
    OTHER_TEAM="AIT-001"
fi

if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "${OTHER_TEAM}/test/should-fail" \
    "test" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cross-team isolation: FAILED${NC}"
    echo -e "${RED}  Token can write to other team prefixes (security issue!)${NC}"
else
    echo -e "${GREEN}✓ Cross-team isolation: OK${NC}"
    echo -e "${GREEN}  Token correctly denied access to prefix: ${OTHER_TEAM}/${NC}"
fi
echo ""

# Test 7: Sensitive data blocking (Sentinel)
echo -e "${YELLOW}Test 7: Testing Sentinel sensitive data blocking...${NC}"
SENSITIVE_KEY="${TEAM_ID}/test/aws-creds"
SENSITIVE_VALUE='{"aws_access_key":"AKIAIOSFODNN7EXAMPLE","aws_secret_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}'

if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "$SENSITIVE_KEY" \
    "$SENSITIVE_VALUE" > /dev/null 2>&1; then
    echo -e "${RED}✗ Sentinel blocking: FAILED${NC}"
    echo -e "${RED}  Sensitive data was not blocked (Sentinel policy issue!)${NC}"
    # Cleanup
    consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$SENSITIVE_KEY" > /dev/null 2>&1
else
    echo -e "${GREEN}✓ Sentinel blocking: OK${NC}"
    echo -e "${GREEN}  Sensitive data correctly blocked${NC}"
fi
echo ""

# Test 8: Size limit enforcement (Sentinel)
echo -e "${YELLOW}Test 8: Testing Sentinel size limit enforcement...${NC}"
LARGE_KEY="${TEAM_ID}/test/large-value"
# Create a value larger than 512 KB
LARGE_VALUE=$(dd if=/dev/zero bs=1024 count=600 2>/dev/null | base64)

if consul kv put \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "$LARGE_KEY" \
    "$LARGE_VALUE" > /dev/null 2>&1; then
    echo -e "${RED}✗ Size limit: FAILED${NC}"
    echo -e "${RED}  Large value was not blocked (Sentinel policy issue!)${NC}"
    # Cleanup
    consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$LARGE_KEY" > /dev/null 2>&1
else
    echo -e "${GREEN}✓ Size limit: OK${NC}"
    echo -e "${GREEN}  Large value correctly blocked${NC}"
fi
echo ""

# Test 9: Delete access
echo -e "${YELLOW}Test 9: Testing delete access...${NC}"
if consul kv delete \
    -token="$TOKEN" \
    -namespace="$TEAM_ID" \
    "$TEST_KEY" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Delete access: OK${NC}"
else
    echo -e "${RED}✗ Delete access: FAILED${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Team ID:       $TEAM_ID"
echo -e "Namespace:     $TEAM_ID"
echo -e "Token:         ${TOKEN:0:8}...${TOKEN: -8}"
echo ""
echo -e "${GREEN}All tests completed!${NC}"
echo ""
echo -e "${YELLOW}Note: If any tests failed, review the ACL policies and Sentinel policies.${NC}"

# Made with Bob
