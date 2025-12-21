resource "vault_policy" "admin" {
  name   = "admin"
  policy = file("policies/admin.hcl")
}

resource "vault_policy" "k8s_kvv2_workload_scoped_read" {
  name = "k8s-kvv2-workload-scoped-read"

  policy = templatefile("policies/k8s_kvv2_workload_scoped_read.hcl", {
    k8s_accessor = vault_auth_backend.kubernetes.accessor
  })
}

resource "vault_policy" "k8s_kvv2_dropzone_rw" {
  name = "k8s-kvv2-dropzone-rw"

  policy = templatefile("policies/k8s_kvv2_dropzone_rw.hcl", {
    k8s_accessor = vault_auth_backend.kubernetes.accessor
  })
}
