#!/bin/bash

set -eE

repoDir=$(git rev-parse --show-toplevel)

giteaRepoName="gitops"
giteaAdminUsername="gitea_admin"
giteaAdminEmail="gitea@local.domain"
giteaAdminPassword="admin"

rootApplicationPath="${repoDir}/clusters/vagrant/application.yml"

portForwardPort=3000
kubectl port-forward --namespace=gitea svc/gitea-http ${portForwardPort}:3000 &
giteaPortForwardPid=$!

clean() {
    kill ${giteaPortForwardPid} 2>/dev/null || true
}
trap 'clean' SIGINT SIGTERM

# Wait for port-forward to be established
while ! nc -z localhost ${portForwardPort}; do
    echo "Waiting for Gitea port-forward to be established..."
    sleep 1
done

(
    tempDir=$(mktemp -d)
    
    curl \
    --request POST \
    --user "${giteaAdminUsername}:${giteaAdminPassword}" \
    --header "Content-Type: application/json" \
    --data '{"name":"'${giteaRepoName}'", "default_branch":"main", "private":true}' \
    "http://localhost:${portForwardPort}/api/v1/user/repos"
    
    rsync -a ${repoDir}/ ${tempDir} --exclude ".git" --filter=':- .gitignore'
    cd "${tempDir}"
    git init
    git remote add origin "http://${giteaAdminUsername}:${giteaAdminPassword}@localhost:${portForwardPort}/${giteaAdminUsername}/${giteaRepoName}.git"
    git add . || true
    git config user.email "${giteaAdminEmail}"
    git config user.name "${giteaAdminUsername}"
    git commit -m "Initial commit" || true
    git push origin HEAD:main --force
    rm -rf "${tempDir}"
)

kill ${giteaPortForwardPid} 2>/dev/null || true

cat<<EOF | kubectl apply --namespace=argocd -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${giteaRepoName}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: http://gitea-http.gitea.svc.cluster.local:${portForwardPort}/${giteaAdminUsername}/${giteaRepoName}
  password: ${giteaAdminPassword}
  username: ${giteaAdminUsername}
EOF

kubectl apply --namespace=argocd -f "${rootApplicationPath}"