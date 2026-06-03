#!/bin/bash
# debug-sentinel.sh
# Applies progressively more complex Sentinel rules to AIT-001/config/
# one layer at a time, testing a clean write after each step.
#
# Purpose: isolate exactly which rule (or which function) causes a denial
# on a known-good payload.
#
# Usage: ./scripts/debug-sentinel.sh <TEAM_ID> <TEAM_TOKEN> <MGMT_TOKEN>
# Example: ./scripts/debug-sentinel.sh AIT-001 "$TEAM_TOKEN" "$MGMT_TOKEN"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ $# -lt 3 ]; then
  echo -e "${RED}Usage: $0 <TEAM_ID> <TEAM_TOKEN> <MGMT_TOKEN>${NC}"
  exit 1
fi

TEAM_ID="$1"
TEAM_TOKEN="$2"
MGMT_TOKEN="$3"
NS=$(echo "$TEAM_ID" | tr '[:upper:]' '[:lower:]')
CLEAN_KEY="${TEAM_ID}/config/debug-probe"
CLEAN_VALUE='{"environment":"prod","port":8080}'
TMPDIR_POLICIES=$(mktemp -d)
trap 'rm -rf "$TMPDIR_POLICIES"' EXIT

# Apply a policy from a temp file and test a clean write
apply_and_test() {
  local step="$1"
  local desc="$2"
  local policy_hcl="$3"

  local tmpfile="${TMPDIR_POLICIES}/step-${step}.hcl"
  printf '%s' "$policy_hcl" > "$tmpfile"

  echo -e "${BLUE}--- Step ${step}: ${desc} ---${NC}"

  consul acl policy update \
    -token="$MGMT_TOKEN" \
    -name "${NS}-kv-policy" \
    -namespace "$NS" \
    -rules "@${tmpfile}" >/dev/null 2>&1

  set +e
  OUTPUT=$(consul kv put \
    -token="$TEAM_TOKEN" \
    -namespace="$NS" \
    "$CLEAN_KEY" \
    "$CLEAN_VALUE" 2>&1)
  RC=$?
  set -e

  if [ $RC -eq 0 ]; then
    echo -e "${GREEN}  ✓ PASS — clean write allowed${NC}"
    echo ""
    return 0
  else
    echo -e "${RED}  ✗ FAIL — clean write denied${NC}"
    echo -e "${RED}  Output: ${OUTPUT}${NC}"
    echo ""
    echo -e "${YELLOW}  ↳ The rule added in this step is the culprit.${NC}"
    echo -e "${YELLOW}  ↳ Restoring ACL-only baseline so subsequent tests are not blocked...${NC}"
    consul acl policy update \
      -token="$MGMT_TOKEN" \
      -name "${NS}-kv-policy" \
      -namespace "$NS" \
      -rules "key_prefix \"${TEAM_ID}/\" { policy = \"write\" }" >/dev/null 2>&1
    echo ""
    return 1
  fi
}

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Sentinel Rule Isolation Debug Script${NC}"
echo -e "${BLUE}Team: ${TEAM_ID}  Namespace: ${NS}${NC}"
echo -e "${BLUE}Clean probe key: ${CLEAN_KEY}${NC}"
echo -e "${BLUE}Clean probe value: ${CLEAN_VALUE}${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# --------------------------------------------------------------------------
# Step 1: trivially true — confirms Sentinel engine runs at all
# --------------------------------------------------------------------------
apply_and_test 1 "main = rule { true }  (Sentinel engine baseline)" \
'key_prefix "'"${TEAM_ID}"'/config/" {
  policy = "write"
  sentinel {
    code = "main = rule { true }"
    enforcementlevel = "hard-mandatory"
  }
}
key_prefix "'"${TEAM_ID}"'/" { policy = "write" }' || exit 1

# --------------------------------------------------------------------------
# Step 2: within_size only — no strings import needed
# --------------------------------------------------------------------------
apply_and_test 2 "within_size rule only (no import)" \
'key_prefix "'"${TEAM_ID}"'/config/" {
  policy = "write"
  sentinel {
    code = <<EOF
within_size = rule { length(value) <= 524288 }
main = rule { within_size }
EOF
    enforcementlevel = "hard-mandatory"
  }
}
key_prefix "'"${TEAM_ID}"'/" { policy = "write" }' || exit 1

