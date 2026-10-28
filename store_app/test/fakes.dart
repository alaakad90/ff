// أدوات الاختبار المشتركة: حسابات وخدمات وهمية، وتشغيل التطبيق.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lacasa_store/data/catalog.dart';
import 'package:lacasa_store/main.dart';
import 'package:lacasa_store/models/order.dart';
import 'package:lacasa_store/models/product.dart';
import 'package:lacasa_store/services/auth_service.dart';
import 'package:lacasa_store/services/device_history.dart';
import 'package:lacasa_store/services/media_uploader.dart';
import 'package:lacasa_store/services/note_attachments.dart';
import 'package:lacasa_store/services/order_service.dart';
import 'package:lacasa_store/services/push_service.dart';
import 'package:lacasa_store/services/store_api.dart';
import 'package:lacasa_store/services/store_repository.dart';
import 'package:lacasa_store/state/theme_settings.dart';

/// حسابات وهمية: الباسورد لازم يكون "secret".
class FakeAuthService implements AuthService {
  final _session = StreamController<Session>.broadcast();
  final Set<String> adminEmails;
  Session current;
  var _nextUid = 1;

  FakeAuthService({this.current = Session.guest, this.adminEmails = const {}});

  void _emit(Session s) {
    current = s;
    _session.add(s);
  }

  @override
  Stream<Session> watchSession() async* {
    yield current;
    yield* _session.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (password != 'secret') throw AuthException('الإيميل أو الباسورد غلط');
    final role = adminEmails.contains(email) ? Role.admin : Role.customer;
    _emit(Session(role, uid: 'u-$email', email: email, usesPassword: true));
  }

  @override
  Future<String> signUp(String name, String email, String password) async {
    final uid = 'new${_nextUid++}';
    _emit(Session(Role.customer, uid: uid, email: email, name: name, usesPassword: true));
    return uid;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => current.signedIn ? 'uid:${current.uid}' : null;

  @override
  Future<void> signOut() async => _emit(Session.guest);

  @override
  bool supportsGoogle = false;

  /// null يعني الزبون سكر نافذة كوكل.
  String? googleName = 'حسين';

  @override
  Future<bool> signInWithGoogle() async {
    if (googleName == null) return false;
    _emit(Session(Role.customer, uid: 'g1', email: 'g@gmail.com', name: googleName!));
    return true;
  }

  @override
  bool supportsApple = false;

  @override
  Future<bool> signInWithApple() async {
    _emit(const Session(Role.customer, uid: 'a1', email: 'x@privaterelay.appleid.com'));
    return true;
  }

  final deleted = <String>[];

  @override
  Future<bool> deleteAccount({String? password}) async {
    if (current.usesPassword && password != 'secret') throw AuthException('الإيميل أو الباسورد غلط');
    deleted.add(current.uid);
    _emit(Session.guest);
    return true;
  }
}

class RecordingNotifier extends OrderNotifier {
  final sent = <StoreOrder>[];
  final statusChanges = <String>[];

  @override
  Future<void> notify(StoreOrder order) async => sent.add(order);

  @override
  Future<void> notifyStatus(String orderId) async => statusChanges.add(orderId);
}

class FakeAttachments implements NoteAttachments {
  bool recording = false;
  final bool micAllowed;

  FakeAttachments({this.micAllowed = true});

  @override
  bool get enabled => true;

  @override
  bool get supportsVoice => true;

  @override
  Future<String?> pickImage({required bool camera}) async => 'https://cdn.example/notes/u/1-a.jpg';

  @override
  Future<bool> startRecording() async => recording = micAllowed;

  @override
  Future<String?> stopRecording() async {
    recording = false;
    return 'https://cdn.example/notes/u/2-b.m4a';
  }

  @override
  Future<void> cancelRecording() async => recording = false;
}

class FakePush extends PushService {
  final String token;
  int asked = 0;

  FakePush([this.token = '']);

  @override
  Future<String> deviceToken() async {
    asked++;
    return token;
  }
}

class FakeUploader implements MediaUploader {
  @override
  bool enabled;

  /// الرابط اللي يرجعه، أو null كأن صاحب المتجر سكر المعرض.
  String? result;
  final picked = <MediaKind>[];

