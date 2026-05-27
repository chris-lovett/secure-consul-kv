# ACL Policy for Team AIT-001
# Grants read/write access to AIT-001/* KV paths in namespace AIT-001
#
# SENTINEL ENFORCEMENT MODEL
# --------------------------
# Sentinel policies are attached directly to key_prefix stanzas and evaluated
# on every KV write operation that matches that prefix. More-specific prefixes
# take precedence, enabling tiered enforcement:
#
#   AIT-001/secrets/  →  hard-mandatory  (strictest — secrets + 64 KB size cap)
#   AIT-001/config/   →  hard-mandatory  (standard  — no sensitive data, 512 KB)
#   AIT-001/          →  hard-mandatory  (baseline  — broad write access guard)
#
# Consul injects three variables into each sentinel code block:
#   key   (string) — the full key path being written
#   value (string) — the value being stored
#   flags (int)    — the optional KV flags integer

  # ---------------------------------------------------------------------------
  # Sub-prefix: AIT-001/secrets/
  # Strictest enforcement. Secrets should be small opaque references or
  # encrypted blobs — never raw credentials, private keys, or connection strings.
  # Size cap: 64 KB (hard-mandatory).
  # ---------------------------------------------------------------------------
  key_prefix "AIT-001/secrets/" {
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
  # Sub-prefix: AIT-001/config/
  # Standard enforcement for configuration data such as app settings,
  # feature flags, and service parameters. Allows larger payloads (512 KB)
  # but still blocks raw credentials and connection strings with passwords.
  # ---------------------------------------------------------------------------
  key_prefix "AIT-001/config/" {
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
  # Sub-prefix: AIT-001/  (catch-all for all other team paths)
  # Baseline enforcement. Covers any path under AIT-001/ that is not already
  # matched by a more-specific prefix above.
  # ---------------------------------------------------------------------------
  key_prefix "AIT-001/" {
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