/// يحول رابط ريل أو منشور إنستغرام لرابط العرض المضمّن (embed) حتى يشتغل داخل التطبيق.
/// يرجع null إذا الرابط مو من إنستغرام.
///
///   https://www.instagram.com/reel/ABC123/?igsh=xyz ← https://www.instagram.com/reel/ABC123/embed/
String? instagramEmbedUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'instagram.com' && !host.endsWith('.instagram.com') && host != 'instagr.am') {
    return null;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  // الرابط ممكن يبدي باسم الحساب: instagram.com/<user>/reel/<code>
  final i = segments.indexWhere((s) => const {'reel', 'reels', 'p', 'tv'}.contains(s));
  if (i < 0 || i + 1 >= segments.length) return null;
  final code = segments[i + 1];
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(code)) return null;
  final kind = segments[i] == 'p' ? 'p' : 'reel';
  return 'https://www.instagram.com/$kind/$code/embed/';
}
