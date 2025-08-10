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

locals {
  one_year = 31536000
  ten_years = 315360000
}