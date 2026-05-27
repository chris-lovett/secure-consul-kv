# Secure Consul KV Access for VMs with ACLs and Sentinel

Customer-facing quickstart for implementing KV access controls and Sentinel policy enforcement with Consul Enterprise.

## Prerequisites

- Consul Enterprise with ACLs enabled
- Admin token exported as `CONSUL_HTTP_TOKEN`
- Consul address exported as `CONSUL_HTTP_ADDR`

## 5-Command Runbook

Use team `AIT-001` for the example.

```bash
# 1) Create namespace
consul namespace create -name AIT-001 -description "Team AIT-001 namespace"

# 2) Create ACL policy (includes Sentinel stanza)
consul acl policy create \
  -name ait-001-kv-policy \
  -namespace AIT-001 \
  -rules @acl-policies/ait-001-kv-policy.hcl

# 3) Create team token (save SecretID from output)
consul acl token create \
  -description "KV access token for team AIT-001" \
  -policy-name ait-001-kv-policy \
  -namespace AIT-001

# 4) Validate ACL behavior
./scripts/test-kv-access.sh AIT-001 <team-token>

# 5) Validate Sentinel behavior
./scripts/test-sentinel-policies.sh AIT-001 <team-token>
```

## Expected Outcomes

- Team token can read/write only under `AIT-001/` in namespace `AIT-001`.
- Cross-namespace and cross-team writes are denied.
- Sensitive payload patterns are denied by Sentinel rules.
- Oversized values are denied by Sentinel rules.

## Repo Contents

- `acl-policies/`: Team ACL policies with Sentinel stanzas
- `sentinel-policies/`: Sentinel policy examples and test cases
- `scripts/test-kv-access.sh`: ACL verification
- `scripts/test-sentinel-policies.sh`: Sentinel verification
- `DEPLOYMENT_GUIDE.md`: Full deployment and troubleshooting guide

## Next Step

Proceed to `DEPLOYMENT_GUIDE.md` for full production rollout instructions.
