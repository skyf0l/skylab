{{/*
All monitor groups: `groups` (public by default) followed by `extraGroups`
(private by default — the $private overlay appends here). Returned as JSON so
callers `fromJsonArray` it.
*/}}
{{- define "uptime-kuma.groups" -}}
{{- $out := list -}}
{{- range .Values.groups -}}
{{- $out = append $out (mergeOverwrite (dict "public" true) .) -}}
{{- end -}}
{{- range .Values.extraGroups -}}
{{- $out = append $out (mergeOverwrite (dict "public" false) .) -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{/*
One AutoKuma monitor definition. Chart defaults (interval/retries, accepted
status codes for HTTP-like types) are applied first, then every key of the
values entry is passed through as-is (AutoKuma's snake_case schema), strings
going through tpl so targets can reference .Values.global.domain.
Expects a dict: {root, group, monitor}.
*/}}
{{- define "uptime-kuma.monitor" -}}
{{- $root := .root -}}
{{- $d := $root.Values.defaults -}}
{{- $out := dict "parent_name" (printf "group-%s" .group.id) "interval" $d.interval "retry_interval" $d.retryInterval "max_retries" $d.maxRetries -}}
{{- if has .monitor.type (list "http" "keyword" "json-query") -}}
{{- $_ := set $out "accepted_statuscodes" (list "200-299") -}}
{{- end -}}
{{- range $k, $v := .monitor -}}
{{- if ne $k "id" -}}
{{- if kindIs "string" $v -}}
{{- $_ := set $out $k (tpl $v $root) -}}
{{- else -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}
