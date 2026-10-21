// إعدادات Cloudinary لرفع صور وفيديوهات لوحة التحكم.
// أزرار الرفع ما تبين إلا لما تنحط القيمتين.

/// Cloud name: يبين بأول صفحة بعد تسجيل الدخول بـ Cloudinary.
const cloudinaryCloudName = '';

/// اسم الـ Upload preset، لازم يكون Unsigned.
/// Settings ← Upload ← Upload presets.
const cloudinaryUploadPreset = '';

bool get cloudinaryConfigured =>
    cloudinaryCloudName.isNotEmpty && cloudinaryUploadPreset.isNotEmpty;
