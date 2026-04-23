#!/bin/bash
# create-team-namespace.sh
# Creates a complete Consul namespace setup for a new team including:
# - Namespace
# - ACL policy
# - ACL token
#
# Usage: ./create-team-namespace.sh <TEAM_ID> [CONTACT_EMAIL]
# Example: ./create-team-namespace.sh AIT-003 team-ait-003@example.com

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Team ID is required${NC}"
    echo "Usage: $0 <TEAM_ID> [CONTACT_EMAIL]"
    echo "Example: $0 AIT-003 team-ait-003@example.com"
    exit 1
fi

TEAM_ID="$1"
CONTACT_EMAIL="${2:-team-${TEAM_ID,,}@example.com}"

# Validate team ID format (AIT-XXX)
if ! [[ "$TEAM_ID" =~ ^AIT-[0-9]{3}$ ]]; then
    echo -e "${YELLOW}Warning: Team ID doesn't match expected format AIT-XXX${NC}"
    echo -e "${YELLOW}Continuing anyway...${NC}"
fi

# Check prerequisites
echo -e "${GREEN}Checking prerequisites...${NC}"

if ! command -v consul &> /dev/null; then
    echo -e "${RED}Error: consul CLI not found${NC}"
    exit 1
fi

if [ -z "$CONSUL_HTTP_ADDR" ]; then
    echo -e "${RED}Error: CONSUL_HTTP_ADDR environment variable not set${NC}"
    exit 1
fi

if [ -z "$CONSUL_HTTP_TOKEN" ]; then
    echo -e "${RED}Error: CONSUL_HTTP_TOKEN environment variable not set${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Step 1: Create namespace
echo -e "${GREEN}Step 1: Creating namespace ${TEAM_ID}...${NC}"

if consul namespace list | grep -q "^${TEAM_ID}$"; then
    echo -e "${YELLOW}Warning: Namespace ${TEAM_ID} already exists${NC}"
else
    consul namespace create \
        -name "${TEAM_ID}" \
        -description "Namespace for team ${TEAM_ID}" \
        -meta "team=${TEAM_ID}" \
        -meta "contact=${CONTACT_EMAIL}" \
        -meta "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    echo -e "${GREEN}✓ Namespace created${NC}"
fi
echo ""

# Step 2: Create ACL policy
echo -e "${GREEN}Step 2: Creating ACL policy...${NC}"

POLICY_NAME="${TEAM_ID,,}-kv-policy"
POLICY_FILE="/tmp/${POLICY_NAME}.hcl"

# Generate policy from template
cat > "$POLICY_FILE" <<EOF
# ACL Policy for Team ${TEAM_ID}
# Grants read/write access to ${TEAM_ID}/* KV paths in namespace ${TEAM_ID}

namespace "${TEAM_ID}" {
  
  # Grant read/write access to team's KV prefix
  key_prefix "${TEAM_ID}/" {
    policy = "write"
  }
  
  # Explicitly deny access to other team prefixes
  key_prefix "" {
    policy = "deny"
  }
  
  # Allow reading service catalog for service discovery
  service_prefix "" {
    policy = "read"
  }
  
  # Allow reading node information
  node_prefix "" {
    policy = "read"
  }
  
  # Allow reading prepared queries
  query_prefix "" {
    policy = "read"
  }
  
  # Deny session creation
  session_prefix "" {
    policy = "deny"
  }
  
  # Deny event creation
  event_prefix "" {
    policy = "deny"
  }
}

# Deny access to other namespaces
namespace_prefix "" {
  key_prefix "" {
    policy = "deny"
  }
}
EOF

if consul acl policy list -namespace "${TEAM_ID}" | grep -q "${POLICY_NAME}"; then
    echo -e "${YELLOW}Warning: Policy ${POLICY_NAME} already exists in namespace ${TEAM_ID}${NC}"
    echo -e "${YELLOW}Updating policy...${NC}"
    consul acl policy update \
        -name "${POLICY_NAME}" \
        -namespace "${TEAM_ID}" \
        -rules @"${POLICY_FILE}"
