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

# Test 7: Delete access
echo -e "${YELLOW}Test 7: Testing delete access...${NC}"
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
echo -e "${YELLOW}Note: This script validates ACL and namespace enforcement only.${NC}"

# Made with Bob
