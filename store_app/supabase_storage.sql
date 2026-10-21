-- قواعد رفع الملفات بـ Supabase Storage لمتجر لاكاسا.
-- الصقه بـ Supabase ← SQL Editor ← New query، وبدّل ADMIN_UID برمز حسابك بـ Firebase،
-- واضغط Run.
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
  and (auth.jwt() ->> 'sub') in ('ADMIN_UID')
);

drop policy if exists "lacasa admins delete media" on storage.objects;
create policy "lacasa admins delete media"
on storage.objects for delete
to anon, authenticated
using (
  bucket_id = 'media'
  and (auth.jwt() ->> 'iss') = 'https://securetoken.google.com/lacasa-store-ef68f'
  and (auth.jwt() ->> 'sub') in ('ADMIN_UID')
);
