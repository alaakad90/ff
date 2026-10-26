import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/stats.dart';
import '../../services/store_repository.dart';
import '../account/my_orders_screen.dart';

/// إحصائيات المتجر: الزوار، المسجلين، والطلبات وتفاصيلها.
class StatsTab extends StatefulWidget {
  const StatsTab({super.key});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<List<StoreOrder>> _orders = _repo.watchOrders();
  late Future<VisitorStats> _visitors = _repo.loadVisitorStats(DateTime.now());

  Future<void> _refresh() async {
    final next = _repo.loadVisitorStats(DateTime.now());
    setState(() => _visitors = next);
    await next.catchError((_) => const VisitorStats());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('الزوار والمسجلين', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<VisitorStats>(
            future: _visitors,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('ما كدرنا نجيب عدد الزوار. اسحب لتحت حتى تعيد المحاولة.');
              }
              final v = snapshot.data;
              String n(int Function(VisitorStats) f) => v == null ? '…' : '${f(v)}';
              return StatGrid(children: [
                StatCard(icon: Icons.today, label: 'زوار اليوم', value: n((v) => v.today)),
                StatCard(icon: Icons.date_range, label: 'زوار آخر 7 أيام', value: n((v) => v.week)),
                StatCard(icon: Icons.devices, label: 'كل الأجهزة', value: n((v) => v.devices)),
                StatCard(icon: Icons.person_outline, label: 'الحسابات المسجلة', value: n((v) => v.members)),
              ]);
            },
          ),
          const SizedBox(height: 24),
          StreamBuilder<List<StoreOrder>>(
            stream: _orders,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('ما كدرنا نجيب الطلبات');
              final orders = snapshot.data;
              if (orders == null) return const Center(child: CircularProgressIndicator());
              return _OrderStatsView(stats: OrderStats.from(orders, DateTime.now()));
            },
          ),
        ],
      ),
    );
  }
}

class _OrderStatsView extends StatelessWidget {
  final OrderStats stats;

  const _OrderStatsView({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الطلبات', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        StatGrid(children: [
          StatCard(icon: Icons.receipt_long, label: 'طلبات اليوم', value: '${stats.today}'),
          StatCard(icon: Icons.date_range, label: 'آخر 7 أيام', value: '${stats.week}'),
          StatCard(icon: Icons.calendar_month, label: 'هذا الشهر', value: '${stats.month}'),
          StatCard(icon: Icons.all_inbox, label: 'كل الطلبات', value: '${stats.total}'),
          StatCard(icon: Icons.payments_outlined, label: 'مبيعات مسلّمة', value: formatPrice(stats.delivered)),
          StatCard(icon: Icons.trending_up, label: 'كل المبيعات (بدون الملغية)', value: formatPrice(stats.expected)),
          StatCard(icon: Icons.shopping_basket_outlined, label: 'معدل الطلب', value: formatPrice(stats.average)),
          StatCard(icon: Icons.groups_outlined, label: 'زبائن طلبوا', value: '${stats.customers}'),
        ]),
        const SizedBox(height: 16),
        StatSection(
          title: 'الطلبات آخر 7 أيام',
          child: _DaysChart(counts: stats.lastSevenDays),
        ),
        StatSection(
          title: 'حسب الحالة',
          child: Column(
            children: [
              for (final s in OrderStatus.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    StatusChip(status: s),
                    const Spacer(),
                    Text('${stats.byStatus[s] ?? 0}', style: theme.textTheme.titleMedium),
                  ]),
                ),
            ],
          ),
        ),
        StatSection(
          title: 'أكثر المنتجات طلباً',
          child: stats.topProducts.isEmpty
              ? const Text('ماكو طلبات بعد')
              : Column(
                  children: [
                    for (final (i, p) in stats.topProducts.indexed)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                        title: Text(p.name),
                        subtitle: Text(formatPrice(p.total)),
                        trailing: Text('× ${p.quantity}', style: theme.textTheme.titleMedium),
                      ),
                  ],
                ),
        ),
        Text(
          'الأرقام من آخر 200 طلب. الزوار ينحسبون من النسخة اللي بيها الإحصائيات وطالع.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class StatGrid extends StatelessWidget {
  final List<Widget> children;

  const StatGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final c in children) SizedBox(width: width, child: c)],
          );
        },
      );
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const StatCard({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.secondary),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(label, maxLines: 2, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class StatSection extends StatelessWidget {
  final String title;
  final Widget child;

  const StatSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
}

/// أعمدة بسيطة لعدد الطلبات بكل يوم.
class _DaysChart extends StatelessWidget {
  final List<int> counts;

  const _DaysChart({required this.counts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = counts.fold(0, (a, b) => a > b ? a : b);
    final today = DateTime.now();
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, count) in counts.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('$count', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Container(
                      height: max == 0 ? 2 : 2 + 90 * count / max,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      weekDayName(today.subtract(Duration(days: 6 - i))),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
