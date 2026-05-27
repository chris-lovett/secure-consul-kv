# Secure Consul KV — Sentinel Policy Quickstart

This repo shows how to lock down Consul KV writes using **ACL policies with embedded Sentinel rules**. You will write a policy, apply it, and prove enforcement in under 10 minutes.

---

## How Sentinel fits inside an ACL policy

Sentinel code lives inside the same HCL file as your ACL rules — nested directly in the `key_prefix` stanza for the path you want to guard. There is no separate command to upload or register it; the policy file is the single source of truth for both who can write **and** what they are allowed to write.

```hcl
namespace "AIT-001" {

  key_prefix "AIT-001/secrets/" {  # ← ACL rule: who can write to this path
    policy = "write"

    sentinel {                      # ← Sentinel block: what they are allowed to write
      code = <<EOF
import "strings"

no_aws_keys = rule { not strings.contains(value, "AKIA") }
no_passwords = rule { not strings.contains(value, "password=") }

main = rule { no_aws_keys and no_passwords }
EOF
      enforcementlevel = "hard-mandatory"  # write is blocked unconditionally if main = false
    }
  }

}
```

**Three injected variables** are available inside every `sentinel { code }` block:

| Variable | Type   | Description                                      |
|----------|--------|--------------------------------------------------|
| `key`    | string | Full KV key path (e.g. `AIT-001/secrets/db-url`) |
| `value`  | string | Raw string value being written                   |
| `flags`  | int    | Optional KV integer flags field                  |

**Enforcement levels:**

| Level            | Behaviour                                           |
|------------------|-----------------------------------------------------|
| `advisory`       | Logs a warning; write proceeds                      |
| `soft-mandatory` | Blocks the write; a Consul operator can override    |
| `hard-mandatory` | Blocks the write unconditionally                    |

---

## Prerequisites

- Consul Enterprise 1.16+ with ACLs enabled
- Admin token: `export CONSUL_HTTP_TOKEN=<admin-token>`
- Cluster address: `export CONSUL_HTTP_ADDR=https://<your-consul>:8501`
- Consul CLI installed and reachable

---

## End-to-end demo

All commands below use team `AIT-001`. The policy file at
`acl-policies/ait-001-kv-policy.hcl` already contains tiered Sentinel stanzas
for `AIT-001/secrets/`, `AIT-001/config/`, and the catch-all `AIT-001/` prefix.

### Step 1 — Create the namespace

```bash
consul namespace create \
  -name AIT-001 \
  -description "Team AIT-001 namespace"
```

### Step 2 — Apply the ACL policy (Sentinel rules are inside it)

```bash
consul acl policy create \
  -name ait-001-kv-policy \
  -namespace AIT-001 \
  -rules @acl-policies/ait-001-kv-policy.hcl
```

> To update Sentinel rules later, edit the `.hcl` file and run
> `consul acl policy update -name ait-001-kv-policy -rules @acl-policies/ait-001-kv-policy.hcl`.
> No other registration step is needed.

### Step 3 — Create a team token

```bash
consul acl token create \
  -description "KV access token for team AIT-001" \
  -policy-name ait-001-kv-policy \
  -namespace AIT-001
```

Save the `SecretID` from the output — you will use it as `<team-token>` below.

### Step 4 — Prove enforcement with a manual write

Run these two writes with the team token. The first should succeed; the second should be denied.

```bash
# This write should SUCCEED — clean config value
consul kv put \
  -token=<team-token> \
  -namespace=AIT-001 \
  "AIT-001/config/app-mode" \
  '{"environment":"prod","port":8080}'

# This write should FAIL — AWS credential pattern detected
consul kv put \
  -token=<team-token> \
  -namespace=AIT-001 \
  "AIT-001/secrets/bad-key" \
  '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
```

Expected output for the second command:
```
Error writing data for key AIT-001/secrets/bad-key: Unexpected response code: 500
```
That 500 is Consul surfacing the Sentinel `hard-mandatory` denial.

### Step 5 — Run the full test suite

```bash
# 12 tests across all three sub-prefix enforcement tiers
./scripts/test-sentinel-policies.sh AIT-001 <team-token>
```

All 12 tests should pass. The suite covers:
- **Section 1** — baseline `AIT-001/` prefix: AWS key blocked, password blocked, valid config allowed, oversized payload blocked
- **Section 2** — `AIT-001/secrets/` sub-prefix: Vault token blocked, GitHub PAT blocked, DB connection string blocked, payload >64 KB blocked, opaque reference allowed
- **Section 3** — `AIT-001/config/` sub-prefix: AWS key blocked, inline password blocked, valid feature-flag config allowed

---

## Adding Sentinel rules for another team

Every team policy follows the same pattern. To onboard team `AIT-003`:

1. Copy `acl-policies/template-kv-policy.hcl` and replace every `AIT-XXX` with `AIT-003`.
2. Edit the Sentinel `code` blocks to tighten or relax rules as needed.
3. Apply:

```bash
consul namespace create -name AIT-003 -description "Team AIT-003 namespace"

consul acl policy create \
  -name ait-003-kv-policy \
  -namespace AIT-003 \
  -rules @acl-policies/ait-003-kv-policy.hcl

consul acl token create \
  -description "KV access token for team AIT-003" \
  -policy-name ait-003-kv-policy \
  -namespace AIT-003
```

Sentinel enforcement is activated the moment the policy is applied — no additional registration, no separate CLI command. Any write to a `key_prefix` stanza that contains a `sentinel { }` block is evaluated before the write is committed.

---

## Repo contents

| Path | Purpose |
|------|---------|
| `acl-policies/ait-001-kv-policy.hcl` | Team AIT-001 policy — tiered Sentinel stanzas |
| `acl-policies/ait-002-kv-policy.hcl` | Team AIT-002 policy — tiered Sentinel stanzas |
| `acl-policies/template-kv-policy.hcl` | Copy-paste template for new teams |
| `sentinel-policies/sensitive-data-blocker.sentinel` | Reference rule library (credentials, keys, connection strings) |
| `sentinel-policies/kv-size-limit.sentinel` | Reference size-limit rules |
| `scripts/test-sentinel-policies.sh` | 12-test Sentinel validation suite |
| `scripts/test-kv-access.sh` | ACL namespace/path isolation tests |
| `DEPLOYMENT_GUIDE.md` | Full production rollout and troubleshooting guide |
