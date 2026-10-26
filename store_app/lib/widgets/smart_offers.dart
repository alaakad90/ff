import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/loyalty.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/device_history.dart';
import '../services/recommendations.dart';
import '../services/store_repository.dart';
import '../state/cart.dart';
import 'product_grid.dart';

/// العروض الذكية: منتجات تناسب اللي طلبه الزبون أو اللي بسلته.
/// مثلاً: اللي طلب بورد زواج تبينله عقود الزواج (حسب قواعد صاحب المتجر).
/// [cartOnly]: بصفحة السلة نعتمد على السلة بس.
class SmartOffers extends StatefulWidget {
  final bool cartOnly;
  final EdgeInsetsGeometry padding;

  const SmartOffers({super.key, this.cartOnly = false, this.padding = const EdgeInsets.only(top: 8)});

  @override
  State<SmartOffers> createState() => _SmartOffersState();
}

class _SmartOffersState extends State<SmartOffers> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<List<Product>> _products = _repo.watchProducts();
  late final Stream<List<RecommendationRule>> _rules = _repo.watchRecommendationRules();
  Stream<List<StoreOrder>> _orders = Stream.value(const []);
  List<String> _deviceIds = const [];
  String _uid = '';

  @override
  void initState() {
    super.initState();
    if (!widget.cartOnly) {
      context.read<DeviceHistory>().purchasedProductIds().then((ids) {
        if (mounted) setState(() => _deviceIds = ids);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<Session>();
    final uid = session.signedIn && !widget.cartOnly ? session.uid : '';
    if (uid != _uid) {
      _uid = uid;
      _orders = uid.isEmpty
          ? Stream.value(const [])
          : _repo.watchUserOrders(uid).handleError((_) {}).map((o) => o.take(10).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    return StreamBuilder<List<Product>>(
      stream: _products,
      builder: (context, productsSnap) => StreamBuilder<List<RecommendationRule>>(
        stream: _rules,
        builder: (context, rulesSnap) => StreamBuilder<List<StoreOrder>>(
          stream: _orders,
          builder: (context, ordersSnap) {
            final catalog = productsSnap.data ?? const <Product>[];
            if (catalog.isEmpty) return const SizedBox.shrink();
            final byId = {for (final p in catalog) p.id: p};
            final basis = <Product>[];
            final seen = <String>{};
            void addBasis(Product p) {
              if (p.id.isNotEmpty && seen.add(p.id)) basis.add(p);
            }

            for (final item in cart.items) {
              addBasis(item.product);
            }
            for (final order in ordersSnap.data ?? const <StoreOrder>[]) {
              for (final item in order.items) {
                // إذا المنتج انخفى نستعمل اسمه بس، حتى الكلمات (مثل "زواج") تبقى تنطبق.
                addBasis(byId[item.productId] ??
                    Product(id: item.productId, name: item.name, price: item.price, categoryId: ''));
              }
            }
            for (final id in _deviceIds) {
              final p = byId[id];
              if (p != null) addBasis(p);
            }
            final groups = recommend(
              catalog: catalog,
              rules: rulesSnap.data ?? const [],
              basis: basis,
              exclude: cart.items.map((i) => i.product.id).toSet(),
              maxGroups: widget.cartOnly ? 1 : 3,
            );
            if (groups.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final group in groups) _GroupRow(group: group)],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final RecommendationGroup group;

  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.secondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(group.title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: group.products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(width: 165, child: ProductCard(product: group.products[i], hero: false)),
          ),
        ),
      ],
    );
  }
}
