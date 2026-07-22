#!/bin/sh
# Reconciles Stalwart's database state to /etc/provision/provision.json
# (rendered from the chart values: hostname, domains, accounts) through the
# v0.16 JMAP management API, then publishes the server-generated DKIM TXT
# records as external-dns DNSEndpoints.
#
# Ensure-only and idempotent: domains/accounts are created when missing, never
# destroyed, and existing account passwords/aliases are never overwritten
# (drift is logged instead). Runs as a post-install/upgrade hook on every sync.
#
# JMAP object shapes below were verified against the v0.16 source
# (crates/registry/src/schema/structs.rs). Notes that cost real debugging:
#   - every tagged object uses "@type" (the published docs show "type")
#   - List<T> (credentials, aliases) serializes as an INDEX-KEYED OBJECT,
#     e.g. {"0": {...}} — not a JSON array
#   - file-backed secrets use "filePath" (not "path")
#   - dnsZoneFile is a COMPUTED property: returned only when the get call
#     requests no explicit property list (as below)
set -eu

apk add --no-cache curl jq >/dev/null

URL="${STALWART_URL:?}"
CFG=/etc/provision/provision.json
AUTH="${STALWART_ADMIN_USER:?}:${STALWART_ADMIN_PASSWORD:?}"

# $1 = JMAP methodCalls JSON array; prints the raw response, fails on HTTP error.
jmap() {
  curl -sfS -u "$AUTH" -H 'Content-Type: application/json' \
    -d "{\"using\":[\"urn:ietf:params:jmap:core\",\"urn:stalwart:jmap\"],\"methodCalls\":$1}" \
    "$URL/jmap"
}

echo "Waiting for Stalwart to be ready..."
i=0
until curl -sf "$URL/healthz/ready" >/dev/null 2>&1; do
  i=$((i+1)); [ "$i" -ge 60 ] && { echo "stalwart not ready" >&2; exit 1; }
  sleep 5
done

# Prints the API's own error for a failed set call — without this, a rejected
# create is invisible and the job just says "failed".
why() { echo "$1" | jq -c '.methodResponses[0][1] | (.notCreated // .notUpdated // .)' 2>/dev/null; }

# ---- file-backed TLS certificate object (cert-manager mounts the PEMs) ----
NCERTS=$(jmap '[["x:Certificate/get",{"ids":null},"c0"]]' \
  | jq '[.methodResponses[0][1].list[]?] | length')
if [ "$NCERTS" = "0" ]; then
  echo "Creating file-backed TLS Certificate object"
  RESP=$(jmap '[["x:Certificate/set",{"create":{"c1":{
      "certificate":{"@type":"File","filePath":"/etc/stalwart/tls/tls.crt"},
      "privateKey":{"@type":"File","filePath":"/etc/stalwart/tls/tls.key"}}}},"c0"]]')
  echo "$RESP" | jq -e '.methodResponses[0][1].created.c1' >/dev/null \
    || { echo "ERROR: Certificate create failed: $(why "$RESP")" >&2; exit 1; }
fi

# ---- domains ----
ensure_domain() { # $1=name $2=catchAll
  # dkimManagement Automatic generates the keypairs (ed25519 + RSA). Rotation is
  # pushed out to ~10y BECAUSE dnsManagement is Manual here: external-dns owns
  # the zone, so a silent server-side rotation would publish nothing and break
  # signing. Rotation is a deliberate, re-run-the-job operation.
  # Duration is a u64 of MILLISECONDS (not a "3650d" string): 3650d = 315360000000.
  RESP=$(jmap "$(jq -nc --arg n "$1" --arg ca "$2" '[["x:Domain/set",{"create":{"d1":(
    {
      "name":$n,
      "certificateManagement":{"@type":"Manual"},
      "dkimManagement":{"@type":"Automatic","rotateAfter":315360000000},
      "dnsManagement":{"@type":"Manual"},
      "subAddressing":{"@type":"Enabled"}
    } + (if $ca == "" then {} else {"catchAllAddress":$ca} end)
  )}},"c0"]]')")
  if ! echo "$RESP" | jq -e '.methodResponses[0][1].created.d1' >/dev/null; then
    echo "  API said: $(why "$RESP")" >&2
    return 1
  fi
}

