[app]

title = LacasaApp
package.name = lacasa
package.domain = org.lacasa.app
source.include_exts = py,png,jpg,kv,ttf,json
version = 0.1
requirements = python3,kivy,requests,arabic_reshaper,python-bidi
orientation = portrait
fullscreen = 0
source.dir = .
icon.filename = icon.png
presplash.filename =

# Entry point
entrypoint = main.py

# Permissions
android.permissions = INTERNET

[buildozer]
log_level = 2
warn_on_root = 1

[android]
android.ndk = 25b
android.api = 31
android.ndk_api = 21
android.archs = armeabi-v7a, arm64-v8a

# لو تستخدم مكتبات إضافية خارجية أو ملفات خطوط
# أضفها هنا إن احتجت
