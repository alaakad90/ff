import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/order.dart';
import '../models/product.dart';
import '../state/cart.dart';
import 'auth_service.dart';

/// سطر من سطور الطلب كما يرسل للسيرفر. السعر ما ينرسل: السيرفر ياخذه من Firestore.
class OrderLine {
  final String productId;
  final int quantity;
  final String note;
  final String imageUrl;
  final String voiceUrl;
  final Map<String, String> options;

  const OrderLine({
    required this.productId,
    required this.quantity,
    this.note = '',
    this.imageUrl = '',
    this.voiceUrl = '',
    this.options = const {},
  });

  factory OrderLine.fromCartItem(CartItem item) => OrderLine(
        productId: item.product.id,
        quantity: item.quantity,
        note: item.note,
        imageUrl: item.imageUrl,
        voiceUrl: item.voiceUrl,
        options: item.options,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity': quantity,
        if (note.isNotEmpty) 'note': note,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (voiceUrl.isNotEmpty) 'voiceUrl': voiceUrl,
        if (options.isNotEmpty) 'options': optionsToList(options),
      };
}

class QuoteLine {
  final String productId;
  final String name;
  final int price;
  final int quantity;
  final Map<String, String> options;

  const QuoteLine(this.productId, this.name, this.price, this.quantity, {this.options = const {}});

  /// يطابق سطر السلة بنفس المنتج ونفس الاختيارات.
  String get key => '$productId\n${optionsLabel(options)}';
}

/// حساب السعر من السيرفر: الأسعار الحالية والخصومات والنقاط.
class OrderQuote {
  final List<QuoteLine> items;
  final List<String> unavailable; // أسماء (أو أرقام) المنتجات اللي ما متوفرة
  final int subtotal;
  final String couponCode;
  final int couponAmount;
  final String couponError;
  final int points;
  final int pointsAmount;
  final int maxPoints;
  final int total;
  final int pointsToEarn;
  final int balance;
  final int deliveryFee; // أجور المحافظة
  final int deliveryCharged; // اللي يندفع فعلاً (0 مع كوبون التوصيل المجاني)
  final bool freeDelivery;

  const OrderQuote({
    this.items = const [],
    this.unavailable = const [],
    required this.subtotal,
    this.couponCode = '',
    this.couponAmount = 0,
    this.couponError = '',
    this.points = 0,
    this.pointsAmount = 0,
    this.maxPoints = 0,
    required this.total,
    this.pointsToEarn = 0,
    this.balance = 0,
    this.deliveryFee = 0,
    this.deliveryCharged = 0,
    this.freeDelivery = false,
  });

  int get discount => couponAmount + pointsAmount;

