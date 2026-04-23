# Secure Consul KV Access for VMs with ACLs and Sentinel

A comprehensive tutorial for securing Consul Key-Value store access on VMs using ACL policies and Sentinel governance policies.

## Use Case

Your organization runs **Consul Enterprise on OpenShift** and needs to provide secure KV store access to VM-based applications. Each team has:

- A unique team identifier (e.g., `AIT-001`, `AIT-002`, etc.)
- A dedicated Consul namespace matching their team ID
- KV paths scoped to their namespace: `AIT-XXX/`
- Users in predefined groups: `AIT-XXX` (matching their team ID)

**Security Requirements:**
1. **ACL Policies:** Users in `AIT-XXX` group have read/write access only to `AIT-XXX/` KV paths in their namespace
2. **Sentinel Policy #1:** Block writes containing sensitive data patterns (SSN, credit cards, API keys, etc.)
3. **Sentinel Policy #2:** Enforce maximum KV entry size limits

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Consul Enterprise Cluster                 │
│                      (on OpenShift)                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    Namespace: AIT-001                   │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │              KV Store: AIT-001/                   │  │ │
│  │  │  ├── config/                                      │  │ │
│  │  │  ├── secrets/  ← Sentinel blocks sensitive data  │  │ │
│  │  │  └── data/     ← Sentinel enforces size limits   │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  │                                                          │ │
│  │  ACL Policy: ait-001-kv-policy                          │ │
│  │  ├── Read: AIT-001/* in namespace AIT-001              │ │
│  │  └── Write: AIT-001/* in namespace AIT-001             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Sentinel Policies (Global):                                │
│  ├── sensitive-data-blocker.sentinel                        │
│  └── kv-size-limit.sentinel                                 │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ Consul API
                              │
                    ┌─────────┴─────────┐
                    │   VM Applications  │
                    │   (AIT-001 group)  │
                    │   Token: ait-001   │
                    └────────────────────┘
```

## Prerequisites

- Consul Enterprise 1.16+ (with Sentinel support)
- Consul cluster deployed on OpenShift
- Consul CLI installed on your workstation
- Cluster-admin or consul-admin access
- `CONSUL_HTTP_ADDR` and `CONSUL_HTTP_TOKEN` environment variables set

### Verify Prerequisites

```bash
# Check Consul version and Enterprise features
consul version

# Verify Sentinel is available (Enterprise only)
consul operator sentinel list 2>/dev/null && echo "✅ Sentinel available" || echo "❌ Sentinel not available"

# Check ACLs are enabled
consul acl bootstrap 2>&1 | grep -q "ACL support disabled" && echo "❌ ACLs disabled" || echo "✅ ACLs enabled"

# Verify you have admin access
consul acl token read -self
```

## Quick Start (30 minutes)

```bash
# 1. Create namespace for team AIT-001
consul namespace create -name AIT-001 -description "Team AIT-001 namespace"

# 2. Create ACL policy for AIT-001
consul acl policy create \
  -name ait-001-kv-policy \
  -namespace AIT-001 \
  -rules @acl-policies/ait-001-kv-policy.hcl

# 3. Create ACL token for AIT-001 users
consul acl token create \
  -description "AIT-001 team KV access" \
  -policy-name ait-001-kv-policy \
  -namespace AIT-001

# 4. Deploy Sentinel policies
consul operator sentinel create \
  -name sensitive-data-blocker \
  -enforcement-level hard-mandatory \
  -code @sentinel-policies/sensitive-data-blocker.sentinel

consul operator sentinel create \
  -name kv-size-limit \
  -enforcement-level soft-mandatory \
  -code @sentinel-policies/kv-size-limit.sentinel

# 5. Test the configuration
./scripts/test-kv-access.sh AIT-001 <token-from-step-3>
```

## Repository Structure

```
consul-kv-security-tutorial/
├── README.md                                    # This file
├── DEPLOYMENT_GUIDE.md                          # Step-by-step instructions
├── acl-policies/                                # ACL policy definitions
│   ├── ait-001-kv-policy.hcl                   # Example for team AIT-001
│   ├── ait-002-kv-policy.hcl                   # Example for team AIT-002
│   └── template-kv-policy.hcl                  # Template for new teams
├── sentinel-policies/                           # Sentinel policy definitions
│   ├── sensitive-data-blocker.sentinel         # Blocks sensitive data patterns
│   ├── kv-size-limit.sentinel                  # Enforces size limits
│   └── test-cases/                             # Test data for Sentinel
│       ├── valid-data.json
│       ├── invalid-ssn.json
│       ├── invalid-credit-card.json
│       └── invalid-size.json
├── scripts/                                     # Automation scripts
│   ├── create-team-namespace.sh                # Create namespace + ACL for new team
│   ├── test-kv-access.sh                       # Test ACL permissions
│   ├── test-sentinel-policies.sh               # Test Sentinel enforcement
│   └── cleanup.sh                              # Remove test data
└── examples/                                    # Usage examples
    ├── vm-consul-config.hcl                    # Consul agent config for VMs
    ├── python-kv-client.py                     # Python KV client example
    └── curl-examples.sh                        # curl command examples
```

## Security Model

### Layer 1: Namespace Isolation
Each team gets a dedicated Consul namespace:
- Namespace name matches team ID: `AIT-001`, `AIT-002`, etc.
- Provides logical isolation between teams
- Prevents cross-team access at the namespace level

### Layer 2: ACL Policies
Fine-grained access control within namespaces:
- **Read access:** `key_prefix "AIT-XXX/" { policy = "read" }`
- **Write access:** `key_prefix "AIT-XXX/" { policy = "write" }`
- **Deny all other paths:** Default deny policy

### Layer 3: Sentinel Policies
Governance and compliance enforcement:
- **Content validation:** Block sensitive data patterns
- **Size limits:** Prevent large entries that could impact performance
- **Audit trail:** All policy violations are logged

## ACL Policy Design

### Template Structure

```hcl
# Template: acl-policies/template-kv-policy.hcl
namespace "AIT-XXX" {
  # Allow read/write to team's KV prefix
  key_prefix "AIT-XXX/" {
    policy = "write"
  }
  
  # Deny access to other team prefixes
  key_prefix "" {
    policy = "deny"
  }
  
  # Allow reading service catalog (optional)
  service_prefix "" {
    policy = "read"
  }
  
  # Allow reading node information (optional)
  node_prefix "" {
    policy = "read"
  }
}
```

### Creating Policies for Multiple Teams

Use the provided script to generate policies for multiple teams:

```bash
# Generate policies for teams AIT-001 through AIT-010
./scripts/create-team-namespace.sh AIT-001
./scripts/create-team-namespace.sh AIT-002
# ... etc
```

## Sentinel Policy Design

### Policy 1: Sensitive Data Blocker

Detects and blocks common sensitive data patterns:

- **Social Security Numbers:** `XXX-XX-XXXX`
- **Credit Card Numbers:** 16-digit patterns
- **API Keys:** Common formats (AWS, GitHub, etc.)
- **Private Keys:** PEM format detection
- **Passwords:** Common password field patterns
- **Email addresses:** PII consideration

**Enforcement Level:** `hard-mandatory` (blocks writes, cannot be overridden)

### Policy 2: KV Size Limit

Enforces maximum entry size to prevent performance issues:

- **Maximum key size:** 512 bytes
- **Maximum value size:** 512 KB (configurable)
- **Total entry size:** 512 KB

**Enforcement Level:** `soft-mandatory` (blocks writes, can be overridden by admin)

## Testing

### Test ACL Permissions

```bash
# Test valid access (should succeed)
./scripts/test-kv-access.sh AIT-001 <token> write AIT-001/config/app.json '{"setting":"value"}'

# Test invalid access (should fail)
./scripts/test-kv-access.sh AIT-001 <token> write AIT-002/config/app.json '{"setting":"value"}'
```

### Test Sentinel Policies

```bash
# Test sensitive data blocking
./scripts/test-sentinel-policies.sh sensitive-data-blocker

# Test size limits
./scripts/test-sentinel-policies.sh kv-size-limit
```

## VM Configuration

### Consul Agent Configuration

VMs need Consul agent configured with the team's ACL token:

```hcl
# /etc/consul.d/consul.hcl
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"

# Connect to Consul cluster on OpenShift
retry_join = ["consul-server.consul.svc.cluster.local"]

# ACL configuration
acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens {
    agent = "ait-001-token-here"
    default = "ait-001-token-here"
  }
}

# Namespace configuration (Enterprise)
namespace = "AIT-001"
```

### Application Integration

Applications on VMs can access KV using:

1. **Consul CLI:**
```bash
export CONSUL_HTTP_TOKEN="ait-001-token"
export CONSUL_NAMESPACE="AIT-001"
consul kv put AIT-001/config/app.json @config.json
consul kv get AIT-001/config/app.json
```

2. **HTTP API:**
```bash
curl -H "X-Consul-Token: ait-001-token" \
     -H "X-Consul-Namespace: AIT-001" \
     -X PUT \
     -d @config.json \
     https://consul.example.com/v1/kv/AIT-001/config/app.json
```

3. **SDK (Python example):**
```python
import consul

c = consul.Consul(
    host='consul.example.com',
    token='ait-001-token',
    namespace='AIT-001'
)

# Write to KV
c.kv.put('AIT-001/config/app.json', '{"setting":"value"}')

# Read from KV
index, data = c.kv.get('AIT-001/config/app.json')
```

## Monitoring and Auditing

### Enable Audit Logging

```bash
# Enable audit logging in Consul Enterprise
consul operator audit enable \
  -type file \
  -path /var/log/consul/audit.log
```

### Monitor Policy Violations

```bash
# Watch for Sentinel policy violations
tail -f /var/log/consul/audit.log | grep -i sentinel

# Watch for ACL denials
tail -f /var/log/consul/audit.log | grep -i "permission denied"
```

### Metrics

Key metrics to monitor:
- `consul.sentinel.policy.evaluation` - Sentinel policy evaluations
- `consul.acl.token.cache_hit` - ACL token cache performance
- `consul.kv.apply` - KV write operations

## Troubleshooting

### ACL Permission Denied

```bash
# Verify token has correct policy
consul acl token read -id <token-id>

# Check policy rules
consul acl policy read -name ait-001-kv-policy

# Test token permissions
consul kv put -token=<token> AIT-001/test "value"
```

### Sentinel Policy Blocking Valid Data

```bash
# Check Sentinel policy logs
consul operator sentinel read -name sensitive-data-blocker

# Test policy with sample data
consul operator sentinel test \
  -name sensitive-data-blocker \
  -data @test-data.json
```

### VM Cannot Connect to Consul

```bash
# Check network connectivity
nc -zv consul-server.consul.svc.cluster.local 8500

# Verify token is valid
curl -H "X-Consul-Token: <token>" \
     https://consul.example.com/v1/agent/self

# Check Consul agent logs on VM
journalctl -u consul -f
```

## Best Practices

1. **Token Rotation:** Rotate ACL tokens regularly (90 days recommended)
2. **Least Privilege:** Grant minimum necessary permissions
3. **Audit Logging:** Always enable audit logging in production
4. **Sentinel Testing:** Test Sentinel policies thoroughly before deployment
5. **Namespace Naming:** Use consistent naming convention (AIT-XXX)
6. **Documentation:** Document team-specific KV path conventions
7. **Monitoring:** Set up alerts for policy violations
8. **Backup:** Regular backups of Consul KV data

## Next Steps

1. Review the [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed setup instructions
2. Customize ACL policies in `acl-policies/` for your teams
3. Review and adjust Sentinel policies in `sentinel-policies/`
4. Test the configuration using provided scripts
5. Deploy to production following the deployment guide

## Resources

- [Consul ACL System](https://developer.hashicorp.com/consul/docs/security/acl)
- [Consul Namespaces](https://developer.hashicorp.com/consul/docs/enterprise/namespaces)
- [Sentinel Policy Language](https://docs.hashicorp.com/sentinel/language)
- [Consul KV Store](https://developer.hashicorp.com/consul/docs/dynamic-app-config/kv)

---

**Ready to get started?** Follow the [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for step-by-step instructions! 🔒