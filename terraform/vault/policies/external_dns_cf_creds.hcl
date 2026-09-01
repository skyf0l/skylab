# Lets the external-dns dynamic-secret generator (ESO, in the external-dns
# namespace) lease short-lived Cloudflare DNS tokens from the cloudflare engine.
# A read here mints a fresh token; ESO's VaultDynamicSecret generator reads it
# once per refresh and Reloader restarts the deployment onto the new value.
path "cloudflare/creds/dns-edit" {
  capabilities = ["read"]
}
