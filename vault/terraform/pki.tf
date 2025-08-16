resource "vault_mount" "pki" {
  path = "pki"
  type = "pki"
  description           = "Root PKI"
  max_lease_ttl_seconds = local.ten_years
}

resource "vault_pki_secret_backend_config_urls" "root" {
  depends_on  = [vault_mount.pki]
  backend = vault_mount.pki.path
  issuing_certificates = [
    "${var.local_vault_address}/v1/pki/ca",
    "${var.vault_address}/v1/pki/ca"
  ]
  crl_distribution_points = [
    "${var.local_vault_address}/v1/pki/crl",
    "${var.vault_address}/v1/pki/crl"
  ]
}

resource "vault_pki_secret_backend_root_cert" "root" {
  depends_on  = [vault_mount.pki]
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "Vault PKI Root CA"
  ttl         = local.ten_years
}

resource "vault_mount" "pki_int" {
  path                  = "pki_int"
  type                  = vault_mount.pki.type
  description           = "Intermediate PKI"
  max_lease_ttl_seconds = local.ten_years
}

# intermediate CSR
resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  depends_on  = [vault_mount.pki, vault_mount.pki_int]
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Vault PKI Intermediate CA"
}

# intermediate cert
resource "vault_pki_secret_backend_root_sign_intermediate" "root" {
  depends_on  = [vault_pki_secret_backend_intermediate_cert_request.intermediate]
  backend     = vault_mount.pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name = "Intermediate CA"
  ttl         = local.ten_years
}

# import intermediate cert to Vault
resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.root.certificate
}
