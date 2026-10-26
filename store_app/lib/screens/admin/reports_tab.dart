import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/report.dart';
import '../../services/store_repository.dart';
import 'stats_tab.dart';

enum ReportPeriod {
  week('7 أيام', 7),
  month('30 يوم', 30),
  quarter('90 يوم', 90),
  thisMonth('هذا الشهر', 0);

  final String label;
  final int days;

  const ReportPeriod(this.label, this.days);

  DateTime start(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return days == 0 ? DateTime(now.year, now.month) : today.subtract(Duration(days: days - 1));
  }
}

/// تقارير المبيعات والخصومات والزبائن العائدين.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  late final _repo = context.read<StoreRepository>();
  var _period = ReportPeriod.month;
  late Stream<List<StoreOrder>> _orders = _load();

  // نجيب سنة قبل الفترة حتى نعرف منو زبون قديم رجع يطلب.
  Stream<List<StoreOrder>> _load() =>
      _repo.watchOrdersSince(_period.start(DateTime.now()).subtract(const Duration(days: 365)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 8, children: [
          for (final p in ReportPeriod.values)
            ChoiceChip(
              label: Text(p.label),
              selected: _period == p,
              onSelected: (_) => setState(() {
                _period = p;
                _orders = _load();
              }),
            ),
        ]),
        const SizedBox(height: 12),
        StreamBuilder<List<StoreOrder>>(
          stream: _orders,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('ما كدرنا نجيب الطلبات');
            final orders = snapshot.data;
            if (orders == null) return const Center(child: CircularProgressIndicator());
            final now = DateTime.now();
            final r = SalesReport.from(orders, _period.start(now), now.add(const Duration(minutes: 1)));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('المبيعات', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              StatGrid(children: [
                StatCard(icon: Icons.receipt_long, label: 'طلبات (بدون الملغية)', value: '${r.orders}'),
                StatCard(icon: Icons.payments_outlined, label: 'صافي المبيعات', value: formatPrice(r.net)),
                StatCard(icon: Icons.check_circle_outline, label: 'صافي المسلّمة', value: formatPrice(r.deliveredNet)),
                StatCard(icon: Icons.shopping_basket_outlined, label: 'معدل الطلب', value: formatPrice(r.averageOrder)),
                StatCard(icon: Icons.cancel_outlined, label: 'ملغية', value: '${r.cancelled}'),
                StatCard(icon: Icons.summarize_outlined, label: 'قبل الخصم', value: formatPrice(r.gross)),
              ]),
              const SizedBox(height: 16),
              Text('الخصومات', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              StatGrid(children: [
                StatCard(icon: Icons.discount_outlined, label: 'كل الخصومات', value: formatPrice(r.discount)),
                StatCard(icon: Icons.local_offer_outlined, label: 'خصم الكوبونات', value: formatPrice(r.couponDiscount)),
                StatCard(icon: Icons.stars_outlined, label: 'خصم النقاط', value: formatPrice(r.pointsDiscount)),
                StatCard(icon: Icons.percent, label: 'طلبات بيها خصم', value: '${r.discountedOrders}'),
                StatCard(icon: Icons.redeem, label: 'نقاط انستعملت', value: '${r.pointsRedeemed}'),
                StatCard(icon: Icons.star_outline, label: 'نقاط انكسبت', value: '${r.pointsEarned}'),
              ]),
              const SizedBox(height: 16),
              StatSection(
                title: 'الكوبونات',
                child: r.coupons.isEmpty
                    ? const Text('ماكو كوبونات انستعملت بهالفترة')
                    : Column(children: [
                        for (final c in r.coupons)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.local_offer_outlined),
                            title: Text(c.code, textDirection: TextDirection.ltr),
                            subtitle: Text('خصم ${formatPrice(c.discount)}'),
                            trailing: Text('× ${c.orders}', style: theme.textTheme.titleMedium),
                          ),
                      ]),
              ),
              Text('الزبائن', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              StatGrid(children: [
                StatCard(icon: Icons.groups_outlined, label: 'زبائن طلبوا', value: '${r.customers}'),
                StatCard(icon: Icons.person_add_alt, label: 'زبائن جدد', value: '${r.newCustomers}'),
                StatCard(icon: Icons.replay, label: 'زبائن عائدين', value: '${r.returningCustomers}'),
                StatCard(icon: Icons.pie_chart_outline, label: 'نسبة العائدين', value: '${r.returningPercent}%'),
              ]),
              const SizedBox(height: 16),
              StatSection(
                title: 'أكثر الزبائن العائدين',
                child: r.topReturning.isEmpty
                    ? const Text('ماكو زبائن عائدين بهالفترة بعد')
                    : Column(children: [
                        for (final c in r.topReturning)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_outline),
                            title: Text(c.name),
                            subtitle: Text(c.phone, textDirection: TextDirection.ltr),
                            trailing: Text('${c.orders} طلب • ${formatPrice(c.spent)}'),
                          ),
                      ]),
              ),
              Text(
                'العائد: طلب أكثر من مرة بالفترة، أو طلب قبلها خلال سنة. الزبون ينعرف بحسابه أو برقم هاتفه.',
                style: theme.textTheme.bodySmall,
              ),
            ]);
          },
        ),
      ],
    );
  }
}
