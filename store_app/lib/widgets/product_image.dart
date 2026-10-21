import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/category_icons.dart';
import '../models/content.dart';
import '../models/product.dart';

/// صورة من رابط، وإذا ماكو رابط أو ما اشتغل تبين [placeholder].
class NetImage extends StatelessWidget {
  final String url;
  final Widget placeholder;
  final BoxFit fit;

  const NetImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

/// صورة المنتج، وإذا ماكو صورة تبين أيقونة القسم.
class ProductImage extends StatelessWidget {
  final Product product;
  final double iconSize;
  final BorderRadius borderRadius;

  /// حركة الصورة بين بطاقة المنتج وصفحته. بس وحدة بكل صفحة لنفس المنتج.
  final bool hero;

  const ProductImage({
    super.key,
    required this.product,
    this.iconSize = 48,
    this.borderRadius = BorderRadius.zero,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<Category>>();
    final category = categories
        .where((c) => c.id == product.categoryId)
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;

    final image = ClipRRect(
      borderRadius: borderRadius,
      child: NetImage(
        url: product.imageUrl,
        placeholder: Container(
          color: colors.secondaryContainer.withValues(alpha: 0.5),
          alignment: Alignment.center,
          child: Icon(
            categoryIcon(category?.iconKey ?? ''),
            size: iconSize,
            color: colors.secondary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
    return hero ? Hero(tag: 'product-${product.id}', child: image) : image;
  }
}

/// أيقونة القسم أو صورته بدائرة.
class CategoryAvatar extends StatelessWidget {
  final Category category;
  final double size;
  final bool selected;

  const CategoryAvatar({
    super.key,
    required this.category,
    this.size = 56,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = selected ? colors.onSecondary : colors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.secondary : Colors.white,
        border: Border.all(color: selected ? colors.secondary : Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: NetImage(
        url: category.imageUrl,
        placeholder: Icon(
          categoryIcon(category.iconKey),
          color: fg,
          size: size * 0.46,
        ),
      ),
    );
  }
}
