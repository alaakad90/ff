import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/category_icons.dart';
import '../../models/content.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/contact.dart';
import '../../services/store_repository.dart';
import '../../widgets/product_grid.dart';
import '../../widgets/product_image.dart';
import '../account/my_orders_screen.dart';
import 'content_editors.dart';
import 'product_edit_screen.dart';

/// لوحة التحكم. تنفتح بتبويب الحساب لما صاحب المتجر يسجل دخول.
class AdminHome extends StatelessWidget {
  final Session session;

  const AdminHome({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
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
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'الطلبات'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المنتجات'),
              Tab(icon: Icon(Icons.grid_view_outlined), text: 'الأقسام'),
              Tab(icon: Icon(Icons.view_carousel_outlined), text: 'العروض'),
              Tab(icon: Icon(Icons.play_circle_outline), text: 'الريلز'),
              Tab(icon: Icon(Icons.storefront_outlined), text: 'المتجر'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _OrdersTab(),
          _ProductsTab(),
          _CategoriesTab(),
          _BannersTab(),
          _ReelsTab(),
          StoreInfoEditor(),
        ]),
      ),
    );
  }
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// قائمة مع زر إضافة، وزر "أضف بيانات تجريبية" إذا القائمة فارغة.
class _ListTab<T> extends StatefulWidget {
  final Stream<List<T>> Function(StoreRepository repo) watch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final VoidCallback onAdd;
  final String addLabel;
  final String emptyText;
  final Future<void> Function(StoreRepository repo)? seed;
  final String seedLabel;

  const _ListTab({
    super.key,
    required this.watch,
    required this.itemBuilder,
    required this.onAdd,
    required this.addLabel,
    required this.emptyText,
    this.seed,
    this.seedLabel = '',
  });

  @override
  State<_ListTab<T>> createState() => _ListTabState<T>();
}

class _ListTabState<T> extends State<_ListTab<T>> {
  late final Stream<List<T>> _items = widget.watch(context.read<StoreRepository>());
  bool _seeding = false;

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      await widget.seed!(context.read<StoreRepository>());
    } catch (_) {
      if (mounted) _showError(context, 'ما كدرنا نضيفها');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: widget.onAdd,
        icon: const Icon(Icons.add),
        label: Text(widget.addLabel),
      ),
      body: StreamBuilder<List<T>>(
        stream: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyMessage(icon: Icons.error_outline, text: 'ما كدرنا نحمل البيانات');
          }
          final items = snapshot.data;
          if (items == null) return const Center(child: CircularProgressIndicator());
          if (items.isEmpty) {
            return EmptyMessage(
              icon: Icons.inbox_outlined,
              text: widget.emptyText,
              action: widget.seed == null
                  ? null
                  : OutlinedButton.icon(
                      onPressed: _seeding ? null : _seed,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(widget.seedLabel),
                    ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => widget.itemBuilder(context, items[i]),
          );
        },
      ),
    );
  }
}

// ───────────── الطلبات ─────────────

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
          return const EmptyMessage(icon: Icons.error_outline, text: 'ما كدرنا نحمل الطلبات');
        }
        final orders = snapshot.data;
        if (orders == null) return const Center(child: CircularProgressIndicator());
        if (orders.isEmpty) {
          return const EmptyMessage(icon: Icons.receipt_long_outlined, text: 'ماكو طلبات بعد');
        }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = order.customer;

    Widget info(IconData icon, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: child),
          ]),
        );

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(customer.name, style: theme.textTheme.titleMedium),
        subtitle: Text('${formatPrice(order.total)} • ${formatOrderDate(order.createdAt)}'),
        trailing: StatusChip(status: order.status),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.chat, size: 20),
                  label: const Text('واتساب'),
                  onPressed: () => openWhatsapp(
                    customer.phone,
                    message: 'هلا ${customer.name}، بخصوص طلبك من La Casa 3D',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.call, size: 20),
                  label: const Text('اتصال'),
                  onPressed: () => callPhone(customer.phone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          info(Icons.phone, SelectableText(customer.phone, textDirection: TextDirection.ltr)),
          if (order.deliveryDay.isNotEmpty)
            info(Icons.event, Text('${order.pickupMethod.label} • ${order.deliveryDay}')),
          if (customer.address.isNotEmpty)
            info(Icons.location_on, SelectableText(customer.address)),
          if (customer.notes.isNotEmpty) info(Icons.note_alt_outlined, Text(customer.notes)),
          const Divider(),
          for (final item in order.items)
            Row(children: [
              Expanded(child: Text('${item.name} × ${item.quantity}${item.note.isEmpty ? '' : '\n📝 ${item.note}'}')),
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
                if (context.mounted) _showError(context, 'ما كدرنا نغير الحالة');
              }
            },
          ),
        ],
      ),
    );
  }
}

