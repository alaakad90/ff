import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../models/product.dart';

/// صورة المنتج من الرابط، وإذا ماكو رابط أو ما اشتغل تبين أيقونة القسم.
class ProductImage extends StatelessWidget {
  final Product product;
  final double iconSize;
  final BorderRadius borderRadius;

  const ProductImage({
    super.key,
    required this.product,
    this.iconSize = 48,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final category = categoryOf(product.categoryId);
    final placeholder = Container(
      color: category.color.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Icon(category.icon, size: iconSize, color: category.color),
    );

    return Hero(
      tag: 'product-${product.id}',
      child: ClipRRect(
        borderRadius: borderRadius,
        child: product.imageUrl.isEmpty
            ? placeholder
            : Image.network(
                product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}
