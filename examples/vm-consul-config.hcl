# Consul Agent Configuration for VM
# This configuration file is for VMs that need to access Consul KV
# Replace placeholders with actual values for your environment

# Basic Configuration
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"

# Node name (unique per VM)
node_name = "vm-ait-001-app-01"

# Connect to Consul cluster
# Replace with your Consul server addresses
retry_join = [
  "consul-server.consul.svc.cluster.local",
  "consul-server-0.consul-server.consul.svc.cluster.local",
  "consul-server-1.consul-server.consul.svc.cluster.local"
]

# ACL Configuration
acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  
  tokens {
    # Agent token - used for agent operations
    # Replace with your team's token
    agent = "REPLACE-WITH-YOUR-TEAM-TOKEN"
    
    # Default token - used for KV operations
    # Replace with your team's token
    default = "REPLACE-WITH-YOUR-TEAM-TOKEN"
  }
}

# Namespace Configuration (Enterprise)
# Replace with your team's namespace
namespace = "AIT-001"

# TLS Configuration (if using TLS)
# Uncomment and configure if your Consul cluster uses TLS
# tls {
#   defaults {
#     ca_file = "/etc/consul.d/certs/ca.pem"
#     cert_file = "/etc/consul.d/certs/client.pem"
#     key_file = "/etc/consul.d/certs/client-key.pem"
#     verify_incoming = false
#     verify_outgoing = true
#     verify_server_hostname = true
#   }
# }

# Ports Configuration
ports {
  http = 8500
  https = -1  # Disable HTTPS on agent (use TLS on server)
  grpc = 8502
  dns = 8600
}

# Performance Tuning
performance {
  raft_multiplier = 1
}

# Telemetry (optional)
# telemetry {
#   prometheus_retention_time = "60s"
#   disable_hostname = true
# }

# Service Registration (optional)
# If this VM runs a service that should be registered in Consul
# service {
#   name = "my-app"
#   port = 8080
#   tags = ["production", "ait-001"]
#   
#   check {
#     http = "http://localhost:8080/health"
#     interval = "10s"
#     timeout = "2s"
#   }
# }

# Watches (optional)
# Watch for changes in KV and trigger actions
# watches = [
#   {
#     type = "key"
#     key = "AIT-001/config/app.json"
#     handler_type = "script"
#     args = ["/usr/local/bin/reload-config.sh"]
#   }
# ]