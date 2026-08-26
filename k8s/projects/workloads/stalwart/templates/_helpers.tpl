{{/*
Normalized served-domain list (public domains + private extraDomains), tpl'd
and with per-domain SPF/DMARC defaults resolved. Consumed via fromJsonArray by
the DNSEndpoint template and the provisioning ConfigMap so both always agree.
*/}}
{{- define "stalwart.domains" -}}
{{- $root := . -}}
{{- $out := list -}}
{{- range concat (default (list) .Values.domains) (default (list) .Values.extraDomains) -}}
{{- $name := tpl .name $root -}}
{{- $d := dict "name" $name "mx" (default false .mx) -}}
{{- $_ := set $d "spf" (default $root.Values.dns.spf .spf) -}}
{{/* Enforcing (p=reject) by default: everything this server sends is DKIM-signed
     with an aligned d=, so it passes. What gets rejected is mail claiming to be
     from these domains that did NOT go through here — which is the point.
     Keep rua so the aggregate reports keep arriving; override per domain with a
     `dmarc:` key if one ever needs a softer policy. */}}
{{- $_ := set $d "dmarc" (default (printf "v=DMARC1; p=reject; rua=mailto:postmaster@%s" $name) .dmarc) -}}
{{- $_ := set $d "catchAll" (tpl (default "" .catchAll) $root) -}}
{{/* Optional per-domain mail hostname. Defaults to the shared .Values.host, so
     one server name and one certificate serve every domain. Setting it gives
     the domain its own MX target + A record + SEPARATE certificate (never a SAN
     on the shared cert, which would place both names in one Certificate
     Transparency entry and publicly tie the domains together). */}}
{{- $_ := set $d "mailHost" (default $root.Values.host (tpl (default "" .mailHost) $root)) -}}
{{- $_ := set $d "slug" (replace "." "-" $name) -}}
{{- $out = append $out $d -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{/*
Normalized account list (public accounts + private extraAccounts): local part,
resolved domain, tpl'd aliases.
*/}}
{{- define "stalwart.accounts" -}}
{{- $root := . -}}
{{- $out := list -}}
{{- range concat (default (list) .Values.accounts) (default (list) .Values.extraAccounts) -}}
{{- $a := dict "name" .name "domain" (tpl (default "{{ .Values.global.domain }}" .domain) $root) -}}
{{- $aliases := list -}}
{{- range (default (list) .aliases) -}}
{{- $aliases = append $aliases (tpl . $root) -}}
{{- end -}}
{{- $_ := set $a "aliases" $aliases -}}
{{- $out = append $out $a -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{/*
File-backed TLS certificate object for a cert-manager mount directory.
*/}}
{{- define "stalwart.fileCert" -}}
{{ dict "certificate" (dict "@type" "File" "filePath" (printf "%s/tls.crt" .)) "privateKey" (dict "@type" "File" "filePath" (printf "%s/tls.key" .)) | toJson }}
{{- end -}}

{{/*
stalwart-cli apply plan: NDJSON, one operation per line, dependency order
(parents before children, `#<key>` references resolve to the real id whether
the object was matched or created). Everything is an `upsert` (match-or-create,
never destroy): the fields declared here are reconciled on every sync, fields
left out (account credentials) are never touched, and objects the plan does not
mention are never pruned. `stalwart-cli apply --dry-run` validates the render
offline.
*/}}
{{- define "stalwart.plan" -}}
{{- $root := . -}}
{{- $domains := include "stalwart.domains" . | fromJsonArray -}}
{{- $defaultSlug := replace "." "-" .Values.global.domain -}}
{{/* Stalwart's bootstrap set creates a pop3s listener (995) that nothing exposes.
     The filter MUST stay name-scoped: an empty filter destroys every listener. */}}
{{ dict "@type" "destroy" "object" "NetworkListener" "value" (dict "name" "pop3s") | toJson }}
{{/* One certificate per configured hostname (cert-manager mounts the PEMs);
     Stalwart selects between them by SNI. Matched on the file paths, which are
     the only client-set fields (SANs are server-set). */}}
{{- $certs := dict "cert-shared" (include "stalwart.fileCert" "/etc/stalwart/tls" | fromJson) -}}
{{- range $domains -}}
{{- if ne .mailHost $root.Values.host -}}
{{- $_ := set $certs (printf "cert-%s" .slug) (include "stalwart.fileCert" (printf "/etc/stalwart/tls-%s" .slug) | fromJson) -}}
{{- end -}}
{{- end }}
{{ dict "@type" "upsert" "object" "Certificate" "matchOn" (list "certificate") "value" $certs | toJson }}
{{/* The bootstrap set has no STARTTLS submission listener (587) although the
     chart exposes it. Listeners are read at startup: a new one only opens after
     a pod restart. */}}
{{ dict "@type" "upsert" "object" "NetworkListener" "matchOn" (list "name") "value" (dict "listener-submission" (dict "name" "submission" "bind" (dict "[::]:587" true) "protocol" "smtp" "useTls" true "tlsImplicit" false)) | toJson }}
{{/* Special-use folders for NEW mailboxes (existing accounts keep theirs). */}}
{{- if .Values.defaultFolders -}}
{{- $folders := dict -}}
{{- range $use, $name := .Values.defaultFolders -}}
{{- $_ := set $folders $use (dict "name" $name "create" true "subscribe" true) -}}
{{- end }}
{{ dict "@type" "update" "object" "Email" "value" (dict "defaultFolders" $folders) | toJson }}
{{- end }}
{{/* dkimManagement Automatic generates the keypairs (ed25519 + RSA). Rotation is
     pushed out to ~10y BECAUSE dnsManagement is Manual: external-dns owns the
     zone, so a silent server-side rotation would publish nothing and break
     signing. Rotation is a deliberate operation. Duration is MILLISECONDS. */}}
{{- $doms := dict -}}
{{- range $domains -}}
{{- $d := dict "name" .name "certificateManagement" (dict "@type" "Manual") "dkimManagement" (dict "@type" "Automatic" "rotateAfter" 315360000000) "dnsManagement" (dict "@type" "Manual") "subAddressing" (dict "@type" "Enabled") -}}
{{- if .catchAll -}}{{- $_ := set $d "catchAllAddress" .catchAll -}}{{- end -}}
{{- $_ := set $doms (printf "dom-%s" .slug) $d -}}
{{- end }}
{{ dict "@type" "upsert" "object" "Domain" "matchOn" (list "name") "value" $doms | toJson }}
{{/* Server identity (SMTP EHLO/banner, reports); needs the default domain to exist. */}}
{{ dict "@type" "update" "object" "SystemSettings" "value" (dict "defaultHostname" .Values.host "defaultDomainId" (printf "#dom-%s" $defaultSlug)) | toJson }}
{{/* Prometheus endpoint with Basic auth read from the pod env, so the secret
     stays in the Kubernetes Secret (never in Stalwart's database). */}}
{{ dict "@type" "update" "object" "Metrics" "value" (dict "prometheus" (dict "@type" "Enabled" "authUsername" .Values.metrics.username "authSecret" (dict "@type" "EnvironmentVariable" "variableName" "STALWART_METRICS_SECRET"))) | toJson }}
{{/* Accounts carry NO credentials on purpose: created without a password (set it
     once from the tailnet-only web-admin), and since the field is absent from
     the plan an existing password is never overwritten. */}}
{{- $accs := dict -}}
{{- range include "stalwart.accounts" . | fromJsonArray -}}
{{- $slug := replace "." "-" .domain -}}
{{- $aliases := dict -}}
{{- range $i, $alias := .aliases -}}
{{- $_ := set $aliases (toString $i) (dict "enabled" true "name" $alias "domainId" (printf "#dom-%s" $slug)) -}}
{{- end -}}
{{- $_ := set $accs (printf "acc-%s-%s" (replace "." "-" .name) $slug) (dict "@type" "User" "name" .name "domainId" (printf "#dom-%s" $slug) "roles" (dict "@type" "User") "permissions" (dict "@type" "Inherit") "encryptionAtRest" (dict "@type" "Disabled") "aliases" $aliases) -}}
{{- end }}
{{ dict "@type" "upsert" "object" "Account" "matchOn" (list "name" "domainId") "value" $accs | toJson }}
{{/* Settings written through the API only take effect after a reload. */}}
{{ dict "@type" "create" "object" "Action" "value" (dict "reload" (dict "@type" "ReloadSettings")) | toJson }}
{{- end -}}
