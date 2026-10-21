import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lacasa_store/data/catalog.dart';
import 'package:lacasa_store/main.dart';
import 'package:lacasa_store/models/order.dart';
import 'package:lacasa_store/models/product.dart';
import 'package:lacasa_store/services/auth_service.dart';
import 'package:lacasa_store/services/order_service.dart';
import 'package:lacasa_store/services/store_repository.dart';
import 'package:lacasa_store/state/cart.dart';

class FakeAuthService implements AuthService {
  final _session = StreamController<AdminSession>.broadcast();
  AdminSession current;

  FakeAuthService([this.current = AdminSession.signedOut]);

  @override
  Stream<AdminSession> watchSession() async* {
    yield current;
    yield* _session.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (password != 'secret') throw AuthException('الإيميل أو الباسورد غلط');
    current = AdminSession(AdminStatus.admin, uid: 'u1', email: email);
    _session.add(current);
  }

  @override
  Future<void> signOut() async {
    current = AdminSession.signedOut;
    _session.add(current);
  }
}

class RecordingNotifier extends TelegramNotifier {
  final sent = <StoreOrder>[];

  @override
  Future<void> notify(StoreOrder order) async => sent.add(order);
}

Product sample(int i) => sampleProducts[i];

void main() {
  test('formatPrice adds thousands separators', () {
    expect(formatPrice(500), '500 د.ع');
    expect(formatPrice(25000), '25,000 د.ع');
    expect(formatPrice(1250000), '1,250,000 د.ع');
  });

  test('cart totals and quantities', () {
    final a = sample(0).copyWith(id: 'a');
    final b = sample(1).copyWith(id: 'b');
    final cart = Cart();
    cart.add(a);
    cart.add(a, 2);
    cart.add(b);
    expect(cart.count, 4);
    expect(cart.total, a.price * 3 + b.price);

    cart.decrement(b);
    expect(cart.quantityOf(b), 0);
    expect(cart.items.length, 1);
  });

  test('product map round trip', () {
    const product = Product(
      id: 'x',
      name: 'عطر',
      price: 1000,
      categoryId: 'perfume',
      imageUrl: 'https://example.com/a.jpg',
      available: false,
    );
    final copy = Product.fromMap('x', product.toMap());
    expect(copy.toMap(), product.toMap());
    expect(copy.available, isFalse);
  });

  test('telegram message lists customer and items', () {
    final cart = Cart()..add(sample(2).copyWith(id: 'c'), 2);
    final order = StoreOrder.fromCart(
      const Customer(name: 'علي', phone: '07701234567', address: 'بغداد'),
      cart,
    ).copyWith(id: 'o42');
    final message = TelegramNotifier.buildMessage(order);
    expect(message, contains('علي'));
    expect(message, contains('o42'));
    expect(message, contains('${sample(2).name} × 2'));
    expect(message, contains(formatPrice(cart.total)));
  });

  test('hidden products are only listed for the admin', () async {
    final repo = InMemoryStoreRepository(products: [
      sample(0),
      sample(1).copyWith(available: false),
    ]);
    expect((await repo.watchProducts().first).length, 1);
    expect((await repo.watchProducts(includeHidden: true).first).length, 2);
  });

  Widget app(StoreRepository repo, {AuthService? auth, TelegramNotifier? notifier}) => StoreApp(
        repository: repo,
        auth: auth ?? FakeAuthService(),
        notifier: notifier ?? RecordingNotifier(),
      );

  testWidgets('customer orders a product end to end', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = InMemoryStoreRepository(products: [sample(0), sample(2)]);
    final notifier = RecordingNotifier();
    await tester.pumpWidget(app(repo, notifier: notifier));
    await tester.pumpAndSettle();
    expect(find.text(sample(0).name), findsOneWidget);

    await tester.tap(find.byTooltip('أضف للسلة').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('السلة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إكمال الطلب'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'علي');
    await tester.enterText(fields.at(1), '07701234567');
    await tester.enterText(fields.at(2), 'بغداد، الكرادة');
    await tester.tap(find.text('أرسل الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('وصلنا طلبك'), findsOneWidget);
    expect(repo.orders, hasLength(1));
    final order = repo.orders.single;
    expect(order.customer.name, 'علي');
    expect(order.items.single.quantity, 1);
    expect(order.status, OrderStatus.pending);
    expect(notifier.sent.single.id, order.id);
  });

  testWidgets('admin signs in, adds sample products and updates an order', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = InMemoryStoreRepository();
    await repo.placeOrder(StoreOrder(
      customer: const Customer(name: 'زينب', phone: '07801234567', address: 'البصرة'),
      items: const [OrderItem(productId: 'p', name: 'كيكة', price: 1000, quantity: 1)],
      total: 1000,
    ));
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.text('ماكو منتجات هنا'), findsOneWidget);

    await tester.tap(find.byTooltip('لوحة التحكم'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(find.text('الإيميل أو الباسورد غلط'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(find.text('زينب'), findsOneWidget);

    await tester.tap(find.text('زينب'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<OrderStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(OrderStatus.delivering.label).last);
    await tester.pumpAndSettle();
    expect(repo.orders.single.status, OrderStatus.delivering);

    await tester.tap(find.text('المنتجات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أضف المنتجات التجريبية'));
    await tester.pumpAndSettle();
    final products = await repo.watchProducts().first;
    expect(products, hasLength(sampleProducts.length));
  });
}
