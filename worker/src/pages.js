// صفحات ويب بسيطة يطلبها App Store وGoogle Play: سياسة الخصوصية والدعم.
// معلومات التواصل تنقرا من إعدادات المتجر (settings/store) اللي تتعدل من لوحة التحكم.

const escape = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));

function waLink(phone) {
  let digits = String(phone).replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = `964${digits.slice(1)}`;
  return `https://wa.me/${digits}`;
}

function contactList(info) {
  const items = [];
  if (info.whatsapp) items.push(`<li>واتساب: <a href="${escape(waLink(info.whatsapp))}" dir="ltr">${escape(info.whatsapp)}</a></li>`);
  if (info.phone) items.push(`<li>الهاتف: <a href="tel:${escape(info.phone)}" dir="ltr">${escape(info.phone)}</a></li>`);
  if (info.address) items.push(`<li>العنوان: ${escape(info.address)}</li>`);
  if (!items.length) items.push('<li>من صفحة "عن المتجر" داخل التطبيق.</li>');
  return `<ul>${items.join('')}</ul>`;
}

function page(title, body) {
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} | متجر لاكاسا</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, system-ui, "Segoe UI", Tahoma, sans-serif; line-height: 1.8;
         max-width: 720px; margin: 0 auto; padding: 24px 16px; }
  h1 { font-size: 1.6rem; margin-bottom: 4px; }
  h2 { font-size: 1.15rem; margin-top: 28px; }
  .muted { opacity: .7; font-size: .9rem; }
  a { color: #D32F2F; }
</style>
</head>
<body>
${body}
</body>
</html>`;
}

export function privacyPage(info = {}) {
  return page('سياسة الخصوصية', `
<h1>سياسة الخصوصية</h1>
<p class="muted">متجر لاكاسا (La Casa 3D) — آخر تحديث: تشرين الأول 2026</p>

<p>هذي الصفحة تشرح شنو المعلومات اللي ياخذها تطبيق "متجر لاكاسا"، وليش، وشلون تكدر تحذفها.</p>

<h2>المعلومات اللي نجمعها</h2>
<ul>
  <li><b>معلومات الطلب:</b> الاسم ورقم الهاتف والعنوان والملاحظات ويوم التسليم، حتى نوصل طلبك ونتواصل وياك.</li>
  <li><b>الصور والتسجيلات الصوتية:</b> إذا أرفقت صورة أو فويس ويا ملاحظة المنتج، تنرفع وتوصلنا ويا الطلب.</li>
  <li><b>الحساب (اختياري):</b> إذا سويت حساب أو دخلت بكوكل أو آبل، نحفظ الإيميل والاسم ومعلومات التوصيل حتى تتعبى بالطلب الجاي وتشوف طلباتك.</li>
  <li><b>الإشعارات:</b> رمز الإشعارات مال الموبايل، حتى نبلغك من ينقبل طلبك ومن يوصل.</li>
  <li><b>الإحصائيات:</b> رقم عشوائي للجهاز ويوم فتح التطبيق، حتى نعرف عدد الزوار. ما بيه أي معلومة شخصية.</li>
</ul>

<h2>شلون نستخدمها</h2>
<p>نستخدم المعلومات بس لتنفيذ الطلبات والتواصل وياك بخصوصها وتحسين المتجر. ما نبيع معلوماتك، وما نستخدمها للإعلانات، وما نشاركها ويا أي جهة غير الخدمات اللي يشتغل عليها التطبيق.</p>

<h2>الخدمات اللي نستخدمها</h2>
<ul>
  <li>Google Firebase: قاعدة البيانات وتسجيل الدخول والإشعارات.</li>
  <li>Supabase: حفظ الصور والتسجيلات الصوتية.</li>
  <li>Cloudflare وTelegram: إرسال إشعار الطلب الجديد لإدارة المتجر.</li>
</ul>

<h2 id="delete">حذف الحساب والمعلومات</h2>
<p>تكدر تحذف حسابك ومعلوماتك المحفوظة من داخل التطبيق: <b>الحساب ← حذف الحساب</b>. الطلبات السابقة تبقى عند المتجر للمدة اللازمة لإكمال التوصيل والحسابات. إذا تريد نحذفها هم، تواصل ويانا.</p>
<p>إذا ما عندك التطبيق، راسلنا على الواتساب أو الهاتف المكتوب جوّة من نفس الرقم أو الإيميل المسجل بالحساب، ونحذف حسابك ومعلوماتك خلال 7 أيام.</p>

<h2>الأطفال</h2>
<p>التطبيق متجر عام، وما نجمع معلومات عن الأطفال بشكل مقصود.</p>

<h2>التواصل</h2>
${contactList(info)}
`);
}

export function supportPage(info = {}) {
  return page('الدعم', `
<h1>الدعم — متجر لاكاسا</h1>
<p>عندك سؤال عن منتج، أو طلب، أو مشكلة بالتطبيق؟ تواصل ويانا:</p>
${contactList(info)}
<h2>أسئلة شائعة</h2>
<ul>
  <li><b>شلون أتابع طلبي؟</b> سجل دخول بالتطبيق وافتح "طلباتي"، ويوصلك إشعار من تتغير حالة الطلب.</li>
  <li><b>شلون أدفع؟</b> الدفع عند الاستلام.</li>
  <li><b>شلون أحذف حسابي؟</b> من التطبيق: الحساب ← حذف الحساب.</li>
</ul>
<p><a href="privacy">سياسة الخصوصية</a></p>
`);
}
