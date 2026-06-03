# Secure Consul KV — Sentinel Policy Quickstart

Lock down Consul KV writes using **ACL policies with embedded Sentinel rules**. Follow the steps below to create a team namespace, apply tiered enforcement, and prove it works end-to-end.

---

## How it works

Sentinel code lives inside the same HCL file as your ACL rules — nested in the `key_prefix` stanza for the path you want to guard. The policy file is the single source of truth for both **who can write** and **what they are allowed to write**.

```hcl
key_prefix "AIT-001/secrets/" {
  policy = "write"

  sentinel {
    code = <<EOF
import "strings"

no_aws_keys = rule { not strings.contains(value, "AKIA") }
no_passwords = rule { not strings.contains(value, "password=") }

main = rule { no_aws_keys and no_passwords }
EOF
    enforcementlevel = "hard-mandatory"
  }
}
```

**Variables injected into every `sentinel { code }` block:**

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

- Consul Enterprise 1.16+ with ACLs enabled (`default_policy = "deny"`)
- Admin (management) token
- Consul CLI installed

```bash
export CONSUL_HTTP_ADDR="https://<your-consul-addr>:8501"
export CONSUL_HTTP_TOKEN="<admin-token>"

# Verify connectivity and admin auth
consul members
consul acl token read -self
```

If either command fails, fix your environment variables before continuing.

---

## Step 1 — Create the team namespace

```bash
consul namespace create \
  -name ait-001 \
  -description "Namespace for team AIT-001"
```

If the namespace already exists, continue to Step 2.

---

## Step 2 — Create a baseline ACL policy (no Sentinel yet)

Start with a minimal write rule to confirm ACL wiring works before introducing Sentinel.

```bash
consul acl policy create \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'
```

If the policy already exists, update it back to the baseline:

```bash
consul acl policy update \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'
```

---

## Step 3 — Create a team token

```bash
consul acl token create \
  -description "KV access token for team AIT-001" \
  -policy-name ait-001-kv-policy \
  -namespace ait-001
```

Save the `SecretID` from the output — this is your team token for all commands below.

```bash
export TEAM_TOKEN="<SecretID from above>"
```

---

## Step 4 — Confirm ACL write works

```bash
consul kv put \
  -token="$TEAM_TOKEN" \
  -namespace=ait-001 \
  AIT-001/config/probe-ok \
  '{"ok":true}'
```

Expected: `Success! Data written to: AIT-001/config/probe-ok`

If this fails with `403 key:write`, the ACL is not wired correctly. Do not continue to Sentinel until this succeeds — see [Troubleshooting](#troubleshooting).

---

## Step 5 — Apply the full Sentinel-enabled policy

```bash
consul acl policy update \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules @acl-policies/ait-001-kv-policy.hcl
```

> **Run this from the repo root** so the `@` file path resolves correctly.

Verify the rules were applied — you should see `key_prefix "AIT-001/secrets/"`, `key_prefix "AIT-001/config/"`, and `key_prefix "AIT-001/"` blocks each with a `sentinel { ... }` stanza:

```bash
consul acl policy read \
  -name ait-001-kv-policy \
  -namespace ait-001
```

---

## Step 6 — Verify Sentinel enforcement manually

**Clean write (should succeed):**

```bash
consul kv put \
  -token="$TEAM_TOKEN" \
  -namespace=ait-001 \
  AIT-001/config/app-settings \
  '{"environment":"prod","port":8080}'
```

**Violating write (should be denied):**

```bash
consul kv put \
  -token="$TEAM_TOKEN" \
  -namespace=ait-001 \
  AIT-001/secrets/bad-key \
  '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
```

Expected: `403 Permission denied`. If both commands succeed, Sentinel is not being evaluated — check that the policy update in Step 5 persisted the `sentinel { }` stanzas.

---

## Step 7 — Run the automated test suite

```bash
./scripts/test-sentinel-policies.sh AIT-001 "$TEAM_TOKEN"
```

This runs 12 tests across three sections:

| Section | Tests | What it checks |
|---------|-------|----------------|
| Baseline prefix (`AIT-001/`) | 4 | AWS keys, passwords, oversized payloads, valid writes |
| `secrets/` sub-prefix | 5 | Vault tokens, GitHub PATs, DB connection strings, size cap, valid secret refs |
| `config/` sub-prefix | 3 | AWS keys, inline passwords, valid config |

Each deny-case first writes a clean `{"sentinel_probe":"ok"}` payload to confirm the ACL path works, then writes the violating payload and confirms it is blocked. This prevents ACL failures from being counted as Sentinel passes.

To also validate namespace isolation between teams:

```bash
./scripts/test-kv-access.sh AIT-001 "$TEAM_TOKEN"
```

---

## Troubleshooting

### ACL vs Sentinel: how to tell what failed

Both ACL denials and Sentinel denials return HTTP `403` with `lacks permission 'key:write'`. The only reliable way to distinguish them is the **probe pair**:

```bash
# Probe A — clean payload on the same key you care about
consul kv put -token="$TEAM_TOKEN" -namespace=ait-001 \
  AIT-001/config/probe-ok '{"ok":true}'

# Probe B — violating payload
consul kv put -token="$TEAM_TOKEN" -namespace=ait-001 \
  AIT-001/secrets/probe-bad '{"access_key":"AKIAIOSFODNN7EXAMPLE"}'
```

| Result | Meaning |
|--------|---------|
| Probe A fails `403 key:write` | ACL problem — fix before touching Sentinel |
| Probe A succeeds, Probe B fails | Sentinel is enforcing correctly |
| Both succeed | Sentinel not attached to that prefix — check the policy was updated from file |
| Both fail `403 key:write` | ACL is blocking before Sentinel evaluates |

### Diagnose a token

```bash
# Check which token is active and what policies it has
consul acl token read -self -token="$TEAM_TOKEN" -namespace=ait-001

# Expanded view: see the full merged effective rules
ACCESSOR_ID=$(consul acl token read -self -token="$TEAM_TOKEN" -namespace=ait-001 -format=json | jq -r '.AccessorID')
consul acl token read -expanded -accessor-id="$ACCESSOR_ID" -namespace=ait-001
```

The expanded output shows the actual `key_prefix` rules that will be evaluated. If `sentinel { }` stanzas are absent, the policy update from Step 5 did not apply correctly — re-run it.

### Policy reads back correctly but Sentinel is still not enforcing

Confirm you are running the update command from the repo root and the file exists:

```bash
pwd                                      # should be the repo root
ls acl-policies/ait-001-kv-policy.hcl   # should exist
```

### Reset to ACL-only baseline

```bash
consul acl policy update \
  -name ait-001-kv-policy \
  -namespace ait-001 \
  -rules 'key_prefix "AIT-001/" { policy = "write" }'
```

Removes all Sentinel stanzas and falls back to plain write access. Useful for isolating whether an issue is ACL or Sentinel.

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
