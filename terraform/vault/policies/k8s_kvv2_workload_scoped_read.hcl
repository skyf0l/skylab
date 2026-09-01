# A workload reads its own area and its namespace's shared area, under the
# cluster-scoped workloads tree:
#   kvv2/data/cluster/<cluster>/workloads/<ns>/<sa>/*
#   kvv2/data/cluster/<cluster>/workloads/<ns>/_shared/*
path "kvv2/data/cluster/${cluster_name}/workloads/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["read"]
}

path "kvv2/metadata/cluster/${cluster_name}/workloads/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["list"]
}

path "kvv2/data/cluster/${cluster_name}/workloads/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_shared/*" {
  capabilities = ["read"]
}

path "kvv2/metadata/cluster/${cluster_name}/workloads/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_shared/*" {
  capabilities = ["list"]
}
