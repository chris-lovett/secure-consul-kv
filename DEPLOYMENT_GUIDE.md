# Deployment Guide - Secure Consul KV Access

Step-by-step instructions for deploying ACL and Sentinel policies for Consul KV access.

## Overview

This guide walks you through:
1. Verifying prerequisites
2. Creating Consul namespaces for teams
3. Deploying ACL policies
4. Creating ACL tokens
5. Validating Sentinel policy parsing and enforcement
6. Testing the configuration
7. Configuring VMs

### Enforcement Model (Important)

- Consul ACLs enforce **who** can read/write and **which** KV paths are allowed.
- Sentinel rules are enforced through ACL policy `sentinel { ... }` stanzas on KV writes.

**Estimated Time:** 45-60 minutes

## Customer Runbook (Happy Path)

```bash
# 0) Preflight (admin auth must work)
consul acl token read -self

# 1) Namespace
consul namespace create -name AIT-001 -description "Namespace for team AIT-001"

# 2) Baseline ACL policy (known-good write rule)
consul acl policy create \
  -name "ait-001-kv-policy" \
  -namespace "AIT-001" \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'

# 3) Team token
consul acl token create \
  -description "KV access token for team AIT-001" \
  -policy-name "ait-001-kv-policy" \
  -namespace "AIT-001"

# 4) Prove ACL write works first
consul kv put -token=<team-token> -namespace=AIT-001 \
  AIT-001/config/app-mode '{"environment":"prod","port":8080}'

# 5) Enable Sentinel by updating policy from file
consul acl policy update \
  -name "ait-001-kv-policy" \
  -namespace "AIT-001" \
  -rules @acl-policies/ait-001-kv-policy.hcl

# 6) Verify rules are present (must show key_prefix + sentinel blocks)
consul acl policy read -name "ait-001-kv-policy" -namespace "AIT-001"

# 7) Validate Sentinel behavior (manual + automated)
consul kv put -token=<team-token> -namespace=AIT-001 \
  AIT-001/secrets/bad-key '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
./scripts/test-sentinel-policies.sh AIT-001 <team-token>
```

## Prerequisites Verification

### Step 1: Verify Consul Enterprise

```bash
# Check Consul version
consul version

# Expected output should show Enterprise
# Consul v1.16.0+ent
# Revision: xxxxx
# Build Date: xxxx-xx-xx

# Verify ACL policy parsing (includes Sentinel stanzas)
consul acl policy create -name validate-policy -rules @acl-policies/template-kv-policy.hcl -dry-run
```

### Step 2: Verify ACLs are Enabled

```bash
# Check ACL status
consul acl bootstrap 2>&1 | grep -q "ACL support disabled" && echo "❌ ACLs disabled - enable them first" || echo "✅ ACLs enabled"

# If ACLs are disabled, enable them in Consul configuration:
# acl {
#   enabled = true
#   default_policy = "deny"
#   enable_token_persistence = true
# }
```

### Step 3: Set Environment Variables

```bash
# Set Consul address
export CONSUL_HTTP_ADDR="https://consul.example.com:8500"

# Set your admin token
export CONSUL_HTTP_TOKEN="your-admin-token-here"

# Verify connectivity
consul members
```

### Step 4: Verify Permissions

```bash
# Check you have admin permissions
consul acl token read -self

# You should see policies that include admin or management permissions
```

## Phase 1: Create Team Namespaces (10 minutes)

### Create Namespace for Team AIT-001

```bash
# Create namespace
consul namespace create \
  -name "AIT-001" \
  -description "Namespace for team AIT-001" \
  -meta "team=AIT-001" \
  -meta "contact=team-ait-001@example.com"

# Verify namespace was created
consul namespace list | grep AIT-001
```

### Create Namespace for Team AIT-002

```bash
# Create namespace
consul namespace create \
  -name "AIT-002" \
  -description "Namespace for team AIT-002" \
  -meta "team=AIT-002" \
  -meta "contact=team-ait-002@example.com"

# Verify namespace was created
consul namespace list | grep AIT-002
```

### Verify All Namespaces

```bash
# List all namespaces
consul namespace list

# Expected output:
# default
# AIT-001
# AIT-002
```

## Phase 2: Deploy ACL Policies (15 minutes)

### Deploy Policy for Team AIT-001

