#!/usr/bin/env bash
# =============================================================================
# Seed bootstrap secrets into Vault.
#
# Terraform (vault/terraform, applied by the Vault GitHub Action) creates the
# *structure*: mounts, auth backends, policies, roles. It does NOT hold secret
# values. This script seeds the *values* that apps expect to exist before their
# ExternalSecret can sync — so a fresh cluster comes up clean instead of ESO
# erroring with SecretSyncError on a missing key.
#
# Two kinds of fields are seeded:
#   - crypto material (jwt/session/encryption/hmac/jwks) -> random, generated
#     here. These are "set once and forget"; you never need to touch them.
#   - human-supplied content (e.g. Authelia users_yaml) -> a clearly-marked
#     PLACEHOLDER you edit later (Vault UI/CLI).
#
# Idempotent: every field is written only if it is missing, so re-running never
# clobbers a random you already generated or a value you filled in by hand.
#
# Run AFTER `terraform apply` (the kvv2 mount must exist) with a token that can
# write under kvv2/. Requires: vault CLI, openssl.
#
#   export VAULT_ADDR=https://vault.skyf0l.dev:8200
#   export VAULT_TOKEN=<root-or-admin-token>
#   ./vault/seed-secrets.sh
#
# Optional: CLUSTER=skylab (default) selects the kvv2/cluster/<CLUSTER>/* prefix.
# =============================================================================
set -euo pipefail

CLUSTER="${CLUSTER:-skylab}"
KV_MOUNT="kvv2"

# ----- prerequisites ---------------------------------------------------------
for bin in vault openssl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' not found in PATH" >&2; exit 1; }
done
: "${VAULT_ADDR:?set VAULT_ADDR (e.g. https://vault.skyf0l.dev:8200)}"
: "${VAULT_TOKEN:?set VAULT_TOKEN to a token that can write under ${KV_MOUNT}/}"
vault token lookup >/dev/null 2>&1 || { echo "error: VAULT_TOKEN is invalid or Vault is unreachable" >&2; exit 1; }

# ----- generators ------------------------------------------------------------
rand_secret() { openssl rand -hex 32; }
rand_hex16()  { openssl rand -hex 8; }             # 16 chars (Harbor secretKey)
rand_hex32()  { openssl rand -hex 16; }            # 32 chars (Harbor CSRF key)            # 64 hex chars (>= Authelia's 64-char minimums)
rsa_key()     { openssl genrsa 4096 2>/dev/null; } # OIDC JWKS signing key (PEM)

authelia_users_placeholder() {
  cat <<'YAML'
# PLACEHOLDER — disabled dummy user. The hash below is a VALID argon2id hash for
# the password "password" (authelia validates every hash at startup, so it must be
# well-formed). Replace with your real users; this field is then left as-is on
# subsequent runs. Generate a hash with:
#   docker run --rm authelia/authelia:4.39.20 \
#     authelia crypto hash generate argon2 --password 'your-password'
users:
  admin:
    disabled: true
    displayname: 'Placeholder Admin'
    password: '$argon2id$v=19$m=65536,t=3,p=4$BpLnfgDsc2WD8F2q$o/vzA4myCqZZ36bUGsDY//8mKUYNZZaR0t4MFFSs+iM'
    email: 'admin@example.com'
    groups:
      - admins
YAML
}

# ChatGPT MCP connector OAuth callback — PLACEHOLDER. ChatGPT uses a
# per-connector callback https://chatgpt.com/connector/oauth/<id> that Authelia
# must match exactly (no wildcards). Grab <id> from the Authelia auth-request
# error log and patch it, then restart Authelia:
#   vault kv patch -mount=kvv2 cluster/<cluster>/apps/authelia \
#     chatgpt_redirect_uri="https://chatgpt.com/connector/oauth/<id>"
chatgpt_redirect_placeholder() {
  printf '%s' 'https://chatgpt.com/connector/oauth/REPLACE_ME'
}

# garth (Garmin Connect) combined token — a PLACEHOLDER so the garmin-mcp
# ExternalSecret can sync and the pod can start before you supply a real token. It
# is NOT functional: the MCP can't reach Garmin until you overwrite it. The upstream
# garmin_mcp chart consumes ONE combined token (contents of garmin_tokens.json) via
# $GARMINTOKENS. Generate the real one locally (handles MFA), then store it:
#   uv run garmin-mcp-auth      # writes ~/.garminconnect/garmin_tokens.json
#   vault kv patch -mount=kvv2 cluster/<cluster>/apps/garmin-mcp \
#     garmin_tokens=@$HOME/.garminconnect/garmin_tokens.json
garmin_tokens_placeholder() {
  printf '%s' '{"oauth1_token":{"oauth_token":"REPLACE_ME","oauth_token_secret":"REPLACE_ME","domain":"garmin.com"},"oauth2_token":{"access_token":"REPLACE_ME","refresh_token":"REPLACE_ME","token_type":"Bearer","expires_at":0}}'
}

# Generic REPLACE_ME placeholder for human-supplied credentials (e.g. R2 tokens).
replace_me() { printf '%s' 'REPLACE_ME'; }

