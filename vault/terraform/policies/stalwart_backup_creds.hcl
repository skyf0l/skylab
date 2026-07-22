# Lets the Stalwart backup generator (ESO, in the stalwart namespace) lease
# short-lived R2 S3 credentials from the cloudflare engine for CNPG's barman WAL
# archiving and base backups. A read here mints a fresh token; ESO refreshes
# well inside the lease and barman picks the new value up per invocation.
path "cloudflare/creds/r2-stalwart-backup" {
  capabilities = ["read"]
}