```bash
# Create baseline ACL policy first (known-good write)
consul acl policy create \
  -name "ait-001-kv-policy" \
  -description "KV access policy for team AIT-001" \
  -namespace "AIT-001" \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'

# Then enable Sentinel rules by updating from file
consul acl policy update \
  -name "ait-001-kv-policy" \
  -namespace "AIT-001" \
  -rules @acl-policies/ait-001-kv-policy.hcl

# Verify policy was created
consul acl policy read -name "ait-001-kv-policy" -namespace "AIT-001"
```

### Deploy Policy for Team AIT-002

```bash
# Create ACL policy from file
consul acl policy create \
  -name "ait-002-kv-policy" \
  -description "KV access policy for team AIT-002" \
  -namespace "AIT-002" \
  -rules @acl-policies/ait-002-kv-policy.hcl

# Verify policy was created
consul acl policy read -name "ait-002-kv-policy" -namespace "AIT-002"
```

### Verify All Policies

```bash
# List policies in AIT-001 namespace
consul acl policy list -namespace "AIT-001"

# List policies in AIT-002 namespace
consul acl policy list -namespace "AIT-002"
```

## Phase 3: Create ACL Tokens (10 minutes)

### Create Token for Team AIT-001

```bash
# Create token with the policy
consul acl token create \
  -description "KV access token for team AIT-001" \
  -policy-name "ait-001-kv-policy" \
  -namespace "AIT-001" \
  -meta "team=AIT-001" \
  -meta "purpose=kv-access"

# IMPORTANT: Save the SecretID from the output!
# Example output:
# AccessorID:       12345678-1234-1234-1234-123456789012
# SecretID:         abcdef12-3456-7890-abcd-ef1234567890  ← SAVE THIS
# Description:      KV access token for team AIT-001
# ...

# Store the SecretID securely (this is the value used with -token=...)
export AIT_001_TOKEN="abcdef12-3456-7890-abcd-ef1234567890"
echo "AIT-001 Token: $AIT_001_TOKEN" >> tokens.txt
```

### Create Token for Team AIT-002

```bash
# Create token with the policy
consul acl token create \
  -description "KV access token for team AIT-002" \
  -policy-name "ait-002-kv-policy" \
  -namespace "AIT-002" \
  -meta "team=AIT-002" \
  -meta "purpose=kv-access"

# Save the SecretID
export AIT_002_TOKEN="<secret-id-from-output>"
echo "AIT-002 Token: $AIT_002_TOKEN" >> tokens.txt
```

### Verify Tokens

```bash
# Read token details for AIT-001
consul acl token read -id "$AIT_001_TOKEN"

# Read token details for AIT-002
consul acl token read -id "$AIT_002_TOKEN"
```

## Phase 4: Validate Sentinel Policy Parsing (10 minutes)

```bash
# Validate team policy parsing support
consul acl policy create \
  -name "validate-ait-001-policy" \
  -namespace "AIT-001" \
  -rules @acl-policies/ait-001-kv-policy.hcl \
  -dry-run
```

### Review Policy Files

```bash
# Review Sentinel policy examples and test data:
ls -1 sentinel-policies/
ls -1 sentinel-policies/test-cases/
```

## Phase 5: Test Configuration (15 minutes)

### Test 1: Valid KV Write (Should Succeed)

```bash
# Test with AIT-001 token
consul kv put \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/config/app.json \
  '{"environment":"production","port":8080}'

# Verify write succeeded
consul kv get \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/config/app.json

# Expected: {"environment":"production","port":8080}
```

### Test 2: Cross-Team Access (Should Fail - ACL)

```bash
# Try to write to AIT-002 namespace with AIT-001 token
consul kv put \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-002" \
  AIT-002/config/app.json \
  '{"test":"data"}'

# Expected: Permission denied error
```

### Test 3: Sentinel Conditional Rule Behavior

```bash
# Try to write AWS credentials
consul kv put \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/config/aws.json \
  '{"aws_access_key":"AKIAIOSFODNN7EXAMPLE","aws_secret_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"}'

# Expected: write denied by Sentinel (hard-mandatory)
```

### Test 4: Oversized Payload Behavior

```bash
# Create a large value (> 512 KB)
dd if=/dev/zero bs=1024 count=600 | base64 > large_value.txt

# Try to write large value
consul kv put \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/data/large.bin \
  @large_value.txt

# Expected: Sentinel policy violation or size-limit rejection

# Cleanup
rm large_value.txt
```

