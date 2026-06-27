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

# NB: dynamic database credentials (database/creds/*) are NOT granted here. ESO's
# VaultDynamicSecret generator authenticates per-app with its own namespace SA +
# Vault role (e.g. defectdojo-db), not via this central ClusterSecretStore login.
