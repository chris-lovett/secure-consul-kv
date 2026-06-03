# ACL Policy for Team AIT-002
# Grants read/write access to AIT-002/* KV paths in namespace AIT-002
#
# SENTINEL ENFORCEMENT MODEL
# --------------------------
# Sentinel policies are attached directly to key_prefix stanzas and evaluated
# on every KV write operation that matches that prefix. More-specific prefixes
# take precedence, enabling tiered enforcement:
#
#   AIT-002/secrets/  →  hard-mandatory  (strictest — secrets + 64 KB size cap)
#   AIT-002/config/   →  hard-mandatory  (standard  — no sensitive data, 512 KB)
#   AIT-002/          →  hard-mandatory  (baseline  — broad write access guard)
#
# Consul injects three variables into each sentinel code block:
#   key   (string) — the full key path being written
#   value (string) — the value being stored
#   flags (int)    — the optional KV flags integer

  # ---------------------------------------------------------------------------
  # Sub-prefix: AIT-002/secrets/
  # Strictest enforcement. Secrets should be small opaque references or
  # encrypted blobs — never raw credentials, private keys, or connection strings.
  # Size cap: 64 KB (hard-mandatory).
  # ---------------------------------------------------------------------------
  key_prefix "AIT-002/secrets/" {
    policy = "write"

    sentinel {
      code = <<EOF
import "strings"

no_aws_keys = rule {
  not ("AKIA" in value) and
  not ("ASIA" in value)
}

no_private_keys = rule {
  not ("BEGIN RSA PRIVATE KEY" in value) and
  not ("BEGIN EC PRIVATE KEY" in value) and
  not ("BEGIN OPENSSH PRIVATE KEY" in value) and
  not ("BEGIN PRIVATE KEY" in value)
}

no_vault_tokens = rule {
  not strings.has_prefix(value, "hvs.") and
  not strings.has_prefix(value, "hvb.")
}

no_github_tokens = rule {
  not strings.has_prefix(value, "ghp_") and
  not strings.has_prefix(value, "ghs_")
}

no_passwords = rule {
  not ("password=" in value) and
  not ("passwd=" in value) and
  not ("\"password\":" in value) and
  not ("'password':" in value)
}

no_db_connection_strings = rule {
  not ("postgres://" in value) and
  not ("mysql://" in value) and
  not ("mongodb://" in value) and
  not ("mongodb+srv://" in value)
}

# 64 KB ceiling — secrets should be references, not full blobs
within_size = rule { length(value) <= 65536 }

main = rule {
  no_aws_keys and
  no_private_keys and
  no_vault_tokens and
  no_github_tokens and
  no_passwords and
  no_db_connection_strings and
  within_size
}
EOF
      enforcementlevel = "hard-mandatory"
    }
  }

  # ---------------------------------------------------------------------------
  # Sub-prefix: AIT-002/config/
  # Standard enforcement for configuration data such as app settings,
  # feature flags, and service parameters. Allows larger payloads (512 KB)
  # but still blocks raw credentials and connection strings with passwords.
  # ---------------------------------------------------------------------------
  key_prefix "AIT-002/config/" {
    policy = "write"

    sentinel {
      code = <<EOF
no_aws_keys = rule {
  not ("AKIA" in value) and
  not ("ASIA" in value)
}

no_private_keys = rule {
  not ("BEGIN RSA PRIVATE KEY" in value) and
  not ("BEGIN PRIVATE KEY" in value)
}

no_passwords = rule {
  not ("password=" in value) and
  not ("\"password\":" in value)
}

# 512 KB ceiling — consistent with Consul's default kv_max_value_size
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

  # ---------------------------------------------------------------------------
  # Sub-prefix: AIT-002/  (catch-all for all other team paths)
  # Baseline enforcement. Covers any path under AIT-002/ that is not already
  # matched by a more-specific prefix above.
  # ---------------------------------------------------------------------------
  key_prefix "AIT-002/" {
    policy = "write"

    sentinel {
      code = <<EOF
main = rule {
  length(value) <= 524288 and
  not ("AKIA" in value) and
  not ("BEGIN RSA PRIVATE KEY" in value) and
  not ("password=" in value)
}
EOF
      enforcementlevel = "hard-mandatory"
    }
  }
  
  # NOTE: No catch-all deny rule is needed. Consul ACL defaults to deny for
  # any path not explicitly granted, and explicit deny rules take precedence.