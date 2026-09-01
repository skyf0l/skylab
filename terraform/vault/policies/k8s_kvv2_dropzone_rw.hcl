# A workload writes/reads its own dropzone area, under the cluster-scoped
# workloads tree:
#   kvv2/data/cluster/<cluster>/workloads/<ns>/_dropzone/<sa>/*
path "kvv2/data/cluster/${cluster_name}/workloads/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_dropzone/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["create", "update", "read", "delete"]
}

path "kvv2/metadata/cluster/${cluster_name}/workloads/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_dropzone/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["list"]
}
