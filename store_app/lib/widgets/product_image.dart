import 'package:flutter/material.dart';

import '../models/product.dart';

/// صورة مؤقتة للمنتج لحد ما تنضاف صور حقيقية.
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
    return Hero(
      tag: 'product-${product.id}',
      child: Container(
        decoration: BoxDecoration(
          color: product.color.withValues(alpha: 0.18),
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: Icon(product.icon, size: iconSize, color: product.color),
      ),
    );
  }
}