# --------------------------------------------------------------------------
# Step 3: strings import with has_prefix / has_suffix only
# (confirmed working in unit tests)
# --------------------------------------------------------------------------
apply_and_test 3 "import strings — has_prefix / has_suffix only" \
'key_prefix "'"${TEAM_ID}"'/config/" {
  policy = "write"
  sentinel {
    code = <<EOF
import "strings"

no_vault_prefix = rule { not strings.has_prefix(value, "hvs.") }

main = rule { no_vault_prefix }
EOF
    enforcementlevel = "hard-mandatory"
  }
}
key_prefix "'"${TEAM_ID}"'/" { policy = "write" }' || exit 1

# --------------------------------------------------------------------------
# Step 4: strings.contains — the suspect function
# If this fails on a clean value, strings.contains does not exist
# in Sentinel v0.16.0 or causes a runtime error.
# --------------------------------------------------------------------------
apply_and_test 4 "strings.contains (suspect — may not exist in v0.16.0)" \
'key_prefix "'"${TEAM_ID}"'/config/" {
  policy = "write"
  sentinel {
    code = <<EOF
import "strings"

no_aws = rule { not strings.contains(value, "AKIA") }

main = rule { no_aws }
EOF
    enforcementlevel = "hard-mandatory"
  }
}
key_prefix "'"${TEAM_ID}"'/" { policy = "write" }' || {
  echo -e "${YELLOW}strings.contains failed. Testing native Sentinel 'in' operator as replacement...${NC}"
  echo ""

  # Step 4b: native 'in' operator (no import needed for substring check)
  apply_and_test "4b" "native 'in' operator for substring check (no import)" \
'key_prefix "'"${TEAM_ID}"'/config/" {
  policy = "write"
  sentinel {
    code = <<EOF
no_aws = rule { not ("AKIA" in value) }

main = rule { no_aws }
EOF
    enforcementlevel = "hard-mandatory"
  }
}
key_prefix "'"${TEAM_ID}"'/" { policy = "write" }' || exit 1

  echo -e "${YELLOW}Result: strings.contains is NOT available. Use native 'in' operator instead.${NC}"
  echo -e "${YELLOW}Run: consul acl policy update ... -rules @acl-policies/ait-001-kv-policy.hcl${NC}"
  echo -e "${YELLOW}after the policy files are updated to use 'in' instead of strings.contains.${NC}"
  exit 0
}

# --------------------------------------------------------------------------
# Step 5: all config/ rules using strings.contains (full policy stanza)
# --------------------------------------------------------------------------
apply_and_test 5 "full AIT-001/config/ stanza (all rules, strings.contains)" \
'key_prefix "'"${TEAM_ID}"'/config/" {
  policy = "write"
  sentinel {
    code = <<EOF
import "strings"

no_aws_keys = rule {
  not strings.contains(value, "AKIA") and
  not strings.contains(value, "ASIA")
}

no_private_keys = rule {
  not strings.contains(value, "BEGIN RSA PRIVATE KEY") and
  not strings.contains(value, "BEGIN PRIVATE KEY")
}

no_passwords = rule {
  not strings.contains(value, "password=") and
  not strings.contains(value, "\"password\":")
}

within_size = rule { length(value) <= 524288 }

main = rule {
  no_aws_keys and
  no_private_keys and
  no_passwords and
  within_size
}
EOF
    enforcementlevel = "hard-mandatory"
  }
}
key_prefix "'"${TEAM_ID}"'/" { policy = "write" }' || exit 1

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}All steps passed. strings.contains works correctly.${NC}"
echo -e "${GREEN}The issue is elsewhere — reapply the full policy file:${NC}"
echo -e "${GREEN}  consul acl policy update -name ${NS}-kv-policy -namespace ${NS} -rules @acl-policies/ait-001-kv-policy.hcl${NC}"
echo -e "${GREEN}======================================${NC}"
