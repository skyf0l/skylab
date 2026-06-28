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

## Ongoing changes

Structure changes go through `terraform/` and are applied by the GitHub Action
(PRs get a plan comment; merges to `main` apply). Adding a new app's bootstrap
secret is a new `seed_field` block in `seed-secrets.sh`.
