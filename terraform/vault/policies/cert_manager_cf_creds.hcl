# Lets the cert-manager dynamic-secret generator (ESO, in the cert-manager
# namespace) lease short-lived Cloudflare tokens for ACME DNS-01 challenges.
# Same engine role as external-dns: Zone Read + DNS Write across the account,
# which is what makes DNS-01 work for EVERY zone instead of a hand-scoped token
# that silently fails on newly added domains.
path "cloudflare/creds/dns-edit" {
  capabilities = ["read"]
}
