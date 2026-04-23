# ACL Policy for Team AIT-001
# Grants read/write access to AIT-001/* KV paths in namespace AIT-001

namespace "AIT-001" {
  
  # Grant read/write access to team's KV prefix
  key_prefix "AIT-001/" {
    policy = "write"
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
}

# Deny access to other namespaces
namespace_prefix "" {
  key_prefix "" {
    policy = "deny"
  }
}