  FakeUploader({this.enabled = false, this.result});

  @override
  Future<String?> pickAndUpload(MediaKind kind) async {
    picked.add(kind);
    return result;
  }
}

Product sample(int i) => sampleProducts[i];

Widget app(
  StoreRepository repo, {
  AuthService? auth,
  OrderNotifier? notifier,
  MediaUploader? uploader,
  PushService? push,
  NoteAttachments? attachments,
  StoreApi? api,
  DeviceHistory? history,
  ThemeSettings? themeSettings,
  bool showSplash = false,
}) =>
    StoreApp(
      repository: repo,
      auth: auth ?? FakeAuthService(),
      notifier: notifier ?? RecordingNotifier(),
      uploader: uploader ?? FakeUploader(),
      push: push ?? FakePush(),
      attachments: attachments ?? FakeAttachments(),
      api: api,
      history: history ?? MemoryDeviceHistory(),
      themeSettings: themeSettings ?? ThemeSettings(),
      showSplash: showSplash,
    );

/// تبويبات لوحة التحكم تتمرر، فنخلي التبويب يبين قبل ما ندوس عليه.
Future<void> tapAdminTab(WidgetTester tester, String label) async {
  final tab = find.widgetWithText(Tab, label);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}


/// سيرفر وهمي (/api) فوق المستودع بالذاكرة: نفس قواعد الحساب المهمة (السعر من المنتجات،
/// الكوبون، النقاط بحد 50%)، ويسجل كل طلب حتى نتأكد شنو انرسل.
class FakeStoreApi implements StoreApi {
  final InMemoryStoreRepository repo;
  final AuthService auth;
  final quotes = <OrderRequest>[];
  final placed = <OrderRequest>[];
  final statusChanges = <(String, OrderStatus)>[];
  final appliedReferrals = <String>[];
  StoreApiException? nextPlaceError;

  FakeStoreApi(this.repo, this.auth);

  @override
  bool get enabled => true;

  Future<String> _uid() async {
    final token = await auth.idToken();
    return token == null ? '' : token.replaceFirst('uid:', '');
  }

  Future<OrderQuote> _compute(OrderRequest request) async {
    final uid = await _uid();
    final products = {for (final p in await repo.getProducts(request.lines.map((l) => l.productId))) p.id: p};
    final items = <QuoteLine>[];
    final unavailable = <String>[];
    for (final line in request.lines) {
      final p = products[line.productId];
      if (p == null || !p.available) {
        unavailable.add(p?.name ?? line.productId);
      } else {
        items.add(QuoteLine(p.id, p.name, p.priceWith(line.options), line.quantity, options: line.options));
      }
    }
    final subtotal = items.fold(0, (sum, l) => sum + l.price * l.quantity);
    // أجور التوصيل من قائمة المحافظات (مثل السيرفر)، والاستلام بلا أجور.
    final zone = repo.deliveryZones.where((z) => z.id == request.zoneId && z.active).firstOrNull;
    final deliveryFee = request.pickupMethod == PickupMethod.delivery ? (zone?.fee ?? 0) : 0;
    var couponAmount = 0;
    var couponError = '';
    var freeDelivery = false;
    if (request.coupon.isNotEmpty) {
      final c = repo.coupons[request.coupon];
      if (c == null || !c.active) {
        couponError = 'الكوبون مو صحيح';
      } else if (c.type.value == 'freeDelivery') {
        if (deliveryFee == 0) {
          couponError = 'كوبون التوصيل المجاني للطلبات اللي تنوصل بس';
        } else {
          freeDelivery = true;
          couponAmount = deliveryFee;
        }
      } else {
        couponAmount = c.type.value == 'percent' ? subtotal * c.value ~/ 100 : c.value;
        if (c.maxDiscount > 0 && couponAmount > c.maxDiscount) couponAmount = c.maxDiscount;
      }
    }
    final afterCoupon = subtotal - (freeDelivery ? 0 : couponAmount);
    final s = repo.loyalty;
    final balance = uid.isEmpty ? 0 : (repo.wallets[uid]?.points ?? 0);
    var maxPoints = uid.isEmpty ? 0 : [balance, afterCoupon * s.maxRedeemPercent ~/ 100 ~/ s.pointValue].reduce((a, b) => a < b ? a : b);
    if (maxPoints < s.minRedeemPoints) maxPoints = 0;
    final points = request.points.clamp(0, maxPoints);
    final pointsAmount = points * s.pointValue;
    final productsTotal = afterCoupon - pointsAmount;
    final deliveryCharged = freeDelivery ? 0 : deliveryFee;
    final total = productsTotal + deliveryCharged;
    return OrderQuote(
      items: items,
      unavailable: unavailable,
      subtotal: subtotal,
      couponCode: couponError.isEmpty ? request.coupon : '',
      couponAmount: couponAmount,
      couponError: couponError,
      points: points,
      pointsAmount: pointsAmount,
      maxPoints: maxPoints,
      total: total,
      pointsToEarn: uid.isEmpty ? 0 : productsTotal * s.pointsPer1000 ~/ 1000,
      balance: balance,
      deliveryFee: deliveryFee,
      deliveryCharged: deliveryCharged,
      freeDelivery: freeDelivery,
    );
  }

