-- قواعد رفع الملفات بـ Supabase Storage لمتجر لاكاسا.
-- الصقه كله بـ Supabase ← SQL Editor ← New query، واضغط Run.
-- لإضافة مدير ثاني: ضيف رمز حسابه (UID) بالقائمتين جوه، مثل ('uid1', 'uid2')، وشغله مرة ثانية.
--
-- الشروط قبلها:
--   1. Authentication ← Third-party auth: Firebase (Project ID: lacasa-store-ef68f)
--   2. Storage: bucket عام (Public) اسمه media
--
-- القراءة: الـ bucket عام، فالصور والفيديوهات تنفتح من الرابط بدون تسجيل.
-- الرفع والحذف: بس لحسابات المدراء، حسب رمز الحساب (sub) بتوكن Firebase.

drop policy if exists "lacasa admins upload media" on storage.objects;
create policy "lacasa admins upload media"
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'media'
  and (auth.jwt() ->> 'iss') = 'https://securetoken.google.com/lacasa-store-ef68f'
  and (auth.jwt() ->> 'sub') in ('AjGMY89FeOh6s1H68SdKvqIEMWG2')
);

drop policy if exists "lacasa admins delete media" on storage.objects;
create policy "lacasa admins delete media"
on storage.objects for delete
to anon, authenticated
using (
  bucket_id = 'media'
  and (auth.jwt() ->> 'iss') = 'https://securetoken.google.com/lacasa-store-ef68f'
  and (auth.jwt() ->> 'sub') in ('AjGMY89FeOh6s1H68SdKvqIEMWG2')
);
