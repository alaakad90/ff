"""يتأكد إن أسرار السيرفر بالشكل الصحيح بدون ما يطبع قيمها.

يفشل البناء برسالة واضحة إذا، مثلاً، ملف مفتاح Firebase انحط بمكان توكن Cloudflare.
"""
import json
import os
import re
import sys
import urllib.request

errors = []

token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
if not re.fullmatch(r"[A-Za-z0-9_\-]{20,200}", token):
    hint = " (it looks like JSON; is the Firebase key file in the wrong secret?)" if "{" in token else ""
    errors.append("CLOUDFLARE_API_TOKEN is not a Cloudflare API token" + hint)

account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
if not re.fullmatch(r"[0-9a-f]{32}", account.strip()):
    errors.append("CLOUDFLARE_ACCOUNT_ID should be the 32-character account id")


def token_is_active(url):
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response).get("result", {}).get("status") == "active"
    except Exception:
        return False


# نسأل Cloudflare إذا التوكن شغال (توكنات الحساب والمستخدم إلهن رابطين).
if not errors:
    api = "https://api.cloudflare.com/client/v4"
    if not (token_is_active(f"{api}/user/tokens/verify")
            or token_is_active(f"{api}/accounts/{account.strip()}/tokens/verify")):
        if token == account.strip():
            shape = "it is the account id"
        elif re.fullmatch(r"[0-9a-f]{37}", token):
            shape = "it looks like the Global API Key, not an API token"
        elif re.fullmatch(r"[0-9a-f]{32}", token):
            shape = "it looks like a token ID, not the token value"
        else:
            shape = f"{len(token)} chars"
        errors.append(f"Cloudflare rejected CLOUDFLARE_API_TOKEN ({shape}); create a new token from the "
                      "'Edit Cloudflare Workers' template and paste the value shown once after creating it")

# Notepad بالويندوز أحياناً يضيف BOM بأول الملف، فنشيله.
raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").lstrip("\ufeff").strip()
# إذا انلصق المحتوى بدون { و } (يبدي بـ "type": ...)، نرجعهن. نفس الشي بالسيرفر.
if raw.startswith('"'):
    raw = "{" + raw.rstrip(",") + "}"
try:
    sa = json.loads(raw)
    if sa.get("type") != "service_account" or "private_key" not in sa or "client_email" not in sa:
        errors.append("FIREBASE_SERVICE_ACCOUNT is JSON but not a Firebase service account key")
    elif sa.get("project_id") != "lacasa-store-ef68f":
        errors.append("FIREBASE_SERVICE_ACCOUNT is for a different Firebase project")
except ValueError as e:
    # تلميحات آمنة بدون ما نطبع المحتوى.
    shape = (
        f"{len(raw)} chars, starts with {'{' if raw.startswith('{') else 'something other than {'}, "
        f"ends with {'}' if raw.endswith('}') else 'something other than }'}"
    )
    errors.append(
        "FIREBASE_SERVICE_ACCOUNT is not the JSON key file from Firebase > Service accounts "
        f"({shape}; JSON error at line {getattr(e, 'lineno', '?')}, column {getattr(e, 'colno', '?')})"
    )

if not os.environ.get("BOT_TOKEN") or not os.environ.get("CHAT_ID"):
    errors.append("BOT_TOKEN / CHAT_ID not set")

for error in errors:
    print(f"::error::{error}")
sys.exit(1 if errors else 0)
