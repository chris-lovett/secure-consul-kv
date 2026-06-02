#!/bin/bash
# test-sentinel-policies.sh
# Validates Sentinel enforcement attached to key_prefix stanzas in ACL policies.
# Tests cover both the tiered sub-prefix model (secrets/ config/) and the
# baseline catch-all prefix enforcement.
#
# Usage: ./test-sentinel-policies.sh <TEAM_ID> <TOKEN>
# Example: ./test-sentinel-policies.sh AIT-001 <token-secret-id>

set -euo pipefail

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

contains_acl_denial() {
	local msg="$1"
	local lowered
	lowered=$(echo "$msg" | tr '[:upper:]' '[:lower:]')

	if [[ "$lowered" == *"permission denied"* ]] || \
		[[ "$lowered" == *"lacks permission"* ]] || \
		[[ "$lowered" == *"http 403"* ]] || \
		[[ "$lowered" == *"403 forbidden"* ]]; then
		return 0
	fi

	return 1
}

kv_put_capture() {
	local key="$1"
	local value="$2"

	set +e
	KV_LAST_OUTPUT=$(consul kv put -token="$TOKEN" -namespace="$TEAM_ID" "$key" "$value" 2>&1)
	KV_LAST_RC=$?
	set -e
}

cleanup_key() {
	local key="$1"
	consul kv delete -token="$TOKEN" -namespace="$TEAM_ID" "$key" >/dev/null 2>&1 || true
}

# For expected Sentinel denials we first validate ACL path access with a clean payload
# on the same key. This prevents ACL denials from being counted as Sentinel passes.
run_expected_sentinel_deny_case() {
	local name="$1"
	local key="$2"
	local violating_value="$3"
	local clean_value='{"sentinel_probe":"ok"}'

	echo -e "${YELLOW}${name}${NC}"

	kv_put_capture "$key" "$clean_value"
	if [ "$KV_LAST_RC" -ne 0 ]; then
		echo -e "${RED}✗ FAILED: ACL or path setup blocked clean probe (cannot prove Sentinel)${NC}"
		echo -e "${RED}  Probe output: ${KV_LAST_OUTPUT}${NC}"
		((FAILED++))
		echo ""
		return
	fi
	cleanup_key "$key"

	kv_put_capture "$key" "$violating_value"
	if [ "$KV_LAST_RC" -eq 0 ]; then
		echo -e "${RED}✗ FAILED: violating payload was allowed${NC}"
		cleanup_key "$key"
		((FAILED++))
		echo ""
		return
	fi

	if contains_acl_denial "$KV_LAST_OUTPUT"; then
		echo -e "${RED}✗ FAILED: denial looked like ACL, not Sentinel${NC}"
		echo -e "${RED}  Output: ${KV_LAST_OUTPUT}${NC}"
		((FAILED++))
	else
		echo -e "${GREEN}✓ PASSED: clean probe allowed, violating payload denied (Sentinel enforcing)${NC}"
		((PASSED++))
	fi

	echo ""
}

