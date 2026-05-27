# ACL Policy Template for Team KV Access
# Replace AIT-XXX with actual team ID (e.g., AIT-001, AIT-002)

# Namespace-scoped policy
namespace "AIT-XXX" {
  
  # Grant read/write access to team's KV prefix
  key_prefix "AIT-XXX/" {
    policy = "write"

    # Sentinel policy is evaluated during KV writes.
    # Update patterns/limits to match your security requirements.
    sentinel {
      code = <<EOF
import "strings"

main = rule {
  length(value) <= 524288 and
  not strings.contains(value, "AKIA") and
  not strings.contains(value, "BEGIN RSA PRIVATE KEY") and
  not strings.contains(value, "password")
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
  
  # Optional: Allow reading service catalog for service discovery
  service_prefix "" {
    policy = "read"
  }
  
  # Optional: Allow reading node information
  node_prefix "" {
    policy = "read"
  }
  
  # Optional: Allow reading prepared queries
  query_prefix "" {
    policy = "read"
  }
  
  # Deny session creation (not needed for KV access)
  session_prefix "" {
    policy = "deny"
  }
  
  # Deny event creation
  event_prefix "" {
    policy = "deny"
  }
}

# If using multiple namespaces, deny access to other namespaces
namespace_prefix "" {
  key_prefix "" {
    policy = "deny"
  }
}