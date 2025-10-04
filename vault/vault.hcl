# /etc/vault.d/vault.hcl
ui            = true
cluster_addr  = "https://127.0.0.1:8201"
api_addr      = "https://127.0.0.1:8200"
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "raft_node_main"
}

listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_cert_file = "/opt/vault/tls/vault.crt"
  tls_key_file  = "/opt/vault/tls/vault.key"
  tls_disable = 1
}

# telemetry {
#   statsite_address = "127.0.0.1:8125"
#   disable_hostname = true
# }
