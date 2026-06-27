## System

path "sys/health" {
  capabilities = ["read", "sudo"]
}

path "sys/audit" {
  capabilities = ["read", "create", "sudo"]
}

# Client-count / activity tracking config (the "Client Usage" dashboard).
path "sys/internal/counters/config" {
  capabilities = ["read", "update"]
}

# Manage leases
path "sys/leases/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

## ACL Policies

# Create, manage ACL policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List existing policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Deny changing own policy
path "sys/policies/acl/admin" {
  capabilities = ["read"]
}

## Auth Methods

# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create, update, delete auth methods
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

# List auth methods
path "sys/auth" {
  capabilities = ["read"]
}

## Identity
path "identity/entity/*" {
  capabilities = ["create", "update", "delete", "read"]
}

path "identity/entity/name" {
  capabilities = ["list"]
}

path "identity/entity/id" {
  capabilities = ["list"]
}

path "identity/entity-alias/*" {
  capabilities = ["create", "update", "delete", "read"]
}

path "identity/entity-alias/id" {
  capabilities = ["list"]
}

## KV Secrets Engine

# No APP secret access on purpose: this CI identity manages Vault *structure*, not
# the app secret tree (kvv2/data/cluster/...). The one exception is its own R2
# Terraform-state backend creds, which terraform must read to init the backend.
# Scoped to cicd/ only.
path "kvv2/data/cicd/*" {
  capabilities = ["read"]
}

## Database Secrets Engine

# Manage the database engine STRUCTURE only: connections, roles, and root-cred
# rotation. Deliberately excludes database/creds/* — the CI configures the engine
# but never mints dynamic logins (that path belongs to the app via ESO).
path "database/config/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "database/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "database/rotate-root/*" {
  capabilities = ["create", "update"]
}

# Manage secrets engine
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List secrets engine
path "sys/mounts" {
  capabilities = ["read"]
}

## Audit

# Manage audit devices
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}