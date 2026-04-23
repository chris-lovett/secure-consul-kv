# ACL Policy Template for Team KV Access
# Replace AIT-XXX with actual team ID (e.g., AIT-001, AIT-002)

# Namespace-scoped policy
namespace "AIT-XXX" {
  
  # Grant read/write access to team's KV prefix
  key_prefix "AIT-XXX/" {
    policy = "write"
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