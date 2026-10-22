import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../supabase_config.dart';

enum MediaKind { image, video }

class UploadException implements Exception {
  final String message;
  UploadException(this.message);

  @override
  String toString() => message;
}

/// يختار صورة أو فيديو من الموبايل ويرفعه، ويرجع رابطه.
abstract class MediaUploader {
  /// إذا false، أزرار الرفع ما تبين.
  bool get enabled;

  /// يرجع null إذا صاحب المتجر سكر المعرض بدون ما يختار.
  Future<String?> pickAndUpload(MediaKind kind);
}

const _contentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'gif': 'image/gif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
};

/// مسار الملف داخل الـ bucket: images/1729550000000-k3j9x2.jpg
String storagePath(MediaKind kind, String fileName, {DateTime? now, Random? random}) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
  final safeExt = _contentTypes.containsKey(ext) ? ext : (kind == MediaKind.image ? 'jpg' : 'mp4');
  final rand = random ?? Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return '${kind == MediaKind.image ? 'images' : 'videos'}/$stamp-$suffix.$safeExt';
}

String contentTypeFor(String path) =>
    _contentTypes[path.substring(path.lastIndexOf('.') + 1)] ?? 'application/octet-stream';

/// الرابط العام للملف بعد الرفع.
String publicUrl(String baseUrl, String bucket, String path) =>
    '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/storage/v1/object/public/$bucket/$path';

/// يرفع لـ Supabase Storage بتوكن Firebase مال صاحب المتجر.
/// Supabase يثق بـ Firebase (Third-party auth)، وقاعدة الـ bucket تسمح
/// بالرفع بس لحسابات المدراء، فالزباين ما يكدرون يرفعون شي.
class SupabaseUploader implements MediaUploader {
  final ImagePicker _picker;
  final http.Client _client;
  final FirebaseAuth? _auth;

  SupabaseUploader({ImagePicker? picker, http.Client? client, FirebaseAuth? auth})
      : _picker = picker ?? ImagePicker(),
        _client = client ?? http.Client(),
        _auth = auth; // ignore: prefer_initializing_formals

  @override
  bool get enabled => supabaseConfigured;

  @override
  Future<String?> pickAndUpload(MediaKind kind) async {
    final XFile? file = switch (kind) {
      // تصغير الصورة هنا، لأن تحويل الصور بـ Supabase مو بالخطة المجانية.
      MediaKind.image =>
        await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85),
      MediaKind.video =>
        await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2)),
    };
    if (file == null) return null;

    // الخطة المجانية ما تقبل ملف أكبر من 50 MB.
    if (await file.length() > 50 * 1024 * 1024) {
      throw UploadException('الملف أكبر من 50 ميغا. اختار فيديو أقصر.');
    }

    final token = await (_auth ?? FirebaseAuth.instance).currentUser?.getIdToken();
    if (token == null) throw UploadException('سجل دخول بحساب المدير بالأول');

    final path = storagePath(kind, file.name);
    return uploadToSupabase(
      _client,
      token: token,
      path: path,
      bytes: await file.readAsBytes(),
      timeout: kind == MediaKind.image ? const Duration(minutes: 1) : const Duration(minutes: 6),
    );
  }
}

/// يرفع ملف لـ Supabase Storage بتوكن Firebase ويرجع رابطه العام.
Future<String> uploadToSupabase(
  http.Client client, {
  required String token,
  required String path,
  required List<int> bytes,
  Duration timeout = const Duration(minutes: 1),
}) async {
  final http.Response response;
  try {
    response = await client
        .post(
          Uri.parse('${supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
              '/storage/v1/object/$supabaseBucket/$path'),
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': supabaseAnonKey,
            'Content-Type': contentTypeFor(path),
            'Cache-Control': 'max-age=31536000',
            'x-upsert': 'false',
          },
          body: bytes,
        )
        .timeout(timeout);
  } catch (_) {
    throw UploadException('ما كدرنا نرفع الملف. تأكد من الإنترنت وحاول مرة ثانية.');
  }

  if (response.statusCode != 200) {
    throw UploadException(switch (response.statusCode) {
      401 || 403 => 'هذا الحساب ما عنده صلاحية يرفع ملفات',
      413 => 'الملف كبير هواية',
      _ => 'ما كدرنا نرفع الملف (${_uploadError(response.body) ?? response.statusCode})',
    });
  }
  return publicUrl(supabaseUrl, supabaseBucket, path);
}

String? _uploadError(String body) {
  try {
    final json = jsonDecode(body) as Map;
    return (json['message'] ?? json['error']) as String?;
  } catch (_) {
    return null;
  }
}
