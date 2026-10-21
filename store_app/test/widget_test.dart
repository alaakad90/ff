import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lacasa_store/data/catalog.dart';
import 'package:lacasa_store/main.dart';
import 'package:lacasa_store/models/content.dart';
import 'package:lacasa_store/models/order.dart';
import 'package:lacasa_store/models/product.dart';
import 'package:lacasa_store/screens/search_screen.dart';
import 'package:lacasa_store/services/auth_service.dart';
import 'package:lacasa_store/services/contact.dart';
import 'package:lacasa_store/services/order_service.dart';
import 'package:lacasa_store/services/store_repository.dart';
import 'package:lacasa_store/state/cart.dart';

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
    _emit(Session(role, uid: 'u-$email', email: email));
  }

  @override
  Future<String> signUp(String name, String email, String password) async {
    final uid = 'new${_nextUid++}';
    _emit(Session(Role.customer, uid: uid, email: email, name: name));
    return uid;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => _emit(Session.guest);
}

class RecordingNotifier extends TelegramNotifier {
  final sent = <StoreOrder>[];

  @override
  Future<void> notify(StoreOrder order) async => sent.add(order);
}

Product sample(int i) => sampleProducts[i];

Widget app(
  StoreRepository repo, {
  AuthService? auth,
  TelegramNotifier? notifier,
  bool showSplash = false,
}) =>
    StoreApp(
      repository: repo,
      auth: auth ?? FakeAuthService(),
      notifier: notifier ?? RecordingNotifier(),
      showSplash: showSplash,
    );

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
    cart.decrement(b);
    expect(cart.quantityOf(b), 0);
  });

  test('content round trips through maps', () {
    const banner = PromoBanner(title: 'خصم', imageUrl: 'https://x/y.jpg', categoryId: 'c', order: 2);
    expect(PromoBanner.fromMap('b', banner.toMap()).toMap(), banner.toMap());
    const reel = Reel(videoUrl: 'https://x/v.mp4', caption: 'جديد', productId: 'p', active: false);
    expect(Reel.fromMap('r', reel.toMap()).toMap(), reel.toMap());
    const category = Category(name: 'خشب', iconKey: 'chair', order: 3);
    expect(Category.fromMap('c', category.toMap()).toMap(), category.toMap());
  });

  test('search matches name and description', () {
    expect(matchesQuery(sample(0), 'بوكس'), isTrue);
    expect(matchesQuery(sample(0), 'شموع'), isTrue);
    expect(matchesQuery(sample(0), 'عطر'), isFalse);
  });

  test('telegram message has order day, delivery day and pickup method', () {
    final cart = Cart()..add(sample(2).copyWith(id: 'c'), 2);
    final order = StoreOrder.fromCart(
      const Customer(name: 'علي', phone: '07701234567', address: 'بغداد'),
      cart,
      deliveryDay: 'الخميس',
      pickupMethod: PickupMethod.pickup,
    ).copyWith(id: 'o42');
    final message = TelegramNotifier.buildMessage(order, now: DateTime(2026, 10, 24, 9, 5));
    expect(message, contains('وقت الطلب: السبت 2026/10/24 09:05'));
    expect(message, contains('يوم التسليم: الخميس'));
    expect(message, contains('طريقة الاستلام: استلام من المحل'));
    expect(message, contains('${sample(2).name} × 2'));
    expect(message, contains('o42'));
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

  testWidgets('customer orders with a delivery day', (tester) async {
    usePhoneSize(tester);
    final repo = InMemoryStoreRepository(products: [sample(0), sample(2)], categories: sampleCategories);
    final notifier = RecordingNotifier();
    await tester.pumpWidget(app(repo, notifier: notifier));
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
    await tester.pumpWidget(app(repo, auth: auth));
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

    // الأقسام القديمة تنضاف بضغطة.
    await tester.tap(find.widgetWithText(Tab, 'الأقسام'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أضف الأقسام القديمة'));
    await tester.pumpAndSettle();
    expect((await repo.watchCategories().first).map((c) => c.id), sampleCategories.map((c) => c.id));

    // عرض جديد يبين بالرئيسية.
    await tester.tap(find.widgetWithText(Tab, 'العروض'));
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
