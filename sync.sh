#!/bin/bash

set -eE

repoDir=$(git rev-parse --show-toplevel)

repoName="gitops"
giteaAdminUsername="admin"
giteaAdminPassword="admin"

portForwardPort=3000
kubectl port-forward --namespace=gitea svc/gitea-http ${portForwardPort}:3000 &
giteaPortForwardPid=$!

clean() {
    kill ${giteaPortForwardPid} 2>/dev/null || true
}
trap 'clean' SIGINT SIGTERM

# Wait for port-forward to be established
while ! nc -z localhost ${portForwardPort}; do
    sleep 1
done

(
    tempDir=$(mktemp -d)
    
    curl \
    --request POST \
    --user "${giteaAdminUsername}:${giteaAdminPassword}" \
    --header "Content-Type: application/json" \
    --data '{"name":"'${repoName}'", "default_branch":"main", "private":true}' \
    "http://localhost:${portForwardPort}/api/v1/user/repos"
    
    rsync -a ${repoDir}/ ${tempDir} --exclude ".git" --filter=':- .gitignore'
    cd "${tempDir}"
    git init
    git remote add origin "http://${giteaAdminUsername}:${giteaAdminPassword}@localhost:${portForwardPort}/${giteaAdminUsername}/${repoName}.git"
    git add . || true
    git config user.email "gitea@local.domain"
    git config user.name "${giteaAdminUsername}"
    git commit -m "Initial commit" || true
    git push origin HEAD:main --force
    rm -rf "${tempDir}"
)

kill ${giteaPortForwardPid} 2>/dev/null || true
