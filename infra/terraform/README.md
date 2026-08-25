# infra/terraform — Cloudflare account infrastructure

Manages Cloudflare **infrastructure** as code: R2 buckets today, zone settings /
account config later. Manual `plan`/`apply` for now (no CI).

## Boundary — what this does and does NOT manage

| Resource                                  | Owner                                                                                          |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| R2 buckets, zone settings, account config | **this module**                                                                                |
| DNS records (A/MX/TXT/DKIM/…)             | **external-dns** (in-cluster) — never add `cloudflare_record` here, it will fight external-dns |
| API tokens                                | **Vault** cloudflare secrets engine                                                            |

State lives in R2 (`tfstates` bucket, key `cloudflare.tfstate`) — separate from
`vault/terraform`'s `vault.tfstate`.

## Credentials (two, different)

1. **Provider** — `CLOUDFLARE_API_TOKEN`, a token with **Account → Workers R2
   Storage → Edit** (+ Zone Settings:Edit if you manage those later). Make it in
   the dashboard: My Profile → API Tokens → Create Token → Custom. There is no
   Terraform "login"/OAuth; `wrangler login` does NOT work for Terraform. Do not
   use a Vault-minted token — those roles are IP-pinned to the VPS.
2. **State backend** — the same R2 S3 keypair `vault/terraform` uses, exported
   as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.

```sh
export CLOUDFLARE_API_TOKEN='<Workers R2 Storage:Edit token>'
export AWS_ACCESS_KEY_ID='<r2 s3 access key id>'
export AWS_SECRET_ACCESS_KEY='<r2 s3 secret access key>'
```

## First run (adopt existing buckets + create the mail one)

```sh
cd infra/terraform
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
