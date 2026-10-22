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
  Future<void> notify(StoreOrder order) => _post(endpoint, order.id);

  /// بعد ما المدير يغير حالة الطلب: السيرفر يرسل إشعار لتليفون الزبون.
  Future<void> notifyStatus(String orderId) =>
      _post(endpoint.replaceFirst(RegExp(r'/notify-order$'), '/notify-status'), orderId);

  Future<void> _post(String url, String orderId) async {
    if (url.isEmpty || orderId.isEmpty) return;
    try {
      await _client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'orderId': orderId}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // الطلب يبين بلوحة التحكم حتى لو فشل الإشعار.
    }
  }
}
