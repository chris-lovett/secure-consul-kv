# ACL Policy Template for Team KV Access
# Replace every occurrence of AIT-XXX with the actual team ID (e.g. AIT-003, AIT-004).
#
# SENTINEL ENFORCEMENT MODEL
# --------------------------
# Sentinel policies are attached directly to key_prefix stanzas and evaluated
# on every KV write operation that matches that prefix. More-specific prefixes
# take precedence over less-specific ones, enabling a tiered enforcement model:
#
#   AIT-XXX/secrets/  →  hard-mandatory  (strictest — no credentials, 64 KB cap)
#   AIT-XXX/config/   →  hard-mandatory  (standard  — no sensitive data, 512 KB)
#   AIT-XXX/          →  hard-mandatory  (baseline  — broad write access guard)
#
# Consul injects three variables into each sentinel code block at evaluation time:
#   key   (string) — the full key path being written (e.g. "AIT-XXX/config/db-host")
#   value (string) — the raw string value being stored
#   flags (int)    — the optional KV flags integer
#
# Enforcement levels:
#   advisory        — logs a warning, write proceeds
#   soft-mandatory  — blocks the write; a Consul operator can override
#   hard-mandatory  — blocks the write unconditionally

  # ---------------------------------------------------------------------------
  # Sub-prefix: AIT-XXX/secrets/
  # Strictest enforcement. Secrets should be small opaque references or
  # encrypted blobs — never raw credentials, private keys, or connection strings.
  # Size cap: 64 KB (hard-mandatory).
  # ---------------------------------------------------------------------------
  key_prefix "AIT-XXX/secrets/" {
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
  not strings.contains(value, "BEGIN EC PRIVATE KEY") and
  not strings.contains(value, "BEGIN OPENSSH PRIVATE KEY") and
  not strings.contains(value, "BEGIN PRIVATE KEY")
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
  not strings.contains(value, "password=") and
  not strings.contains(value, "passwd=") and
  not strings.contains(value, "\"password\":") and
  not strings.contains(value, "'password':")
}

no_db_connection_strings = rule {
  not strings.contains(value, "postgres://") and
  not strings.contains(value, "mysql://") and
  not strings.contains(value, "mongodb://") and
  not strings.contains(value, "mongodb+srv://")
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
  # Sub-prefix: AIT-XXX/config/
  # Standard enforcement for configuration data such as app settings,
  # feature flags, and service parameters. Allows larger payloads (512 KB)
  # but still blocks raw credentials and connection strings with passwords.
  # ---------------------------------------------------------------------------
  key_prefix "AIT-XXX/config/" {
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
  # Sub-prefix: AIT-XXX/  (catch-all for all other team paths)
  # Baseline enforcement. Covers any path under AIT-XXX/ that is not already
  # matched by a more-specific prefix above. Tune patterns to your requirements.
  # ---------------------------------------------------------------------------
  key_prefix "AIT-XXX/" {
    policy = "write"

    sentinel {
      code = <<EOF
import "strings"

main = rule {
  length(value) <= 524288 and
  not strings.contains(value, "AKIA") and
  not strings.contains(value, "BEGIN RSA PRIVATE KEY") and
  not strings.contains(value, "password=")
}
EOF
      enforcementlevel = "hard-mandatory"
    }
  }
  
  # Explicitly deny access to other team prefixes
  # This prevents cross-team access within the namespace
  key_prefix "" {
    policy = "deny"
  }