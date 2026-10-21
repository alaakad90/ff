import 'package:flutter_test/flutter_test.dart';
import 'package:lacasa_store/data/catalog.dart';
import 'package:lacasa_store/main.dart';
import 'package:lacasa_store/models/product.dart';
import 'package:lacasa_store/services/order_service.dart';
import 'package:lacasa_store/state/cart.dart';

void main() {
  test('formatPrice adds thousands separators', () {
    expect(formatPrice(500), '500 د.ع');
    expect(formatPrice(25000), '25,000 د.ع');
    expect(formatPrice(1250000), '1,250,000 د.ع');
  });

  test('cart totals and quantities', () {
    final cart = Cart();
    cart.add(products[0]);
    cart.add(products[0], 2);
    cart.add(products[1]);
    expect(cart.count, 4);
    expect(cart.total, products[0].price * 3 + products[1].price);

    cart.decrement(products[1]);
    expect(cart.quantityOf(products[1]), 0);
    expect(cart.items.length, 1);
  });

  test('order message lists customer and items', () {
    final cart = Cart()..add(products[2], 2);
    final message = OrderService.buildMessage(
      const Customer(name: 'علي', phone: '07701234567', address: 'بغداد'),
      cart.items,
      cart.total,
    );
    expect(message, contains('علي'));
    expect(message, contains('${products[2].name} × 2'));
    expect(message, contains(formatPrice(cart.total)));
  });

  testWidgets('add product to cart from home screen', (tester) async {
    await tester.pumpWidget(const StoreApp());
    expect(find.text('متجر لاكاسا'), findsOneWidget);

    await tester.tap(find.byTooltip('أضف للسلة').first);
    await tester.pump();
    expect(find.text('1'), findsOneWidget); // عداد السلة
  });
}
