# R2 buckets. These are the STORAGE CONTAINERS only — what goes inside them
# (backups, chunks, blocks) is written by the apps, and DNS records are owned by
# external-dns. Terraform manages the buckets; nothing else touches this layer.
#
# prevent_destroy is a seatbelt: these hold live data (metrics/logs history, mail
# backups). A stray `terraform destroy` or an accidental resource removal must
# NOT be able to delete a bucket full of backups — Terraform will error instead.

# Loki log chunks (~11GB, 30d retention).
resource "cloudflare_r2_bucket" "loki" {
  account_id = var.cloudflare_account_id
  name       = "skylab-loki"

  lifecycle {
    prevent_destroy = true
  }
}

# Thanos metric blocks (~28GB, downsampled long-term).
resource "cloudflare_r2_bucket" "thanos" {
  account_id = var.cloudflare_account_id
  name       = "skylab-thanos"

  lifecycle {
    prevent_destroy = true
  }
}

# Stalwart mail Postgres backups (barman WAL + base backups). NEW — create this
# one, then flip backup.enabled in the stalwart chart and point it at this bucket.
resource "cloudflare_r2_bucket" "stalwart_pg" {
  account_id = var.cloudflare_account_id
  name       = "skylab-stalwart-pg"

  lifecycle {
    prevent_destroy = true
  }
}

# Harbor registry blobs (image layers, scan artifacts). NEW — create this one,
# then mint an R2 token scoped to it for kvv2/cluster/skylab/apps/harbor.
resource "cloudflare_r2_bucket" "harbor" {
  account_id = var.cloudflare_account_id
  name       = "skylab-harbor"

  lifecycle {
    prevent_destroy = true
  }
}
