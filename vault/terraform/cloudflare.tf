# Cloudflare secrets engine: mints short-lived Cloudflare API tokens (and,
# opt-in, derived R2 S3 credentials) on demand. The plugin binary is delivered
# into the Vault pods by an initContainer (k8s/projects/gitops-stack/vault);
# here we register the versioned plugin and mount it.
#
# The parent API token is a real, powerful credential and is deliberately NOT
# managed here: it is seeded once via CLI and then owned by Vault
# (config/rotate-root), so no Cloudflare secret ever lands in git or in this
# module's state. See vault/README.md "Cloudflare engine" for the one-time seed.

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID that owns the minted tokens and R2 buckets."
  default     = "72daf8bcee8eb1ea408602f0d509a61f"
}

variable "cloudflare_plugin_version" {
  type        = string
  description = "Released plugin version; MUST match the Vault initContainer PLUGIN_VERSION."
  default     = "1.2.0"
}

variable "cloudflare_plugin_sha256" {
  type        = string
  description = "SHA-256 of the linux/amd64 release binary (from the release checksums.txt)."
  default     = "54b530d90c714d55dab5151f4f5d23ca5449f2d1dc61102b1ff74bb9367a7bfa"
}

# Register the versioned plugin in Vault's catalog. The binary must already be
# in /vault/plugins (delivered by the initContainer) before the mount below
# spawns it, so apply the Helm change (restart + unseal) first.
resource "vault_plugin" "cloudflare" {
  type    = "secret"
  name    = "vault-cloudflare-secret-engine"
  command = "vault-cloudflare-secret-engine"
  version = "v${var.cloudflare_plugin_version}"
  sha256  = var.cloudflare_plugin_sha256
}

resource "vault_mount" "cloudflare" {
  depends_on     = [vault_plugin.cloudflare]
  path           = "cloudflare"
  type           = vault_plugin.cloudflare.name
  plugin_version = vault_plugin.cloudflare.version
  description    = "Dynamic Cloudflare API tokens (+ opt-in R2 S3 credentials)"
}

# Example role: R2 object read/write on the account, exposing a derived S3
# keypair. Structure only, no secrets. Add DNS / zone-scoped roles the same way.
resource "vault_generic_endpoint" "cloudflare_role_r2" {
  depends_on           = [vault_mount.cloudflare]
  path                 = "cloudflare/role/r2-objects"
  disable_read         = true # plugin canonicalises policies JSON; avoid perpetual diffs
  disable_delete       = false
  ignore_absent_fields = true

  data_json = jsonencode({
    token_type        = "account"
    r2_s3_credentials = true
    ttl               = "30m"
    max_ttl           = "2h"
    policies = jsonencode([{
      effect            = "allow"
      permission_groups = [{ name = "Workers R2 Storage Bucket Item Write" }]
      resources         = { "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*" }
    }])
  })
}

# --- Ongoing parent-token rotation ---------------------------------------------
# The initial roll happens once at seed time (CLI, see README). This grants the
# rotation CronJob (k8s/projects/gitops-stack/vault templates) permission to roll
# the parent token on a schedule, authenticating via the existing k8s auth.

resource "vault_policy" "cloudflare_rotate_root" {
  name   = "cloudflare-rotate-root"
  policy = file("policies/cloudflare_rotate_root.hcl")
}

resource "vault_kubernetes_auth_backend_role" "cloudflare_rotate" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cloudflare-rotate"
  bound_service_account_names      = ["cloudflare-rotate"]
  bound_service_account_namespaces = ["vault"]
  token_policies                   = [vault_policy.cloudflare_rotate_root.name]
  token_ttl                        = 120
}
