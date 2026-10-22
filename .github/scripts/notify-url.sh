#!/usr/bin/env bash
# يطبع NOTIFY_URL=<رابط السيرفر> حتى ينضاف لـ $GITHUB_ENV.
# الرابط: https://lacasa-store.<subdomain>.workers.dev/notify-order
# الـ subdomain مال حساب Cloudflare نجيبه من الـ API. إذا ما كدرنا، الرابط يبقى فارغ
# والتطبيق ينبني بدون إشعارات (الطلبات تنحفظ عادي).
set -u

warn() { echo "::warning::$1" >&2; echo "NOTIFY_URL="; exit 0; }

[ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] \
  || warn "CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set; building without order notifications"

# توكن Cloudflare حروف وأرقام بس. إذا انحط شي ثاني بمكانه (مثل ملف JSON) ما نرسله.
[[ "$CLOUDFLARE_API_TOKEN" =~ ^[A-Za-z0-9_-]{20,200}$ ]] \
  || warn "CLOUDFLARE_API_TOKEN doesn't look like a Cloudflare API token; building without order notifications"

response=$(curl -sS --max-time 20 \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain") \
  || warn "Could not reach the Cloudflare API; building without order notifications"

subdomain=$(printf '%s' "$response" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("result") or {}).get("subdomain") or "")' 2>/dev/null)
[ -n "$subdomain" ] \
  || warn "No workers.dev subdomain on the Cloudflare account (open Workers & Pages once in the dashboard); building without order notifications"

url="https://lacasa-store.$subdomain.workers.dev/notify-order"
echo "Server URL: $url" >&2
echo "NOTIFY_URL=$url"
