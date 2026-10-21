import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/product.dart';
import '../services/store_repository.dart';
import '../widgets/cart_button.dart';
import '../widgets/product_grid.dart';
import '../widgets/product_image.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<Category>>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('الأقسام')),
      body: categories.isEmpty
          ? const EmptyMessage(icon: Icons.grid_view_outlined, text: 'ماكو أقسام بعد')
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final category = categories[i];
                return Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CategoryProductsScreen(category: category),
                    )),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CategoryAvatar(category: category, size: 72),
                        const SizedBox(height: 10),
                        Text(
                          category.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class CategoryProductsScreen extends StatefulWidget {
  final Category category;

  const CategoryProductsScreen({super.key, required this.category});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  late final Stream<List<Product>> _products = context.read<StoreRepository>().watchProducts();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name), actions: const [CartButton()]),
      body: StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, snapshot) {
          final all = snapshot.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final products = all.where((p) => p.categoryId == widget.category.id).toList();
          if (products.isEmpty) {
            return const EmptyMessage(icon: Icons.inventory_2_outlined, text: 'ماكو منتجات بهذا القسم');
          }
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverProductGrid(products: products),
            ],
          );
        },
      ),
    );
  }
}
