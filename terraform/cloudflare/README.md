# terraform/cloudflare — Cloudflare account infrastructure

Manages Cloudflare **infrastructure** as code: R2 buckets today, zone settings /
account config later. Plan on PR, apply on push to `main` (`.github/workflows/cloudflare.yml`).

## Boundary — what this does and does NOT manage

| Resource                                  | Owner                                                                                          |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| R2 buckets, zone settings, account config | **this module**                                                                                |
| DNS records (A/MX/TXT/DKIM/…)             | **external-dns** (in-cluster) — never add `cloudflare_record` here, it will fight external-dns |
| API tokens                                | **Vault** cloudflare secrets engine                                                            |

State lives in R2 (`tfstates` bucket, key `cloudflare.tfstate`) — separate from
`terraform/vault`'s `vault.tfstate`.

## Credentials

None to create by hand. CI (`.github/workflows/cloudflare.yml`) mints everything
at runtime: the R2 state keypair from `kvv2/cicd/cloudflare-tfstates` and a
short-lived Cloudflare token from the Vault cloudflare engine (`r2-read` on PR
plans, `r2-admin` on main applies — roles in `terraform/vault/cloudflare.tf`).

For a local escape-hatch run, mint the same token yourself:

```sh
export VAULT_ADDR=https://vault.tail.skyf0l.dev VAULT_TOKEN=<admin>
export CLOUDFLARE_API_TOKEN=$(vault read -field=token cloudflare/creds/r2-admin)
export AWS_ACCESS_KEY_ID=$(vault kv get -mount=kvv2 -field=AWS_ACCESS_KEY_ID cicd/cloudflare-tfstates)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -mount=kvv2 -field=AWS_SECRET_ACCESS_KEY cicd/cloudflare-tfstates)
```

## First run (adopt existing buckets + create the mail one)

```sh
cd terraform/cloudflare
terraform init          # downloads the cloudflare v5 provider, writes .terraform.lock.hcl
terraform plan          # MUST read: 2 to import (loki, thanos), 1 to create (stalwart-pg)
terraform apply
```

The `import {}` blocks in `imports.tf` bring the two existing, data-filled
buckets under management without recreating them. If `plan` says it wants to
_create_ skylab-loki or skylab-thanos rather than _import_ them, stop — the
import id or name is wrong, and creating would clobber/duplicate live data.

## Ongoing

- Change HCL → `terraform plan` (review) → `terraform apply`.
- Adding a bucket: new `cloudflare_r2_bucket` block; no import needed for a
  brand-new one.
- `prevent_destroy` guards the data buckets: removing a bucket for real means
  deleting its resource block AND the lifecycle guard, deliberately.

## NOT managed here (bootstrap chicken-and-egg)

The `tfstates` bucket holds this module's own state, so it can't be a resource
here. It stays a one-time manually created bucket.
