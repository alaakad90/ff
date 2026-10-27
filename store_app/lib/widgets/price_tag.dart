import 'package:flutter/material.dart';

import '../theme.dart';

import '../models/product.dart';

/// السعر: الحالي، وإذا عليه تخفيض السعر القديم مشطوب ويا نسبة التخفيض.
class PriceTag extends StatelessWidget {
  final Product product;
  final TextStyle? style; // ستايل السعر الحالي
  final int quantity;
  final bool showBadge;

  const PriceTag({super.key, required this.product, this.style, this.quantity = 1, this.showBadge = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = style ?? theme.textTheme.bodyMedium;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(formatPrice(product.price * quantity), style: current),
        if (product.onSale) ...[
          Text(
            formatPrice(product.oldPrice * quantity),
            style: (current ?? const TextStyle()).copyWith(
              fontSize: ((current?.fontSize ?? 14) * 0.8),
              fontWeight: FontWeight.normal,
              color: theme.colorScheme.outline,
              decoration: TextDecoration.lineThrough,
              decorationColor: theme.colorScheme.error,
              decorationThickness: 2,
            ),
          ),
          if (showBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: brandRed,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '-${product.discountPercent}%',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ],
    );
  }
}
