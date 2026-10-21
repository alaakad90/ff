"""يتأكد إن أسرار السيرفر بالشكل الصحيح بدون ما يطبع قيمها.

يفشل البناء برسالة واضحة إذا، مثلاً، ملف مفتاح Firebase انحط بمكان توكن Cloudflare.
"""
import json
import os
import re
import sys

errors = []

token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
if not re.fullmatch(r"[A-Za-z0-9_\-]{20,200}", token):
    hint = " (it looks like JSON; is the Firebase key file in the wrong secret?)" if "{" in token else ""
    errors.append("CLOUDFLARE_API_TOKEN is not a Cloudflare API token" + hint)

account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
if not re.fullmatch(r"[0-9a-f]{32}", account.strip()):
    errors.append("CLOUDFLARE_ACCOUNT_ID should be the 32-character account id")

raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
try:
    sa = json.loads(raw)
    if sa.get("type") != "service_account" or "private_key" not in sa or "client_email" not in sa:
        errors.append("FIREBASE_SERVICE_ACCOUNT is JSON but not a Firebase service account key")
    elif sa.get("project_id") != "lacasa-store-ef68f":
        errors.append("FIREBASE_SERVICE_ACCOUNT is for a different Firebase project")
except ValueError:
    errors.append("FIREBASE_SERVICE_ACCOUNT is not the JSON key file from Firebase > Service accounts")

if not os.environ.get("BOT_TOKEN") or not os.environ.get("CHAT_ID"):
    errors.append("BOT_TOKEN / CHAT_ID not set")

for error in errors:
    print(f"::error::{error}")
sys.exit(1 if errors else 0)
