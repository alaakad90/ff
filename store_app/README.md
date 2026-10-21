# متجر لاكاسا

تطبيق متجر للآيفون والأندرويد مبني بـ Flutter.

| الرئيسية | السلة | إكمال الطلب |
|---|---|---|
| ![](screenshots/home.png) | ![](screenshots/cart.png) | ![](screenshots/checkout.png) |

## الميزات
- واجهة عربية كاملة من اليمين لليسار بخط Amiri
- أقسام وبحث عن المنتجات
- صفحة لكل منتج مع اختيار الكمية
- سلة مشتريات
- إكمال الطلب (اسم، هاتف، عنوان، ملاحظات) والدفع عند الاستلام
- الطلب يوصل كرسالة لمجموعة تليجرام مالت المتجر

## تعديل المنتجات
المنتجات والأقسام موجودة بملف `lib/data/catalog.dart`.

## ربط تليجرام
التوكن ما ينكتب بالكود. ينطى وقت البناء:

```bash
flutter run --dart-define=BOT_TOKEN=xxxx --dart-define=CHAT_ID=-100xxxx
```

بـ GitHub: روح على Settings ← Secrets and variables ← Actions، وضيف `BOT_TOKEN` و `CHAT_ID`.

## البناء
- **أندرويد:** `flutter build apk --release`
- **آيفون:** `flutter build ipa` (يحتاج جهاز Mac وحساب Apple Developer)

GitHub Actions (`.github/workflows/build.yml`) يبني نسخة APK ونسخة iOS غير موقعة مع كل push.
