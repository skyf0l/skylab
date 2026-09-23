# Vault

In-cluster HashiCorp Vault (HA / Raft) — the cluster's secret backend, read by
the External Secrets Operator (ESO) and the Vault Injector.

## Layout

- this module — Vault _structure_ as code: mounts (PKI, KV v2), auth backends
  (GitHub OIDC + Kubernetes), policies, and roles. Applied by the `Vault`
  GitHub Action on push to `main` (`.github/workflows/vault.yml`). Holds **no
  secret values**.
- `scripts/seed-secrets.sh` (repo root) — seeds bootstrap secret _values_ (random crypto material +
  human-filled placeholders) so apps' ExternalSecrets can sync on a fresh
  cluster. Idempotent; never clobbers existing values.

## How Vault is deployed

The Vault server itself is **not** managed here. It is deployed in-cluster via
the Helm chart at `k8s/projects/bootstrap/vault` and initialized/unsealed by
the Ansible role `ansible/roles/gitops/install` (init/unseal is imperative and
can't be done by ArgoCD; ArgoCD adopts the release afterwards). The unseal keys
and root token are written only to the gitignored Ansible workdir.

## Bootstrap order (fresh cluster)

1. **Deploy + init/unseal Vault** — Ansible (`gitops/install`).
2. **Apply Terraform structure** — the first apply needs the root token (it
   creates the auth backends the GitHub Action later authenticates with, and
   seeds the R2 state creds). After that the GitHub Action handles every change:

   ```sh
   cd terraform/vault
   export VAULT_ADDR=https://vault.skyf0l.dev
   export VAULT_TOKEN=<root-token>   # one-time, bootstrap only
   terraform init && terraform apply
   ```

3. **Seed bootstrap secrets** — so ESO finds the keys it expects:

   ```sh
   export VAULT_ADDR=https://vault.skyf0l.dev
   export VAULT_TOKEN=<root-or-admin-token>
   ./scripts/seed-secrets.sh   # from the repo root
   ```

   Crypto fields are generated random and need no attention. Fields marked
   `PLACEHOLDER` (e.g. Authelia's `users_yaml`) must be filled in via the Vault
   UI/CLI — re-running the script leaves whatever you set untouched.

## Cloudflare engine (one-time seed)

The `cloudflare` secrets engine (dynamic Cloudflare API tokens + opt-in R2 S3
creds) is structure-as-code in `terraform/cloudflare.tf` (plugin registration,
mount, roles, rotation policy/role); the plugin binary is delivered to the Vault
pods by an initContainer in `k8s/projects/bootstrap/vault`. Adding or bumping
the plugin needs a Vault restart + unseal (the `plugin_directory` lives in server
config), so:

1. **Helm first**: merge the values change (initContainer + `plugin_directory`),
   let ArgoCD sync, then **unseal** (`gitops/install`). Only then does
   `terraform apply` succeed (the mount spawns the plugin, which must be on disk).
2. **Seed the parent token once, via CLI**: it is a real credential, so it is
   never put in git or Terraform state. Write it, then immediately roll it so
   Vault owns a fresh value and the seeded one dies:

   ```sh
   export VAULT_ADDR=https://vault.skyf0l.dev VAULT_TOKEN=<root-or-admin>
   CF_BOOTSTRAP='<parent token: Account API Tokens Edit + Workers R2 Storage Edit>'
   vault write cloudflare/config \
     cloudflare_account_id=2620dc6ee3d578b27347d8e5efd95f32 \
     cloudflare_api_token="$CF_BOOTSTRAP"
   vault write -f cloudflare/config/rotate-root token_type=account
   unset CF_BOOTSTRAP
   ```

Ongoing rotation is automatic: the `cloudflare-rotate-root` CronJob (vault chart)
rolls the parent value monthly via the `cloudflare-rotate` k8s-auth role. On a
full Vault rebuild the Vault-owned value is lost (as with the database engine's
`vault_mgr`), so DR = create a fresh parent token and re-run the seed above.

## Harbor engine (one-time seed)

The `harbor` secrets engine ([skyf0l/vault-plugin-harbor](https://github.com/skyf0l/vault-plugin-harbor),
Go module path still `github.com/manhtukhang/...` on purpose) mints one Harbor robot
per `vault read harbor/creds/<role>` and deletes it when the lease ends. Plugin,
mount (15m default / 24h max lease), roles, rate limit and the rotation
policy/role are in `harbor.tf`; the binary comes from the `fetch-harbor-plugin`
initContainer. Vault reaches Harbor in-cluster at `https://harbor.harbor.svc`,
served with the harbor chart's namespace-local CA.

The principal is a Harbor **system robot**, the one credential that can mint
robots. It never goes in KV (`external-secrets` reads all of
`kvv2/cluster/<cluster>/apps/*`) nor in Terraform state: seed it by CLI, then
rotate at once so only Vault knows the live secret. Order: Harbor TLS live,
plugin on disk (see "Plugin bump" steps 2-3), `terraform apply` done.

1. **Harbor** (admin, over the tailnet). Without `adminonly`, any system-level
   robot can create projects whatever its permissions say:

   ```sh
   H=https://harbor.tail.skyf0l.dev/api/v2.0
   HARBOR_ADMIN='<kvv2/cluster/skylab/apps/harbor admin_password>'
   curl -fsS -u "admin:$HARBOR_ADMIN" -H 'Content-Type: application/json' \
     -X PUT "$H/configurations" -d '{"project_creation_restriction":"adminonly"}'
   curl -fsS -u "admin:$HARBOR_ADMIN" -H 'Content-Type: application/json' \
     -X POST "$H/robots" -d @principal.json   # prints name + secret ONCE
   ```

   `principal.json`: robot CRUD at system level (rotate-root, lookups), and per
   project robot CRUD, `project:read` (rollback resolves the project by name and
   403s on a private one without it) plus every permission a role grants.
   Harbor only lets a robot create robots whose permissions are a subset of its
   own, so this list is the hard ceiling of the engine. Add a project entry
   before adding a role for it.

   ```json
   {
     "name": "vault-harbor",
     "description": "Vault harbor secrets engine principal",
     "duration": -1,
     "level": "system",
     "permissions": [
       {
         "kind": "system",
         "namespace": "/",
         "access": [
           { "resource": "robot", "action": "create" },
           { "resource": "robot", "action": "read" },
           { "resource": "robot", "action": "list" },
           { "resource": "robot", "action": "delete" }
         ]
       },
       {
         "kind": "project",
         "namespace": "skyf0l.dev",
         "access": [
           { "resource": "robot", "action": "create" },
           { "resource": "robot", "action": "read" },
           { "resource": "robot", "action": "list" },
           { "resource": "robot", "action": "delete" },
           { "resource": "project", "action": "read" },
           { "resource": "repository", "action": "pull" },
           { "resource": "repository", "action": "push" }
         ]
       }
     ]
   }
   ```

2. **Vault** (root token). Settle the URL first: after `rotate-root` the robot
   is renamed (`robot$vault-harbor.r<unixnano>`) and nobody knows its secret, so
   `url`/`username` can no longer change without re-seeding. `ca_cert` can
   (see "Harbor CA rotation"):

   ```sh
   export VAULT_ADDR=https://vault.tail.skyf0l.dev VAULT_TOKEN=<root>
   kubectl -n harbor get secret harbor-internal-tls -o jsonpath='{.data.ca\.crt}' \
     | base64 -d > harbor-ca.pem
   HARBOR_BOOTSTRAP='<secret printed by the robot creation>'
   vault write harbor/config url=https://harbor.harbor.svc \
     username='robot$vault-harbor' password="$HARBOR_BOOTSTRAP" ca_cert=@harbor-ca.pem
   vault write -f harbor/config/rotate-root   # returns username + robot_id only
   unset HARBOR_BOOTSTRAP HARBOR_ADMIN
   ```

Ongoing rotation: the `harbor-rotate-root` CronJob (vault chart, 15th of the
month, `harbor-rotate` k8s-auth role); `HarborRotateRootStale` fires after 35
days without a success. DR: a Vault rebuild loses the principal, so delete the
old `robot$vault-harbor.r*` in Harbor and re-run this seed.

Never `vault delete harbor/config`: revocation reads it to reach Harbor, so
every outstanding lease becomes irrevocable and its robot lives on.

### Harbor CA rotation

The CA (`harbor-internal-ca`, 10y) outlives leaf renewals, so `ca_cert` only
changes if the CA is re-issued. No password needed; pass old + new as one PEM
bundle while both are served, then the new one alone:

```sh
vault write harbor/config ca_cert=@harbor-ca.pem
```

Symptom if missed: issuance and revocation fail with
`x509: certificate signed by unknown authority`.

### Plugin bump

1. Bump `PLUGIN_VERSION` in the `fetch-harbor-plugin` initContainer
   (`k8s/projects/bootstrap/vault/values.yaml`) and `harbor_plugin_version` +
   `harbor_plugin_sha256` here (sha of `vault-plugin-harbor_<v>_linux_x86_64`
   from the release `_SHA256SUMS`, itself signed by the `.sigstore.json`
   bundle), in two PRs: helm first.
2. After ArgoCD syncs the StatefulSet (OnDelete: nothing restarts by itself):
   `kubectl -n vault delete pod vault-0`, then `make vault-unseal`.
3. From here until step 4 the mount is down: the file on disk no longer
   matches the registered sha256. Merge the Terraform PR right away; the apply
   registers the new version and moves the mount's `plugin_version`.
4. `vault plugin reload -type=secret -plugin=vault-plugin-harbor`, then check
   `vault secrets list -detailed -format=json | jq '."harbor/".running_plugin_version'`.

### Orphaned robot sweep

An orphan is a `vault.*` robot whose lease no longer exists (a `-force` revoke,
a Vault rebuild). It dies on its own at Harbor expiry (lease max + 1h, rounded
up to whole days); sweep by hand only when that is too long.

- Harbor IGNORES `q=ProjectID=<id>` unless `Level=project` is in the same `q`,
  and then returns the system robots, the engine principal and `robot$pull`
  included. That has already deleted a shared principal once. Always send
  both, and never bulk-delete from an unfiltered listing:

  ```sh
  PID=$(curl -fsS -u "admin:$HARBOR_ADMIN" "$H/projects/skyf0l.dev" | jq .project_id)
  curl -fsS -u "admin:$HARBOR_ADMIN" \
    "$H/robots?q=Level%3Dproject,ProjectID%3D$PID&page_size=100" \
    | jq -r '.[] | select(.name | startswith("robot$skyf0l.dev+vault.")) | "\(.id) \(.name)"'
  vault list sys/leases/lookup/harbor/creds/skyf0l-dev-push   # live leases
  ```

- Robots with a live lease are not orphans; the audit log joins them
  (`robot_account_id` is logged in clear next to the lease ID). Delete the
  rest one id at a time: `curl -u ... -X DELETE "$H/robots/<id>"`.

### Irrevocable leases

`VaultIrrevocableLeases` means Vault gave up revoking a lease (Harbor down
longer than the retry window, config changed). For `harbor/creds/*` the robot
is still live in Harbor.

1. List them (the `error` field says why):
   `vault read sys/leases type=irrevocable`.
2. `vault lease revoke -prefix harbor/creds/` reports success and does
   **nothing** for irrevocable leases. Only `-force` clears them:
   `vault lease revoke -force -prefix harbor/creds/<role>/`.
3. `-force` still calls the engine's revoke but drops the lease whatever it
   returns. Fix Harbor reachability FIRST so that call deletes the robot; forced
   while Harbor is down, the lease vanishes and the robot stays.
4. Then run the orphaned robot sweep above for anything left over.

## Ongoing changes

Structure changes go through `terraform/` and are applied by the GitHub Action
(PRs get a plan comment; merges to `main` apply). Adding a new app's bootstrap
secret is a new `seed_field` block in `scripts/seed-secrets.sh`.