### Test 5: Read Access (Should Succeed)

```bash
# Read previously written data
consul kv get \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/config/app.json

# List all keys in team's prefix
consul kv get \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  -recurse \
  AIT-001/
```

## Phase 6: Configure VMs (10 minutes)

### Install Consul Agent on VM

```bash
# Download Consul Enterprise
wget https://releases.hashicorp.com/consul/1.16.0+ent/consul_1.16.0+ent_linux_amd64.zip

# Extract
unzip consul_1.16.0+ent_linux_amd64.zip

# Move to /usr/local/bin
sudo mv consul /usr/local/bin/

# Verify installation
consul version
```

### Create Consul Configuration

```bash
# Create config directory
sudo mkdir -p /etc/consul.d

# Create configuration file for AIT-001 VM
sudo tee /etc/consul.d/consul.hcl > /dev/null <<EOF
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"

# Connect to Consul cluster
retry_join = ["consul-server.consul.svc.cluster.local"]

# ACL configuration
acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens {
    agent = "$AIT_001_TOKEN"
    default = "$AIT_001_TOKEN"
  }
}

# Namespace configuration (Enterprise)
namespace = "AIT-001"

# TLS configuration (if using TLS)
# tls {
#   defaults {
#     ca_file = "/etc/consul.d/ca.pem"
#     verify_incoming = false
#     verify_outgoing = true
#   }
# }
EOF
```

### Start Consul Agent

```bash
# Create systemd service
sudo tee /etc/systemd/system/consul.service > /dev/null <<EOF
[Unit]
Description=Consul Agent
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target

[Service]
Type=simple
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Create consul user
sudo useradd --system --home /etc/consul.d --shell /bin/false consul

# Create data directory
sudo mkdir -p /opt/consul
sudo chown -R consul:consul /opt/consul /etc/consul.d

# Start service
sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl start consul

# Verify service is running
sudo systemctl status consul
```

### Test VM Access

```bash
# Test KV access from VM
consul kv put AIT-001/vm-test/hostname "$(hostname)"

# Verify write
consul kv get AIT-001/vm-test/hostname

# Test that cross-namespace access is denied
consul kv put AIT-002/test/data "should-fail" 2>&1 | grep -i "permission denied"
```

## Verification Checklist

Run through this checklist to ensure everything is configured correctly:

```bash
# 1. Namespaces exist
consul namespace list | grep -E "AIT-001|AIT-002"
# ✅ Both namespaces should be listed

# 2. ACL policies exist
consul acl policy list -namespace "AIT-001" | grep "ait-001-kv-policy"
consul acl policy list -namespace "AIT-002" | grep "ait-002-kv-policy"
# ✅ Both policies should be listed

# 3. ACL tokens exist and work
consul kv put -token="$AIT_001_TOKEN" -namespace="AIT-001" AIT-001/test "ok"
consul kv get -token="$AIT_001_TOKEN" -namespace="AIT-001" AIT-001/test
# ✅ Should write and read successfully

# 4. Sentinel policy blocks sensitive content
consul kv put -token="$AIT_001_TOKEN" -namespace="AIT-001" AIT-001/test/aws '{"aws_access_key":"AKIAIOSFODNN7EXAMPLE"}' 2>&1 | grep -Ei "sentinel|permission denied|denied"
# ✅ Should be denied

# 5. Validate namespace ACL boundaries still work as expected
consul kv put -token="$AIT_001_TOKEN" -namespace="AIT-001" AIT-001/test/acl "ok"
consul kv put -token="$AIT_001_TOKEN" -namespace="AIT-002" AIT-002/test/acl "fail" 2>&1 | grep -i "permission denied"
# ✅ First write succeeds, second is denied by ACL

# 6. Cross-namespace access is denied
consul kv put -token="$AIT_001_TOKEN" -namespace="AIT-002" \
  AIT-002/test "fail" 2>&1 | grep -i "permission denied"
# ✅ Should be denied by ACL

# 7. VM can access Consul
ssh vm-ait-001 "consul kv put AIT-001/vm-test 'success' && consul kv get AIT-001/vm-test"
# ✅ Should work from VM
```

## Troubleshooting

### Issue: ACL Policy Creation Fails

```bash
# Check if namespace exists
consul namespace list | grep AIT-001

# Check if you have admin permissions
consul acl token read -self

# Verify policy file syntax
consul acl policy create -name test -rules @acl-policies/ait-001-kv-policy.hcl -dry-run
```

