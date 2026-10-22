import 'order.dart';

/// عدد الزوار والمسجلين، من Firestore.
class VisitorStats {
  final int devices; // كل الأجهزة اللي فتحت التطبيق
  final int today; // الأجهزة اللي فتحته اليوم
  final int week; // آخر 7 أيام
  final int members; // الحسابات المسجلة

  const VisitorStats({this.devices = 0, this.today = 0, this.week = 0, this.members = 0});
}

class ProductSales {
  final String name;
  final int quantity;
  final int total;

  const ProductSales(this.name, this.quantity, this.total);
}

/// أرقام الطلبات، محسوبة من قائمة الطلبات.
class OrderStats {
  final int total;
  final int today;
  final int week;
  final int month;
  final Map<OrderStatus, int> byStatus;
  final int delivered; // مبيعات الطلبات المسلّمة
  final int expected; // مبيعات كل الطلبات غير الملغية
  final int customers; // زبائن مختلفين (حسب رقم الهاتف)
  final List<ProductSales> topProducts;
  final List<int> lastSevenDays; // عدد الطلبات لكل يوم، من قبل 6 أيام لليوم

  const OrderStats({
    required this.total,
    required this.today,
    required this.week,
    required this.month,
    required this.byStatus,
    required this.delivered,
    required this.expected,
    required this.customers,
    required this.topProducts,
    required this.lastSevenDays,
  });

  int get average {
    final count = total - (byStatus[OrderStatus.cancelled] ?? 0);
    return count == 0 ? 0 : expected ~/ count;
  }

  factory OrderStats.from(List<StoreOrder> orders, DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(const Duration(days: 6));
    final startOfMonth = DateTime(now.year, now.month);
    final byStatus = {for (final s in OrderStatus.values) s: 0};
    final sales = <String, ProductSales>{};
    final phones = <String>{};
    final days = List.filled(7, 0);
    var today = 0, week = 0, month = 0, delivered = 0, expected = 0;

    for (final order in orders) {
      byStatus[order.status] = byStatus[order.status]! + 1;
      final created = order.createdAt?.toLocal();
      if (created != null) {
        if (!created.isBefore(startOfToday)) today++;
        if (!created.isBefore(startOfWeek)) {
          week++;
          final day = DateTime(created.year, created.month, created.day);
          final index = 6 - startOfToday.difference(day).inDays;
          if (index >= 0 && index < 7) days[index]++;
        }
        if (!created.isBefore(startOfMonth)) month++;
      }
      if (order.status == OrderStatus.cancelled) continue;
      expected += order.total;
      if (order.status == OrderStatus.done) delivered += order.total;
      final phone = order.customer.phone.replaceAll(RegExp(r'\D'), '');
      if (phone.isNotEmpty) phones.add(phone);
      for (final item in order.items) {
        final key = item.productId.isEmpty ? item.name : item.productId;
        final old = sales[key];
        sales[key] = ProductSales(
          item.name,
          (old?.quantity ?? 0) + item.quantity,
          (old?.total ?? 0) + item.total,
        );
      }
    }

    final top = sales.values.toList()..sort((a, b) => b.quantity.compareTo(a.quantity));
    return OrderStats(
      total: orders.length,
      today: today,
      week: week,
      month: month,
      byStatus: byStatus,
      delivered: delivered,
      expected: expected,
      customers: phones.length,
      topProducts: top.take(5).toList(),
      lastSevenDays: days,
    );
  }
}