  @override
  Future<OrderQuote> quote(OrderRequest request) async {
    quotes.add(request);
    return _compute(request);
  }

  @override
  Future<PlacedOrder> placeOrder(OrderRequest request) async {
    placed.add(request);
    final error = nextPlaceError;
    if (error != null) {
      nextPlaceError = null;
      throw error;
    }
    final quote = await _compute(request);
    if (request.pickupMethod == PickupMethod.delivery &&
        !repo.deliveryZones.any((z) => z.id == request.zoneId && z.active)) {
      throw StoreApiException('اختار المحافظة', code: 'invalid_zone');
    }
    if (request.expectedTotal != null && request.expectedTotal != quote.total) {
      throw StoreApiException('الأسعار تغيرت، شوف المجموع الجديد', code: 'price_changed', quote: quote);
    }
    final uid = await _uid();
    await repo.putOrder(StoreOrder(
      id: request.requestId,
      customer: request.customer!,
      items: [for (final l in quote.items) OrderItem(productId: l.productId, name: l.name, price: l.price, quantity: l.quantity, options: l.options)],
      total: quote.total,
      subtotal: quote.subtotal,
      couponCode: quote.couponCode,
      couponAmount: quote.couponAmount,
      pointsUsed: quote.points,
      pointsDiscount: quote.pointsAmount,
      deliveryFee: quote.deliveryCharged,
      deliveryZone: repo.deliveryZones.where((z) => z.id == request.zoneId).firstOrNull?.name ?? '',
      freeDelivery: quote.freeDelivery,
      deliveryDay: request.deliveryDay,
      pickupMethod: request.pickupMethod,
      userId: uid,
      createdAt: DateTime.now(),
      statusHistory: [StatusEvent(OrderStatus.pending, DateTime.now())],
      pricedByServer: true,
    ));
    return PlacedOrder(
      orderId: request.requestId,
      trackingKey: 'key-${request.requestId}',
      total: quote.total,
      discount: quote.discount,
    );
  }

  @override
  Future<StoreOrder> track(String orderId, String key) async {
    if (key != 'key-$orderId') throw StoreApiException('الطلب مو موجود', code: 'not_found');
    return repo.orders.firstWhere((o) => o.id == orderId);
  }

  @override
  Future<String> referralCode() async => 'LCTEST22';

  @override
  Future<void> applyReferral(String code) async {
    if (code == 'LCTEST22') throw StoreApiException('ما تكدر تدعو نفسك', code: 'self');
    appliedReferrals.add(code);
  }

  @override
  Future<void> setOrderStatus(String orderId, OrderStatus status) async {
    statusChanges.add((orderId, status));
    await repo.setOrderStatus(orderId, status);
  }
}

/// يختار المحافظة من قائمة "المحافظة" بإكمال الطلب.
Future<void> pickGovernorate(WidgetTester tester, String name) async {
  final field = find.byIcon(Icons.map_outlined);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  final option = find.widgetWithText(ListTile, name);
  final sheet = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(option, 100, scrollable: sheet);
  await tester.tap(option);
  await tester.pumpAndSettle();
}
