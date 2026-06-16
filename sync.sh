#!/bin/bash
# Bootstrap ArgoCD against the GitHub source of truth.
# ArgoCD reads everything from https://github.com/skyf0l/skylab.git (public repo,
# so no repository credential is needed). This applies the root ApplicationSet
# (clusters/<cluster>/application.yml), which reads clusters/<cluster>/config.json
# and fans out every stack. Idempotent — safe to re-run.
#
# Usage: ./sync.sh [cluster]   (default: skylab)

set -eE

repoDir=$(git rev-parse --show-toplevel)
cluster="${1:-skylab}"
rootApplicationPath="${repoDir}/clusters/${cluster}/application.yml"

if [[ ! -f "${rootApplicationPath}" ]]; then
    echo "No bootstrap application for cluster '${cluster}' at ${rootApplicationPath}" >&2
    exit 1
fi

kubectl apply --namespace=argocd -f "${rootApplicationPath}"
