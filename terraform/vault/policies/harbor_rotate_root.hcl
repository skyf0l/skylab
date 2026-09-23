# Least-privilege policy for the principal rotation CronJob: it may only roll
# the Harbor principal robot, nothing else.
path "harbor/config/rotate-root" {
  capabilities = ["update"]
}
