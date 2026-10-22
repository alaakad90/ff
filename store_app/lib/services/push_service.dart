import 'package:firebase_messaging/firebase_messaging.dart';

/// إشعارات تليفون الزبون: يطلب الإذن ويجيب توكن التليفون حتى السيرفر يرسل عليه
/// إشعار من تنقبل الطلب، ومن يطلع للتوصيل، ومن يتسلم.
class PushService {
  const PushService();

  /// توكن التليفون، أو نص فارغ إذا الزبون رفض الإشعارات أو صار خطأ.
  /// ما يرمي أخطاء: الطلب يكمل حتى بدون إشعارات.
  Future<String> deviceToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission().timeout(const Duration(seconds: 30));
      if (settings.authorizationStatus == AuthorizationStatus.denied) return '';
      return await messaging.getToken().timeout(const Duration(seconds: 10)) ?? '';
    } catch (_) {
      // بالآيفون يحتاج حساب Apple Developer (مفتاح APNs) قبل ما يشتغل.
      return '';
    }
  }
}