  factory OrderQuote.fromJson(Map<String, dynamic> j) => OrderQuote(
        items: [
          for (final i in j['items'] as List? ?? const [])
            QuoteLine(i['productId'] as String, i['name'] as String? ?? '', (i['price'] as num).toInt(),
                (i['quantity'] as num).toInt(),
                options: optionsFromList(i['options'])),
        ],
        unavailable: [
          for (final u in j['unavailable'] as List? ?? const [])
            ((u['name'] as String?)?.isNotEmpty == true ? u['name'] as String : u['productId'] as String) +
                (u['reason'] == 'options' ? ' (خياراته تغيرت، احذفه واختاره من جديد)' : ''),
        ],
        subtotal: (j['subtotal'] as num?)?.toInt() ?? 0,
        couponCode: (j['coupon'] as Map?)?['code'] as String? ?? '',
        couponAmount: ((j['coupon'] as Map?)?['amount'] as num?)?.toInt() ?? 0,
        couponError: (j['couponError'] as Map?)?['message'] as String? ?? '',
        points: ((j['points'] as Map?)?['points'] as num?)?.toInt() ?? 0,
        pointsAmount: ((j['points'] as Map?)?['amount'] as num?)?.toInt() ?? 0,
        maxPoints: (j['maxPoints'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        pointsToEarn: (j['pointsToEarn'] as num?)?.toInt() ?? 0,
        balance: (j['balance'] as num?)?.toInt() ?? 0,
        deliveryFee: (j['deliveryFee'] as num?)?.toInt() ?? 0,
        deliveryCharged: (j['deliveryCharged'] as num?)?.toInt() ?? 0,
        freeDelivery: (j['coupon'] as Map?)?['freeDelivery'] == true,
      );
}

/// اللي يحتاجه السيرفر حتى يحسب أو ينشئ الطلب.
class OrderRequest {
  final String requestId;
  final List<OrderLine> lines;
  final Customer? customer;
  final String deliveryDay;
  final PickupMethod pickupMethod;
  final String zoneId; // المحافظة (للتوصيل)
  final String coupon;
  final int points;
  final int? expectedTotal;
  final String pushToken;

  const OrderRequest({
    this.requestId = '',
    required this.lines,
    this.customer,
    this.deliveryDay = '',
    this.pickupMethod = PickupMethod.delivery,
    this.zoneId = '',
    this.coupon = '',
    this.points = 0,
    this.expectedTotal,
    this.pushToken = '',
  });

  Map<String, dynamic> toJson() => {
        if (requestId.isNotEmpty) 'requestId': requestId,
        'items': lines.map((l) => l.toJson()).toList(),
        if (customer != null) 'customer': customer!.toMap(),
        if (customer != null) 'phone': customer!.phone,
        if (deliveryDay.isNotEmpty) 'deliveryDay': deliveryDay,
        'pickupMethod': pickupMethod.value,
        // دايماً للتوصيل (حتى لو فارغ): السيرفر يعرف إنها نسخة جديدة، فما يقبل توصيل بلا محافظة.
        if (pickupMethod == PickupMethod.delivery) 'zoneId': zoneId,
        if (coupon.isNotEmpty) 'coupon': coupon,
        if (points > 0) 'points': points,
        'expectedTotal': ?expectedTotal,
        if (pushToken.isNotEmpty) 'pushToken': pushToken,
      };
}

class PlacedOrder {
  final String orderId;
  final String trackingKey;
  final int total;
  final int discount;
  final bool duplicate;

  const PlacedOrder({
    required this.orderId,
    this.trackingKey = '',
    required this.total,
    this.discount = 0,
    this.duplicate = false,
  });
}

/// خطأ من السيرفر برسالة عربية جاهزة. quote موجود إذا السعر تغير (الزبون يشوف الجديد).
class StoreApiException implements Exception {
  final String message;
  final String code;
  final OrderQuote? quote;

  StoreApiException(this.message, {this.code = '', this.quote});

  @override
  String toString() => message;
}

/// رقم طلب عشوائي يتولد مرة وحدة لكل محاولة طلب. إذا انعاد نفس الطلب، السيرفر ما يكرره.
String newRequestId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();
}

/// كلام التطبيق ويا سيرفر المتجر (/api). السيرفر يتحقق من كل شي، فالتطبيق ما يقرر الأسعار.
abstract class StoreApi {
  /// false إذا رابط السيرفر ما انطى وقت البناء: الطلب يمشي بالطريقة القديمة بدون خصومات.
  bool get enabled;

  Future<OrderQuote> quote(OrderRequest request);
  Future<PlacedOrder> placeOrder(OrderRequest request);

  /// متابعة طلب زائر (بدون حساب) بمفتاح المتابعة.
  Future<StoreOrder> track(String orderId, String key);

  Future<String> referralCode();
  Future<void> applyReferral(String code);

  /// المدير بس: يغير الحالة، والسيرفر يرسل الإشعار ويضيف النقاط.
  Future<void> setOrderStatus(String orderId, OrderStatus status);
}

class HttpStoreApi implements StoreApi {
  static const _notifyUrl = String.fromEnvironment('NOTIFY_URL');

  final AuthService auth;
  final http.Client _client;
  final String baseUrl;

