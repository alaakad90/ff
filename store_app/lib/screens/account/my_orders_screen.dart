import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/store_repository.dart';
import '../../widgets/product_grid.dart';
import 'order_details_screen.dart';

String formatOrderDate(DateTime? date) {
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${weekDayName(date)} ${date.year}/${two(date.month)}/${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

Color orderStatusColor(OrderStatus status, ColorScheme colors) => switch (status) {
      OrderStatus.pending => colors.secondary,
      OrderStatus.confirmed || OrderStatus.delivering => Colors.orange.shade800,
      OrderStatus.done => Colors.green.shade700,
      OrderStatus.cancelled => colors.outline,
    };

class StatusChip extends StatelessWidget {
  final OrderStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status, Theme.of(context).colorScheme);
    return Chip(
      label: Text(status.label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      side: BorderSide(color: color),
      backgroundColor: Theme.of(context).cardTheme.color,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// سجل طلبات الزبون.
class MyOrdersScreen extends StatefulWidget {
  final String userId;

  const MyOrdersScreen({super.key, required this.userId});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  late final Stream<List<StoreOrder>> _orders =
      context.read<StoreRepository>().watchUserOrders(widget.userId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: StreamBuilder<List<StoreOrder>>(
        stream: _orders,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyMessage(icon: Icons.wifi_off, text: 'ما كدرنا نحمل طلباتك');
          }
          final orders = snapshot.data;
          if (orders == null) return const Center(child: CircularProgressIndicator());
          if (orders.isEmpty) {
            return const EmptyMessage(icon: Icons.receipt_long_outlined, text: 'ما عندك طلبات بعد');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => OrderSummaryCard(order: orders[i]),
          );
        },
      ),
    );
  }
}

/// بطاقة طلب بالسجل: تنضغط وتفتح المتابعة، وبيها "اطلب مرة ثانية".
class OrderSummaryCard extends StatelessWidget {
  final StoreOrder order;
  final bool canReorder;

  const OrderSummaryCard({super.key, required this.order, this.canReorder = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatOrderDate(order.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  StatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 8),
              for (final item in order.items)
                Row(children: [
                  Expanded(child: Text('${item.name} × ${item.quantity}${item.note.isEmpty ? '' : '\n📝 ${item.note}'}${item.hasAttachments ? '\n📎 مرفقات' : ''}')),
                  Text(formatPrice(item.total)),
                ]),
              const Divider(),
              if (order.deliveryDay.isNotEmpty) Text('${order.pickupMethod.label} • ${order.deliveryDay}'),
              OrderAmounts(order: order),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.timeline, size: 18),
                    const SizedBox(width: 4),
                    Text('تابع الطلب', style: theme.textTheme.bodySmall),
                  ]),
                  if (canReorder && order.items.any((i) => i.productId.isNotEmpty))
                    ReorderButton(order: order, compact: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
