terraform {
  required_version = ">= 1.6"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"  # pin as you like
    }
  }

  backend "s3" {
    bucket  = "tfstates"
    key     = "vault.tfstate"
    endpoints = {
      s3 = "https://2620dc6ee3d578b27347d8e5efd95f32.r2.cloudflarestorage.com"
    }
    region = "auto"

    # Cloudflare R2 specifics:
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

provider "vault" {
  # It is strongly recommended to configure this provider through the
  # environment variables described above, so that each user can have
  # separate credentials set in the environment.
  #
  # This will default to using $VAULT_ADDR
  # But can be set explicitly
  # address = "https://vault.example.net:8200"
}