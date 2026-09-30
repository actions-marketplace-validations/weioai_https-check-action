# HTTPS certificate check (GitHub Action)

Fails your workflow before your visitors find out: checks each host's TLS certificate the way a browser does and reports

- **expired** or **expiring within `min-days`** (default 14)
- **hostname mismatch** (the classic: the certificate covers `example.com` but not `www.example.com`)
- **self-signed / untrusted chain**
- **no certificate at all** (port 443 refused or timing out)

bash + openssl only: no Docker image, no API key, nothing leaves the runner except the TLS handshakes.

## Usage

Nightly check of a few client sites:

```yaml
name: certificates
on:
  schedule:
    - cron: '17 6 * * *'
  workflow_dispatch:
jobs:
  https:
    runs-on: ubuntu-latest
    steps:
      - uses: weioai/https-check-action@v1
        with:
          urls: |
            example.com
            www.example.com
            shop.example.com:8443
          min-days: 21
```

A failing host shows as an error annotation and a table in the job summary:

| host | result | detail | expires |
|---|---|---|---|
| example.com | ok | valid, 87 days left | Dec 26 20:56:11 2026 GMT |
| wrong.host.badssl.com | FAIL | hostname mismatch | Dec 28 20:02:55 2026 GMT |
| expired.badssl.com | FAIL | certificate has expired | Apr 12 23:59:59 2015 GMT |

Inputs: `urls` (required; spaces, commas or newlines; `https://` and paths are stripped), `min-days` (default `14`), `timeout` seconds per handshake (default `10`). Output: `failed` (`1`/`0`). Run it locally too: `URLS="example.com www.example.com" ./check.sh`.

## Fixing what it finds (free, on your own host)

| result | usual cause | free fix |
|---|---|---|
| expired / expiring | auto-renew stopped (DNS moved, a validation file blocked, a paid certificate nobody renewed) | cPanel: *SSL/TLS Status → Run AutoSSL*. Plesk: *SSL/TLS Certificates → Let's Encrypt*. Own server: `certbot renew --dry-run` and read the error |
| hostname mismatch | certificate issued for `example.com` only, or for the hosting provider's own name | re-issue covering both `example.com` and `www.example.com` (AutoSSL / `certbot -d example.com -d www.example.com`) |
| self-signed / untrusted | a default or placeholder certificate is still installed | replace it with a Let's Encrypt or host-issued certificate |
| no certificate | nothing listens on 443, or the domain points at the wrong server | check the DNS A/CNAME records, then enable SSL at the host |

If you'd rather hand it off, Weio fixes this for a fixed $99, fix-or-full-refund: https://weio.ai/services/https-fix.html?utm_source=github&utm_medium=repo&utm_campaign=https-check-action

Checking many domains from code or an AI agent (cause codes, browser-warning yes/no, hosting provider, plus site facts): the Weio site-check API and MCP server, https://weio.ai/services/site-check-api.html?utm_source=github&utm_medium=repo&utm_campaign=https-check-action

## About

Made by Weio, Inc. (Santa Barbara, CA), a small company where AI operators do most of the work and a human owner is accountable. Issues and PRs welcome. MIT licensed.
