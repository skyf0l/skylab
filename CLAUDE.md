# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

GitOps monorepo for `skylab`, a personal prod-like homelab: a single RKE2 cluster on a rented VPS (the only schedulable node, labeled `node-role.skylab/heavy`) plus a Raspberry Pi 5 worker (tainted `node-role.skylab/light=true:NoSchedule`, joined over WireGuard). ArgoCD syncs from `main` of the public GitHub repo `skyf0l/skylab` (~60s poll); domain is `skyf0l.dev`. A sibling private repo `skyf0l/skylab-private` holds everything private.

## Working rules

- **Never commit or push yourself.** Make the edits, then hand over a commit message; the user commits. Only commit/push when explicitly told (e.g. "ok commit"). Occasional debug-pushes to main are tolerated only when explicitly granted.
- **Commit style**: single line, conventional prefix matching repo history (`feat(mail): ...`, `fix(opencost): ...`, `chore(deps): ...`), written like a human. No em-dash, no body, no AI attribution.
- **Suggest first, then edit.** For design decisions, present options and trade-offs and wait for "ok do X" before touching files. Audit requests mean audit only.
- **Minimal, exactly-scoped diffs.** No meta-comments ("moved from ..."), no unrequested defensive code, no gold-plating. Don't mention learning/demo motivations in code or comments — the repo must read as prod.
- **Everything as code.** No manual/UI-only configuration: OIDC clients, DNS records, Vault roles, mail domains/accounts all land in this repo (or skylab-private).
- **GitOps only, never touch the live cluster.** Every change lands in git and reaches the cluster through ArgoCD. Never `kubectl apply/create/edit/patch/scale/delete`, never `helm install/upgrade`, never edit a resource in a UI — even to test something. `kubectl` is for reading and diffing only (`get`, `describe`, `logs`, `exec` for debug). The rare exceptions are the documented manual steps below (`./sync.sh` for `clusters/<name>/application.yml`, unwedging a stuck sync, `make vault-*`, ansible lifecycle) and anything the user explicitly asks for.
- **Private data discipline**: private domains, headscale users/ACLs, private accounts go only in `skylab-private` (multi-source `$private` values overlay). The public repo must not name or hint at them — that includes Cloudflare zone IDs.
- **After a deploy, verify it**: check `kubectl -n argocd get application skylab-<app> -o jsonpath='{.status.sync.status}|{.status.health.status}|{.status.operationState.phase}'`.

## Commands

The Makefile hard-pins `KUBECONFIG` to `ansible/artifacts/$(CLUSTER)/$(CLUSTER).kubeconfig` (default `CLUSTER=skylab`). This is deliberate: the ambient shell context may be the user's unrelated GKE prod cluster — never run bare `kubectl` against the default context; export that KUBECONFIG first.

```sh
# daily loop
make template                 # fast offline render of every chart (values/templating errors)
make preview                  # helm template | kubectl diff (live cluster)
make preview-apps             # diff the ApplicationSet layer (k8s/apps)
make deploy MSG="..."         # commit + push (user-run; agents hand over the message instead)
make refresh                  # hard-refresh all ArgoCD apps after a push

# offline validation (no cluster needed; CI runs these)
make validate                 # validate-schema + validate-policy
make validate-schema          # render + kubeconform      <- the actual CI gate
make validate-policy          # render + kyverno           <- currently disabled in CI
make deps                     # helm dependency build (only after adding/bumping a subchart)
make tf-validate              # terraform fmt -check + validate (isolated, no real state)
yarn format / yarn format:check   # prettier (CI `format` job checks YAML formatting)

# vault (config-as-code in terraform/vault, values via seed script)
make vault-plan / vault-apply     # needs VAULT_ADDR + VAULT_TOKEN; CI also applies on main
make vault-seed                   # seed bootstrap secret values (idempotent, needs root token)
make vault-unseal                 # after a Vault pod restart (keys in ansible/artifacts/)

# cluster lifecycle (ansible)
make bootstrap / upgrade / add-node / delete
./sync.sh [cluster]               # re-apply clusters/<cluster>/application.yml (AppProjects + roots)
```

