#!/bin/bash
# test-sentinel-policies.sh
# Validates Sentinel enforcement attached to key_prefix stanzas in ACL policies.
# Tests cover both the tiered sub-prefix model (secrets/ config/) and the
# baseline catch-all prefix enforcement.
#
# Usage: ./test-sentinel-policies.sh <TEAM_ID> <TOKEN>
# Example: ./test-sentinel-policies.sh AIT-001 <token-secret-id>

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

# ---------------------------------------------------------------------------
# Section 1: Baseline prefix  (TEAM_ID/)
# Covered by the catch-all key_prefix sentinel stanza.
# ---------------------------------------------------------------------------
echo -e "${BLUE}--- Section 1: Baseline prefix (${TEAM_ID}/) ---${NC}"
echo ""

run_case "Test 1: AWS key pattern blocked at baseline prefix" \
	"${TEAM_ID}/test/sentinel/aws" \
	'{"aws_access_key":"AKIAIOSFODNN7EXAMPLE"}' \
	"yes"

run_case "Test 2: Password field blocked at baseline prefix" \
	"${TEAM_ID}/test/sentinel/password" \
	'{"password":"super-secret"}' \
	"yes"

run_case "Test 3: Valid business config allowed at baseline prefix" \
	"${TEAM_ID}/test/sentinel/valid" \
	'{"environment":"prod","port":8080}' \
	"no"

echo -e "${YELLOW}Test 4: Oversized payload (>512 KB) blocked at baseline prefix${NC}"
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

# ---------------------------------------------------------------------------
# Section 2: secrets/ sub-prefix  (TEAM_ID/secrets/)
# Covered by the most-specific key_prefix sentinel stanza.
# Extra rules: no Vault tokens, no GitHub tokens, no DB connection strings,
# strict 64 KB size cap.
# ---------------------------------------------------------------------------
echo -e "${BLUE}--- Section 2: secrets/ sub-prefix (${TEAM_ID}/secrets/) ---${NC}"
echo ""

run_case "Test 5: Vault service token blocked under secrets/" \
	"${TEAM_ID}/secrets/vault-token" \
	"hvs.AQICAHiMQhZgMwaaaExampleVaultToken1234567890" \
	"yes"

run_case "Test 6: GitHub PAT blocked under secrets/" \
	"${TEAM_ID}/secrets/gh-token" \
	"ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890ab" \
	"yes"

run_case "Test 7: DB connection string blocked under secrets/" \
	"${TEAM_ID}/secrets/db-url" \
	"postgres://appuser:hunter2@db.example.com:5432/mydb" \
	"yes"

echo -e "${YELLOW}Test 8: Payload >64 KB blocked under secrets/ (stricter size cap)${NC}"
MEDIUM_VALUE=$(dd if=/dev/zero bs=1024 count=70 2>/dev/null | base64)
if consul kv put -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/secrets/oversize" "$MEDIUM_VALUE" >/dev/null 2>&1; then
	echo -e "${RED}✗ FAILED: >64 KB payload was allowed under secrets/${NC}"
	((FAILED++))
	consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "${TEAM_ID}/secrets/oversize" >/dev/null 2>&1 || true
else
	echo -e "${GREEN}✓ PASSED: >64 KB payload denied under secrets/${NC}"
	((PASSED++))
fi
echo ""

run_case "Test 9: Valid opaque secret reference allowed under secrets/" \
	"${TEAM_ID}/secrets/api-ref" \
	"vault:secret/data/ait-001/api-key" \
	"no"

# ---------------------------------------------------------------------------
# Section 3: config/ sub-prefix  (TEAM_ID/config/)
# Covered by the mid-level key_prefix sentinel stanza.
# Allows payloads up to 512 KB; blocks credentials but permits larger config.
# ---------------------------------------------------------------------------
echo -e "${BLUE}--- Section 3: config/ sub-prefix (${TEAM_ID}/config/) ---${NC}"
echo ""

run_case "Test 10: AWS key blocked under config/" \
	"${TEAM_ID}/config/app-settings" \
	'{"region":"us-east-1","access_key":"AKIAIOSFODNN7EXAMPLE"}' \
	"yes"

run_case "Test 11: Inline password blocked under config/" \
	"${TEAM_ID}/config/db-settings" \
	'{"host":"db.example.com","password":"hunter2"}' \
	"yes"

run_case "Test 12: Valid app configuration allowed under config/" \
	"${TEAM_ID}/config/feature-flags" \
	'{"dark_mode":true,"max_retries":3,"timeout_ms":5000}' \
	"no"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Sentinel Test Summary (12 tests)${NC}"
echo -e "${BLUE}  Section 1 — baseline prefix (4 tests)${NC}"
echo -e "${BLUE}  Section 2 — secrets/ sub-prefix (5 tests)${NC}"
echo -e "${BLUE}  Section 3 — config/  sub-prefix (3 tests)${NC}"
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
