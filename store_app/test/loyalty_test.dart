// اختبارات الميزات الجديدة: الطلب السريع وإعادة الطلب، الكوبونات والنقاط، المتابعة،
// المحفظة والدعوات، العروض الذكية، ولوحة التحكم (الكوبونات والتقارير).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lacasa_store/models/content.dart';
import 'package:lacasa_store/models/delivery.dart';
import 'package:lacasa_store/models/loyalty.dart';
import 'package:lacasa_store/models/order.dart';
import 'package:lacasa_store/models/product.dart';
import 'package:lacasa_store/models/report.dart';
import 'package:lacasa_store/screens/account/order_details_screen.dart';
import 'package:lacasa_store/screens/admin/loyalty_admin.dart';
import 'package:lacasa_store/screens/product_screen.dart';
import 'package:lacasa_store/services/auth_service.dart';
import 'package:lacasa_store/services/device_history.dart';
import 'package:lacasa_store/services/recommendations.dart';
import 'package:lacasa_store/services/reorder.dart';
import 'package:lacasa_store/services/store_api.dart';
import 'package:lacasa_store/services/store_repository.dart';
import 'package:lacasa_store/state/cart.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

const weddingBoard = Product(id: 'wb', name: 'بورد زواج خشب', price: 40000, categoryId: 'boards');
const contract = Product(id: 'wc', name: 'عقد الزواج المزخرف', price: 25000, categoryId: 'contracts');
const contractBox = Product(id: 'wc2', name: 'علبة عقود قران', price: 30000, categoryId: 'contracts');
const babyBoard = Product(id: 'bb', name: 'بورد استقبال طفل', price: 35000, categoryId: 'boards');
const babyGift = Product(id: 'bg', name: 'توزيعات المواليد', price: 15000, categoryId: 'baby');
const clock = Product(id: 'ck', name: 'ساعة جدار', price: 50000, categoryId: 'decor');
const lamp = Product(id: 'lp', name: 'إضاءة ليلية', price: 20000, categoryId: 'decor');
const hidden = Product(id: 'hd', name: 'عقد قديم', price: 10000, categoryId: 'contracts', available: false);

const catalog = [weddingBoard, contract, contractBox, babyBoard, babyGift, clock, lamp, hidden];

const weddingRule = RecommendationRule(
  id: 'r1',
  title: 'كمّل فرحتكم: عقود الزواج',
  triggerKeywords: ['زواج', 'عرس'],
  targetKeywords: ['عقد', 'عقود'],
  order: 1,
);
const babyRule = RecommendationRule(
  id: 'r2',
  title: 'هدايا استقبال المولود',
  triggerKeywords: ['مولود', 'طفل'],
  targetCategoryIds: ['baby'],
  order: 2,
);

StoreOrder pastOrder(String id, List<Product> products, {String userId = 'u1', DateTime? at, OrderStatus? status}) =>
    StoreOrder(
      id: id,
      customer: const Customer(name: 'زينب', phone: '07801234567'),
      items: [for (final p in products) OrderItem(productId: p.id, name: p.name, price: p.price, quantity: 1)],
      total: products.fold(0, (s, p) => s + p.price),
      deliveryDay: 'الأحد',
      userId: userId,
      createdAt: at ?? DateTime(2026, 10, 1, 12),
      status: status ?? OrderStatus.done,
    );