DOMAINS_JSON=$(jmap '[["x:Domain/get",{"ids":null},"c0"]]')
jq -c '.domains[]' "$CFG" | while read -r d; do
  NAME=$(echo "$d" | jq -r .name)
  CATCHALL=$(echo "$d" | jq -r '.catchAll // ""')
  if echo "$DOMAINS_JSON" | jq -e --arg n "$NAME" \
    '.methodResponses[0][1].list[]? | select(.name == $n)' >/dev/null; then
    echo "Domain $NAME: exists"
  else
    echo "Domain $NAME: creating"
    ensure_domain "$NAME" "$CATCHALL" \
      || { echo "ERROR: Domain create failed for $NAME" >&2; exit 1; }
  fi
done

# Refetch: ids + dnsZoneFile now include freshly created domains + DKIM keys.
DOMAINS_JSON=$(jmap '[["x:Domain/get",{"ids":null},"c0"]]')

# ---- server identity (SMTP EHLO/banner, reports) ----
# Must run AFTER the domains exist: the singleton requires defaultDomainId, so
# this cannot be done on an empty server.
HOSTNAME=$(jq -r .hostname "$CFG")
DEFAULT_DOMAIN=$(jq -r .defaultDomain "$CFG")
DEFAULT_DID=$(echo "$DOMAINS_JSON" | jq -r --arg n "$DEFAULT_DOMAIN" \
  '.methodResponses[0][1].list[]? | select(.name == $n) | .id')
if [ -n "$DEFAULT_DID" ] && [ "$DEFAULT_DID" != "null" ]; then
  echo "Ensuring defaultHostname=$HOSTNAME defaultDomain=$DEFAULT_DOMAIN"
  RESP=$(jmap "$(jq -nc --arg h "$HOSTNAME" --arg d "$DEFAULT_DID" \
    '[["x:SystemSettings/set",{"update":{"singleton":
       {"defaultHostname":$h,"defaultDomainId":$d}}},"c0"]]')")
  echo "$RESP" | jq -e '.methodResponses[0][1] | (.notUpdated // {}) | length == 0' >/dev/null \
    || echo "WARN: SystemSettings update rejected: $(why "$RESP")" >&2
else
  echo "WARN: default domain $DEFAULT_DOMAIN not found — skipping SystemSettings" >&2
fi

