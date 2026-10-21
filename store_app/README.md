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
خطة Spark المجانية ما بيها رفع ملفات، فالصور والفيديوهات تنحط كروابط تبدي بـ `https://`.
للصور: [imgbb.com](https://imgbb.com) (Direct link). للفيديو: [Cloudinary](https://cloudinary.com) يعطي رابط mp4 مباشر.

## إشعار تليجرام
التوكن ما ينكتب بالكود. ينطى وقت البناء:

```bash
flutter run --dart-define=BOT_TOKEN=xxxx --dart-define=CHAT_ID=-100xxxx
```

بـ GitHub: Settings ← Secrets and variables ← Actions، وضيف `BOT_TOKEN` و `CHAT_ID`.

## الأيقونة
الأيقونة تنولد من `assets/icon/`:

```bash
dart run flutter_launcher_icons
```

## البناء
- **أندرويد:** `flutter build apk --release`
- **آيفون:** `flutter build ipa` (يحتاج جهاز Mac وحساب Apple Developer)

GitHub Actions (`.github/workflows/build.yml`) يبني نسخة APK ونسخة iOS غير موقعة مع كل push.
