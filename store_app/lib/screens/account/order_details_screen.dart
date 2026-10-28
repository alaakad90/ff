import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/reorder.dart';
import '../../services/store_repository.dart';
import '../../state/cart.dart';
import '../../widgets/product_grid.dart';
import '../checkout_screen.dart';
import '../shell.dart';
import 'my_orders_screen.dart';

/// تفاصيل الطلب ومتابعته: مراحل الطلب وأوقاتها، والمبالغ، وإعادة الطلب.
class OrderDetailsScreen extends StatelessWidget {
  final StoreOrder order;

  const OrderDetailsScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('متابعة الطلب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: Text(formatOrderDate(order.createdAt), style: theme.textTheme.bodySmall)),
            StatusChip(status: order.status),
          ]),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: OrderTimeline(order: order))),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                            child: Text('${item.name} × ${item.quantity}'
                                '${item.options.isEmpty ? '' : '\n🔹 ${optionsLabel(item.options)}'}'
                                '${item.note.isEmpty ? '' : '\n📝 ${item.note}'}')),
                        Text(formatPrice(item.total)),
                      ]),
                    ),
                  const Divider(),
                  OrderAmounts(order: order),
                  if (order.deliveryDay.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('${order.pickupMethod.label} • ${order.deliveryDay}'),
                  ],
                  if (order.pointsEarned > 0) ...[
                    const SizedBox(height: 8),
                    Text('⭐ كسبت ${order.pointsEarned} نقطة من هذا الطلب'),
                  ],
                ],
              ),
            ),
          ),
          if (order.items.any((i) => i.productId.isNotEmpty)) ...[
            const SizedBox(height: 16),
            ReorderButton(order: order),
          ],
        ],
      ),
    );
  }
}

/// المبالغ: قبل الخصم، الكوبون، النقاط، والمجموع.
class OrderAmounts extends StatelessWidget {
  final StoreOrder order;

  const OrderAmounts({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
        );
    final hasDelivery = order.deliveryZone.isNotEmpty || order.deliveryFee > 0;
    return Column(children: [
      if (order.discount > 0 || hasDelivery) ...[
        row('المنتجات', formatPrice(order.subtotal)),
        if (order.couponAmount > 0 && !order.freeDelivery)
          row(order.couponCode.isEmpty ? 'خصم' : 'كوبون ${order.couponCode}', '- ${formatPrice(order.couponAmount)}'),
        if (order.pointsDiscount > 0) row('${order.pointsUsed} نقطة', '- ${formatPrice(order.pointsDiscount)}'),
        if (hasDelivery)
          row(
            order.deliveryZone.isEmpty ? 'التوصيل' : 'التوصيل (${order.deliveryZone})',
            order.freeDelivery ? 'مجاني (كوبون ${order.couponCode})' : formatPrice(order.deliveryFee),
          ),
      ],
      row(
        'المجموع',
        formatPrice(order.total),
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.secondary),
      ),
    ]);
  }
}

/// مراحل الطلب: جديد ← تم التأكيد ← بالطريق ← تم التسليم (أو ملغي).
class OrderTimeline extends StatelessWidget {
  final StoreOrder order;

  const OrderTimeline({super.key, required this.order});

