import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalog.dart';
import '../models/product.dart';
import '../services/store_repository.dart';
import '../state/cart.dart';
import '../widgets/cart_button.dart';
import '../widgets/product_image.dart';
import 'admin/admin_gate.dart';
import 'product_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<List<Product>> _products =
      context.read<StoreRepository>().watchProducts();
  String? _categoryId;
  String _query = '';

  List<Product> _filter(List<Product> products) => products
      .where((p) => _categoryId == null || p.categoryId == _categoryId)
      .where((p) => _query.isEmpty || p.name.contains(_query))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('متجر لاكاسا'),
        actions: [
          IconButton(
            tooltip: 'لوحة التحكم',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminGate()),
            ),
          ),
          const CartButton(),
        ],
      ),
      body: StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('ما كدرنا نحمل المنتجات. تأكد من الإنترنت.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildCatalog(_filter(snapshot.data!));
        },
      ),
    );
  }

  Widget _buildCatalog(List<Product> visible) {
    return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'دور على منتج...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                children: [
                  _categoryChip(null, 'الكل', Icons.apps),
                  for (final c in categories) _categoryChip(c.id, c.name, c.icon),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('ماكو منتجات هنا')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.7,
                ),
                itemCount: visible.length,
                itemBuilder: (context, i) => _ProductCard(product: visible[i]),
              ),
            ),
        ],
    );
  }

  Widget _categoryChip(String? id, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: _categoryId == id,
        onSelected: (_) => setState(() => _categoryId = id),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductScreen(product: product)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ProductImage(product: product)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 10, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Text(
                        formatPrice(product.price),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'أضف للسلة',
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    onPressed: () {
                      context.read<Cart>().add(product);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text('انضاف "${product.name}" للسلة'),
                          duration: const Duration(seconds: 1),
                        ));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
