import 'package:http/http.dart' as http;

import '../models/order.dart';
import '../models/product.dart';

/// يرسل إشعار بالطلب لمجموعة تليجرام مالت المتجر.
///
/// التوكن ما ينكتب بالكود. ينطى وقت البناء:
///   flutter build apk --dart-define=BOT_TOKEN=... --dart-define=CHAT_ID=...
/// وبـ GitHub Actions ينقرا من الـ Secrets.
/// إذا ما انطى، الطلب ينحفظ بقاعدة البيانات بس وما يوصل إشعار.
class TelegramNotifier {
  static const _botToken = String.fromEnvironment('BOT_TOKEN');
  static const _chatId = String.fromEnvironment('CHAT_ID');

  final http.Client _client;

  TelegramNotifier({http.Client? client}) : _client = client ?? http.Client();

  static String buildMessage(StoreOrder order) {
    final customer = order.customer;
    final lines = <String>[
      '🛍️ طلب جديد',
      if (order.id.isNotEmpty) '🔖 رقم الطلب: ${order.id}',
      '',
      '👤 الاسم: ${customer.name}',
      '📞 الهاتف: ${customer.phone}',
      '📍 العنوان: ${customer.address}',
      if (customer.notes.isNotEmpty) '📝 ملاحظات: ${customer.notes}',
      '',
      '📦 المنتجات:',
      for (final item in order.items)
        '• ${item.name} × ${item.quantity} = ${formatPrice(item.total)}',
      '',
      '💰 المجموع: ${formatPrice(order.total)}',
      '💵 الدفع: عند الاستلام',
    ];
    return lines.join('\n');
  }

  /// ما يرمي أخطاء: الطلب محفوظ أصلاً، والإشعار إضافة.
  Future<void> notify(StoreOrder order) async {
    if (_botToken.isEmpty || _chatId.isEmpty) return;
    try {
      await _client
          .post(
            Uri.https('api.telegram.org', '/bot$_botToken/sendMessage'),
            body: {'chat_id': _chatId, 'text': buildMessage(order)},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // الطلب يبين بلوحة التحكم حتى لو فشل الإشعار.
    }
  }
}
