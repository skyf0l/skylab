variable "local_vault_address" {
  type        = string
  description = "Vault address"
  default     = "https://localhost:8200"
}

variable "vault_domain" {
  type        = string
  description = "Vault domain"
  default     = "vault.skyf0l.dev"
}

variable "vault_address" {
  type        = string
  description = "Vault address"
  default     = "https://vault.skyf0l.dev:8200"
}

variable "kubernetes_auth_backend_kubernetes_host" {
  type        = string
  description = "Host must be a host string, a host:port pair, or a URL to the base of the Kubernetes API server."
  default     = "https://127.0.0.1:6443"
}

# PEM encoded CA cert for use by the TLS client used to talk with the Kubernetes API.
# Retrieve with `kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d`
variable "kubernetes_auth_backend_ca_cert" {
  type        = string
  description = "PEM encoded CA cert for use by the TLS client used to talk with the Kubernetes API."
}

# JWT token used by the Vault Kubernetes auth backend to validate service account tokens.
# Retrieve with `kubectl -n vault-injector create token vault-auth --duration=8760h`
variable "kubernetes_auth_backend_token_reviewer_jwt" {
  type        = string
  description = "A service account JWT used as a bearer token to access the TokenReview API to validate other JWTs during login."
}

locals {
  one_year  = 31536000
  ten_years = 315360000
}
