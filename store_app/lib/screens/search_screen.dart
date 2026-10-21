import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../services/store_repository.dart';
import '../widgets/cart_button.dart';
import '../widgets/product_grid.dart';

/// يدور بالاسم والوصف.
bool matchesQuery(Product product, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return product.name.toLowerCase().contains(q) || product.description.toLowerCase().contains(q);
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final Stream<List<Product>> _products = context.read<StoreRepository>().watchProducts();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'ابحث في كل المنتجات',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: const [CartButton()],
      ),
      body: StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, snapshot) {
          final all = snapshot.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final results = all.where((p) => matchesQuery(p, _query)).toList();
          if (results.isEmpty) {
            return const EmptyMessage(icon: Icons.search_off, text: 'ماكو منتجات تطابق البحث');
          }
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverProductGrid(products: results),
            ],
          );
        },
      ),
    );
  }
}
