# External Secrets Operator (ESO) reads app secrets on behalf of ExternalSecrets
# across all namespaces, via a single ClusterSecretStore login. It is a central
# operator, so it needs read across this cluster's app secret tree
# (kvv2/data/cluster/<cluster>/apps/<app>) — but strictly read-only, confined to
# this cluster's prefix, and to the apps/ subtree (workload/injector secrets live
# under workloads/ and are not exposed to ESO).
path "kvv2/data/cluster/${cluster_name}/apps/*" {
  capabilities = ["read"]
}

path "kvv2/metadata/cluster/${cluster_name}/apps/*" {
  capabilities = ["read", "list"]
}

# Dynamic database credentials from the database engine. A read here triggers
# issuance of a fresh leased role; ESO projects it into a workload Secret. Wildcard
# so any app's role is covered (mirrors the apps/* kv grant) — one role per app.
path "database/creds/*" {
  capabilities = ["read"]
}
