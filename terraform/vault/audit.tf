# File audit device, written to the persistent auditStorage volume the Helm
# chart mounts at /vault/audit (server.auditStorage.enabled). Captures every
# request/response for accountability. log_raw=false keeps sensitive values
# HMAC'd in the log.
resource "vault_audit" "file" {
  type = "file"

  options = {
    file_path = "/vault/audit/vault_audit.log"
  }
}
