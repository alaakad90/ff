import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lacasa_store/data/catalog.dart';
import 'package:lacasa_store/main.dart';
import 'package:lacasa_store/models/content.dart';
import 'package:lacasa_store/models/order.dart';
import 'package:lacasa_store/models/product.dart';
import 'package:lacasa_store/models/stats.dart';
import 'package:lacasa_store/screens/admin/stats_tab.dart';
import 'package:lacasa_store/screens/search_screen.dart';
import 'package:lacasa_store/services/auth_service.dart';
import 'package:lacasa_store/services/contact.dart';
import 'package:lacasa_store/services/instagram.dart';
import 'package:lacasa_store/services/media_uploader.dart';
import 'package:lacasa_store/services/note_attachments.dart';
import 'package:lacasa_store/services/order_service.dart';
import 'package:lacasa_store/services/push_service.dart';
import 'package:lacasa_store/services/store_repository.dart';
import 'package:lacasa_store/services/visit_tracker.dart';
import 'package:lacasa_store/state/cart.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool showSplash = false,
}) =>
    StoreApp(
      repository: repo,
      auth: auth ?? FakeAuthService(),
      notifier: notifier ?? RecordingNotifier(),
      uploader: uploader ?? FakeUploader(),
      push: push ?? FakePush(),
      attachments: attachments ?? FakeAttachments(),
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

void main() {
  test('formatPrice adds thousands separators', () {
    expect(formatPrice(500), '500 د.ع');
    expect(formatPrice(25000), '25,000 د.ع');
    expect(formatPrice(1250000), '1,250,000 د.ع');
  });

  test('week days start on Saturday', () {
    expect(weekDayName(DateTime(2026, 10, 24)), 'السبت');
    expect(weekDayName(DateTime(2026, 10, 30)), 'الجمعة');
    expect(weekDayName(DateTime(2026, 10, 26)), 'الإثنين');
  });

  test('Iraqi phone numbers become international for WhatsApp', () {
    expect(internationalPhone('07701234567'), '9647701234567');
    expect(internationalPhone('0770 123 4567'), '9647701234567');
    expect(internationalPhone('+964 770 123 4567'), '9647701234567');
    expect(internationalPhone('009647701234567'), '9647701234567');
    expect(whatsappUri('07701234567').toString(), 'https://wa.me/9647701234567');
  });

  test('cart totals and quantities', () {
    final a = sample(0).copyWith(id: 'a');
    final b = sample(1).copyWith(id: 'b');
    final cart = Cart()
      ..add(a)
      ..add(a, 2)
      ..add(b);
    expect(cart.count, 4);
    expect(cart.total, a.price * 3 + b.price);
    cart.decrement(cart.items.last);
    expect(cart.quantityOf(b), 0);
  });

  test('the same product with different notes stays on separate lines', () {
    final a = sample(0).copyWith(id: 'a');
    final cart = Cart()
      ..add(a, 1, 'بدون لون')
      ..add(a, 2, ' بدون لون ')
      ..add(a);
    expect(cart.items.length, 2);
    expect(cart.quantityOf(a), 4);
    final order = StoreOrder.fromCart(
      const Customer(name: 'x', phone: '07700000000'),
      cart,
      deliveryDay: 'السبت',
      pickupMethod: PickupMethod.delivery,
    );
    expect(order.items.first.note, 'بدون لون');
    expect(OrderItem.fromMap(order.items.first.toMap()).note, 'بدون لون');
    expect(order.items.last.toMap().containsKey('note'), isFalse);
  });

  test('Instagram reel links become embed links', () {
    expect(instagramEmbedUrl('https://www.instagram.com/reel/C7xYz_1-a/?igsh=abc'),
        'https://www.instagram.com/reel/C7xYz_1-a/embed/');
    expect(instagramEmbedUrl('https://instagram.com/reels/ABC/'), 'https://www.instagram.com/reel/ABC/embed/');
    expect(instagramEmbedUrl('https://www.instagram.com/lacasa3d/reel/ABC'),
        'https://www.instagram.com/reel/ABC/embed/');
    expect(instagramEmbedUrl('https://www.instagram.com/p/XYZ/'), 'https://www.instagram.com/p/XYZ/embed/');
    expect(instagramEmbedUrl('https://www.instagram.com/lacasa3d/'), isNull);
    expect(instagramEmbedUrl('https://x/v.mp4'), isNull);
  });

  test('content round trips through maps', () {
    const banner = PromoBanner(title: 'خصم', imageUrl: 'https://x/y.jpg', categoryId: 'c', order: 2);
    expect(PromoBanner.fromMap('b', banner.toMap()).toMap(), banner.toMap());
    const reel = Reel(videoUrl: 'https://x/v.mp4', caption: 'جديد', productId: 'p', active: false);
    expect(Reel.fromMap('r', reel.toMap()).toMap(), reel.toMap());
    const category = Category(name: 'خشب', iconKey: 'chair', order: 3);
    expect(Category.fromMap('c', category.toMap()).toMap(), category.toMap());
  });

  test('Supabase upload paths, content types and public links', () {
    final path = storagePath(
      MediaKind.image,
      'IMG_0001.JPEG',
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      random: Random(1),
    );
    expect(path, matches(RegExp(r'^images/1700000000000-[a-z0-9]{6}\.jpeg$')));
    expect(contentTypeFor(path), 'image/jpeg');
    expect(storagePath(MediaKind.video, 'clip.MOV'), endsWith('.mov'));
    expect(contentTypeFor('videos/x.mov'), 'video/quicktime');
    expect(storagePath(MediaKind.video, 'noext'), endsWith('.mp4'));
    expect(storagePath(MediaKind.image, 'x.exe'), endsWith('.jpg'));
    expect(
      publicUrl('https://abcd.supabase.co/', 'media', 'images/a.jpg'),
      'https://abcd.supabase.co/storage/v1/object/public/media/images/a.jpg',
    );
  });

  test('search matches name and description', () {
    expect(matchesQuery(sample(0), 'بوكس'), isTrue);
    expect(matchesQuery(sample(0), 'شموع'), isTrue);
    expect(matchesQuery(sample(0), 'عطر'), isFalse);
  });

  test('order notifier posts only the order id to the server', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{"ok":true}', 200);
    });
    const order = StoreOrder(
      id: 'o42',
      customer: Customer(name: 'علي', phone: '07701234567'),
      items: [],
      total: 1,
    );
    await OrderNotifier(client: client, endpoint: 'https://srv.example/notify-order').notify(order);
    expect(requests.single.url.toString(), 'https://srv.example/notify-order');
    expect(jsonDecode(requests.single.body), {'orderId': 'o42'});

    // بدون رابط، أو بدون رقم طلب، ما يدز شي.
    await OrderNotifier(client: client, endpoint: '').notify(order);
    await OrderNotifier(client: client, endpoint: 'https://srv.example/x').notify(order.copyWith(id: ''));
    expect(requests, hasLength(1));

    // تغيير الحالة يروح لـ /notify-status بنفس السيرفر.
    await OrderNotifier(client: client, endpoint: 'https://srv.example/notify-order').notifyStatus('o42');
    expect(requests.last.url.toString(), 'https://srv.example/notify-status');
    expect(jsonDecode(requests.last.body), {'orderId': 'o42'});

    // فشل السيرفر ما يوكف الطلب.
    final failing = MockClient((_) async => throw Exception('offline'));
    await OrderNotifier(client: failing, endpoint: 'https://srv.example/x').notify(order);
  });

  test('order stats count days, statuses, sales and top products', () {
    final now = DateTime(2026, 10, 24, 15);
    StoreOrder order(int total, OrderStatus status, DateTime at, {String phone = '07701234567', int qty = 1}) =>
        StoreOrder(
          customer: Customer(name: 'x', phone: phone),
          items: [OrderItem(productId: 'p$total', name: 'منتج $total', price: total ~/ qty, quantity: qty)],
          total: total,
          status: status,
          createdAt: at,
        );
    final stats = OrderStats.from([
      order(1000, OrderStatus.done, DateTime(2026, 10, 24, 9), qty: 2),
      order(2000, OrderStatus.pending, DateTime(2026, 10, 22), phone: '0780 000 0000'),
      order(5000, OrderStatus.cancelled, DateTime(2026, 10, 24, 10)),
      order(3000, OrderStatus.confirmed, DateTime(2026, 10, 2), phone: '+964 780 000 0000'),
      order(4000, OrderStatus.done, DateTime(2026, 9, 30)),
    ], now);
    expect(stats.total, 5);
    expect(stats.today, 2);
    expect(stats.week, 3);
    expect(stats.month, 4);
    expect(stats.byStatus[OrderStatus.done], 2);
    expect(stats.delivered, 5000);
    expect(stats.expected, 10000);
    expect(stats.average, 2500);
    expect(stats.customers, 3); // 07701234567، 07800000000، 9647800000000
    expect(stats.lastSevenDays, [0, 0, 0, 0, 1, 0, 2]);
    expect(stats.topProducts.first.name, 'منتج 1000');
    expect(stats.topProducts.first.quantity, 2);
    expect(stats.topProducts.any((p) => p.name == 'منتج 5000'), isFalse); // الملغي ما ينحسب
  });

  test('a device counts as a visitor once a day', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = InMemoryStoreRepository();
    final tracker = VisitTracker(repo);
    await tracker.track(now: DateTime(2026, 10, 24, 9));
    await tracker.track(now: DateTime(2026, 10, 24, 20));
    expect(repo.visits, hasLength(1));
    final first = repo.visits.keys.single;
    repo.visits.clear();
    await tracker.track(now: DateTime(2026, 10, 25, 9));
    expect(repo.visits.keys.single, first); // نفس الجهاز، نفس الرقم
    final stats = await repo.loadVisitorStats(DateTime.now());
    expect(stats.devices, 1);
    expect(stats.today, 1);
  });

  test('user orders only include that user', () async {
    final repo = InMemoryStoreRepository();
    const customer = Customer(name: 'a', phone: '07701234567');
    await repo.placeOrder(const StoreOrder(customer: customer, items: [], total: 1, userId: 'u1'));
    await repo.placeOrder(const StoreOrder(customer: customer, items: [], total: 2, userId: 'u2'));
    final mine = await repo.watchUserOrders('u1').first;
    expect(mine.map((o) => o.total), [1]);
  });

  testWidgets('splash animates the logo then opens the store', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(InMemoryStoreRepository(), showSplash: true));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.image(const AssetImage('assets/images/logo.png')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('home shows search box, banners and categories, with no admin button',
      (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository(
      products: [sample(0)],
      categories: sampleCategories,
      banners: const [PromoBanner(title: 'خصم الجمعة', categoryId: 'gifts')],
    );
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    expect(find.text('ابحث في كل المنتجات'), findsOneWidget);
    expect(find.text('خصم الجمعة'), findsOneWidget);
    expect(find.text('هدايا'), findsOneWidget);
    expect(find.byTooltip('لوحة التحكم'), findsNothing);
    for (final tab in ['الرئيسية', 'الأقسام', 'ريلز', 'السلة', 'الحساب']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget);
    }

    // البنر يفتح القسم المربوط بيه.
    await tester.tap(find.text('خصم الجمعة'));
    await tester.pumpAndSettle();
    expect(find.text(sample(0).name), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'هدايا'), findsOneWidget);
  });

  testWidgets('customer attaches a photo and a voice note to a product', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository(products: [sample(0)], categories: sampleCategories);
    final attachments = FakeAttachments();
    await tester.pumpWidget(app(repo, attachments: attachments));
    await tester.pumpAndSettle();

    await tester.tap(find.text(sample(0).name).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'ملاحظات على المنتج (اختياري)'), 'مثل الصورة');

    await tester.ensureVisible(find.text('أرفق صورة'));
    await tester.tap(find.text('أرفق صورة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اختار من الصور'));
    await tester.pumpAndSettle();
    expect(find.text('✓ الصورة'), findsOneWidget);

    await tester.tap(find.text('سجّل فويس'));
    await tester.pump();
    expect(attachments.recording, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('جاري التسجيل… 0:02'), findsOneWidget);
    // زر السلة يوكف بينما يتسجل.
    expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull);
    await tester.tap(find.byTooltip('خلص'));
    await tester.pumpAndSettle();
    expect(find.text('✓ الفويس'), findsOneWidget);

    await tester.tap(find.textContaining('أضف للسلة'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tapTab(tester, 'السلة');
    expect(find.text('🖼️ صورة  🎤 فويس'), findsOneWidget);

    final order = StoreOrder.fromCart(
      const Customer(name: 'x', phone: '07700000000'),
      tester.element(find.byType(NavigationBar)).read<Cart>(),
      deliveryDay: 'السبت',
      pickupMethod: PickupMethod.delivery,
    );
    final item = OrderItem.fromMap(order.items.single.toMap());
    expect(item.note, 'مثل الصورة');
    expect(item.imageUrl, 'https://cdn.example/notes/u/1-a.jpg');
    expect(item.voiceUrl, 'https://cdn.example/notes/u/2-b.m4a');
  });

  test('customer uploads go to their own folder', () {
    final path = notePath('uid42', 'm4a', now: DateTime.fromMillisecondsSinceEpoch(1700000000000), random: Random(1));
    expect(path, matches(RegExp(r'^notes/uid42/1700000000000-[a-z0-9]{6}\.m4a$')));
  });

  testWidgets('customer orders with a delivery day', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository(products: [sample(0), sample(2)], categories: sampleCategories);
    final notifier = RecordingNotifier();
    final push = FakePush('phone-token-1');
    await tester.pumpWidget(app(repo, notifier: notifier, push: push));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('أضف للسلة').first);
    await tester.pump(const Duration(seconds: 3)); // نستنى رسالة "انضاف للسلة" تختفي
    await tester.pumpAndSettle();
    await tapTab(tester, 'السلة');
    await tester.tap(find.text('إكمال الطلب'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'علي');
    await tester.enterText(fields.at(1), '07701234567');
    await tester.enterText(fields.at(2), 'بغداد، الكرادة');

    // بدون يوم ما يرسل.
    await tester.ensureVisible(find.text('أرسل الطلب'));
    await tester.tap(find.text('أرسل الطلب'));
    await tester.pumpAndSettle();
    expect(find.text('اختار يوم'), findsOneWidget);
    expect(repo.orders, isEmpty);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'الخميس'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'الخميس'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرسل الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('وصلنا طلبك'), findsOneWidget);
    final order = repo.orders.single;
    expect(order.deliveryDay, 'الخميس');
    expect(order.pickupMethod, PickupMethod.delivery);
    expect(order.customer.address, 'بغداد، الكرادة');
    expect(order.userId, isEmpty);
    expect(notifier.sent.single.id, order.id);
    expect(push.asked, 1);
    expect(order.pushToken, 'phone-token-1');
  });

  testWidgets('customer signs up and sees their orders', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository();
    final auth = FakeAuthService();
    await tester.pumpWidget(app(repo, auth: auth));
    await tester.pumpAndSettle();
    await tapTab(tester, 'الحساب');

    await tester.tap(find.text('حساب جديد'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'زينب');
    await tester.enterText(fields.at(1), 'zainab@example.com');
    await tester.enterText(fields.at(2), 'secret1');
    await tester.tap(find.text('سوي الحساب'));
    await tester.pumpAndSettle();

    expect(find.text('زينب'), findsOneWidget);
    final uid = auth.current.uid;
    expect(repo.profiles[uid]?.name, 'زينب');

    await repo.placeOrder(StoreOrder(
      customer: const Customer(name: 'زينب', phone: '07801234567'),
      items: const [OrderItem(productId: 'p', name: 'ساعة خشب', price: 30000, quantity: 1)],
      total: 30000,
      deliveryDay: 'الأحد',
      userId: uid,
    ));
    await tester.tap(find.text('طلباتي'));
    await tester.pumpAndSettle();
    expect(find.text('ساعة خشب × 1'), findsOneWidget);
    expect(find.text('توصيل • الأحد'), findsOneWidget);
  });

  testWidgets('customer signs in with Apple and deletes the account', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository();
    final auth = FakeAuthService()..supportsApple = true;
    await tester.pumpWidget(app(repo, auth: auth));
    await tester.pumpAndSettle();
    await tapTab(tester, 'الحساب');

    await tester.ensureVisible(find.text('المتابعة بحساب Apple'));
    await tester.tap(find.text('المتابعة بحساب Apple'));
    await tester.pumpAndSettle();
    expect(auth.current.uid, 'a1');

    await tester.ensureVisible(find.text('حذف الحساب'));
    await tester.tap(find.text('حذف الحساب'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); // داخل بآبل، فما يحتاج باسورد
    await tester.tap(find.text('احذف'));
    await tester.pumpAndSettle();
    expect(auth.deleted, ['a1']);
    expect(find.text('انحذف حسابك'), findsOneWidget);
    expect(find.text('سجل دخول حتى تتابع طلباتك'), findsOneWidget);
  });

  testWidgets('deleting a password account asks for the password', (tester) async {
    usePhoneSize(tester);
    final auth = FakeAuthService();
    await tester.pumpWidget(app(InMemoryStoreRepository(), auth: auth));
    await tester.pumpAndSettle();
    await auth.signIn('a@b.com', 'secret');
    await tapTab(tester, 'الحساب');

    await tester.ensureVisible(find.text('حذف الحساب'));
    await tester.tap(find.text('حذف الحساب'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'اكتب الباسورد حتى نتأكد'), 'wrong');
    await tester.tap(find.text('احذف'));
    await tester.pumpAndSettle();
    expect(auth.deleted, isEmpty);
    expect(find.text('الإيميل أو الباسورد غلط'), findsOneWidget);
  });

  testWidgets('Google button only shows when configured and signs in', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository();
    final auth = FakeAuthService();
    await tester.pumpWidget(app(repo, auth: auth));
    await tester.pumpAndSettle();
    await tapTab(tester, 'الحساب');
    expect(find.text('المتابعة بحساب Google'), findsNothing);

    auth.supportsGoogle = true;
    auth.googleName = null; // سكر النافذة
    await tester.pumpWidget(app(repo, auth: auth));
    await tester.pumpAndSettle();
    await tapTab(tester, 'الحساب');
    await tester.ensureVisible(find.text('المتابعة بحساب Google'));
    await tester.tap(find.text('المتابعة بحساب Google'));
    await tester.pumpAndSettle();
    expect(auth.current.signedIn, isFalse);
    expect(find.textContaining('خطأ'), findsNothing);

    auth.googleName = 'حسين';
    await tester.tap(find.text('المتابعة بحساب Google'));
    await tester.pumpAndSettle();
    expect(find.text('حسين'), findsOneWidget);
    expect(find.text('طلباتي'), findsOneWidget);
    expect(repo.profiles['g1']?.name, 'حسين');
  });

  testWidgets('admin uploads a product photo from the phone', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository(categories: sampleCategories);
    final auth = FakeAuthService(adminEmails: {'owner@example.com'});
    final uploader = FakeUploader();
    await tester.pumpWidget(app(repo, auth: auth, uploader: uploader));
    await tester.pumpAndSettle();
    await tapTab(tester, 'الحساب');
    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'دخول'));
    await tester.pumpAndSettle();
    await tapAdminTab(tester, 'المنتجات');
    await tester.pumpAndSettle();
    await tester.tap(find.text('منتج جديد'));
    await tester.pumpAndSettle();

    // بدون إعداد Supabase ماكو زر رفع.
    expect(find.text('اختار صورة من الموبايل'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    uploader
      ..enabled = true
      ..result = 'https://abcd.supabase.co/storage/v1/object/public/media/images/a.jpg';
    await tester.tap(find.text('منتج جديد'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('اختار صورة من الموبايل'));
    await tester.tap(find.text('اختار صورة من الموبايل'));
    await tester.pumpAndSettle();
    expect(uploader.picked, [MediaKind.image]);

    await tester.enterText(find.widgetWithText(TextFormField, 'اسم المنتج'), 'ساعة خشب');
    await tester.enterText(find.widgetWithText(TextFormField, 'السعر'), '30000');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('هدايا').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchProducts().first).single;
    expect(saved.name, 'ساعة خشب');
    expect(saved.imageUrl, uploader.result);
  });

  testWidgets('admin login from the account tab opens the control panel', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository();
    await repo.placeOrder(StoreOrder(
      customer: const Customer(name: 'زينب', phone: '07801234567', address: 'البصرة'),
      items: const [OrderItem(productId: 'p', name: 'كيكة', price: 1000, quantity: 1)],
      total: 1000,
      deliveryDay: 'السبت',
    ));
    final auth = FakeAuthService(adminEmails: {'owner@example.com'});
    final notifier = RecordingNotifier();
    await tester.pumpWidget(app(repo, auth: auth, notifier: notifier, push: FakePush('owner-phone')));
    await tester.pumpAndSettle();
    await tapTab(tester, 'الحساب');

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'دخول'));
    await tester.pumpAndSettle();
    expect(find.text('الإيميل أو الباسورد غلط'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'دخول'));
    await tester.pumpAndSettle();
    expect(find.text('لوحة التحكم'), findsOneWidget);
    // موبايل المدير يتسجل حتى يوصله إشعار الطلبات الجديدة.
    expect(repo.adminDevices.keys, ['owner-phone']);

    await tester.tap(find.text('زينب'));
    await tester.pumpAndSettle();
    expect(find.text('واتساب'), findsOneWidget);
    expect(find.text('اتصال'), findsOneWidget);
    expect(find.text('توصيل • السبت'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<OrderStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(OrderStatus.delivering.label).last);
    await tester.pumpAndSettle();
    expect(repo.orders.single.status, OrderStatus.delivering);
    // الزبون ينبعثله إشعار بالحالة الجديدة.
    expect(notifier.statusChanges, [repo.orders.single.id]);

    // الإحصائيات.
    await tapAdminTab(tester, 'الإحصائيات');
    await tester.pumpAndSettle();
    expect(find.text('زوار اليوم'), findsOneWidget);
    expect(find.text('طلبات اليوم'), findsOneWidget);
    expect(find.text('أكثر المنتجات طلباً'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('كيكة'),
      200,
      scrollable: find.descendant(of: find.byType(StatsTab), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('كيكة'), findsOneWidget);

    // الأقسام القديمة تنضاف بضغطة.
    await tapAdminTab(tester, 'الأقسام');
    await tester.pumpAndSettle();
    await tester.tap(find.text('أضف الأقسام القديمة'));
    await tester.pumpAndSettle();
    expect((await repo.watchCategories().first).map((c) => c.id), sampleCategories.map((c) => c.id));

    // عرض جديد يبين بالرئيسية.
    await tapAdminTab(tester, 'العروض');
    await tester.pumpAndSettle();
    await tester.tap(find.text('عرض جديد'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'العنوان (اختياري)'),
      'تخفيضات العيد',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect((await repo.watchBanners().first).single.title, 'تخفيضات العيد');

    await tapTab(tester, 'الرئيسية');
    expect(find.text('تخفيضات العيد'), findsOneWidget);
  });
}