else
    consul acl policy create \
        -name "${POLICY_NAME}" \
        -description "KV access policy for team ${TEAM_ID}" \
        -namespace "${TEAM_ID}" \
        -rules @"${POLICY_FILE}"
fi

echo -e "${GREEN}✓ ACL policy created/updated${NC}"
echo ""

# Step 3: Create ACL token
echo -e "${GREEN}Step 3: Creating ACL token...${NC}"

TOKEN_OUTPUT=$(consul acl token create \
    -description "KV access token for team ${TEAM_ID}" \
    -policy-name "${POLICY_NAME}" \
    -namespace "${TEAM_ID}" \
    -meta "team=${TEAM_ID}" \
    -meta "purpose=kv-access" \
    -meta "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -format=json)

TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | jq -r '.SecretID')
TOKEN_ACCESSOR=$(echo "$TOKEN_OUTPUT" | jq -r '.AccessorID')

echo -e "${GREEN}✓ ACL token created${NC}"
echo ""

# Step 4: Save token to file
TOKEN_FILE="tokens/${TEAM_ID}-token.txt"
mkdir -p tokens

cat > "$TOKEN_FILE" <<EOF
Team: ${TEAM_ID}
Contact: ${CONTACT_EMAIL}
Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Namespace: ${TEAM_ID}
Policy: ${POLICY_NAME}

AccessorID: ${TOKEN_ACCESSOR}
SecretID: ${TOKEN_SECRET}

Usage:
  export CONSUL_HTTP_TOKEN="${TOKEN_SECRET}"
  export CONSUL_NAMESPACE="${TEAM_ID}"
  consul kv put ${TEAM_ID}/config/app.json '{"key":"value"}'
EOF

echo -e "${GREEN}✓ Token saved to ${TOKEN_FILE}${NC}"
echo ""

# Step 5: Test the configuration
echo -e "${GREEN}Step 4: Testing configuration...${NC}"

# Test write access
if consul kv put \
    -token="${TOKEN_SECRET}" \
    -namespace="${TEAM_ID}" \
    "${TEAM_ID}/test/setup" \
    "created-$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Write access: OK${NC}"
else
    echo -e "${RED}✗ Write access: FAILED${NC}"
fi

# Test read access
if consul kv get \
    -token="${TOKEN_SECRET}" \
    -namespace="${TEAM_ID}" \
    "${TEAM_ID}/test/setup" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Read access: OK${NC}"
else
    echo -e "${RED}✗ Read access: FAILED${NC}"
fi

# Test cross-namespace denial (should fail)
if consul kv put \
    -token="${TOKEN_SECRET}" \
    -namespace="default" \
    "test/should-fail" \
    "test" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cross-namespace isolation: FAILED (should be denied)${NC}"
else
    echo -e "${GREEN}✓ Cross-namespace isolation: OK${NC}"
fi

echo ""

# Cleanup
rm -f "$POLICY_FILE"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Team Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Team ID:       ${TEAM_ID}"
echo -e "Namespace:     ${TEAM_ID}"
echo -e "Policy:        ${POLICY_NAME}"
echo -e "Contact:       ${CONTACT_EMAIL}"
echo ""
echo -e "${YELLOW}IMPORTANT: Save this token securely!${NC}"
echo -e "Token file:    ${TOKEN_FILE}"
echo -e "AccessorID:    ${TOKEN_ACCESSOR}"
echo -e "SecretID:      ${TOKEN_SECRET}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Securely distribute the token to team ${TEAM_ID}"
echo -e "2. Configure VMs with the token"
echo -e "3. Test KV access from VMs"
echo -e "4. Document team-specific KV paths"
echo ""
echo -e "${GREEN}Done!${NC}"

# Made with Bob
