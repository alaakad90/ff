// إعدادات Supabase Storage لرفع صور وفيديوهات لوحة التحكم.
// أزرار الرفع ما تبين إلا لما تنحط القيمتين.

/// Project URL: Project Settings ← Data API، مثل https://abcd.supabase.co
const supabaseUrl = '';

/// المفتاح العام (anon أو publishable). مو سري، والحماية بقواعد الـ bucket.
const supabaseAnonKey = '';

/// اسم الـ bucket العام اللي تنحفظ بيه الملفات.
const supabaseBucket = 'media';

bool get supabaseConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
