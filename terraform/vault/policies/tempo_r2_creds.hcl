# Lets the Tempo R2 generator (ESO, in the tracing namespace) lease R2 S3
# credentials from the cloudflare engine for Tempo's trace block storage. A read
# here mints a fresh token; ESO refreshes well inside the lease and Reloader
# restarts Tempo onto the new keypair while the old one is still valid.
path "cloudflare/creds/r2-tempo" {
  capabilities = ["read"]
}
