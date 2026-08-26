#!/bin/sh
# Publishes each served domain's DKIM TXT records as external-dns DNSEndpoints.
# Runs after `stalwart-cli apply` has reconciled the domains (init container),
# so the DKIM keys exist; this is the one piece of state that only the server
# can produce (the private keys are generated server-side, and the public half
# is exposed solely through the Domain's computed dnsZoneFile).
#
# Static records (MX/SPF/DMARC/...) are chart-owned. One DNSEndpoint per
# domain; leftovers from a removed domain are pruned by hand (harmless residue).
set -eu

URL="${STALWART_URL:?}"
AUTH="${STALWART_ADMIN_USER:?}:${STALWART_ADMIN_PASSWORD:?}"
NS="${POD_NAMESPACE:?}"

# dnsZoneFile is a COMPUTED property: returned only when the get call requests
# no explicit property list (verified against the v0.16 source).
domains_json() {
  curl -sfS -u "$AUTH" -H 'Content-Type: application/json' \
    -d '{"using":["urn:ietf:params:jmap:core","urn:stalwart:jmap"],"methodCalls":[["x:Domain/get",{"ids":null},"c0"]]}' \
    "$URL/jmap"
}
DOMAINS_JSON=$(domains_json)

# dkimManagement Automatic generates ed25519 AND RSA, but ASYNCHRONOUSLY and at
# different speeds (RSA-2048 keygen is much slower). Reading the zone file right
# after creating a domain therefore yields only the ed25519 record, silently
# publishing half the DKIM set. Poll until both are present.
EXPECT_DKIM=2
while read -r NAME; do
  [ -n "$NAME" ] || continue
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
    DOMAINS_JSON=$(domains_json)
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
done < /etc/provision/domains.txt

echo "DKIM publishing done."