// ───────────── المنتجات ─────────────

class _ProductsTab extends StatelessWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<Category>>();
    return _ListTab<Product>(
      watch: (repo) => repo.watchProducts(includeHidden: true),
      addLabel: 'منتج جديد',
      onAdd: () => _push(context, const ProductEditScreen()),
      emptyText: 'ماكو منتجات بعد. ضيف منتج جديد، أو جرب بالمنتجات التجريبية.',
      seedLabel: 'أضف المنتجات التجريبية',
      seed: (repo) async {
        for (final p in sampleProducts) {
          await repo.saveProduct(p);
        }
      },
      itemBuilder: (context, product) {
        final category = categories.where((c) => c.id == product.categoryId).firstOrNull;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: () => _push(context, ProductEditScreen(product: product)),
            leading: SizedBox.square(
              dimension: 48,
              child: ProductImage(
                product: product,
                iconSize: 24,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            title: Text(product.name),
            subtitle: Text('${formatPrice(product.price)} • ${category?.name ?? 'بدون قسم'}'),
            trailing: Switch(
              value: product.available,
              onChanged: (v) =>
                  context.read<StoreRepository>().saveProduct(product.copyWith(available: v)),
            ),
          ),
        );
      },
    );
  }
}

// ───────────── الأقسام ─────────────

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context) {
    return _ListTab<Category>(
      watch: (repo) => repo.watchCategories(),
      addLabel: 'قسم جديد',
      onAdd: () => _push(context, const CategoryEditScreen()),
      emptyText: 'ماكو أقسام بعد. ضيف قسم جديد، أو ضيف الأقسام اللي كانت بالتطبيق.',
      seedLabel: 'أضف الأقسام القديمة',
      seed: (repo) async {
        for (final c in sampleCategories) {
          await repo.saveCategory(c);
        }
      },
      itemBuilder: (context, category) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => _push(context, CategoryEditScreen(category: category)),
          leading: CategoryAvatar(category: category, size: 44),
          title: Text(category.name),
          subtitle: Text('الترتيب: ${category.order}'),
          trailing: Icon(categoryIcon(category.iconKey)),
        ),
      ),
    );
  }
}

// ───────────── العروض ─────────────

class _BannersTab extends StatelessWidget {
  const _BannersTab();

  @override
  Widget build(BuildContext context) {
    return _ListTab<PromoBanner>(
      watch: (repo) => repo.watchBanners(includeHidden: true),
      addLabel: 'عرض جديد',
      onAdd: () => _push(context, const BannerEditScreen()),
      emptyText: 'ماكو عروض. العروض تبين كبنر قلّاب بأول الصفحة الرئيسية.',
      itemBuilder: (context, banner) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => _push(context, BannerEditScreen(banner: banner)),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 72,
              height: 40,
              child: NetImage(
                url: banner.imageUrl,
                placeholder: Container(color: Theme.of(context).colorScheme.secondaryContainer),
              ),
            ),
          ),
          title: Text(banner.title.isEmpty ? '(بدون عنوان)' : banner.title),
          subtitle: Text('الترتيب: ${banner.order}'),
          trailing: Switch(
            value: banner.active,
            onChanged: (v) =>
                context.read<StoreRepository>().saveBanner(banner.copyWith(active: v)),
          ),
        ),
      ),
    );
  }
}

// ───────────── الريلز ─────────────

class _ReelsTab extends StatelessWidget {
  const _ReelsTab();

  @override
  Widget build(BuildContext context) {
    return _ListTab<Reel>(
      watch: (repo) => repo.watchReels(includeHidden: true),
      addLabel: 'فيديو جديد',
      onAdd: () => _push(context, const ReelEditScreen()),
      emptyText: 'ماكو فيديوهات. الفيديوهات تبين بتبويب "ريلز".',
      itemBuilder: (context, reel) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => _push(context, ReelEditScreen(reel: reel)),
          leading: const CircleAvatar(child: Icon(Icons.play_arrow)),
          title: Text(
            reel.caption.isEmpty ? reel.videoUrl : reel.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('الترتيب: ${reel.order}'),
          trailing: Switch(
            value: reel.active,
            onChanged: (v) => context.read<StoreRepository>().saveReel(reel.copyWith(active: v)),
          ),
        ),
      ),
    );
  }
}
