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
