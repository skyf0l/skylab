# Vault client-count / activity tracking — the "Client Usage" dashboard. It's a
# RUNTIME config (sys/internal/counters/config), DISABLED by default until turned on.
resource "vault_generic_endpoint" "client_count" {
  path                 = "sys/internal/counters/config"
  disable_delete       = true # config endpoint has no DELETE
  ignore_absent_fields = true # only manage the fields we set; leave the rest at defaults
  data_json = jsonencode({
    enabled          = "enable"
    retention_months = 48
  })
}
