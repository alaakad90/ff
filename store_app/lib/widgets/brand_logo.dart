import 'package:flutter/material.dart';

/// شعار المتجر. الشعار أسود، فبالوضع الليلي نحطه على خلفية فاتحة حتى يبين.
class BrandLogo extends StatelessWidget {
  final double height;

  const BrandLogo({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset('assets/images/logo.png', height: height);
    if (Theme.of(context).brightness == Brightness.light) return image;
    return Center(
      widthFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: image),
      ),
    );
  }
}
