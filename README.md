# Secure Consul KV — Sentinel Policy Quickstart

This repo shows how to lock down Consul KV writes using **ACL policies with embedded Sentinel rules**. You will write a policy, apply it, and prove enforcement.

---

## How Sentinel fits inside an ACL policy

Sentinel code lives inside the same HCL file as your ACL rules — nested directly in the `key_prefix` stanza for the path you want to guard. There is no separate command to upload or register it; the policy file is the single source of truth for both who can write **and** what they are allowed to write.

```hcl
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

All commands below use namespace `ait-001` and key path prefix `AIT-001/`.

### Step 1 — Preflight environment

```bash
echo "$CONSUL_HTTP_ADDR"
echo "${CONSUL_HTTP_TOKEN:+TOKEN_SET}"
consul acl token read -self
```

If `consul acl token read -self` fails, fix admin auth first.

### Step 2 — Create the namespace

```bash
consul namespace create \
  -name ait-001 \
  -description "Team ait-001 namespace"
```

If it already exists, continue.

### Step 3 — Create a known-good ACL baseline policy

Start with a minimal policy to prove ACL wiring before adding Sentinel complexity.

```bash
consul acl policy create \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'
```

If policy already exists:

```bash
consul acl policy update \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'
```

### Step 4 — Create a team token

```bash
consul acl token create \
  -description "KV access token for team ait-001" \
  -policy-name ait-001-kv-policy \
  -namespace ait-001
```

Save the `SecretID` as `<team-token>`.

### Step 5 — Prove ACL write works (no Sentinel yet)

```bash
consul kv put \
  -token=<team-token> \
  -namespace=ait-001 \
  "AIT-001/config/app-mode" \
  '{"environment":"prod","port":8080}'
```

Expected result: success.

### Step 6 — Apply full Sentinel-enabled policy from file

```bash
consul acl policy update \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules @acl-policies/ait-001-kv-policy.hcl
```

Immediately verify rules are present:

```bash
consul acl policy read \
  -name ait-001-kv-policy \
  -namespace ait-001
```

You should see `key_prefix "AIT-001/secrets/"`, `key_prefix "AIT-001/config/"`, and `key_prefix "AIT-001/"` blocks with `sentinel { ... }` stanzas.

### Step 7 — Prove Sentinel enforcement

Positive write (should succeed):

```bash
consul kv put \
  -token=<team-token> \
  -namespace=ait-001 \
  "AIT-001/config/app-mode" \
  '{"environment":"prod","port":8080}'
```

Negative write (should fail due to Sentinel):

```bash
consul kv put \
  -token=<team-token> \
  -namespace=ait-001 \
  "AIT-001/secrets/bad-key" \
  '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
```

The second command should be denied (typically surfaced as HTTP 500 from the KV API because Sentinel blocked the write).

### Step 8 — Run full Sentinel test suite

```bash
./scripts/test-sentinel-policies.sh ait-001 <team-token>
```

All tests should pass across baseline, `secrets/`, and `config/` sub-prefixes.

### Troubleshooting quick checks

```bash
# Confirm token is in expected namespace and has expected policy
consul acl token read -self -token=<team-token> -namespace=ait-001

# If writes fail with key:write denied, inspect effective permissions
consul acl token read -self -token=<team-token> -namespace=ait-001 -expanded
```

### ACL vs Sentinel: how to tell what failed

Use message signatures first:

- ACL denial: HTTP `403` and message contains `lacks permission 'key:write'`.
- Sentinel denial: token has confirmed `key:write` for path, clean write succeeds, policy-violating write fails (often surfaces as HTTP `500`).

Run this probe pair with the same token:

```bash
# Probe A (clean payload): should succeed when ACL is correct
consul kv put \
  -token=<team-token> \
  -namespace=ait-001 \
  AIT-001/config/probe-ok \
  '{"ok":true}'

# Probe B (policy-violating payload): should fail only when Sentinel is enforcing
consul kv put \
  -token=<team-token> \
  -namespace=ait-001 \
  AIT-001/secrets/probe-bad \
  '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
```

Interpretation:

- A fails with `403 key:write` -> ACL problem.
- A succeeds and B fails -> Sentinel is enforcing as expected.
- A and B both succeed -> Sentinel not attached/enforced for that prefix.
- A and B both fail with `403 key:write` -> ACL is blocking before Sentinel.

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
