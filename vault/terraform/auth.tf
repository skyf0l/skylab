# JWT (GitHub OIDC) so your pipeline can auth without static secrets
resource "vault_jwt_auth_backend" "jwt" {
  path               = "jwt"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"
}

resource "vault_jwt_auth_backend_role" "admin" {
  backend          = vault_jwt_auth_backend.jwt.path
  role_name        = "admin"
  role_type        = "jwt"
  token_policies   = [vault_policy.admin.name]

  user_claim = "actor"
  bound_audiences = ["https://github.com/skyf0l"]
  bound_claims= {
    repository= "skyf0l/skylab"
  }
}
