# Database secrets engine — issues short-lived PostgreSQL credentials on demand.
# The engine connects to the defectdojo-pg CloudNativePG cluster as a CREATEROLE
# role (vault_mgr, not a superuser) and mints per-lease login roles for the app.
resource "vault_mount" "database" {
  path        = "database"
  type        = "database"
  description = "Dynamic database credentials"
}

locals {
  # vault_mgr is created with this password at cluster bootstrap (CNPG postInitSQL)
  # and Vault replaces it via rotate-root on the first apply below — after which
  # the real password exists only inside Vault. Must match the chart value
  # (security-stack/defectdojo postgres.vaultMgrBootstrapPassword).
  vault_mgr_bootstrap_password = "bootstrap-rotated-by-vault"
}

resource "vault_database_secret_backend_connection" "defectdojo" {
  # The admin policy grants database/* — apply that update before writing here, or
  # the same token 403s on its first run.
  depends_on = [vault_policy.admin]

  backend       = vault_mount.database.path
  name          = "defectdojo"
  allowed_roles = ["defectdojo"]

  # Don't probe at config time; the engine may be applied before the DB exists.
  verify_connection = false

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@defectdojo-pg-rw.defectdojo.svc.cluster.local:5432/defectdojo?sslmode=require"
    username       = "vault_mgr"
    password       = local.vault_mgr_bootstrap_password
  }

  # After rotate-root, Vault owns this password. Never re-send the bootstrap value
  # on later applies (it can't be read back to diff anyway).
  lifecycle {
    ignore_changes = [postgresql[0].password]
  }
}

# Replace vault_mgr's password immediately so the privileged credential lives only
# inside Vault — not in git, Terraform state, or KV. This connects to the live
# database, so the apply must run once the CNPG cluster is reachable (re-run the
# Vault workflow if the first apply lands before the cluster is up).
resource "vault_generic_endpoint" "rotate_root_defectdojo" {
  depends_on = [vault_database_secret_backend_connection.defectdojo]

  path                 = "database/rotate-root/defectdojo"
  disable_read         = true
  disable_delete       = true
  ignore_absent_fields = true
  data_json            = "{}"
}

# Each issued role logs in, joins the defectdojo_app parent role, and runs every
# session as defectdojo_app — so objects it creates are owned by the parent, not
# the ephemeral role. Revocation is then a clean DROP (the role owns nothing).
# (vault_mgr is CREATEROLE + ADMIN on defectdojo_app, so these run without
# superuser; requires PostgreSQL 16+, which is the CNPG default.)
resource "vault_database_secret_backend_role" "defectdojo" {
  depends_on = [vault_policy.admin]

  backend = vault_mount.database.path
  name    = "defectdojo"
  db_name = vault_database_secret_backend_connection.defectdojo.name

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT \"defectdojo_app\" TO \"{{name}}\";",
    "ALTER ROLE \"{{name}}\" SET ROLE \"defectdojo_app\";",
  ]

  # The leased role owns nothing (every session runs as defectdojo_app via SET
  # ROLE), so revocation is a plain DROP — no REASSIGN/DROP OWNED, which a
  # non-superuser vault_mgr can't run against a role it isn't a member of.
  revocation_statements = [
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]

  default_ttl = 86400  # 24h
  max_ttl     = 604800 # 7d
}
