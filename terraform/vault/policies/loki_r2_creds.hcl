# Lets the Loki R2 generator (ESO, in the logging namespace) lease R2 S3
# credentials from the cloudflare engine for Loki's S3 backend (chunks + index). A read
# here mints a fresh token; ESO refreshes well inside the lease and Reloader
# restarts the consumers onto the new keypair while the old one is still valid.
path "cloudflare/creds/r2-loki" {
  capabilities = ["read"]
}
