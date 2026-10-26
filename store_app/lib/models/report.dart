import 'order.dart';

/// استعمال كوبون خلال الفترة.
class CouponUsage {
  final String code;
  final int orders;
  final int discount;

  const CouponUsage(this.code, this.orders, this.discount);
}

/// زبون رجع يطلب.
class ReturningCustomer {
  final String name;
  final String phone;
  final int orders; // بالفترة
  final int spent; // بالفترة

  const ReturningCustomer(this.name, this.phone, this.orders, this.spent);
}

/// الزبون: بحسابه إذا مسجل، وإلا برقم الهاتف (آخر 10 أرقام).
String customerKey(StoreOrder order) {
  if (order.userId.isNotEmpty) return 'u:${order.userId}';
  final digits = order.customer.phone.replaceAll(RegExp(r'\D'), '');
  return 'p:${digits.length > 10 ? digits.substring(digits.length - 10) : digits}';
}

/// تقرير المبيعات والخصومات والزبائن العائدين لفترة [from, to).
/// [orders]: طلبات الفترة وقبلها (حتى نعرف منو طلب قبل). الملغية ما تنحسب بالمبيعات.
class SalesReport {
  final int orders;
  final int cancelled;
  final int gross; // قبل الخصم
  final int couponDiscount;
  final int pointsDiscount;
  final int net; // بعد الخصم
  final int deliveredNet;
  final int pointsRedeemed;
  final int pointsEarned;
  final int discountedOrders;
  final List<CouponUsage> coupons;
  final int customers;
  final int newCustomers;
  final int returningCustomers;
  final List<ReturningCustomer> topReturning;

  const SalesReport({
    required this.orders,
    required this.cancelled,
    required this.gross,
    required this.couponDiscount,
    required this.pointsDiscount,
    required this.net,
    required this.deliveredNet,
    required this.pointsRedeemed,
    required this.pointsEarned,
    required this.discountedOrders,
    required this.coupons,
    required this.customers,
    required this.newCustomers,
    required this.returningCustomers,
    required this.topReturning,
  });

  int get discount => couponDiscount + pointsDiscount;
  int get averageOrder => orders == 0 ? 0 : net ~/ orders;

  /// نسبة الزبائن العائدين من كل زبائن الفترة (0..100).
  int get returningPercent => customers == 0 ? 0 : (returningCustomers * 100 / customers).round();

  factory SalesReport.from(List<StoreOrder> all, DateTime from, DateTime to) {
    bool inPeriod(StoreOrder o) => o.createdAt != null && !o.createdAt!.isBefore(from) && o.createdAt!.isBefore(to);
    final valid = all.where((o) => o.status != OrderStatus.cancelled).toList();
    final period = valid.where(inPeriod).toList();
    final before = {
      for (final o in valid)
        if (o.createdAt != null && o.createdAt!.isBefore(from)) customerKey(o),
    };

    var gross = 0, coupon = 0, points = 0, net = 0, delivered = 0, redeemed = 0, earned = 0, discounted = 0;
    final couponMap = <String, (int, int)>{};
    final perCustomer = <String, List<StoreOrder>>{};
    for (final o in period) {
      gross += o.subtotal;
      coupon += o.couponAmount;
      points += o.pointsDiscount;
      net += o.total;
      redeemed += o.pointsUsed;
      earned += o.pointsEarned;
      if (o.discount > 0) discounted++;
      if (o.status == OrderStatus.done) delivered += o.total;
      if (o.couponCode.isNotEmpty) {
        final (count, amount) = couponMap[o.couponCode] ?? (0, 0);
        couponMap[o.couponCode] = (count + 1, amount + o.couponAmount);
      }
      perCustomer.putIfAbsent(customerKey(o), () => []).add(o);
    }

    final returningKeys = {
      for (final MapEntry(:key, :value) in perCustomer.entries)
        if (value.length > 1 || before.contains(key)) key,
    };
    final top = [
      for (final key in returningKeys)
        ReturningCustomer(
          perCustomer[key]!.first.customer.name,
          perCustomer[key]!.first.customer.phone,
          perCustomer[key]!.length,
          perCustomer[key]!.fold(0, (sum, o) => sum + o.total),
        ),
    ]..sort((a, b) => b.spent.compareTo(a.spent));

    return SalesReport(
      orders: period.length,
      cancelled: all.where((o) => o.status == OrderStatus.cancelled && inPeriod(o)).length,
      gross: gross,
      couponDiscount: coupon,
      pointsDiscount: points,
      net: net,
      deliveredNet: delivered,
      pointsRedeemed: redeemed,
      pointsEarned: earned,
      discountedOrders: discounted,
      coupons: [for (final e in couponMap.entries) CouponUsage(e.key, e.value.$1, e.value.$2)]
        ..sort((a, b) => b.orders.compareTo(a.orders)),
      customers: perCustomer.length,
      newCustomers: perCustomer.length - returningKeys.length,
      returningCustomers: returningKeys.length,
      topReturning: top.take(10).toList(),
    );
  }
}