# ---- publish DKIM TXT records as DNSEndpoints ----
# Static records (MX/SPF/DMARC/...) are chart-owned; only the DKIM TXTs come
# from the server, because the key material is generated server-side and only
# the public half is derivable from it. One DNSEndpoint per domain; leftovers
# from a removed domain are pruned by hand (harmless residue).
NS="${POD_NAMESPACE:?}"
# dkimManagement Automatic generates ed25519 AND RSA, but ASYNCHRONOUSLY and at
# different speeds (RSA-2048 keygen is much slower). Reading the zone file right
# after creating a domain therefore yields only the ed25519 record, silently
# publishing half the DKIM set. Poll until both are present.
EXPECT_DKIM=2
jq -r '.domains[].name' "$CFG" | while read -r NAME; do
  k=0
  while :; do
    ZONE=$(echo "$DOMAINS_JSON" | jq -r --arg n "$NAME" \
      '.methodResponses[0][1].list[]? | select(.name == $n) | .dnsZoneFile // ""')
    FOUND=$(printf '%s\n' "$ZONE" | grep -c '_domainkey' || true)
    [ "$FOUND" -ge "$EXPECT_DKIM" ] && break
    k=$((k+1))
    if [ "$k" -ge 20 ]; then
      echo "WARN: $NAME has $FOUND/$EXPECT_DKIM DKIM records after 60s — publishing what exists" >&2
      break
    fi
    sleep 3
    DOMAINS_JSON=$(jmap '[["x:Domain/get",{"ids":null},"c0"]]')
  done
  # BIND zone lines, NO ttl field: `<fqdn>. IN TXT "value"`. Values over 255
  # bytes (every RSA DKIM key) are emitted as a parenthesized MULTI-LINE block
  # of quoted chunks, which must be concatenated back into one string:
  #   name. IN TXT (
  #       "chunk1"
  #       "chunk2"
  #   )
  RECORDS=$(printf '%s\n' "$ZONE" | awk '
    function flush() { if (n != "") { print n "|" b }; n=""; b="" }
    inp == 1 {
      if ($0 ~ /^[ \t]*\)/) { inp=0; flush(); next }
      s=$0; sub(/^[ \t]*"/,"",s); sub(/"[ \t]*$/,"",s); b=b s; next
    }
    /_domainkey/ && /[ \t]IN[ \t]+TXT[ \t]*\(/ {
      n=$1; sub(/\.$/,"",n); b=""; inp=1; next
    }
    /_domainkey/ && /[ \t]IN[ \t]+TXT[ \t]+"/ {
      n=$1; sub(/\.$/,"",n)
      s=$0; sub(/^[^"]*"/,"",s); sub(/"[ \t]*$/,"",s); b=s; flush()
    }')
  if [ -z "$RECORDS" ]; then
    echo "WARN: no DKIM records in dnsZoneFile for $NAME (DKIM not generated?)" >&2
    continue
  fi
  {
    echo "apiVersion: externaldns.k8s.io/v1alpha1"
    echo "kind: DNSEndpoint"
    echo "metadata:"
    echo "  name: stalwart-dkim-$(echo "$NAME" | tr '.' '-')"
    echo "  namespace: $NS"
    echo "  labels:"
    echo "    app: stalwart"
    echo "    app.kubernetes.io/managed-by: stalwart-provision"
    echo "spec:"
    echo "  endpoints:"
    printf '%s\n' "$RECORDS" | while IFS='|' read -r rname rtxt; do
      echo "    - dnsName: \"$rname\""
      echo "      recordType: TXT"
      echo "      recordTTL: 300"
      echo "      targets: [\"$rtxt\"]"
    done
  } | kubectl apply -f -
  echo "Domain $NAME: DKIM DNSEndpoint applied"
done

# ---- accounts (ensure-only) ----
ACCOUNTS_JSON=$(jmap '[["x:Account/get",{"ids":null},"c0"]]')
jq -c '.accounts[]' "$CFG" | while read -r a; do
  NAME=$(echo "$a" | jq -r .name)
  DOMAIN=$(echo "$a" | jq -r .domain)
  DID=$(echo "$DOMAINS_JSON" | jq -r --arg n "$DOMAIN" \
    '.methodResponses[0][1].list[]? | select(.name == $n) | .id')
  if [ -z "$DID" ] || [ "$DID" = "null" ]; then
    echo "ERROR: account $NAME: domain $DOMAIN not found" >&2; exit 1
  fi
  if echo "$ACCOUNTS_JSON" | jq -e --arg n "$NAME" --arg d "$DID" \
    '.methodResponses[0][1].list[]? | select(.name == $n and .domainId == $d)' >/dev/null; then
    echo "Account $NAME@$DOMAIN: exists (password/aliases left untouched)"
    continue
  fi
  # Created WITHOUT credentials on purpose: only the admin password lives in
  # Vault. Set the mailbox password once from the web-admin (tailnet-only) —
  # user passwords are personal, rotate independently, and must never be
  # declarative state.
  echo "Account $NAME@$DOMAIN: creating (aliases: $(echo "$a" | jq -cr .aliases))"
  echo "  -> set its password in the web-admin; it cannot log in until you do"
  RESP=$(jmap "$(echo "$a" | jq -c --arg did "$DID" '[["x:Account/set",{"create":{"a1":
    {
      "@type":"User",
      "name":.name,
      "domainId":$did,
      "roles":{"@type":"User"},
      "permissions":{"@type":"Inherit"},
      "encryptionAtRest":{"@type":"Disabled"},
      "quotas":{},
      "memberGroupIds":{},
      "aliases":([.aliases[] | {enabled:true, name:., domainId:$did}]
                 | to_entries | map({(.key|tostring): .value}) | add // {}),
      "credentials":{}
    }
  }},"c0"]]')")
  echo "$RESP" | jq -e '.methodResponses[0][1].created.a1' >/dev/null \
    || { echo "ERROR: Account create failed for $NAME@$DOMAIN: $(why "$RESP")" >&2; exit 1; }
done

echo "Provisioning done."
