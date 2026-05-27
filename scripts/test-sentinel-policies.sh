#!/bin/bash
# test-sentinel-policies.sh
# Tests Sentinel enforcement through ACL policy stanzas on KV writes.
#
# Usage: ./test-sentinel-policies.sh <TEAM_ID> <TOKEN>

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ $# -lt 2 ]; then
	echo -e "${RED}Error: Team ID and token are required${NC}"
	echo "Usage: $0 <TEAM_ID> <TOKEN>"
	exit 1
fi

TEAM_ID="$1"
TOKEN="$2"

if ! command -v consul >/dev/null 2>&1; then
	echo -e "${RED}Error: consul CLI not found${NC}"
	exit 1
fi

if [ -z "$CONSUL_HTTP_ADDR" ]; then
	echo -e "${RED}Error: CONSUL_HTTP_ADDR environment variable not set${NC}"
	exit 1
fi

PASSED=0
FAILED=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Sentinel Policy Enforcement${NC}"
echo -e "${BLUE}Team: ${TEAM_ID}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

run_case() {
	local name="$1"
	local key="$2"
	local value="$3"
	local expect_deny="$4"

	echo -e "${YELLOW}${name}${NC}"

	if consul kv put -token="$TOKEN" -namespace="$TEAM_ID" "$key" "$value" >/dev/null 2>&1; then
		if [ "$expect_deny" = "yes" ]; then
			echo -e "${RED}✗ FAILED: write succeeded but should be denied${NC}"
			((FAILED++))
			consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$key" >/dev/null 2>&1 || true
		else
			echo -e "${GREEN}✓ PASSED: write allowed${NC}"
			((PASSED++))
			consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$key" >/dev/null 2>&1 || true
		fi
	else
		if [ "$expect_deny" = "yes" ]; then
			echo -e "${GREEN}✓ PASSED: write denied${NC}"
			((PASSED++))
		else
			echo -e "${RED}✗ FAILED: write denied but should be allowed${NC}"
			((FAILED++))
		fi
	fi

	echo ""
}

run_case "Test 1: Sensitive pattern (AWS key)" \
	"${TEAM_ID}/test/sentinel/aws" \
	'{"aws_access_key":"AKIAIOSFODNN7EXAMPLE"}' \
	"yes"

run_case "Test 2: Sensitive pattern (password field)" \
	"${TEAM_ID}/test/sentinel/password" \
	'{"password":"super-secret"}' \
	"yes"

run_case "Test 3: Allowed business config" \
	"${TEAM_ID}/test/sentinel/valid" \
	'{"environment":"prod","port":8080}' \
	"no"

echo -e "${YELLOW}Test 4: Oversized payload (>512KB)${NC}"
LARGE_VALUE=$(dd if=/dev/zero bs=1024 count=600 2>/dev/null | base64)
if consul kv put -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/test/sentinel/oversize" "$LARGE_VALUE" >/dev/null 2>&1; then
	echo -e "${RED}✗ FAILED: oversized payload was allowed${NC}"
	((FAILED++))
	consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/test/sentinel/oversize" >/dev/null 2>&1 || true
else
	echo -e "${GREEN}✓ PASSED: oversized payload denied${NC}"
	((PASSED++))
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Sentinel Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Passed: ${PASSED}${NC}"
echo -e "${RED}Failed: ${FAILED}${NC}"

if [ $FAILED -eq 0 ]; then
	echo -e "${GREEN}All Sentinel tests passed.${NC}"
	exit 0
fi

echo -e "${RED}Some Sentinel tests failed.${NC}"
echo -e "${YELLOW}Check ACL policy sentinel stanzas and enforcement levels.${NC}"
exit 1
