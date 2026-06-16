# Skylab deploy loop.
#
# ArgoCD watches GitHub (main) and auto-syncs. The daily loop is:
#   edit -> `make preview` (instant local render/diff, no apply) -> `make deploy`
#
# `make deploy` just commits + pushes; ArgoCD reconciles the cluster from GitHub.

SHELL    := /bin/bash
CLUSTER  ?= skylab
MSG      ?= deploy
# Every helm-wrapper chart (a directory containing a Chart.yaml under k8s/projects).
PROJECTS := $(shell find k8s/projects -name Chart.yaml -exec dirname {} \;)

# Ansible bootstrap (local-only inventory + secrets; see ansible/inventories/skylab/).
ANSIBLE_DIR := ansible
LAB_INV     := inventories/skylab/hosts.local.ini
LAB_SECRETS := inventories/skylab/secrets.local.yml

.PHONY: help deps deploy preview preview-apps template bootstrap delete vault-unseal upgrade add-node refresh

help:
	@echo "make bootstrap             provision cluster + ArgoCD + Vault (init+unseal) + root app"
	@echo "make delete                DESTRUCTIVE: uninstall RKE2 on every node (wipes all data)"
	@echo "make upgrade               rolling RKE2 upgrade (bump rke2_version first) + re-unseal"
	@echo "make add-node              join new node(s) added to hosts.local.ini"
	@echo "make vault-unseal          unseal Vault from local keys (after a Vault pod restart)"
	@echo "make deploy   [MSG=...]   commit + push to GitHub; ArgoCD auto-syncs"
	@echo "make refresh               force ArgoCD to re-pull GitHub now (hard refresh all apps)"
	@echo "make preview  [CLUSTER=skylab] helm template + kubectl diff (needs a live cluster)"
	@echo "make preview-apps          kubectl diff the app-of-apps (ApplicationSets)"
	@echo "make template [CLUSTER=skylab] render every chart to validate values (no cluster)"
	@echo "make deps                  helm dependency build/update for every chart"

# One-shot cluster bootstrap: RKE2 + Cilium + Traefik + ArgoCD + Vault
# (deploy/init/unseal) + applies the root ApplicationSet. Idempotent.
bootstrap:
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(LAB_INV) -e @$(LAB_SECRETS) playbooks/skylab/start.yml

# Tear the cluster down: runs rke2-uninstall on every node. DESTRUCTIVE — wipes
# all workloads, PVCs, and Vault data. For a clean rebuild: `make delete bootstrap`.
delete:
	@read -r -p "Delete the $(CLUSTER) cluster — uninstall RKE2 and wipe ALL data? [y/N] " ok; \
	  [ "$$ok" = y ] || [ "$$ok" = Y ] || { echo "aborted"; exit 1; }
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(LAB_INV) -e @$(LAB_SECRETS) playbooks/skylab/delete.yml

# Rolling RKE2 upgrade. Bump `rke2_version` in ansible/playbooks/skylab/vars.yml
# first (one minor at a time). Skips the one-time Helm bootstrap; re-unseals Vault.
upgrade:
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(LAB_INV) -e @$(LAB_SECRETS) playbooks/skylab/upgrade.yml

# Join new node(s) added to hosts.local.ini (reuse the same rke2_token). Skips
# the one-time Helm bootstrap — Cilium's DaemonSet covers the new node.
add-node:
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(LAB_INV) -e @$(LAB_SECRETS) playbooks/skylab/add-node.yml

# Unseal Vault from the locally-saved keys. Idempotent: no-op if already unsealed.
# Run this after a reboot / Vault pod restart re-seals it. Does not touch Helm.
vault-unseal:
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(LAB_INV) playbooks/skylab/unseal.yml

# Force ArgoCD to re-pull GitHub immediately (hard refresh every app), instead of
# waiting for the per-tier ~3min reconcile to cascade through the app-of-apps.
refresh:
	kubectl -n argocd annotate applications.argoproj.io --all argocd.argoproj.io/refresh=hard --overwrite

# Vendored subcharts (charts/*.tgz) need their deps resolved before templating.
deps:
	@for d in $(PROJECTS); do \
	  echo "deps: $$d"; \
	  helm dependency build "$$d" 2>/dev/null || helm dependency update "$$d" || true; \
	done

# Inner loop: commit + push. ArgoCD (auto-sync) does the rest from GitHub.
# `argocd app wait` is best-effort and needs `argocd login` first.
deploy:
	git add -A
	git commit -m "$(MSG)" || true
	git push origin HEAD
	-argocd app wait -l argocd.argoproj.io/instance --timeout 600

# Render each chart with its base + per-cluster values. No cluster required;
# catches values/templating errors fast.
template: deps
	@for d in $(PROJECTS); do \
	  vf="-f $$d/values.yaml"; \
	  [ -f "$$d/values/$(CLUSTER).yaml" ] && vf="$$vf -f $$d/values/$(CLUSTER).yaml"; \
	  echo "=== template $$d ($(CLUSTER)) ==="; \
	  helm template "$$(basename $$d)" "$$d" $$vf >/dev/null || exit 1; \
	done
	@echo "all charts rendered OK"

# Diff rendered charts against the live cluster (requires kubectl context).
preview: deps
	@for d in $(PROJECTS); do \
	  vf="-f $$d/values.yaml"; \
	  [ -f "$$d/values/$(CLUSTER).yaml" ] && vf="$$vf -f $$d/values/$(CLUSTER).yaml"; \
	  echo "=== diff $$d ($(CLUSTER)) ==="; \
	  helm template "$$(basename $$d)" "$$d" $$vf | kubectl diff -f - || true; \
	done

# Render/diff the ApplicationSet app-of-apps layer (the kustomize tree).
preview-apps:
	kubectl kustomize k8s/apps | kubectl diff -f - || true
