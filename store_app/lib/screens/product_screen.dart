import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../state/cart.dart';
import '../widgets/cart_button.dart';
import '../widgets/product_image.dart';

class ProductScreen extends StatefulWidget {
  final Product product;

  const ProductScreen({super.key, required this.product});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(actions: const [CartButton()]),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: ProductImage(product: product, iconSize: 120),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  formatPrice(product.price),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(product.description, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('الكمية', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    IconButton.outlined(
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('$_quantity', style: theme.textTheme.titleLarge),
                    ),
                    IconButton.outlined(
                      onPressed: () => setState(() => _quantity++),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.add_shopping_cart),
            label: Text('أضف للسلة • ${formatPrice(product.price * _quantity)}'),
            onPressed: () {
              context.read<Cart>().add(product, _quantity);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('انضاف "${product.name}" للسلة'),
                duration: const Duration(seconds: 1),
              ));
            },
          ),
        ),
      ),
    );
  }
}
