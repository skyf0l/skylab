# Kubernetes roles for workloads
resource "vault_kubernetes_auth_backend_role" "workload_scoped" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "k8s-workload-scoped"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["*"]

  token_policies = [
    vault_policy.k8s_kvv2_workload_scoped_read.name
  ]
}

resource "vault_kubernetes_auth_backend_role" "workload_scoped_dropzone" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "k8s-workload-scoped-dropzone"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["*"]

  token_policies = [
    vault_policy.k8s_kvv2_workload_scoped_read.name,
    vault_policy.k8s_kvv2_dropzone_rw.name
  ]
}

# External Secrets Operator: one ClusterSecretStore (vault-backend) logs in with
# this role and reads app secrets for ExternalSecrets across all namespaces.
# Scoped to ESO's own service account; read-only on this cluster's secret tree.
# role_name MUST stay "external-secrets" — it's referenced by
# k8s/projects/security-stack/external-secrets-stores (vault.role).
resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "external-secrets"

  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]

  token_policies = [
    vault_policy.external_secrets.name
  ]
}

# DefectDojo dynamic DB creds. ESO's VaultDynamicSecret generator is namespaced
# and can't use the external-secrets SA cross-namespace, so it authenticates as a
# dedicated SA in the defectdojo namespace, bound here to read its leased logins.
resource "vault_kubernetes_auth_backend_role" "defectdojo_db" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "defectdojo-db"

  bound_service_account_names      = ["defectdojo-db"]
  bound_service_account_namespaces = ["defectdojo"]

  token_policies = [
    vault_policy.defectdojo_db_creds.name
  ]

  # A dynamic DB lease is a child of the auth token Vault issues here — when the
  # token expires, the lease is revoked (DROP ROLE) and the app's credential dies.
  # Keep the token alive longer than the DB role's default_ttl (24h) so the lease
  # lives its full life; ESO refreshes (12h) well inside that, with overlap.
  token_ttl     = 90000 # 25h
  token_max_ttl = 90000
}

# external-dns dynamic Cloudflare DNS tokens. Same shape as defectdojo-db: the
# ESO VaultDynamicSecret generator is namespaced, so it authenticates as the
# external-dns SA (created by the upstream chart) in its own namespace.
resource "vault_kubernetes_auth_backend_role" "external_dns_cf" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "external-dns-cf"

  bound_service_account_names      = ["external-dns"]
  bound_service_account_namespaces = ["external-dns"]

  token_policies = [
    vault_policy.external_dns_cf_creds.name
  ]

  # The Cloudflare token lease is a child of this auth token — keep it alive
  # longer than the role's ttl (24h) so the lease lives its full life; ESO
  # refreshes (8h) well inside that, with overlap.
  token_ttl     = 90000 # 25h
  token_max_ttl = 90000
}

# Stalwart CNPG backups: the ESO VaultDynamicSecret generator leases R2 S3
# credentials as a dedicated SA in the stalwart namespace (namespaced generator,
# so it cannot use the external-secrets SA cross-namespace).
resource "vault_kubernetes_auth_backend_role" "stalwart_backup" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "stalwart-backup"

  bound_service_account_names      = ["stalwart-backup"]
  bound_service_account_namespaces = ["stalwart"]

  token_policies = [
    vault_policy.stalwart_backup_creds.name
  ]

  # Keep the auth token alive longer than the R2 role's ttl (24h) so the lease
  # lives its full life; ESO refreshes (8h) well inside that, with overlap.
  token_ttl     = 90000 # 25h
  token_max_ttl = 90000
}

# cert-manager DNS-01 solver credentials. The ESO VaultDynamicSecret generator
# is namespaced, so it authenticates as a dedicated SA in the cert-manager
# namespace. Replaces the hand-created, single-zone Cloudflare token.
resource "vault_kubernetes_auth_backend_role" "cert_manager_cf" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "cert-manager-cf"

  bound_service_account_names      = ["cert-manager-cf"]
  bound_service_account_namespaces = ["cert-manager"]

  token_policies = [
    vault_policy.cert_manager_cf_creds.name
  ]

  # Outlive the engine role's 24h ttl so the lease runs its full life; ESO
  # refreshes (8h) well inside it. cert-manager reads the token per API call,
  # so a rotation needs no restart.
  token_ttl     = 90000 # 25h
  token_max_ttl = 90000
}
