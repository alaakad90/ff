import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../supabase_config.dart';
import 'media_uploader.dart';

/// صورة أو فويس يرفقه الزبون ويا ملاحظة المنتج.
/// ينرفع أول ما يختاره، والسلة تحفظ الرابط بس.
abstract class NoteAttachments {
  bool get enabled;

  /// تسجيل الفويس بالموبايل بس، مو بالمتصفح.
  bool get supportsVoice;

  /// يرجع null إذا الزبون سكر بدون ما يختار.
  Future<String?> pickImage({required bool camera});

  /// false إذا الزبون ما سمح بالمايكروفون.
  Future<bool> startRecording();

  /// يوكف التسجيل ويرفعه، ويرجع رابطه. null إذا ماكو تسجيل.
  Future<String?> stopRecording();

  Future<void> cancelRecording();
}

/// مسار ملفات الزبون: `notes/<uid>/1729550000000-k3j9x2.m4a`
/// قاعدة Supabase تسمح لكل زبون يرفع بس بمجلده.
String notePath(String uid, String ext, {DateTime? now, Random? random}) {
  final rand = random ?? Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return 'notes/$uid/$stamp-$suffix.$ext';
}

class SupabaseNoteAttachments implements NoteAttachments {
  static const maxVoice = Duration(minutes: 2);

  final ImagePicker _picker = ImagePicker();
  final http.Client _client = http.Client();
  AudioRecorder? _recorder;

  @override
  bool get enabled => supabaseConfigured;

  @override
  bool get supportsVoice => !kIsWeb;

  /// الزبون ممكن ما يكون مسجل دخول، فناخذ له حساب مجهول (Anonymous) بس حتى يرفع.
  Future<(String, String)> _identity() async {
    final auth = FirebaseAuth.instance;
    try {
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
      return (user.uid, (await user.getIdToken())!);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'operation-not-allowed' || e.code == 'admin-restricted-operation') {
        throw UploadException('رفع الصور والفويس بعده مو مفعّل بالمتجر');
      }
      throw UploadException('ما كدرنا نرفع الملف. تأكد من الإنترنت وحاول مرة ثانية.');
    }
  }

  Future<String> _upload(List<int> bytes, String ext) async {
    final (uid, token) = await _identity();
    return uploadToSupabase(_client, token: token, path: notePath(uid, ext), bytes: bytes);
  }

  @override
  Future<String?> pickImage({required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    if (await file.length() > 10 * 1024 * 1024) throw UploadException('الصورة كبيرة هواية');
    final dot = file.name.lastIndexOf('.');
    final ext = dot == -1 ? 'jpg' : file.name.substring(dot + 1).toLowerCase();
    return _upload(await file.readAsBytes(), const {'png', 'webp', 'heic'}.contains(ext) ? ext : 'jpg');
  }

  @override
  Future<bool> startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, numChannels: 1),
      path: '${dir.path}/note-${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    return true;
  }

  @override
  Future<String?> stopRecording() async {
    final path = await _recorder?.stop();
    if (path == null) return null;
    return _upload(await XFile(path).readAsBytes(), 'm4a');
  }

  @override
  Future<void> cancelRecording() async => _recorder?.cancel();
}
