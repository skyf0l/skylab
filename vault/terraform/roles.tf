# Role for Vault itself
resource "vault_pki_secret_backend_role" "vault" {
  backend            = vault_mount.pki_int.path
  name               = "vault"
  allowed_domains    = ["${var.vault_domain}", "vault", "localhost"]
  allow_bare_domains = true
  allow_subdomains   = false
  allow_ip_sans      = true
  ttl                = local.one_year
}

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
