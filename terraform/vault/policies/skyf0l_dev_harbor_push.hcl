# skyf0l/skyf0l.dev CI: mint one push robot for the skyf0l.dev Harbor project.
# One exact role path, never a glob: harbor/creds/* would grant every role on
# the mount. A read creates the robot; the lease is the robot's lifetime.
path "harbor/creds/skyf0l-dev-push" {
  capabilities = ["read"]
}

# Hand the credential back early (`vault lease revoke <lease_id>` puts the lease
# ID in the URL). revoke-self at job end already cascades to the lease; this
# covers revoking the lease alone.
path "sys/leases/revoke/harbor/creds/skyf0l-dev-push/*" {
  capabilities = ["update"]
}
