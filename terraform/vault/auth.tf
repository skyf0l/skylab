# JWT (GitHub OIDC) so the pipeline can auth without static secrets.
resource "vault_jwt_auth_backend" "jwt" {
  path               = "jwt"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"
}

# Apply role — full admin, but only mintable from the `production` GitHub
# Environment (push to main, gated by environment protection rules). The
# `environment` claim is only present when a job declares `environment:`.
resource "vault_jwt_auth_backend_role" "admin" {
  backend        = vault_jwt_auth_backend.jwt.path
  role_name      = "admin"
  role_type      = "jwt"
  token_policies = [vault_policy.admin.name]

  user_claim      = "actor"
  bound_audiences = ["https://github.com/skyf0l"]
  bound_claims = {
    repository  = "skyf0l/skylab"
    environment = "production"
  }
}

# Plan role — read-only, usable from any branch (for PR `terraform plan`).
# Cannot mutate Vault, so it is safe to expose to untrusted-branch workflows.
resource "vault_jwt_auth_backend_role" "tf_plan" {
  backend        = vault_jwt_auth_backend.jwt.path
  role_name      = "tf-plan"
  role_type      = "jwt"
  token_policies = [vault_policy.tf_readonly.name]

  user_claim      = "actor"
  bound_audiences = ["https://github.com/skyf0l"]
  bound_claims = {
    repository = "skyf0l/skylab"
  }
}

# Image push for skyf0l/skyf0l.dev. The FIRST role bound to another repository:
# anyone who can run a workflow on that repo's main branch gets this role, so it
# holds exactly one Harbor creds path (a robot scoped to one project) and
# nothing else. ref pins it to main, so a branch or PR workflow can't mint push
# credentials. The token dies with the job (revoke-self), taking the robot with
# it; token_ttl caps it if that step never runs.
resource "vault_jwt_auth_backend_role" "skyf0l_dev_harbor_push" {
  backend        = vault_jwt_auth_backend.jwt.path
  role_name      = "skyf0l-dev-harbor-push"
  role_type      = "jwt"
  token_policies = [vault_policy.skyf0l_dev_harbor_push.name]
  token_ttl      = 900
  token_max_ttl  = 3600

  user_claim      = "actor"
  bound_audiences = ["https://github.com/skyf0l"]
  bound_claims = {
    repository = "skyf0l/skyf0l.dev"
    ref        = "refs/heads/main"
  }
}

# Kubernetes auth backend for ESO and the Vault Injector.
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

# In-cluster config: Vault authenticates to the Kubernetes API with its own pod
# ServiceAccount token and the in-cluster CA (both read from disk on each
# TokenReview, so they rotate automatically). No static reviewer JWT or CA cert
# to manage/rotate. Requires the Vault SA to hold system:auth-delegator, which
# the Helm chart grants by default (server.authDelegator.enabled).
resource "vault_kubernetes_auth_backend_config" "kubernetes_config" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = var.kubernetes_auth_backend_kubernetes_host
}
