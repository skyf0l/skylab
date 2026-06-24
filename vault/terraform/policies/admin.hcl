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

# No kvv2/data or kvv2/metadata grant on purpose: this CI identity manages Vault
# *structure*, never reads or writes secret *values*. The KV engine MOUNT is
# managed via sys/mounts/* below; seeding secret values is a root/break-glass op.
# (If the kv-v2 mount refresh ever needs it, add `kvv2/config` READ only — never
# data/metadata.)

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