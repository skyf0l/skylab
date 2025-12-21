{{- with secret "kvv2/data/cluster/cloudflare-ddns/cloudflare-ddns/cloudflare-ddns-config" -}}
{
"cloudflare": [
	{
	"authentication": {
		"api_token": "{{ .Data.data.API_TOKEN }}",
		"api_key": {
		"api_key": "{{ .Data.data.API_KEY }}",
		"account_email": "{{ .Data.data.ACCOUNT_EMAIL }}"
		}
	},
	"zone_id": "{{ .Data.data.ZONE_ID }}",
	"subdomains": [
		{ "name": "",   "proxied": true  },
		{ "name": "pi", "proxied": false },
		{ "name": "vault", "proxied": false },
		{ "name": "*",  "proxied": true  }
	]
	}
],
"a": true,
"aaaa": false,
"purgeUnknownRecords": false,
"ttl": 300
}
{{- end -}}