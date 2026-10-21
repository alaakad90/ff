import 'package:http/http.dart' as http;

import '../models/product.dart';
import '../state/cart.dart';

class Customer {
  final String name;
  final String phone;
  final String address;
  final String notes;

  const Customer({
    required this.name,
    required this.phone,
    required this.address,
    this.notes = '',
  });
}

class OrderException implements Exception {
  final String message;
  OrderException(this.message);

  @override
  String toString() => message;
}

/// يرسل الطلب كرسالة لمجموعة تليجرام مالت المتجر.
///
/// التوكن ما ينكتب بالكود. ينطى وقت البناء:
///   flutter build apk --dart-define=BOT_TOKEN=... --dart-define=CHAT_ID=...
/// وبـ GitHub Actions ينقرا من الـ Secrets.
class OrderService {
  static const _botToken = String.fromEnvironment('BOT_TOKEN');
  static const _chatId = String.fromEnvironment('CHAT_ID');

  final http.Client _client;

  OrderService({http.Client? client}) : _client = client ?? http.Client();

  static String buildMessage(Customer customer, List<CartItem> items, int total) {
    final lines = <String>[
      '🛍️ طلب جديد',
      '',
      '👤 الاسم: ${customer.name}',
      '📞 الهاتف: ${customer.phone}',
      '📍 العنوان: ${customer.address}',
      if (customer.notes.isNotEmpty) '📝 ملاحظات: ${customer.notes}',
      '',
      '📦 المنتجات:',
      for (final item in items)
        '• ${item.product.name} × ${item.quantity} = ${formatPrice(item.total)}',
      '',
      '💰 المجموع: ${formatPrice(total)}',
      '💵 الدفع: عند الاستلام',
    ];
    return lines.join('\n');
  }

  Future<void> submit(Customer customer, List<CartItem> items, int total) async {
    if (_botToken.isEmpty || _chatId.isEmpty) {
      throw OrderException('التطبيق مو مربوط بتليجرام. لازم ينبنى مع BOT_TOKEN و CHAT_ID.');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.https('api.telegram.org', '/bot$_botToken/sendMessage'),
            body: {'chat_id': _chatId, 'text': buildMessage(customer, items, total)},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw OrderException('ماكو اتصال بالإنترنت. تأكد من الشبكة وحاول مرة ثانية.');
    }

    if (response.statusCode != 200) {
      throw OrderException('صار خطأ بإرسال الطلب (${response.statusCode}). حاول مرة ثانية.');
    }
  }
}
