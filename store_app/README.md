# La Casa 3D

تطبيق متجر La Casa 3D للآيفون والأندرويد، مبني بـ Flutter و Firebase.

| البداية | الرئيسية | الأقسام | إكمال الطلب |
|---|---|---|---|
| ![](screenshots/splash.png) | ![](screenshots/home.png) | ![](screenshots/categories.png) | ![](screenshots/checkout.png) |

| الحساب | لوحة التحكم: الطلبات | لوحة التحكم: تعديل قسم |
|---|---|---|
| ![](screenshots/account.png) | ![](screenshots/admin_orders.png) | ![](screenshots/admin_category.png) |

## للزبون
- شاشة بداية بحركة للشعار
- الأزرار اللي جوه: الرئيسية، الأقسام، ريلز، السلة، الحساب
- الرئيسية: مستطيل "ابحث في كل المنتجات"، بنر قلّاب للعروض، الأقسام، وكل المنتجات
- ريلز: فيديوهات عمودية، وزر يفتح المنتج المربوط بالفيديو
- إكمال الطلب: توصيل أو استلام من المحل، ويوم التسليم (السبت - الجمعة)، والدفع عند الاستلام
- الحساب: تسجيل دخول أو حساب جديد بالإيميل أو بحساب Google، طلباتي، معلوماتي، عن المتجر
- الخط: بالآيفون خط النظام (SF Arabic)، وبالأندرويد IBM Plex Sans Arabic لأن خط Apple ما مسموح بغير أجهزتها

## لوحة التحكم
ما إلها أي زر ظاهر. صاحب المتجر يسجل دخول من تبويب "الحساب"، وإذا حسابه مدير تنفتح اللوحة مباشرة.

- **الطلبات:** معلومات الزبون، أزرار واتساب واتصال، يوم التسليم، وتغيير الحالة
- **المنتجات:** إضافة وتعديل وحذف وإخفاء
- **الأقسام:** الاسم والترتيب والأيقونة (من 24 أيقونة) أو صورة
- **العروض:** بنرات الصفحة الرئيسية، وكل بنر ممكن يفتح قسم
- **الريلز:** روابط فيديو مباشرة (mp4)، وكل فيديو ممكن يتربط بمنتج
- **المتجر:** نبذة، واتساب، رقم الاتصال، العنوان، أوقات الدوام، إنستغرام

## إعداد Firebase
المشروع: `lacasa-store-ef68f`. الإعدادات موجودة بـ `lib/firebase_options.dart`.

1. **قواعد الحماية:** كل ما يتغير `firestore.rules`، انسخه كله والصقه بـ Firestore ← Rules، واضغط Publish.
2. **حساب المدير:** بـ Authentication ← Users ضيف إيميلك وباسورد، وبـ Firestore سوي document بـ `admins/{UID}`.

## مفتاح التوقيع (أندرويد)
GitHub Actions يوقع الـ APK بمفتاح ثابت إذا هذني الـ Secrets موجودة:

| Secret | القيمة |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | ملف المفتاح `.jks` بصيغة base64 |
| `ANDROID_KEYSTORE_PASSWORD` | باسورد المفتاح (الـ alias هو `upload`) |

بدونهم يوقع بمفتاح debug يتغير كل بناء، فالتحديث ما ينصب فوق النسخة القديمة ودخول كوكل ما يشتغل.
**احتفظ بنسخة من ملف المفتاح والباسورد بمكان آمن.** خطوة "Show APK signing certificate" بالبناء تطبع بصمة SHA-1 و SHA-256.

## دخول كوكل
1. Firebase ← Project settings ← تطبيق الأندرويد ← **Add fingerprint**: ضيف SHA-1 و SHA-256 مال مفتاح التوقيع.
2. Authentication ← Sign-in method ← فعّل **Google**.
3. نزّل `google-services.json` و `GoogleService-Info.plist` من جديد، وحط القيم بـ `lib/google_sign_in_config.dart`:
   `googleWebClientId` (oauth_client بـ client_type: 3) و `googleIosClientId` (CLIENT_ID).
4. للآيفون: ضيف REVERSED_CLIENT_ID كـ URL scheme بـ `ios/Runner/Info.plist`.

الزر ما يبين إلا لما تنحط القيم.

## الصور والفيديوهات
لوحة التحكم بيها زر **"اختار صورة/فيديو من الموبايل"** يرفع الملف لـ Supabase Storage
(خطة Spark بـ Firebase ما بيها تخزين ملفات). وتبقى الخانة تقبل رابط `https://` من أي مكان.

الإعداد (مرة وحدة):
1. Supabase ← Authentication ← Third-party auth ← **Firebase**، بـ Project ID: `lacasa-store-ef68f`.
2. Storage ← New bucket اسمه `media` و **Public**، بحد 50 MB وأنواع `image/*, video/*`.
3. SQL Editor: الصق `supabase_storage.sql` (بيه رموز المدراء)، واضغط Run.
4. حط Project URL والمفتاح العام (anon/publishable) بـ `lib/supabase_config.dart`.

الزر ما يبين إلا لما تنحط القيم. الصور تتصغر بالموبايل قبل الرفع (عرض أقصاه 1600).
الفيديو أقصاه دقيقتين و50 MB؛ وأفضل يكون mp4، لأن فيديوهات الآيفون (HEVC) ما تشتغل على كل أجهزة الأندرويد.

## إشعار تليجرام (السيرفر)
الإشعار يندز من سيرفر صغير على Cloudflare Workers (مجلد `worker/` بأول المستودع)، مو من التطبيق،
فتوكن البوت ما يكون داخل الـ APK:

1. التطبيق يحفظ الطلب بـ Firestore، وبعدها يدز رقمه لـ `POST /notify-order`.
2. السيرفر يقرا الطلب بمفتاح خدمة Firebase، ويتأكد إنه جديد (أقل من ساعة) وما انبعث قبل.
3. يحط `notifiedAt` على الطلب بشرط ما تغير (حتى ما تنبعث الرسالة مرتين)، ويدز للتليجرام.

GitHub Secrets المطلوبة:

| Secret | شنو |
|---|---|
| `CLOUDFLARE_API_TOKEN` | توكن بقالب "Edit Cloudflare Workers" |
| `CLOUDFLARE_ACCOUNT_ID` | رقم حساب Cloudflare |
| `FIREBASE_SERVICE_ACCOUNT` | محتوى ملف مفتاح الخدمة (JSON) من Firebase ← Service accounts |
| `BOT_TOKEN` و `CHAT_ID` | البوت والمجموعة |

السيرفر ينشر أوتوماتيكياً مع كل دمج بـ `master` (أو من زر Run workflow)، والتطبيق ياخذ رابطه
(`https://lacasa-store.<subdomain>.workers.dev/notify-order`) وقت البناء. اختبارات السيرفر: `cd worker && npm test`.

## الأيقونة
الأيقونة تنولد من `assets/icon/`:

```bash
dart run flutter_launcher_icons
```

## البناء
- **أندرويد:** `flutter build apk --release`
- **آيفون:** `flutter build ipa` (يحتاج جهاز Mac وحساب Apple Developer)

GitHub Actions (`.github/workflows/build.yml`) يبني نسخة APK ونسخة iOS غير موقعة مع كل push.
