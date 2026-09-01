# Least-privilege policy for the parent-token rotation CronJob: it may only roll
# the Cloudflare parent token in place, nothing else.
path "cloudflare/config/rotate-root" {
  capabilities = ["update"]
}