  /// baseUrl مثل https://lacasastores.com، أو فارغ بالمتصفح (نفس الموقع).
  HttpStoreApi(this.auth, {http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _notifyUrl.replaceFirst(RegExp(r'/notify-order$'), '');

  @override
  bool get enabled => _notifyUrl.isNotEmpty || baseUrl.isNotEmpty;

  Uri _uri(String path) {
    final url = '$baseUrl$path';
    // بالمتصفح الرابط نسبي (/api/...): نكمله من عنوان الصفحة.
    return url.startsWith('/') && kIsWeb ? Uri.base.resolve(url) : Uri.parse(url);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {bool retryToken = true}) async {
    final token = await auth.idToken();
    final http.Response response;
    try {
      response = await _client
          .post(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw StoreApiException('ماكو اتصال بالسيرفر. تأكد من الإنترنت وحاول مرة ثانية.', code: 'network');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      json = const {};
    }
    if (response.statusCode == 401 && retryToken) {
      // التوكن انتهى: نجدده ونعيد مرة وحدة.
      await auth.idToken(forceRefresh: true);
      return _post(path, body, retryToken: false);
    }
    if (response.statusCode != 200) {
      throw StoreApiException(
        json['error'] as String? ?? 'صار خطأ بالسيرفر (${response.statusCode})',
        code: json['code'] as String? ?? '',
        quote: json['quote'] is Map ? OrderQuote.fromJson(Map<String, dynamic>.from(json['quote'] as Map)) : null,
      );
    }
    return json;
  }

  @override
  Future<OrderQuote> quote(OrderRequest request) async =>
      OrderQuote.fromJson(await _post('/api/quote', request.toJson()));

  @override
  Future<PlacedOrder> placeOrder(OrderRequest request) async {
    final j = await _post('/api/orders', request.toJson());
    return PlacedOrder(
      orderId: j['orderId'] as String,
      trackingKey: j['trackingKey'] as String? ?? '',
      total: (j['total'] as num?)?.toInt() ?? 0,
      discount: (j['discount'] as num?)?.toInt() ?? 0,
      duplicate: j['duplicate'] as bool? ?? false,
    );
  }

  @override
  Future<StoreOrder> track(String orderId, String key) async {
    final j = await _post('/api/orders/track', {'orderId': orderId, 'key': key});
    final items = [
      for (final i in j['items'] as List? ?? const [])
        OrderItem(
          productId: i['productId'] as String? ?? '',
          name: i['name'] as String? ?? '',
          price: (i['price'] as num?)?.toInt() ?? 0,
          quantity: (i['quantity'] as num?)?.toInt() ?? 0,
          options: optionsFromList(i['options']),
        ),
    ];
    final total = (j['total'] as num?)?.toInt() ?? 0;
    return StoreOrder(
      id: orderId,
      customer: const Customer(name: '', phone: ''),
      items: items,
      total: total,
      subtotal: (j['subtotal'] as num?)?.toInt() ?? total,
      couponAmount: (j['discount'] as num?)?.toInt() ?? 0,
      deliveryDay: j['deliveryDay'] as String? ?? '',
      pickupMethod: PickupMethod.fromValue(j['pickupMethod'] as String?),
      deliveryFee: (j['deliveryFee'] as num?)?.toInt() ?? 0,
      deliveryZone: j['deliveryZone'] as String? ?? '',
      freeDelivery: j['freeDelivery'] == true,
      status: OrderStatus.fromValue(j['status'] as String?),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      statusHistory: [
        for (final h in j['statusHistory'] as List? ?? const [])
          StatusEvent(OrderStatus.fromValue(h['status'] as String?), DateTime.tryParse(h['at'] as String? ?? '')?.toLocal()),
      ],
      pricedByServer: true,
    );
  }

  @override
  Future<String> referralCode() async => (await _post('/api/referral/code', const {}))['code'] as String;

  @override
  Future<void> applyReferral(String code) => _post('/api/referral/apply', {'code': code.trim().toUpperCase()});

  @override
  Future<void> setOrderStatus(String orderId, OrderStatus status) =>
      _post('/api/admin/order-status', {'orderId': orderId, 'status': status.value});
}