# ----- seeding helpers -------------------------------------------------------
field_exists() { vault kv get -mount="$KV_MOUNT" -field="$2" "$1" >/dev/null 2>&1; }
key_exists()   { vault kv get -mount="$KV_MOUNT" "$1" >/dev/null 2>&1; }

# seed_field <path> <field> <generator-cmd...>  — write only if the field is absent
seed_field() {
  local path="$1" field="$2"; shift 2
  if field_exists "$path" "$field"; then
    printf '  = %s : %-22s present, skipping\n' "$path" "$field"
    return
  fi
  local value; value="$("$@")"
  if key_exists "$path"; then
    vault kv patch -mount="$KV_MOUNT" "$path" "$field=$value" >/dev/null
  else
    vault kv put -mount="$KV_MOUNT" "$path" "$field=$value" >/dev/null
  fi
  printf '  + %s : %-22s seeded\n' "$path" "$field"
}

# ----- apps ------------------------------------------------------------------
echo "Seeding bootstrap secrets into ${VAULT_ADDR} (cluster: ${CLUSTER})"

# Authelia — kvv2/cluster/<cluster>/apps/authelia
# Field requirements are documented in k8s/.../authelia/values.yaml.
authelia="cluster/${CLUSTER}/apps/authelia"
echo "[authelia] ${KV_MOUNT}/${authelia}"
seed_field "$authelia" jwt_secret             rand_secret
seed_field "$authelia" session_secret         rand_secret
seed_field "$authelia" storage_encryption_key rand_secret
seed_field "$authelia" oidc_hmac_secret       rand_secret
seed_field "$authelia" oidc_jwks_key          rsa_key
seed_field "$authelia" users_yaml             authelia_users_placeholder
seed_field "$authelia" chatgpt_redirect_uri   chatgpt_redirect_placeholder

# garmin-mcp — kvv2/cluster/<cluster>/apps/garmin-mcp
# Placeholder garth token so the app deploys clean; overwrite with the REAL token.
garmin="cluster/${CLUSTER}/apps/garmin-mcp"
echo "[garmin-mcp] ${KV_MOUNT}/${garmin}"
seed_field "$garmin" garmin_tokens garmin_tokens_placeholder

# keycloak — kvv2/cluster/<cluster>/apps/keycloak
# Bootstrap-admin password (random, set-once). NOT here: the DB credential (CNPG
# owns it via the keycloak-pg-app secret) and the backup R2 keypair (minted by the
# cloudflare engine's r2-keycloak-backup role, leased via ESO).
keycloak="cluster/${CLUSTER}/apps/keycloak"
echo "[keycloak] ${KV_MOUNT}/${keycloak}"
seed_field "$keycloak" admin_password        rand_secret

# harbor — kvv2/cluster/<cluster>/apps/harbor
# Every secret the upstream chart would otherwise randomise per render. secretKey
# MUST be 16 chars and csrf_key 32 (Harbor validates both). NOT here: the DB
# credential (CNPG owns it via the harbor-pg-app secret) and the R2 keypair (minted
# by the cloudflare engine's r2-harbor role, leased via ESO).
harbor="cluster/${CLUSTER}/apps/harbor"
echo "[harbor] ${KV_MOUNT}/${harbor}"
seed_field "$harbor" admin_password        rand_secret
seed_field "$harbor" secret_key            rand_hex16
seed_field "$harbor" core_secret           rand_secret
seed_field "$harbor" csrf_key              rand_hex32
seed_field "$harbor" jobservice_secret     rand_secret
seed_field "$harbor" registry_http_secret  rand_secret
seed_field "$harbor" registry_password     rand_secret

# grafana — kvv2/cluster/<cluster>/apps/grafana
# OIDC client secret shared by the Keycloak `grafana` client (substituted into the realm
# by keycloak-config-cli) and Grafana's auth.generic_oauth. Random, set-once.
grafana="cluster/${CLUSTER}/apps/grafana"
echo "[grafana] ${KV_MOUNT}/${grafana}"
seed_field "$grafana" oidc_client_secret     rand_secret

# stalwart — kvv2/cluster/<cluster>/apps/stalwart
# admin_password is human-supplied (see the chart values) and NOT seeded here.
# metrics_password: Basic-auth secret for Stalwart's Prometheus endpoint, shared by
# the server config and the ServiceMonitor. Random, set-once.
stalwart="cluster/${CLUSTER}/apps/stalwart"
echo "[stalwart] ${KV_MOUNT}/${stalwart}"
seed_field "$stalwart" metrics_password     rand_secret

# alertmanager — kvv2/cluster/<cluster>/apps/alertmanager
# Pushover credentials (an Application's API token + your user key) — PLACEHOLDERS
# so the ExternalSecret syncs and Alertmanager starts; overwrite with the real ones:
#   vault kv patch -mount=kvv2 cluster/<cluster>/apps/alertmanager \
#     pushover_user_key=<user key> pushover_token=<app token>
alertmanager="cluster/${CLUSTER}/apps/alertmanager"
echo "[alertmanager] ${KV_MOUNT}/${alertmanager}"
seed_field "$alertmanager" pushover_user_key   replace_me
seed_field "$alertmanager" pushover_token      replace_me

echo "Done. Fill in any PLACEHOLDER fields via the Vault UI/CLI; re-running won't overwrite them."
