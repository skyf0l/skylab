# Vault

In-cluster HashiCorp Vault (HA / Raft) — the cluster's secret backend, read by
the External Secrets Operator (ESO) and the Vault Injector.

## Layout

- `terraform/` — Vault _structure_ as code: mounts (PKI, KV v2), auth backends
  (GitHub OIDC + Kubernetes), policies, and roles. Applied by the `Vault`
  GitHub Action on push to `main` (`.github/workflows/vault.yml`). Holds **no
  secret values**.
- `seed-secrets.sh` — seeds bootstrap secret _values_ (random crypto material +
  human-filled placeholders) so apps' ExternalSecrets can sync on a fresh
  cluster. Idempotent; never clobbers existing values.

## How Vault is deployed

The Vault server itself is **not** managed here. It is deployed in-cluster via
the Helm chart at `k8s/projects/gitops-stack/vault` and initialized/unsealed by
the Ansible role `ansible/roles/gitops/install` (init/unseal is imperative and
can't be done by ArgoCD; ArgoCD adopts the release afterwards). The unseal keys
and root token are written only to the gitignored Ansible workdir.

## Bootstrap order (fresh cluster)

1. **Deploy + init/unseal Vault** — Ansible (`gitops/install`).
2. **Apply Terraform structure** — the first apply needs the root token (it
   creates the auth backends the GitHub Action later authenticates with, and
   seeds the R2 state creds). After that the GitHub Action handles every change:

   ```sh
   cd terraform
   export VAULT_ADDR=https://vault.skyf0l.dev
   export VAULT_TOKEN=<root-token>   # one-time, bootstrap only
   terraform init && terraform apply
   ```

3. **Seed bootstrap secrets** — so ESO finds the keys it expects:

   ```sh
   export VAULT_ADDR=https://vault.skyf0l.dev
   export VAULT_TOKEN=<root-or-admin-token>
   ./seed-secrets.sh
   ```

   Crypto fields are generated random and need no attention. Fields marked
   `PLACEHOLDER` (e.g. Authelia's `users_yaml`) must be filled in via the Vault
   UI/CLI — re-running the script leaves whatever you set untouched.

## Cloudflare engine (one-time seed)

The `cloudflare` secrets engine (dynamic Cloudflare API tokens + opt-in R2 S3
creds) is structure-as-code in `terraform/cloudflare.tf` (plugin registration,
mount, roles, rotation policy/role); the plugin binary is delivered to the Vault
pods by an initContainer in `k8s/projects/gitops-stack/vault`. Adding or bumping
the plugin needs a Vault restart + unseal (the `plugin_directory` lives in server
config), so:

1. **Helm first** — merge the values change (initContainer + `plugin_directory`),
   let ArgoCD sync, then **unseal** (`gitops/install`). Only then does
   `terraform apply` succeed (the mount spawns the plugin, which must be on disk).
2. **Seed the parent token once, via CLI** — it is a real credential, so it is
   never put in git or Terraform state. Write it, then immediately roll it so
   Vault owns a fresh value and the seeded one dies:

   ```sh
   export VAULT_ADDR=https://vault.skyf0l.dev VAULT_TOKEN=<root-or-admin>
   CF_BOOTSTRAP='<parent token: Account API Tokens Edit + Workers R2 Storage Edit>'
   vault write cloudflare/config \
     cloudflare_account_id=72daf8bcee8eb1ea408602f0d509a61f \
     cloudflare_api_token="$CF_BOOTSTRAP"
   vault write -f cloudflare/config/rotate-root token_type=account
   unset CF_BOOTSTRAP
   ```

Ongoing rotation is automatic: the `cloudflare-rotate-root` CronJob (vault chart)
rolls the parent value monthly via the `cloudflare-rotate` k8s-auth role. On a
full Vault rebuild the Vault-owned value is lost (as with the database engine's
`vault_mgr`), so DR = create a fresh parent token and re-run the seed above.

## Ongoing changes

Structure changes go through `terraform/` and are applied by the GitHub Action
(PRs get a plan comment; merges to `main` apply). Adding a new app's bootstrap
secret is a new `seed_field` block in `seed-secrets.sh`.
