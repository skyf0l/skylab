# Harbor secrets engine: mints short-lived Harbor robot accounts on demand, one
# per `vault read harbor/creds/<role>`, deleted when the lease ends. The plugin
# binary is delivered into the Vault pods by an initContainer
# (k8s/projects/bootstrap/vault); here we register the versioned plugin, mount
# it and define the roles.
#
# The Harbor principal (a system robot) is deliberately NOT managed here: it is
# seeded once via CLI and immediately rotated so only Vault knows its secret
# (config/rotate-root). It never goes in KV either: the external-secrets policy
# reads all of kvv2/cluster/<cluster>/apps/*. See README.md "Harbor engine".

variable "harbor_plugin_version" {
  type        = string
  description = "Released plugin version; MUST match the Vault initContainer PLUGIN_VERSION."
  default     = "1.1.0"
}

variable "harbor_plugin_sha256" {
  type        = string
  description = "SHA-256 of the linux/x86_64 release binary (from the release _SHA256SUMS)."
  default     = "35988816693ee2e4fff9c09e6b7a990f87daf205a1b82135499d0c5a9534542a"
}

# Register the versioned plugin in Vault's catalog. The binary must already be
# in /vault/plugins (delivered by the initContainer) before the mount below
# spawns it, so apply the Helm change (restart + unseal) first.
resource "vault_plugin" "harbor" {
  type    = "secret"
  name    = "vault-plugin-harbor"
  command = "vault-plugin-harbor"
  version = "v${var.harbor_plugin_version}"
  sha256  = var.harbor_plugin_sha256
}

# Explicit lease ceiling: without it roles inherit the system max (768h) and a
# role with max_ttl unset would mint 33-day robots. Harbor robot expiry is
# max_ttl + 1h rounded up to whole days, so 24h keeps a leaked robot to ~2 days
# even if revocation never reaches Harbor.
resource "vault_mount" "harbor" {
  depends_on                = [vault_plugin.harbor]
  path                      = "harbor"
  type                      = vault_plugin.harbor.name
  plugin_version            = vault_plugin.harbor.version
  description               = "Short-lived Harbor robot accounts"
  default_lease_ttl_seconds = 900
  max_lease_ttl_seconds     = 86400
}

# Every creds read creates a Harbor robot; there is no per-role cap. Counted per
# client IP (group_by "none" is Enterprise-only), and every tailnet caller
# arrives from the Traefik pod, so for CI this is one shared bucket.
resource "vault_quota_rate_limit" "harbor_creds" {
  name     = "harbor-creds"
  path     = "${vault_mount.harbor.path}/creds/*"
  rate     = 10
  interval = 60
}

# skyf0l.dev image push from its GitHub Actions workflow (jwt role
# skyf0l-dev-harbor-push in auth.tf). One concrete project, never "*": a
# wildcard namespace makes Harbor issue a system-level robot. pull is added by
# the plugin at mint time.
resource "vault_generic_endpoint" "harbor_role_skyf0l_dev_push" {
  depends_on           = [vault_mount.harbor]
  path                 = "${vault_mount.harbor.path}/roles/skyf0l-dev-push"
  disable_read         = true # plugin canonicalises permissions JSON; avoid perpetual diffs
  disable_delete       = false
  ignore_absent_fields = true

  data_json = jsonencode({
    ttl     = "15m"
    max_ttl = "1h"
    permissions = jsonencode([{
      kind      = "project"
      namespace = "skyf0l.dev"
      access    = [{ resource = "repository", action = "push" }]
    }])
  })
}

# --- Ongoing principal rotation ------------------------------------------------
# The initial roll happens once at seed time (CLI, see README). This grants the
# rotation CronJob (k8s/projects/bootstrap/vault templates) permission to roll
# the principal on a schedule, authenticating via the existing k8s auth.

resource "vault_policy" "harbor_rotate_root" {
  name   = "harbor-rotate-root"
  policy = file("policies/harbor_rotate_root.hcl")
}

resource "vault_kubernetes_auth_backend_role" "harbor_rotate" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "harbor-rotate"
  bound_service_account_names      = ["harbor-rotate"]
  bound_service_account_namespaces = ["vault"]
  token_policies                   = [vault_policy.harbor_rotate_root.name]
  token_ttl                        = 120
}