### Issue: Sentinel Policy Not Enforcing

```bash
# Verify policy includes sentinel stanza
consul acl policy read -name "ait-001-kv-policy" -namespace "AIT-001"

# Re-run Sentinel policy test script
./scripts/test-sentinel-policies.sh AIT-001 "$AIT_001_TOKEN"
```

### Issue: Need to tell ACL vs Sentinel failure

Use failure signatures first:

- ACL denial: HTTP `403` with `lacks permission 'key:write'`.
- Sentinel denial: token has `key:write`, clean payload succeeds, violating payload fails (often HTTP `500`).

Run this probe pair with the same token:

```bash
# Probe A (clean payload): should succeed when ACL is correct
consul kv put \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/config/probe-ok \
  '{"ok":true}'

# Probe B (violating payload): should fail only when Sentinel is enforcing
consul kv put \
  -token="$AIT_001_TOKEN" \
  -namespace="AIT-001" \
  AIT-001/secrets/probe-bad \
  '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
```

Interpretation:

- Probe A fails with `403 key:write` -> ACL issue.
- Probe A succeeds and Probe B fails -> Sentinel enforcement is working.
- Probe A and B both succeed -> Sentinel not attached/enforced for that prefix.
- Probe A and B both fail with `403 key:write` -> ACL is blocking before Sentinel.

### Issue: key:write denied on valid AIT-001 path

```bash
# Confirm token identity and attached policies in the target namespace
consul acl token read -self -token="$AIT_001_TOKEN" -namespace="AIT-001"

# Expanded view shows effective merged rules
ACCESSOR_ID=$(consul acl token read -self -token="$AIT_001_TOKEN" -namespace="AIT-001" -format=json | jq -r '.AccessorID')
consul acl token read -expanded -accessor-id="$ACCESSOR_ID" -namespace="AIT-001"

# Confirm policy rules are not empty after update
consul acl policy read -name "ait-001-kv-policy" -namespace "AIT-001"

# If needed, reset to baseline write-only policy and re-test before Sentinel
consul acl policy update -name "ait-001-kv-policy" -namespace "AIT-001" \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'
```

### Issue: VM Cannot Connect

```bash
# Check network connectivity
nc -zv consul-server.consul.svc.cluster.local 8500

# Check token is valid
consul acl token read -id "$AIT_001_TOKEN"

# Check Consul agent logs
sudo journalctl -u consul -f

# Verify namespace configuration
consul members -namespace="AIT-001"
```

### Issue: Permission Denied on Valid Path

```bash
# Verify token has correct policy
consul acl token read -id "$AIT_001_TOKEN"

# Check policy rules
consul acl policy read -name "ait-001-kv-policy" -namespace "AIT-001"

# Test with explicit namespace
consul kv put -token="$AIT_001_TOKEN" -namespace="AIT-001" AIT-001/test "value"
```

## Cleanup (Optional)

To remove the test configuration:

```bash
# Delete test KV entries
consul kv delete -recurse -token="$AIT_001_TOKEN" -namespace="AIT-001" AIT-001/

# Delete tokens (optional - only if recreating)
consul acl token delete -id "$AIT_001_TOKEN"
consul acl token delete -id "$AIT_002_TOKEN"

# Delete policies (optional - only if recreating)
consul acl policy delete -name "ait-001-kv-policy" -namespace "AIT-001"
consul acl policy delete -name "ait-002-kv-policy" -namespace "AIT-002"

# Delete namespaces (optional - only if recreating)
consul namespace delete -name "AIT-001"
consul namespace delete -name "AIT-002"
```

## Next Steps

1. **Create additional teams:** Use the template policy to create policies for more teams
2. **Configure monitoring:** Set up audit logging and metrics collection
3. **Automate onboarding:** Use the provided scripts to automate team creation
4. **Document team-specific paths:** Create documentation for each team's KV structure
5. **Set up token rotation:** Implement regular token rotation (90 days recommended)

## Support

- [Consul ACL Documentation](https://developer.hashicorp.com/consul/docs/security/acl)
- [Sentinel ACL Policies (Enterprise)](https://developer.hashicorp.com/consul/docs/secure/acl/sentinel)
- [Consul Enterprise Features](https://developer.hashicorp.com/consul/docs/enterprise)

---

**Deployment complete!** 🎉 Your Consul KV store is now secured with ACL policies.