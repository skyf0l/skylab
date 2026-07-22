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
{{- $_ := set $d "dmarc" (default (printf "v=DMARC1; p=none; rua=mailto:postmaster@%s" $name) .dmarc) -}}
{{- $_ := set $d "catchAll" (tpl (default "" .catchAll) $root) -}}
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
