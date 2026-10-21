import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/order.dart';

/// يبلغ سيرفر المتجر (Cloudflare Worker) إن اكو طلب جديد.
/// السيرفر يقرا الطلب من Firestore بنفسه ويدز رسالة التليجرام،
/// فتوكن البوت ما يكون داخل التطبيق.
///
/// الرابط ينطى وقت البناء:
///   `flutter build apk --dart-define=NOTIFY_URL=https://lacasa-store.SUBDOMAIN.workers.dev/notify-order`
/// وGitHub Actions يحسبه من حساب Cloudflare. إذا ما انطى، الطلب ينحفظ بس وما يوصل إشعار.
class OrderNotifier {
  static const _endpoint = String.fromEnvironment('NOTIFY_URL');

  final http.Client _client;
  final String endpoint;

  OrderNotifier({http.Client? client, String? endpoint})
      : _client = client ?? http.Client(),
        endpoint = endpoint ?? _endpoint;

  /// ما يرمي أخطاء: الطلب محفوظ أصلاً، والإشعار إضافة.
  Future<void> notify(StoreOrder order) async {
    if (endpoint.isEmpty || order.id.isEmpty) return;
    try {
      await _client
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'orderId': order.id}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // الطلب يبين بلوحة التحكم حتى لو فشل الإشعار.
    }
  }
}