  String _time(DateTime? at) {
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${weekDayName(at)} ${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = order.status == OrderStatus.cancelled;
    final reached = cancelled ? -1 : orderSteps.indexOf(order.status);
    final steps = [
      for (final (i, status) in orderSteps.indexed)
        (
          status == OrderStatus.delivering && order.pickupMethod == PickupMethod.pickup ? 'جاهز للاستلام' : status.label,
          i <= reached,
          order.reachedAt(status),
        ),
      if (cancelled) ('ملغي', true, order.reachedAt(OrderStatus.cancelled)),
    ];
    return Column(
      children: [
        for (final (i, (label, done, at)) in steps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: [
                Icon(
                  cancelled && i == steps.length - 1
                      ? Icons.cancel
                      : done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                  color: cancelled && i == steps.length - 1
                      ? theme.colorScheme.error
                      : done
                          ? Colors.green.shade700
                          : theme.colorScheme.outline,
                ),
                if (i < steps.length - 1)
                  Container(width: 2, height: 22, color: done ? Colors.green.shade700 : theme.colorScheme.outlineVariant),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(label,
                          style: TextStyle(fontWeight: done ? FontWeight.w600 : FontWeight.normal)),
                    ),
                    if (done) Text(_time(at), style: theme.textTheme.bodySmall),
                  ]),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// زر "اطلب مرة ثانية": يجيب الأسعار الحالية ويبين شنو تغير قبل ما يضيف.
class ReorderButton extends StatelessWidget {
  final StoreOrder order;
  final bool compact;

  const ReorderButton({super.key, required this.order, this.compact = false});

  @override
  Widget build(BuildContext context) {
    void onPressed() => showReorderSheet(context, order);
    return compact
        ? TextButton.icon(onPressed: onPressed, icon: const Icon(Icons.replay), label: const Text('اطلب مرة ثانية'))
        : OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.replay), label: const Text('اطلب مرة ثانية'));
  }
}

Future<void> showReorderSheet(BuildContext context, StoreOrder order) async {
  final repo = context.read<StoreRepository>();
  final messenger = ScaffoldMessenger.of(context);
  List<ReorderLine> lines;
  try {
    lines = planReorder(order, await repo.getProducts(order.items.map((i) => i.productId)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('ما كدرنا نجيب الأسعار الحالية. تأكد من الإنترنت.')));
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ReorderSheet(lines: lines, outerContext: context),
  );
}

class _ReorderSheet extends StatelessWidget {
  final List<ReorderLine> lines;
  final BuildContext outerContext;

  const _ReorderSheet({required this.lines, required this.outerContext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = reorderCartItems(lines);
    final total = lines.fold(0, (sum, l) => sum + l.currentTotal);
    final changed = lines.where((l) => l.change != ReorderChange.same).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('اطلب مرة ثانية', style: theme.textTheme.titleLarge),
            if (changed > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('حدّثنا الأسعار والتوفر حسب اليوم', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            for (final line in lines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(switch (line.change) {
                  ReorderChange.unavailable => Icons.block,
                  ReorderChange.cheaper => Icons.trending_down,
                  ReorderChange.pricier => Icons.trending_up,
                  ReorderChange.same => Icons.check,
                }),
                title: Text(
                  '${line.item.name} × ${line.item.quantity}',
                  style: line.available ? null : const TextStyle(decoration: TextDecoration.lineThrough),
                ),
                subtitle: Text(switch (line.change) {
                  ReorderChange.unavailable => 'ما متوفر هسه',
                  ReorderChange.same => formatPrice(line.currentTotal),
                  _ => 'كان ${formatPrice(line.item.total)} • هسه ${formatPrice(line.currentTotal)}',
                }),
              ),
            const Divider(),
            Row(children: [
              Expanded(child: Text('المجموع التقريبي', style: theme.textTheme.titleMedium)),
              Text(formatPrice(total), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const EmptyMessage(icon: Icons.inventory_2_outlined, text: 'كل منتجات هذا الطلب ما متوفرة هسه')
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('أضف للسلة'),
                    onPressed: () {
                      final cart = outerContext.read<Cart>();
                      for (final item in items) {
                        cart.add(item.product, item.quantity, item.note, item.imageUrl, item.voiceUrl, item.options);
                      }
                      // نبدل للسلة قبل ما نسكر الصفحات (بعدها هالصفحة ما تبقى).
                      AppShell.goTo(outerContext, ShellTab.cart);
                      Navigator.of(context).pop();
                      Navigator.of(outerContext).popUntil((r) => r.isFirst);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.bolt),
                    label: const Text('اطلب الآن'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(outerContext).push(
                        MaterialPageRoute(builder: (_) => CheckoutScreen(items: items)),
                      );
                    },
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
