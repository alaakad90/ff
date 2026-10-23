import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

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
      // بالآيفون توكن Firebase يحتاج توكن APNs من آبل أول، وهذا ممكن يتأخر ثواني.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        for (var i = 0; i < 20 && await messaging.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      return await messaging.getToken().timeout(const Duration(seconds: 10)) ?? '';
    } catch (_) {
      return '';
    }
  }
}
