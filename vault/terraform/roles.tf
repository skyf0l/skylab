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
