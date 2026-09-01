terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0" # v5 is a schema rewrite vs v4; run `terraform init` to lock the exact patch
    }
  }

  # State in R2, same backend as terraform/vault but its OWN key so the two
  # never collide. The `tfstates` bucket is bootstrap infra and is deliberately
  # NOT managed here (it holds this very state — chicken-and-egg).
  backend "s3" {
    bucket = "tfstates"
    key    = "cloudflare.tfstate"
    endpoints = {
      s3 = "https://2620dc6ee3d578b27347d8e5efd95f32.r2.cloudflarestorage.com"
    }
    region = "auto"

    # Cloudflare R2 specifics (identical to terraform/vault).
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

# The provider reads CLOUDFLARE_API_TOKEN from the environment. The token needs
# Account -> Workers R2 Storage -> Edit (add Zone -> Zone Settings -> Edit if you
# start managing zone settings here too). NOT a Vault-minted token: those roles
# are IP-pinned to the VPS and won't authenticate from a workstation.
provider "cloudflare" {}