/// يمرر صفحة القائمة لحد ما العنصر يبين (القوائم تبني العناصر لما تقترب من الشاشة).
Future<void> scrollTo(WidgetTester tester, Finder finder, {Type within = Form, double delta = 200}) async {
  final scrollable = find.descendant(of: find.byType(within), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(finder, delta, scrollable: scrollable);
  await tester.pumpAndSettle();
}

void main() {
  group('smart offers', () {
    test('a wedding board brings marriage contracts, a baby board brings newborn gifts', () {
      final wedding = recommend(catalog: catalog, rules: [weddingRule, babyRule], basis: [weddingBoard]);
      expect(wedding.single.title, 'كمّل فرحتكم: عقود الزواج');
      expect(wedding.single.products.map((p) => p.id), ['wc', 'wc2'], reason: 'hidden contract is not offered');

      final baby = recommend(catalog: catalog, rules: [weddingRule, babyRule], basis: [babyBoard]);
      expect(baby.single.title, 'هدايا استقبال المولود');
      expect(baby.single.products.map((p) => p.id), ['bg']);
    });

    test('Arabic spelling differences still match', () {
      expect(normalizeArabic('الزَّواج إستقبال مولودة'), 'الزواج استقبال مولوده');
      final rule = weddingRule.copyWith();
      const board = Product(id: 'x', name: 'لوحة الزّواج', price: 1, categoryId: '');
      expect(recommend(catalog: catalog, rules: [rule], basis: [board]).single.products, isNotEmpty);
    });

    test('falls back to the same category, and never offers what is in the cart', () {
      final groups = recommend(catalog: catalog, rules: [weddingRule], basis: [clock], exclude: {'lp'});
      expect(groups, isEmpty, reason: 'only lamp shares the category, and it is in the cart');
      final fallback = recommend(catalog: catalog, rules: [weddingRule], basis: [clock]);
      expect(fallback.single.title, 'مقترحة لك');
      expect(fallback.single.products.map((p) => p.id), ['lp']);
      expect(recommend(catalog: catalog, rules: [weddingRule], basis: const []), isEmpty);
    });

    testWidgets('home shows wedding contracts to someone who ordered a wedding board', (tester) async {
      usePhoneSize(tester);
      final repo = InMemoryStoreRepository(products: catalog);
      await repo.saveRecommendationRule(weddingRule);
      await repo.putOrder(pastOrder('o1', [weddingBoard]));
      final auth = FakeAuthService(current: const Session(Role.customer, uid: 'u1', name: 'زينب'));
      await tester.pumpWidget(app(repo, auth: auth));
      await tester.pumpAndSettle();
      expect(find.text('كمّل فرحتكم: عقود الزواج'), findsOneWidget);
    });

    testWidgets('a guest sees offers from what this phone ordered before', (tester) async {
      usePhoneSize(tester);
      final repo = InMemoryStoreRepository(products: catalog);
      await repo.saveRecommendationRule(babyRule);
      final history = MemoryDeviceHistory()..products.add('bb');
      await tester.pumpWidget(app(repo, history: history));
      await tester.pumpAndSettle();
      expect(find.text('هدايا استقبال المولود'), findsOneWidget);
    });
  });

  group('reorder', () {
    test('uses today\'s prices and drops what is no longer sold', () {
      const cheaper = Product(id: 'wb', name: 'بورد زواج خشب', price: 35000, categoryId: 'boards');
      final order = pastOrder('o1', [weddingBoard, clock, hidden]);
      final lines = planReorder(order, [cheaper, clock, hidden]);
      expect(lines.map((l) => l.change), [ReorderChange.cheaper, ReorderChange.same, ReorderChange.unavailable]);
      final items = reorderCartItems(lines);
      expect(items.map((i) => (i.product.id, i.product.price)), [('wb', 35000), ('ck', 50000)]);
    });

    testWidgets('customer reorders from their order history', (tester) async {
      usePhoneSize(tester);
      const pricier = Product(id: 'ck', name: 'ساعة جدار', price: 55000, categoryId: 'decor');
      final repo = InMemoryStoreRepository(products: [weddingBoard, pricier, hidden]);
      await repo.putOrder(pastOrder('o1', [clock, hidden]));
      final auth = FakeAuthService(current: const Session(Role.customer, uid: 'u1', name: 'زينب'));
      await tester.pumpWidget(app(repo, auth: auth));
      await tester.pumpAndSettle();
      await tapTab(tester, 'الحساب');
      await tester.tap(find.text('طلباتي'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('اطلب مرة ثانية'));
      await tester.pumpAndSettle();
      expect(find.text('ما متوفر هسه'), findsOneWidget);
      expect(find.textContaining('كان 50,000 د.ع • هسه 55,000 د.ع'), findsOneWidget);
      await tester.tap(find.text('أضف للسلة'));
      await tester.pumpAndSettle();

      final cart = tester.element(find.byType(NavigationBar)).read<Cart>();
      expect(cart.items.single.product.price, 55000);
      expect(find.text('إكمال الطلب'), findsOneWidget, reason: 'opens the cart');
    });
  });

  group('checkout through the server', () {
    Future<(InMemoryStoreRepository, FakeStoreApi, MemoryDeviceHistory)> openCheckout(
      WidgetTester tester, {
      Session session = Session.guest,
      int points = 0,
    }) async {
      usePhoneSize(tester);
      final repo = InMemoryStoreRepository(products: [clock, lamp]);
      repo.coupons['EID10'] = const Coupon(code: 'EID10', value: 10, maxDiscount: 4000);
      if (points > 0) repo.wallets[session.uid] = Wallet(points: points);
      final auth = FakeAuthService(current: session);
      final api = FakeStoreApi(repo, auth);
      final history = MemoryDeviceHistory();
      await tester.pumpWidget(app(repo, auth: auth, api: api, history: history));
      await tester.pumpAndSettle();
      final cart = tester.element(find.byType(NavigationBar)).read<Cart>();
      cart.add(clock, 1);
      await tapTab(tester, 'السلة');
      await tester.tap(find.text('إكمال الطلب'));
      await tester.pumpAndSettle();
      return (repo, api, history);
    }

    /// [governorate] null = استلام من المحل (بلا أجور توصيل)، وإلا توصيل لهاي المحافظة.
    Future<void> fillAndSend(WidgetTester tester, {String? governorate}) async {
      await scrollTo(tester, find.widgetWithText(TextFormField, 'الاسم'), delta: -300);
      await tester.enterText(find.widgetWithText(TextFormField, 'الاسم'), 'علي');
      await tester.enterText(find.widgetWithText(TextFormField, 'رقم الهاتف'), '07701234567');
      if (governorate == null) {
        await tester.ensureVisible(find.text('استلام من المحل'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('استلام من المحل'));
        await tester.pumpAndSettle();
      } else {
        await pickGovernorate(tester, governorate);
        await tester.enterText(find.widgetWithText(TextFormField, 'الحي والمنطقة وتفاصيل العنوان'), 'حي العسكري');
      }
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'الخميس'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'الخميس'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أرسل الطلب'));
      await tester.pumpAndSettle();
    }

    testWidgets('a guest applies a coupon, orders, and can track the order later', (tester) async {
      final (repo, api, history) = await openCheckout(tester);
      await scrollTo(tester, find.widgetWithText(TextField, 'كوبون خصم (اختياري)'));
      await tester.enterText(find.widgetWithText(TextField, 'كوبون خصم (اختياري)'), 'eid10');
      await tester.tap(find.text('طبّق'));
      await tester.pumpAndSettle();
      expect(find.text('كوبون EID10'), findsWidgets);
      await scrollTo(tester, find.text('- 4,000 د.ع'));
      expect(find.text('- 4,000 د.ع'), findsOneWidget);
      expect(find.text('46,000 د.ع'), findsOneWidget);

      await fillAndSend(tester);
      expect(find.text('وصلنا طلبك'), findsOneWidget);
      final request = api.placed.single;
      expect(request.coupon, 'EID10');
      expect(request.expectedTotal, 46000);
      expect(request.lines.single.productId, 'ck');
      expect(repo.orders.single.total, 46000);
      expect(history.orders.single.key, 'key-${request.requestId}');
      expect(history.products, ['ck']);

      await tester.tap(find.text('تمام'));
      await tester.pumpAndSettle();
      await tapTab(tester, 'الحساب');
      await tester.tap(find.text('تتبع طلباتي'));
      await tester.pumpAndSettle();
      expect(find.text('ساعة جدار × 1'), findsOneWidget);
      await tester.tap(find.text('تابع الطلب'));
      await tester.pumpAndSettle();
      expect(find.text('متابعة الطلب'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'only "new" is reached');
    });

    testWidgets('a wrong coupon is shown and blocks sending', (tester) async {
      final (_, api, _) = await openCheckout(tester);
      await scrollTo(tester, find.widgetWithText(TextField, 'كوبون خصم (اختياري)'));
      await tester.enterText(find.widgetWithText(TextField, 'كوبون خصم (اختياري)'), 'NOPE');
      await tester.tap(find.text('طبّق'));
      await tester.pumpAndSettle();
      expect(find.text('الكوبون مو صحيح'), findsOneWidget);
      await fillAndSend(tester);
      expect(api.placed, isEmpty);
      expect(find.text('الكوبون مو صالح، شيله أو غيّره'), findsOneWidget);
    });

    testWidgets('a member pays part with points', (tester) async {
      final (_, api, _) = await openCheckout(
        tester,
        session: const Session(Role.customer, uid: 'u1', name: 'علي'),
        points: 300,
      );
      await scrollTo(tester, find.text('استعمل نقاطك (عندك 300)'));
      expect(find.text('استعمل نقاطك (عندك 300)'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('300 نقطة = خصم 15,000 د.ع'), findsOneWidget);
      await scrollTo(tester, find.text('35,000 د.ع'));
      expect(find.text('35,000 د.ع'), findsOneWidget);
      await fillAndSend(tester);
      expect(api.placed.single.points, 300);
      expect(api.placed.single.expectedTotal, 35000);
    });

    testWidgets('if the price changed, the customer sees the new total and nothing is placed', (tester) async {
      final (repo, api, _) = await openCheckout(tester);
      // نختار الاستلام أول (هذا يعيد الحساب)، وبعدها يتغير السعر بالسيرفر.
      await tester.tap(find.text('استلام من المحل'));
      await tester.pumpAndSettle();
      await repo.saveProduct(const Product(id: 'ck', name: 'ساعة جدار', price: 52000, categoryId: 'decor'));
      await fillAndSend(tester);
      expect(find.text('الأسعار تغيرت، شوف المجموع الجديد'), findsOneWidget);
      expect(find.text('52,000 د.ع'), findsWidgets);
      expect(repo.orders, isEmpty);
      // الضغطة الثانية بنفس رقم الطلب وبالسعر الجديد تنجح.
      await tester.tap(find.text('أرسل الطلب'));
      await tester.pumpAndSettle();
      expect(repo.orders.single.total, 52000);
      expect(api.placed.map((r) => r.requestId).toSet().length, 1, reason: 'same request id on retry');
    });

    testWidgets('delivery fee follows the governorate, stays out of discounts, and pickup is free', (tester) async {
      final (repo, api, _) = await openCheckout(tester);
      await scrollTo(tester, find.text('أجور التوصيل'));
      expect(find.text('اختار المحافظة'), findsWidgets, reason: 'no fee until a governorate is chosen');

      // كوبون 10% (حد 4,000) على المنتجات بس: 50,000 - 4,000 + 2,000 توصيل.
      await scrollTo(tester, find.widgetWithText(TextField, 'كوبون خصم (اختياري)'), delta: -200);
      await tester.enterText(find.widgetWithText(TextField, 'كوبون خصم (اختياري)'), 'EID10');
      await tester.tap(find.text('طبّق'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byIcon(Icons.map_outlined), delta: -300);
      await pickGovernorate(tester, 'الديوانية - المركز');
      expect(find.text('الديوانية - المركز • التوصيل 2,000 د.ع'), findsOneWidget);
      await scrollTo(tester, find.text('48,000 د.ع'));
      expect(find.text('2,000 د.ع'), findsOneWidget);
      expect(find.text('- 4,000 د.ع'), findsOneWidget);

      await scrollTo(tester, find.byIcon(Icons.map_outlined), delta: -300);
      await pickGovernorate(tester, 'الديوانية - الأقضية والنواحي');
      // سطر الساعة 50,000، والمنتجات 50,000، والمجموع 50,000 (50,000 - 4,000 خصم + 4,000 توصيل).
      await scrollTo(tester, find.text('50,000 د.ع').first);
      expect(find.text('50,000 د.ع'), findsNWidgets(3));
      expect(find.text('4,000 د.ع'), findsOneWidget);

      await scrollTo(tester, find.byIcon(Icons.map_outlined), delta: -300);
      await pickGovernorate(tester, 'البصرة');
      await scrollTo(tester, find.text('51,000 د.ع'));

      await fillAndSend(tester, governorate: 'البصرة');
      final request = api.placed.single;
      expect((request.zoneId, request.expectedTotal), ('basra', 51000));
      final order = repo.orders.single;
      expect((order.deliveryFee, order.deliveryZone, order.total), (5000, 'البصرة', 51000));
    });

    testWidgets('pickup has no delivery fee', (tester) async {
      final (repo, api, _) = await openCheckout(tester);
      await fillAndSend(tester);
      expect(api.placed.single.pickupMethod, PickupMethod.pickup);
      expect(repo.orders.single.total, 50000);
    });

    testWidgets('a free-delivery coupon removes only the delivery fee', (tester) async {
      final (repo, _, _) = await openCheckout(tester);
      repo.coupons['FREESHIP'] = const Coupon(code: 'FREESHIP', value: 0, type: CouponType.freeDelivery);
      await pickGovernorate(tester, 'بغداد');
      await scrollTo(tester, find.widgetWithText(TextField, 'كوبون خصم (اختياري)'));
      await tester.enterText(find.widgetWithText(TextField, 'كوبون خصم (اختياري)'), 'FREESHIP');
      await tester.tap(find.text('طبّق'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('مجاني (كوبون FREESHIP)'));
      expect(find.text('50,000 د.ع'), findsWidgets);
      await fillAndSend(tester, governorate: 'بغداد');
      final order = repo.orders.single;
      expect((order.total, order.deliveryFee, order.freeDelivery), (50000, 0, true));
    });

    testWidgets('a delivery order cannot be sent without a governorate', (tester) async {
      final (repo, api, _) = await openCheckout(tester);
      await scrollTo(tester, find.widgetWithText(TextFormField, 'الاسم'), delta: -300);
      await tester.enterText(find.widgetWithText(TextFormField, 'الاسم'), 'علي');
      await tester.enterText(find.widgetWithText(TextFormField, 'رقم الهاتف'), '07701234567');
      await tester.enterText(find.widgetWithText(TextFormField, 'الحي والمنطقة وتفاصيل العنوان'), 'حي العسكري');
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'الخميس'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'الخميس'));
      await tester.tap(find.text('أرسل الطلب'));
      await tester.pumpAndSettle();
      expect(api.placed, isEmpty);
      await scrollTo(tester, find.byIcon(Icons.map_outlined), delta: -300);
      expect(find.text('اختار المحافظة'), findsWidgets);
    });

    testWidgets('quick order buys one product without touching the cart', (tester) async {
      usePhoneSize(tester);
      final repo = InMemoryStoreRepository(products: [clock, lamp]);
      final auth = FakeAuthService();
      final api = FakeStoreApi(repo, auth);
      await tester.pumpWidget(app(repo, auth: auth, api: api));
      await tester.pumpAndSettle();
      final cart = tester.element(find.byType(NavigationBar)).read<Cart>()..add(lamp, 2);
      Navigator.of(tester.element(find.byType(NavigationBar)))
          .push(MaterialPageRoute(builder: (_) => const ProductScreen(product: clock)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اطلب الآن'));
      await tester.pumpAndSettle();
      expect(find.text('طلب سريع'), findsOneWidget);
      await fillAndSend(tester);
      expect(api.placed.single.lines.map((l) => l.productId), ['ck']);
      expect(cart.items.single.product.id, 'lp', reason: 'cart untouched');
    });
  });

  group('order tracking', () {
    testWidgets('timeline shows each reached step with its time', (tester) async {
      usePhoneSize(tester);
      final order = pastOrder('o1', [clock], status: OrderStatus.delivering).copyWith(statusHistory: [
        StatusEvent(OrderStatus.pending, DateTime(2026, 10, 1, 12, 0)),
        StatusEvent(OrderStatus.confirmed, DateTime(2026, 10, 1, 13, 5)),
        StatusEvent(OrderStatus.delivering, DateTime(2026, 10, 2, 9, 30)),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: OrderTimeline(order: order)),
        ),
      ));
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(find.text('${weekDayName(DateTime(2026, 10, 2))} 02/10 09:30'), findsOneWidget);
    });
  });

  group('wallet and referrals', () {
    testWidgets('shows points, personal coupons, the invite code, and adds a friend code', (tester) async {
      usePhoneSize(tester);
      final repo = InMemoryStoreRepository();
      repo.wallets['u1'] = const Wallet(points: 240);
      repo.ledgers['u1'] = [const LedgerEntry(id: 'e1', type: 'earn', points: 240, note: 'نقاط الطلب بعد التسليم')];
      repo.coupons['VIP'] = const Coupon(code: 'VIP', value: 5000, type: CouponType.fixed, assignedTo: 'u1');
      repo.coupons['OTHER'] = const Coupon(code: 'OTHER', value: 5, assignedTo: 'u2');
      final auth = FakeAuthService(current: const Session(Role.customer, uid: 'u1', name: 'زينب'));
      final api = FakeStoreApi(repo, auth);
      await tester.pumpWidget(app(repo, auth: auth, api: api));
      await tester.pumpAndSettle();
      await tapTab(tester, 'الحساب');
      await tester.tap(find.text('محفظتي ونقاطي'));
      await tester.pumpAndSettle();

      expect(find.text('240'), findsOneWidget);
      expect(find.text('نقطة • قيمتها 12,000 د.ع'), findsOneWidget);
      expect(find.text('VIP • 5000 د.ع'), findsOneWidget);
      expect(find.textContaining('OTHER'), findsNothing);

      await tester.ensureVisible(find.text('اعرض كود الدعوة مالتي'));
      await tester.tap(find.text('اعرض كود الدعوة مالتي'));
      await tester.pumpAndSettle();
      expect(find.text('LCTEST22'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'عندك كود من صديق؟'), 'LCTEST22');
      await tester.tap(find.text('أضف'));
      await tester.pumpAndSettle();
      expect(find.text('ما تكدر تدعو نفسك'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'عندك كود من صديق؟'), 'lcfriend');
      await tester.tap(find.text('أضف'));
      await tester.pumpAndSettle();
      expect(api.appliedReferrals, ['lcfriend']);
    });
  });

  group('admin', () {
    Future<(InMemoryStoreRepository, FakeStoreApi)> openAdmin(WidgetTester tester, String tab) async {
      usePhoneSize(tester);
      final repo = InMemoryStoreRepository(products: [clock], categories: const [Category(id: 'decor', name: 'ديكور')]);
      final auth = FakeAuthService(current: const Session(Role.admin, uid: 'admin1'));
      final api = FakeStoreApi(repo, auth);
      await tester.pumpWidget(app(repo, auth: auth, api: api));
      await tester.pumpAndSettle();
      await tapTab(tester, 'الحساب');
      await tapAdminTab(tester, tab);
      await tester.pumpAndSettle();
      return (repo, api);
    }

    testWidgets('creates a coupon and switches it off', (tester) async {
      final (repo, _) = await openAdmin(tester, 'الكوبونات');
      await tester.tap(find.text('كوبون جديد'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'رمز الكوبون'), 'eid15');
      await tester.enterText(find.widgetWithText(TextFormField, 'النسبة %'), '150');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(find.text('النسبة لازم 100 أو أقل'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'النسبة %'), '15');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(repo.coupons['EID15']?.value, 15);
      expect(repo.coupons['EID15']?.perUserLimit, 1);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(repo.coupons['EID15']?.active, isFalse);
    });

    testWidgets('adds the wedding and newborn example offers', (tester) async {
      final (repo, _) = await openAdmin(tester, 'عروض ذكية');
      await tester.tap(find.text('أضف مثال الزواج والمولود'));
      await tester.pumpAndSettle();
      expect(repo.rules.values.map((r) => r.title), containsAll(['كمّل فرحتكم: عقود الزواج', 'هدايا استقبال المولود']));
      expect(find.text('كمّل فرحتكم: عقود الزواج'), findsOneWidget);
    });

    testWidgets('changes a delivery fee and adds a district, no new build needed', (tester) async {
      final (repo, _) = await openAdmin(tester, 'التوصيل');
      final centerFee = find.descendant(
        of: find.ancestor(of: find.text('الديوانية - المركز'), matching: find.byType(Row)).first,
        matching: find.widgetWithText(TextFormField, 'الأجور'),
      );
      await tester.enterText(centerFee, '2500');
      await scrollTo(tester, find.text('أضف محافظة أو قضاء'), within: DeliveryFeesTab);
      await tester.tap(find.text('أضف محافظة أو قضاء'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('أضف محافظة أو قضاء'), within: DeliveryFeesTab);
      final newName = find.widgetWithText(TextFormField, 'المحافظة / القضاء').last;
      await tester.enterText(newName, 'الديوانية - عفك');
      await tester.tap(find.text('حفظ أجور التوصيل'));
      await tester.pumpAndSettle();
      final zones = repo.deliveryZones;
      expect(zones.firstWhere((z) => z.id == 'diwaniyah-center').fee, 2500);
      expect(zones.last.name, 'الديوانية - عفك');
      expect(zones.last.id, matches(DeliveryZone.idPattern));
      expect(zones.length, defaultDeliveryZones.length + 1);
    });

    testWidgets('creates a free-delivery coupon without a value', (tester) async {
      final (repo, _) = await openAdmin(tester, 'الكوبونات');
      await tester.tap(find.text('كوبون جديد'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'رمز الكوبون'), 'freeship');
      await tester.tap(find.text('توصيل مجاني'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'النسبة %'), findsNothing);
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(repo.coupons['FREESHIP']?.type, CouponType.freeDelivery);
      expect(repo.coupons['FREESHIP']?.value, 0);
    });

    testWidgets('saves loyalty settings', (tester) async {
      final (repo, _) = await openAdmin(tester, 'الولاء');
      await tester.enterText(find.widgetWithText(TextFormField, 'قيمة النقطة بالدينار'), '25');
      await scrollTo(tester, find.text('حفظ الإعدادات'), within: LoyaltySettingsTab);
      await tester.tap(find.text('حفظ الإعدادات'));
      await tester.pumpAndSettle();
      expect(repo.loyalty.pointValue, 25);
    });

    testWidgets('status changes go through the server', (tester) async {
      final (repo, api) = await openAdmin(tester, 'الطلبات');
      await repo.putOrder(pastOrder('o1', [clock], status: OrderStatus.pending));
      await tester.pumpAndSettle();
      await tester.tap(find.text('زينب'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<OrderStatus>));
      await tester.tap(find.byType(DropdownButtonFormField<OrderStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تم التأكيد').last);
      await tester.pumpAndSettle();
      expect(api.statusChanges.single, ('o1', OrderStatus.confirmed));
    });
  });

  group('reports', () {
    test('sales, discounts and returning customers for a period', () {
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 11, 1);
      final orders = [
        // قبل الفترة: زينب طلبت من قبل.
        pastOrder('old', [clock], userId: 'u1', at: DateTime(2026, 9, 1)),
        StoreOrder(
          id: 'a', customer: const Customer(name: 'زينب', phone: '07801234567'), userId: 'u1',
          items: const [], total: 40000, subtotal: 50000, couponCode: 'EID10', couponAmount: 5000,
          pointsUsed: 100, pointsDiscount: 5000, pointsEarned: 40, status: OrderStatus.done,
          createdAt: DateTime(2026, 10, 3),
        ),
        // زبون ضيف طلب مرتين بنفس الرقم (بصيغتين).
        StoreOrder(
          id: 'b', customer: const Customer(name: 'علي', phone: '07701234567'),
          items: const [], total: 20000, couponCode: 'EID10', couponAmount: 2000, subtotal: 22000,
          createdAt: DateTime(2026, 10, 5),
        ),
        StoreOrder(
          id: 'c', customer: const Customer(name: 'علي', phone: '+964 770 123 4567'),
          items: const [], total: 30000, createdAt: DateTime(2026, 10, 9),
        ),
        // زبون جديد مرة وحدة، وطلب ملغي ما ينحسب.
        StoreOrder(
          id: 'd', customer: const Customer(name: 'سارة', phone: '07901112222'),
          items: const [], total: 10000, createdAt: DateTime(2026, 10, 10),
        ),
        StoreOrder(
          id: 'e', customer: const Customer(name: 'سارة', phone: '07901112222'),
          items: const [], total: 99000, status: OrderStatus.cancelled, createdAt: DateTime(2026, 10, 11),
        ),
      ];
      final r = SalesReport.from(orders, from, to);
      expect(r.orders, 4);
      expect(r.cancelled, 1);
      expect(r.gross, 50000 + 22000 + 30000 + 10000);
      expect(r.net, 100000);
      expect(r.couponDiscount, 7000);
      expect(r.pointsDiscount, 5000);
      expect(r.deliveredNet, 40000);
      expect(r.pointsRedeemed, 100);
      expect(r.pointsEarned, 40);
      expect(r.coupons.single.code, 'EID10');
      expect(r.coupons.single.orders, 2);
      expect(r.customers, 3);
      expect(r.returningCustomers, 2, reason: 'زينب (ordered before) and علي (twice)');
      expect(r.newCustomers, 1);
      expect(r.returningPercent, 67);
      expect(r.topReturning.first.name, 'علي');
    });
  });

  group('server client', () {
    test('sends the Firebase token, parses quotes, and refreshes an expired token once', () async {
      final auth = FakeAuthService(current: const Session(Role.customer, uid: 'u9'));
      final calls = <http.Request>[];
      var first = true;
      final client = MockClient((request) async {
        calls.add(request);
        if (request.url.path == '/api/orders' && first) {
          first = false;
          return http.Response('{"error":"invalid token"}', 401);
        }
        if (request.url.path == '/api/orders') {
          return http.Response(
            jsonEncode({
              'error': 'الأسعار تغيرت، شوف المجموع الجديد',
              'code': 'price_changed',
              'quote': {'subtotal': 52000, 'total': 52000, 'items': [], 'unavailable': []},
            }),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'items': [{'productId': 'ck', 'name': 'ساعة', 'price': 50000, 'quantity': 1}],
            'unavailable': [],
            'subtotal': 50000,
            'coupon': {'code': 'EID10', 'amount': 4000},
            'couponError': null,
            'points': null,
            'maxPoints': 120,
            'total': 46000,
            'pointsToEarn': 46,
            'balance': 300,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = HttpStoreApi(auth, client: client, baseUrl: 'https://lacasastores.com');
      final quote = await api.quote(const OrderRequest(lines: [OrderLine(productId: 'ck', quantity: 1)], coupon: 'EID10'));
      expect(calls.single.url.toString(), 'https://lacasastores.com/api/quote');
      expect(calls.single.headers['Authorization'], 'Bearer uid:u9');
      expect(jsonDecode(calls.single.body), {
        'items': [{'productId': 'ck', 'quantity': 1}],
        'pickupMethod': 'delivery',
        'coupon': 'EID10',
      }, reason: 'no prices are sent');
      expect((quote.total, quote.couponAmount, quote.maxPoints, quote.balance), (46000, 4000, 120, 300));

      await expectLater(
        api.placeOrder(const OrderRequest(requestId: 'abcdefghijklmnop', lines: [OrderLine(productId: 'ck', quantity: 1)])),
        throwsA(isA<StoreApiException>()
            .having((e) => e.code, 'code', 'price_changed')
            .having((e) => e.quote?.total, 'new total', 52000)),
      );
      expect(calls.where((c) => c.url.path == '/api/orders').length, 2, reason: 'one retry after 401');
    });
  });
}
