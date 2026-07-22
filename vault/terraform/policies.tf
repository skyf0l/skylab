resource "vault_policy" "admin" {
  name   = "admin"
  policy = file("policies/admin.hcl")
}

# Read-only mirror of admin, for PR `terraform plan` (the tf-plan JWT role).
resource "vault_policy" "tf_readonly" {
  name   = "tf-readonly"
  policy = file("policies/tf_readonly.hcl")
}

resource "vault_policy" "k8s_kvv2_workload_scoped_read" {
  name = "k8s-kvv2-workload-scoped-read"

  policy = templatefile("policies/k8s_kvv2_workload_scoped_read.hcl", {
    k8s_accessor = vault_auth_backend.kubernetes.accessor
    cluster_name = var.cluster_name
  })
}

resource "vault_policy" "k8s_kvv2_dropzone_rw" {
  name = "k8s-kvv2-dropzone-rw"

  policy = templatefile("policies/k8s_kvv2_dropzone_rw.hcl", {
    k8s_accessor = vault_auth_backend.kubernetes.accessor
    cluster_name = var.cluster_name
  })
}

resource "vault_policy" "external_secrets" {
  name = "external-secrets"

  policy = templatefile("policies/external_secrets_read.hcl", {
    cluster_name = var.cluster_name
  })
}

# Read-only on DefectDojo's dynamic DB-creds path. Bound to the defectdojo-db
# role below so ESO's generator (in the defectdojo namespace) can lease logins.
resource "vault_policy" "defectdojo_db_creds" {
  name   = "defectdojo-db-creds"
  policy = file("policies/defectdojo_db_creds.hcl")
}

resource "vault_policy" "external_dns_cf_creds" {
  name   = "external-dns-cf-creds"
  policy = file("policies/external_dns_cf_creds.hcl")
}

resource "vault_policy" "stalwart_backup_creds" {
  name   = "stalwart-backup-creds"
  policy = file("policies/stalwart_backup_creds.hcl")
}
