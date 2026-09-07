# CLAUDE.md

## What this repo is

GitOps monorepo for `skylab`, a personal prod-like homelab: a single RKE2 cluster on a rented VPS. ArgoCD syncs from `main` of the public GitHub repo `skyf0l/skylab` (~60s poll); domain is `skyf0l.dev`. A sibling private repo `skyf0l/skylab-private` holds everything private.

Treat it as production: it runs real mail, real DNS and real public endpoints, and it is
world-readable.

## Rules of engagement

### The cluster is read-only

The live cluster is never edited by hand — desired state lives in git and ArgoCD is the only
thing that writes to the API server. Drift you introduce by hand is invisible in review, gets
reverted by selfHeal, and hides the real bug.

- **Read-only verbs only**: `get`, `describe`, `logs`, `events`, `top`, `diff`, `port-forward`, and `exec` for inspection. Always `export KUBECONFIG=ansible/artifacts/skylab/skylab.kubeconfig` first (see Commands) — a bare `kubectl` may hit the user's unrelated cluster.
- **Never mutate**: no `apply`/`create`/`edit`/`patch`/`replace`/`delete`/`scale`/`label`/`annotate`/`rollout restart`/`cordon`/`drain`, no `helm install|upgrade`, no `argocd app sync|set`, no writes through any UI, no config edits over `ssh`.
- **Escape hatch**: when something genuinely needs a live action (unwedging a stuck sync, `./sync.sh`, `make vault-*`, ansible lifecycle, a `rollout restart`), hand the user the exact command and let them run it. Only act live when they explicitly say to.

### Every change ships through git

- **Never commit or push yourself.** Make the edits, hand over a commit message, the user commits. Only commit when explicitly told ("ok commit").
- **Stage named paths only.** Never `git add -A`, `git add .`, or anything showing as `??` in `git status --short`. An untracked file is untracked on purpose.
- **`main` is protected**: no direct pushes. Ship as branch → `gh pr create` → `gh pr merge --squash --auto`, and let the CI gates (`validate`, `terraform`, `format`, `actionlint`) run.
- **Anything pushed here is public and permanent.** Before staging, ask what the file would leak if it were on the front page of the repo.
- **Commit style**: single-line subject, conventional prefix matching repo history (`feat(mail): ...`, `fix(opencost): ...`, `chore(deps): ...`). No em-dash, no AI attribution, no session or tool links in commits or PR bodies.
- **Body only when it beats reading the diff**: the symptom and root cause behind a fix, the upstream bug or version constraint that forced this shape, what was tried and ruled out, what to check if it regresses. Obvious changes stay a bare subject; never restate the diff.
- **The PR carries the rest**, four short headings: **What**, **Why** (symptom, upstream bug, constraint), **Verification** (commands run and what they returned), **Risk** (blast radius, data at stake, rollback or what makes it one-way). Commit body = why this shape, PR = how it was proven.

### Scope and data

- **Suggest first, then edit.** For design decisions, present options and trade-offs and wait for "ok do X" before touching files. Audit requests mean audit only.
- **Minimal, exactly-scoped diffs.** No unrequested defensive code, no gold-plating. Don't mention learning/demo motivations in code or comments — the repo must read as prod.
- **Comments carry the why, once.** A line earns its place if it holds what the code cannot: an upstream bug, an ordering constraint, a trap that will bite again. Never narrate the diff or the state it replaced ("moved from ...", "was 30s before") — that is history, it rots, and git already has it. One line usually does it.
- **Everything as code.** No manual/UI-only configuration: OIDC clients, DNS records, Vault roles, mail domains/accounts all land in this repo (or skylab-private).
- **Private data discipline**: private domains, headscale users/ACLs, private accounts go only in `skylab-private` (multi-source `$private` values overlay). The public repo must not name or hint at them — that includes Cloudflare zone IDs.
- **Never print or copy a secret** into a file, a commit, a PR body or a chat answer. Vault unseal keys, kubeconfigs and `ansible/artifacts/` are gitignored, and stay that way.

### Verify, then report

- Offline first: `make template` and `make validate-schema` catch most of it without a cluster; `make preview` diffs the render against live.
- After the user deploys: `kubectl -n argocd get application skylab-<app> -o jsonpath='{.status.sync.status}|{.status.health.status}|{.status.operationState.phase}'`.
- Report what the commands actually returned. If a check was skipped or a step is still pending, say so.

## Commands

The Makefile hard-pins `KUBECONFIG` to `ansible/artifacts/$(CLUSTER)/$(CLUSTER).kubeconfig` (default `CLUSTER=skylab`). This is deliberate: the ambient shell context may be the user's unrelated GKE prod cluster — never run bare `kubectl` against the default context; export that KUBECONFIG first.

```sh
# daily loop
make template                 # fast offline render of every chart (values/templating errors)
make preview                  # helm template | kubectl diff (live cluster)
make preview-apps             # diff the ApplicationSet layer (k8s/apps)
make deploy MSG="..."         # git add -A + commit + push (USER-RUN ONLY: it stages every
                              # untracked file and pushes HEAD; agents hand over the message)
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

Live access when granted: `ssh ubuntu@ns3101300.ip-54-36-175.eu` (sudo ok) — read-only inspection unless the user asks for a specific command. Vault unseal keys + root token: `ansible/artifacts/skylab/vault-cluster-keys.json` (gitignored, sensitive).

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

### Chart conventions

- **Wrapper charts** (most apps): 6-line `Chart.yaml` with one `dependencies:` entry on the upstream repo; `values.yaml` nests everything under the subchart name (`cilium:`, `argo-cd:` ...). Extra templates (DNSEndpoints, ExternalSecrets, NetworkPolicies) go in the wrapper's own `templates/`.
- **Hand-rolled charts** where upstream is unusable or absent. Prefer official images (quay/ghcr) — Bitnami free-tier images are dead; hand-roll rather than use Bitnami charts.
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

## Keeping this file useful

- **Suggest edits to it.** When a session turns up something the next one would want — a missing rule, a stale command, a trap that cost time, a convention that has drifted — propose the change instead of quietly working around it. Propose it, don't silently rewrite it.
- **Stay generic.** A rule earns a line here if it applies repo-wide or will bite again elsewhere. A single app's edge case belongs in a comment next to that chart, not in a file loaded into every session.
- **Prune as you go.** Delete what became false, merge duplicates, cut what the code already says. Short and current beats exhaustive.
