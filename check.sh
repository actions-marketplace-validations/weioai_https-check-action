#!/usr/bin/env bash
# Checks each host's TLS certificate the way a browser would care about:
# trusted chain, name matches, not expired, and not expiring within MIN_DAYS.
# Needs only bash, openssl and date. Exit 1 if any host fails.
set -uo pipefail

MIN_DAYS="${MIN_DAYS:-14}"
TIMEOUT="${TIMEOUT:-10}"
fail=0
rows=()

hosts=$(printf '%s\n' "${URLS:-}" | tr ', ' '\n\n' | sed -E 's#^[a-zA-Z]+://##; s#[/?].*$##' | grep -v '^$' || true)
if [ -z "$hosts" ]; then echo "::error::no urls given"; exit 2; fi

for hp in $hosts; do
  host="${hp%%:*}"; port=443
  [ "$hp" != "$host" ] && port="${hp#*:}"
  out=$(timeout "$TIMEOUT" openssl s_client -connect "$host:$port" -servername "$host" \
          -verify_hostname "$host" -verify_return_error </dev/null 2>&1)
  rc=$?
  cert=$(printf '%s\n' "$out" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
  if [ -z "$cert" ]; then
    # With -verify_return_error the handshake aborts on a bad chain; fetch the cert anyway to report details.
    out2=$(timeout "$TIMEOUT" openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>&1)
    cert=$(printf '%s\n' "$out2" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
  fi
  if [ -z "$cert" ]; then
    rows+=("| $hp | FAIL | no TLS certificate (connection refused or timed out) | |"); fail=1
    echo "::error title=https-check::$hp: no TLS certificate (connection refused or timed out)"; continue
  fi
  end=$(printf '%s\n' "$cert" | openssl x509 -noout -enddate | cut -d= -f2)
  days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
  verr=$(printf '%s\n' "$out" | grep -m1 -E '^Verify return code:|verify error:' | sed -E 's/.*(Verify return code|verify error):[^:]*:?//; s/^ *//')
  vcode=$(printf '%s\n' "$out" | grep -m1 '^Verify return code:' | sed -E 's/Verify return code: ([0-9]+).*/\1/')
  problem=""
  if [ "$rc" -ne 0 ] || { [ -n "$vcode" ] && [ "$vcode" != "0" ]; }; then
    problem=$(printf '%s\n' "$out" | sed -n 's/.*verify error:num=[0-9]*://p' | head -1)
    [ -z "$problem" ] && problem="${verr:-handshake failed}"
  elif [ "$days" -lt 0 ]; then problem="expired $(( -days )) days ago"
  elif [ "$days" -lt "$MIN_DAYS" ]; then problem="expires in $days days (threshold $MIN_DAYS)"
  fi
  if [ -n "$problem" ]; then
    rows+=("| $hp | FAIL | $problem | $end |"); fail=1
    echo "::error title=https-check::$hp: $problem (notAfter $end)"
  else
    rows+=("| $hp | ok | valid, $days days left | $end |")
    echo "$hp: ok, $days days left"
  fi
done

{
  echo "### HTTPS certificate check"
  echo "| host | result | detail | expires |"
  echo "|---|---|---|---|"
  printf '%s\n' "${rows[@]}"
  if [ "$fail" -ne 0 ]; then
    echo
    echo "Visitors to a failing host see Chrome's full-page \"Your connection is not private\" warning. Most causes (expired certificate, www-only certificate, broken auto-renew) have a free fix on your host; see the README. If you'd rather hand it off: https://weio.ai/services/https-fix.html?utm_source=github&utm_medium=action&utm_campaign=https-check-action"
  fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

echo "failed=$fail" >> "${GITHUB_OUTPUT:-/dev/null}"
exit "$fail"
