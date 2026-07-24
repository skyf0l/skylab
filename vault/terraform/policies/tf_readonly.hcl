# Read-only mirror of admin.hcl. Used by the `tf-plan` JWT role so PR
# `terraform plan` can refresh state without any ability to mutate Vault.
# Also covers reading the CI/CD secrets the workflow imports (R2 state creds).

path "sys/health" {
  capabilities = ["read"]
}

# ACL policies
path "sys/policies/acl" {
  capabilities = ["list"]
}
path "sys/policies/acl/*" {
  capabilities = ["read"]
}

# Auth methods
path "sys/auth" {
  capabilities = ["read"]
}
path "auth/*" {
  capabilities = ["read", "list"]
}

# Identity
path "identity/*" {
  capabilities = ["read", "list"]
}

# Secrets engines
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/mounts/*" {
  capabilities = ["read"]
}

# Own R2 Terraform-state backend creds, so plan can init the backend. Scoped to
# cicd/ only, never the app secret tree.
path "kvv2/data/cicd/*" {
  capabilities = ["read"]
}

# Database engine STRUCTURE — read-only, so plan can refresh connection/role
# state. Excludes database/creds/* so a PR plan can't mint dynamic logins.
path "database/config/*" {
  capabilities = ["read", "list"]
}
path "database/roles/*" {
  capabilities = ["read", "list"]
}

# Audit devices
path "sys/audit" {
  capabilities = ["read"]
}

# Client-count / activity tracking config (refresh vault_generic_endpoint.client_count).
path "sys/internal/counters/config" {
  capabilities = ["read"]
}

# Cloudflare engine STRUCTURE — read-only, so plan can refresh config/role state.
# Excludes cloudflare/creds/* so a PR plan can't mint tokens (mirrors database/).
path "cloudflare/config" {
  capabilities = ["read"]
}
path "cloudflare/role/*" {
  capabilities = ["read", "list"]
}

# Plugin catalog — read-only refresh of vault_plugin.cloudflare. The catalog is a
# root-protected path, so even a read needs sudo.
path "sys/plugins/catalog/*" {
  capabilities = ["read", "sudo"]
}

# Own token lookup
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
