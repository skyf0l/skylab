# Lets the Thanos R2 generator (ESO, in the monitoring namespace) lease R2 S3
# credentials from the cloudflare engine for the store, the compactor and the Prometheus sidecar's objstore.yml. A read
# here mints a fresh token; ESO refreshes well inside the lease and Reloader
# restarts the consumers onto the new keypair while the old one is still valid.
path "cloudflare/creds/r2-thanos" {
  capabilities = ["read"]
}
