# Lets the Harbor R2 generator (ESO, in the harbor namespace) lease R2 S3
# credentials from the cloudflare engine for the registry's blob storage. A read
# here mints a fresh token; ESO refreshes well inside the lease and Reloader
# rolls the registry onto the new keypair while the old one is still valid.
path "cloudflare/creds/r2-harbor" {
  capabilities = ["read"]
}
