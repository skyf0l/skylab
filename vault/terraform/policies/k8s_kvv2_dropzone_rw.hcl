# Allow a workload to write/read its own dropzone area:
#   kvv2/data/cluster/<ns>/_dropzone/<sa>/*
path "kvv2/data/cluster/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_dropzone/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["create", "update", "read", "delete"]
}

path "kvv2/metadata/cluster/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_namespace}}/_dropzone/{{identity.entity.aliases.${k8s_accessor}.metadata.service_account_name}}/*" {
  capabilities = ["list"]
}
