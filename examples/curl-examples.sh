#!/bin/bash
# curl-examples.sh
# Examples of using curl to interact with Consul KV API
#
# Prerequisites:
# - Set CONSUL_HTTP_ADDR environment variable
# - Set CONSUL_HTTP_TOKEN environment variable
# - Set CONSUL_NAMESPACE environment variable (for Enterprise)

# Configuration
CONSUL_ADDR="${CONSUL_HTTP_ADDR:-https://consul.example.com:8500}"
TOKEN="${CONSUL_HTTP_TOKEN}"
NAMESPACE="${CONSUL_NAMESPACE:-AIT-001}"

if [ -z "$TOKEN" ]; then
    echo "Error: CONSUL_HTTP_TOKEN environment variable not set"
    exit 1
fi

echo "Using Consul at: $CONSUL_ADDR"
echo "Using namespace: $NAMESPACE"
echo ""

# Example 1: Write a simple value
echo "=== Example 1: Write Simple Value ==="
curl -X PUT \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    -d "production" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/environment"
echo ""
echo ""

# Example 2: Write JSON data
echo "=== Example 2: Write JSON Data ==="
curl -X PUT \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    -H "Content-Type: application/json" \
    -d '{"port":8080,"debug":false,"replicas":3}' \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json"
echo ""
echo ""

# Example 3: Read a value
echo "=== Example 3: Read Value ==="
curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/environment?raw"
echo ""
echo ""

# Example 4: Read JSON data (decoded)
echo "=== Example 4: Read JSON Data ==="
curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json" | \
    jq -r '.[0].Value' | base64 -d | jq '.'
echo ""

# Example 5: List keys with prefix
echo "=== Example 5: List Keys ==="
curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/?keys" | jq '.'
echo ""

# Example 6: Get key metadata
echo "=== Example 6: Get Key Metadata ==="
curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json" | jq '.'
echo ""

# Example 7: Delete a key
echo "=== Example 7: Delete Key ==="
curl -X DELETE \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/environment"
echo ""
echo ""

# Example 8: Delete keys recursively
echo "=== Example 8: Delete Keys Recursively ==="
curl -X DELETE \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/test/?recurse"
echo ""
echo ""

# Example 9: Conditional write (CAS - Check-And-Set)
echo "=== Example 9: Conditional Write (CAS) ==="
# First, get the current modify index
MODIFY_INDEX=$(curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json" | jq -r '.[0].ModifyIndex')

echo "Current ModifyIndex: $MODIFY_INDEX"

# Then, update only if the index matches
curl -X PUT \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    -d '{"port":8080,"debug":true,"replicas":5}' \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json?cas=$MODIFY_INDEX"
echo ""
echo ""

# Example 10: Watch for changes (blocking query)
echo "=== Example 10: Watch for Changes ==="
echo "Watching ${NAMESPACE}/config/app.json for changes (press Ctrl+C to stop)..."
echo ""

# Get initial index
INITIAL_INDEX=$(curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json" | jq -r '.[0].ModifyIndex')

# Watch for changes (this will block until the key changes)
# In another terminal, modify the key to see this trigger
curl -s \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/config/app.json?index=$INITIAL_INDEX&wait=30s" | \
    jq -r '.[0].Value' | base64 -d | jq '.'
echo ""

# Example 11: Test cross-namespace access (should fail)
echo "=== Example 11: Test Cross-Namespace Access (Should Fail) ==="
curl -X PUT \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: default" \
    -d "should-fail" \
    "$CONSUL_ADDR/v1/kv/test/cross-namespace" 2>&1 | head -5
echo ""
echo ""

# Example 12: Test sensitive data blocking (should fail)
echo "=== Example 12: Test Sensitive Data Blocking (Should Fail) ==="
curl -X PUT \
    -H "X-Consul-Token: $TOKEN" \
    -H "X-Consul-Namespace: $NAMESPACE" \
    -d '{"aws_access_key":"AKIAIOSFODNN7EXAMPLE"}' \
    "$CONSUL_ADDR/v1/kv/${NAMESPACE}/test/aws-creds" 2>&1 | head -5
echo ""
echo ""

echo "=== Examples Complete ==="
echo ""
echo "For more information, see:"
echo "  - Consul KV API: https://developer.hashicorp.com/consul/api-docs/kv"
echo "  - Consul ACLs: https://developer.hashicorp.com/consul/docs/security/acl"

# Made with Bob
