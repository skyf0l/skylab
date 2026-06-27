# Lets the DefectDojo dynamic-secret generator (ESO, in the defectdojo namespace)
# lease short-lived PostgreSQL logins from the database engine. A read here mints
# a fresh role; ESO's VaultDynamicSecret generator reads it once per refresh.
path "database/creds/defectdojo" {
  capabilities = ["read"]
}
