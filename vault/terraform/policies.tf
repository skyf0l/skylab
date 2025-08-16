resource "vault_policy" "admin" {
  name   = "admin"
  policy = file("policies/admin.hcl")
}