run_expected_allow_case() {
	local name="$1"
	local key="$2"
	local value="$3"

	echo -e "${YELLOW}${name}${NC}"

	kv_put_capture "$key" "$value"
	if [ "$KV_LAST_RC" -eq 0 ]; then
		echo -e "${GREEN}✓ PASSED: write allowed${NC}"
		((PASSED++))
		cleanup_key "$key"
	else
		echo -e "${RED}✗ FAILED: write denied but should be allowed${NC}"
		echo -e "${RED}  Output: ${KV_LAST_OUTPUT}${NC}"
		((FAILED++))
	fi

	echo ""
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Sentinel Policy Enforcement${NC}"
echo -e "${BLUE}Team: ${TEAM_ID}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Section 1: Baseline prefix  (TEAM_ID/)
# Covered by the catch-all key_prefix sentinel stanza.
# ---------------------------------------------------------------------------
echo -e "${BLUE}--- Section 1: Baseline prefix (${TEAM_ID}/) ---${NC}"
echo ""

run_expected_sentinel_deny_case "Test 1: AWS key pattern blocked at baseline prefix" \
	"${TEAM_ID}/test/sentinel/aws" \
	'{"aws_access_key":"AKIAIOSFODNN7EXAMPLE"}'

run_expected_sentinel_deny_case "Test 2: Password field blocked at baseline prefix" \
	"${TEAM_ID}/test/sentinel/password" \
	'{"password":"super-secret"}'

run_expected_allow_case "Test 3: Valid business config allowed at baseline prefix" \
	"${TEAM_ID}/test/sentinel/valid" \
	'{"environment":"prod","port":8080}'

echo -e "${YELLOW}Test 4: Oversized payload (>512 KB) blocked at baseline prefix${NC}"
LARGE_VALUE=$(dd if=/dev/zero bs=1024 count=600 2>/dev/null | base64)
run_expected_sentinel_deny_case "Test 4: Oversized payload (>512 KB) blocked at baseline prefix" \
	"${TEAM_ID}/test/sentinel/oversize" \
	"$LARGE_VALUE"
echo ""

# ---------------------------------------------------------------------------
# Section 2: secrets/ sub-prefix  (TEAM_ID/secrets/)
# Covered by the most-specific key_prefix sentinel stanza.
# Extra rules: no Vault tokens, no GitHub tokens, no DB connection strings,
# strict 64 KB size cap.
# ---------------------------------------------------------------------------
echo -e "${BLUE}--- Section 2: secrets/ sub-prefix (${TEAM_ID}/secrets/) ---${NC}"
echo ""

run_expected_sentinel_deny_case "Test 5: Vault service token blocked under secrets/" \
	"${TEAM_ID}/secrets/vault-token" \
	"hvs.AQICAHiMQhZgMwaaaExampleVaultToken1234567890"

run_expected_sentinel_deny_case "Test 6: GitHub PAT blocked under secrets/" \
	"${TEAM_ID}/secrets/gh-token" \
	"ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890ab"

run_expected_sentinel_deny_case "Test 7: DB connection string blocked under secrets/" \
	"${TEAM_ID}/secrets/db-url" \
	"postgres://appuser:hunter2@db.example.com:5432/mydb"

echo -e "${YELLOW}Test 8: Payload >64 KB blocked under secrets/ (stricter size cap)${NC}"
MEDIUM_VALUE=$(dd if=/dev/zero bs=1024 count=70 2>/dev/null | base64)
run_expected_sentinel_deny_case "Test 8: Payload >64 KB blocked under secrets/ (stricter size cap)" \
	"${TEAM_ID}/secrets/oversize" \
	"$MEDIUM_VALUE"
echo ""

run_expected_allow_case "Test 9: Valid opaque secret reference allowed under secrets/" \
	"${TEAM_ID}/secrets/api-ref" \
	"vault:secret/data/ait-001/api-key"

# ---------------------------------------------------------------------------
# Section 3: config/ sub-prefix  (TEAM_ID/config/)
# Covered by the mid-level key_prefix sentinel stanza.
# Allows payloads up to 512 KB; blocks credentials but permits larger config.
# ---------------------------------------------------------------------------
echo -e "${BLUE}--- Section 3: config/ sub-prefix (${TEAM_ID}/config/) ---${NC}"
echo ""

run_expected_sentinel_deny_case "Test 10: AWS key blocked under config/" \
	"${TEAM_ID}/config/app-settings" \
	'{"region":"us-east-1","access_key":"AKIAIOSFODNN7EXAMPLE"}'

run_expected_sentinel_deny_case "Test 11: Inline password blocked under config/" \
	"${TEAM_ID}/config/db-settings" \
	'{"host":"db.example.com","password":"hunter2"}'

run_expected_allow_case "Test 12: Valid app configuration allowed under config/" \
	"${TEAM_ID}/config/feature-flags" \
	'{"dark_mode":true,"max_retries":3,"timeout_ms":5000}'

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
echo -e "${YELLOW}Check ACL policy sentinel stanzas, token permissions, and enforcement levels.${NC}"
exit 1
