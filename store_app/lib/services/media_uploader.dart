import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../cloudinary_config.dart';

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

/// روابط Cloudinary بتحويلات تخلي الملف أخف وتشتغل على كل الأجهزة:
/// الصور بصيغة وجودة تلقائية وعرض أقصاه 1600،
/// والفيديو mp4 بـ H.264 (فيديوهات الآيفون HEVC ما تشتغل على كل أندرويد).
String deliveryUrl(String secureUrl, MediaKind kind) {
  switch (kind) {
    case MediaKind.image:
      return secureUrl.replaceFirst('/image/upload/', '/image/upload/f_auto,q_auto,c_limit,w_1600/');
    case MediaKind.video:
      return secureUrl
          .replaceFirst('/video/upload/', '/video/upload/c_limit,w_1080,q_auto,vc_h264/')
          .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.mp4');
  }
}

class CloudinaryUploader implements MediaUploader {
  final ImagePicker _picker;
  final http.Client _client;

  CloudinaryUploader({ImagePicker? picker, http.Client? client})
      : _picker = picker ?? ImagePicker(),
        _client = client ?? http.Client();

  @override
  bool get enabled => cloudinaryConfigured;

  @override
  Future<String?> pickAndUpload(MediaKind kind) async {
    final XFile? file = switch (kind) {
      MediaKind.image =>
        await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 88),
      MediaKind.video =>
        await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3)),
    };
    if (file == null) return null;

    final resource = kind == MediaKind.image ? 'image' : 'video';
    final request = http.MultipartRequest(
      'POST',
      Uri.https('api.cloudinary.com', '/v1_1/$cloudinaryCloudName/$resource/upload'),
    )
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final http.Response response;
    try {
      final streamed = await _client
          .send(request)
          .timeout(kind == MediaKind.image ? const Duration(minutes: 1) : const Duration(minutes: 6));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw UploadException('ما كدرنا نرفع الملف. تأكد من الإنترنت وحاول مرة ثانية.');
    }

    final body = _decode(response.body);
    if (response.statusCode != 200) {
      final error = (body['error'] as Map?)?['message'];
      throw UploadException('ما كدرنا نرفع الملف${error == null ? '' : ': $error'}');
    }
    final url = body['secure_url'] as String?;
    if (url == null) throw UploadException('ما كدرنا نرفع الملف');
    return deliveryUrl(url, kind);
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      return const {};
    }
  }
}
