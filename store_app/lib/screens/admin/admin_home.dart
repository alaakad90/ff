import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/store_repository.dart';
import '../../widgets/product_image.dart';
import 'product_edit_screen.dart';

class AdminHome extends StatelessWidget {
  final AdminSession session;

  const AdminHome({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة التحكم'),
          actions: [
            IconButton(
              tooltip: 'تسجيل خروج',
              icon: const Icon(Icons.logout),
              onPressed: () => context.read<AuthService>().signOut(),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.receipt_long), text: 'الطلبات'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المنتجات'),
          ]),
        ),
        body: const TabBarView(children: [_OrdersTab(), _ProductsTab()]),
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  late final Stream<List<StoreOrder>> _orders = context.read<StoreRepository>().watchOrders();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreOrder>>(
      stream: _orders,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('ما كدرنا نحمل الطلبات'));
        }
        final orders = snapshot.data;
        if (orders == null) return const Center(child: CircularProgressIndicator());
        if (orders.isEmpty) return const Center(child: Text('ماكو طلبات بعد'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (context, i) => _OrderCard(order: orders[i]),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final StoreOrder order;

  const _OrderCard({required this.order});

  Color _statusColor(ColorScheme colors) => switch (order.status) {
        OrderStatus.pending => colors.primary,
        OrderStatus.confirmed || OrderStatus.delivering => Colors.orange.shade800,
        OrderStatus.done => Colors.green.shade700,
        OrderStatus.cancelled => colors.outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = order.customer;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(customer.name, style: theme.textTheme.titleMedium),
        subtitle: Text('${formatPrice(order.total)} • ${_formatDate(order.createdAt)}'),
        trailing: Chip(
          label: Text(order.status.label),
          labelStyle: TextStyle(color: _statusColor(theme.colorScheme)),
          side: BorderSide(color: _statusColor(theme.colorScheme)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.phone, size: 18),
            const SizedBox(width: 8),
            SelectableText(customer.phone, textDirection: TextDirection.ltr),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on, size: 18),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(customer.address)),
          ]),
          if (customer.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.note_alt_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(customer.notes)),
            ]),
          ],
          const Divider(),
          for (final item in order.items)
            Row(children: [
              Expanded(child: Text('${item.name} × ${item.quantity}')),
              Text(formatPrice(item.total)),
            ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<OrderStatus>(
            initialValue: order.status,
            decoration: const InputDecoration(labelText: 'حالة الطلب', isDense: true),
            items: [
              for (final s in OrderStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (status) async {
              if (status == null || status == order.status) return;
              try {
                await context.read<StoreRepository>().setOrderStatus(order.id, status);
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ما كدرنا نغير الحالة')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ProductsTab extends StatefulWidget {
  const _ProductsTab();

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  late final Stream<List<Product>> _products =
      context.read<StoreRepository>().watchProducts(includeHidden: true);
  bool _seeding = false;

  void _edit([Product? product]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductEditScreen(product: product)),
    );
  }

  Future<void> _addSamples() async {
    final repository = context.read<StoreRepository>();
    setState(() => _seeding = true);
    try {
      for (final p in sampleProducts) {
        await repository.saveProduct(p);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ما كدرنا نضيف المنتجات')));
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('منتج جديد'),
      ),
      body: StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('ما كدرنا نحمل المنتجات'));
          }
          final products = snapshot.data;
          if (products == null) return const Center(child: CircularProgressIndicator());
          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ماكو منتجات بعد. ضيف منتج جديد، أو جرب بالمنتجات التجريبية.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _seeding ? null : _addSamples,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('أضف المنتجات التجريبية'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final product = products[i];
              return Card(
                child: ListTile(
                  onTap: () => _edit(product),
                  leading: SizedBox.square(
                    dimension: 48,
                    child: ProductImage(
                      product: product,
                      iconSize: 24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  title: Text(product.name),
                  subtitle: Text(
                    '${formatPrice(product.price)} • ${categoryOf(product.categoryId).name}',
                  ),
                  trailing: Switch(
                    value: product.available,
                    onChanged: (v) => context
                        .read<StoreRepository>()
                        .saveProduct(product.copyWith(available: v)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