New DB-/secret-backed app rollout order: `make vault-apply` → `make vault-seed` (if new KV values) → deploy → `make refresh`. The Vault role must exist before ESO can auth.

Live access when granted: `ssh ubuntu@ns3101300.ip-54-36-175.eu` (sudo ok). Vault unseal keys + root token: `ansible/artifacts/skylab/vault-cluster-keys.json` (gitignored, sensitive).

## Architecture

### Bootstrap chain

`make bootstrap` (ansible: RKE2 + Cilium + Traefik + ArgoCD + Vault init/unseal) → applies `clusters/skylab/application.yml`. That file is **hand-applied, not auto-synced** — after editing it (AppProjects, root ApplicationSets), re-run `./sync.sh`. It defines:

- 3 AppProjects by blast radius: `platform` (full), `observability` (limited cluster-scoped kinds), `workloads` (no cluster-scoped resources — apps in it can't `CreateNamespace`). Every Application carries a matching `skylab.dev/tier` label.
- Two root ApplicationSets: `apps` → `k8s/apps` (public) and `private-apps` → `skylab-private.git:clusters/<name>/apps`.

### Three-level ApplicationSet app-of-apps

1. root (`clusters/skylab/application.yml`) → 2. one ApplicationSet per stack (`k8s/apps/<stack>/applications.yaml`) → 3. one ApplicationSet per app (`k8s/apps/<stack>/apps/<app>.yaml`) → the real Application (named `skylab-<app>`).

Every ApplicationSet uses a matrix generator: `list` (cluster name, hardcoded `skylab` under the comment `# Auto updated by parent ApplicationSet`) × git-file generator over `clusters/{{.name}}/config.json`. Parents rewrite children's generator values via `kustomize.patches` JSON-patches — copy an existing app file when adding a new one; this block is the repo's most repeated pattern.

`clusters/skylab/config.json` is the single source of cluster facts (`global.domain`, `global.publicIp`, repo url/revision). Charts never hardcode hostnames — the app-level ApplicationSet injects them as `helm.parameters` (e.g. `mail.{{.global.domain}}`).

Stack-level waves (bootstrap -10, core -8, network -5, identity -3, observability -2, security 0, finops 0, workloads 1) only order the creation of the stack ApplicationSets during the root sync; ApplicationSets never order their children. Real ordering is the per-app wave inside each stack (small positive integers, e.g. core: cert-manager 0 → issuers 1 → ESO 2 → stores 3 → CNPG/keda 4 → keda-http 5; network-policies last at 5) plus leaf `retry.limit: 10` for cross-stack dependencies (CRDs from another stack). The wave annotation appears twice per app file: on the ApplicationSet and on its template.

### Stacks

`k8s/apps/<stack>/` holds the Application definitions; `k8s/projects/<stack>/<app>/` holds the chart. Both use the same stack name, no suffix. Stacks, in wave order: `bootstrap` (cilium, traefik, cluster-bootstrap, vault, argocd — installed by ansible before ArgoCD exists and adopted afterwards; ansible references these paths), `core` (cert-manager + issuers, external-secrets + stores, external-dns, reloader, cloudnative-pg, keda + http add-on: operators whose CRDs other charts instantiate), `network` (headscale + proxy/exit, network-policies), `identity` (authelia, keycloak), `observability` (kube-prometheus, thanos on R2, grafana-dashboards, loki on R2, alloy, uptime-kuma), `security` (trivy, falco-operator + falco, harbor), `finops` (vpa, opencost, goldilocks), `workloads` (stalwart, garmin-mcp). Rule of thumb for a new app: operators others depend on → core; who-can-reach-what → network; OIDC providers → identity; metrics/logs/uptime → observability; things that inspect the cluster → security; end-user products → workloads. Each stack's `kustomization.yml` and the root `k8s/apps/kustomization.yml` are explicit resource lists: a new app file or stack must be added there or it silently never renders.

Exception: `k8s/projects/security/kyverno/` has no ApplicationSet — it is never deployed; it exists only so `make render` can produce `build/policies.yaml` for the (currently disabled) CI policy gate.

### Chart conventions

- **Wrapper charts** (most apps): 6-line `Chart.yaml` with one `dependencies:` entry on the upstream repo; `values.yaml` nests everything under the subchart name (`cilium:`, `argo-cd:` ...). Extra templates (DNSEndpoints, ExternalSecrets, NetworkPolicies) go in the wrapper's own `templates/`.
- **Hand-rolled charts** where upstream is unusable or absent (stalwart, thanos, headscale\*, keycloak, authelia, ...). Prefer official images (quay/ghcr) — Bitnami free-tier images are dead (404 since 2025); hand-roll rather than use Bitnami charts.
- **Values layering**: `values.yaml` (base, cluster-agnostic) → `values/skylab.yaml` (per-cluster) → optional `$private/clusters/<name>/<app>/values.yaml`.
- `**/charts` and `**/Chart.lock` are **gitignored** — ArgoCD resolves helm dependencies at sync time, so a Renovate `Chart.yaml` bump is a self-contained one-line change. Run `make deps` locally after bumping.
- Standard syncPolicy: automated prune+selfHeal, `CreateNamespace`, `RespectIgnoreDifferences`, `ServerSideApply` (with documented exceptions for workloads-project and hostPort apps).

### Secrets: Vault + ESO (no SOPS/sealed-secrets)

- Vault _structure_ (mounts, policies, k8s-auth roles, database + Cloudflare secrets engines) is Terraform in `terraform/vault/`, state in Cloudflare R2, applied by `.github/workflows/vault.yml` (joins the tailnet as a `tag:ci` node, GitHub-OIDC → Vault). Secret _values_ are seeded by `vault/seed-secrets.sh`.
- KV path convention: `kvv2/cluster/<cluster>/apps/<app>`. Each chart owns a `templates/externalsecret.yaml` gated by `externalSecret.enabled`, referencing ClusterSecretStore `vault-backend`.
- Dynamic creds where possible: Cloudflare API tokens (cert-manager, external-dns) are minted by Vault engines — never add static Cloudflare tokens. Engine-minted CF tokens are IP-pinned to the VPS and won't work from a laptop.
- Rotation → Reloader annotations restart consumers.

### Networking

- Cilium CNI (kube-proxy replacement, Hubble). CiliumNetworkPolicies are namespace default-deny via `network/network-policies`, currently in `policyAuditMode: true` (log-only). Per-app exceptions live in each app's own chart.
- Traefik = hostPort DaemonSet (no LB). Public exposure is rare (authelia, keycloak OIDC, garmin-mcp gateway, stalwart well-known/jmap) via plain Ingress + cert-manager (DNS-01 Cloudflare; HTTP-01 is broken here).
- **Everything else is tailnet-only** via self-hosted Headscale. `headscale-proxy`'s `services:` list is the pattern: each entry renders a tailscale node (`<name>.tail.skyf0l.dev`) + an IngressRoute guarded by the `tailnet-only` middleware (ipAllowList on pod CIDR). Add tailnet services there.
- DNS-as-code: external-dns with `sources: [crd]` only — apps ship `DNSEndpoint` CRs; `policy: sync`, TXT ownership `edns-<type>-` prefixed.

### Public/private split

Three mechanisms: (1) `private-apps` root ApplicationSet → fully private apps; (2) multi-source `$private` values overlay (`headscale.yaml`, `stalwart.yaml` use `ignoreMissingValueFiles: true` + a values-only `ref: private` source); (3) `garmin-mcp.yaml` inverts it — upstream chart repo as source, this repo provides `$values` plus a sibling gateway chart.

### Renovate + CI

Renovate auto-merges minor/patch (docker + all majors need a human) and relies on branch protection requiring the CI checks `validate`, `terraform`, `format`, `actionlint`. CI's `validate` job runs only `make validate-schema` — the kyverno policy gate is commented out in `ci.yml`. Renovate PRs are handled one-by-one; fixing CI (usually prettier) is part of merging them.

## Gotchas

- **Never re-run `make bootstrap` against a live cluster** for a config change — the ansible helm-init steps fight ArgoCD over Cilium/Traefik. Use `make upgrade` (skips init) or hand-edit `/etc/rancher/rke2/config.yaml` + restart `rke2-server` on the node (take `rke2 etcd-snapshot save` first).
- A failing ArgoCD **Sync/PostSync hook Job wedges the whole app** — even the fix can't sync. Keep provisioning jobs non-blocking; unwedge manually. Similarly, a crashlooping StatefulSet can pin a sync operation in `phase=Running` forever, blocking newer revisions.
- Upstream charts that render resources as **Helm hooks** (e.g. a ServiceAccount created as a `pre-install` hook) are mishandled by ArgoCD — disable the hooks and manage the resource in the wrapper chart.
- **ExternalSecrets**: `spec.target.template.engine` was removed in ESO v2.6.0 (SyncError if present). Perpetual-OutOfSync from server defaults is already fixed globally via `ignoreDifferences` in `bootstrap/argocd/values.yaml`; changing that customization needs an application-controller restart, not just a refresh.
- **external-dns Cloudflare provider bugs**: declare MX priority `0` (anything else churns forever); TXT records are create-only (SPF/DMARC edits silently don't apply — delete the record in CF and let it recreate); an unowned manual record on a name silently blocks external-dns for that name.
- **Headscale Renovate bumps are coupled**: a headscale upgrade runs one-way DB migrations and requires compatible tailscale client versions — bump the tailscale image in `headscale-proxy`/`headscale-exit` in the same change. Forward-fix beats rollback. CLI: `preauthkeys create --user <numeric-id>` (not a name); stale pre-auth keys crash-loop tailnet pods.
- Vault chart: injector is disabled (redundant with ESO; its podAntiAffinity deadlocks on one node). To clear chart affinity use `affinity: ""` (empty string — the chart `tpl`s it, `{}` fails).
- Traefik v3 rejects encoded slashes by default (broke Vault UI KV browsing — `allowEncodedSlash` is set); a backend restart can leave a stale route serving 502 → `kubectl -n traefik rollout restart daemonset traefik`.
- `make render` output has no namespaces (ArgoCD injects them), so kyverno CLI flags `disallow-default-namespace` on everything — scan artifact, ignore.
- `kubeconform -ignore-missing-schemas` means CRDs aren't schema-validated; `helm template` skips CRDs but ArgoCD renders with `--include-crds`.
- New apps referencing a new AppProject fail with "project does not exist" until `./sync.sh` has applied the bootstrap file.
- **Renaming or merging a stack deletes workloads unless you disarm the finalizers first.** Generated Applications carry `resources-finalizer.argocd.argoproj.io` (added by the ApplicationSet controller by default) and parents prune with foreground propagation, so pruning a stack ApplicationSet cascades down to the pods and tracked PVCs. Safe recipe (used for the 2026-08 reorg, no data loss): set `spec.syncPolicy.preserveResourcesOnDeletion: true` on every stack and app ApplicationSet in a first PR (the controller then strips the finalizers; verify with `kubectl -n argocd get applications -o json | jq '.items[]|select(.metadata.finalizers==null)|.metadata.name'`), move stacks one PR at a time (leaf Application names `skylab-<app>` must not change; they re-adopt their resources), then remove the flag in a last PR so pruning works again. Take an etcd snapshot, a Vault raft snapshot and `pg_dumpall` of the CNPG clusters before starting; none of them has automated backups.
