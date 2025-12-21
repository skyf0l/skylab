# Allow a workload to read its own area and the shared area:
#   kvv2/data/cluster/<ns>/<sa>/*
#   kvv2/data/cluster/<ns>/_shared/*
path "kvv2/data/cluster/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["read"]
}

path "kvv2/metadata/cluster/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["list"]
}

path "kvv2/data/cluster/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_shared/*" {
  capabilities = ["read"]
}

path "kvv2/metadata/cluster/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_shared/*" {
  capabilities = ["list"]
}
