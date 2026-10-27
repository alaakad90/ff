import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../state/cart.dart';
import '../widgets/product_image.dart';
import '../widgets/smart_offers.dart';
import 'checkout_screen.dart';
import 'shell.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: cart.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 72, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('السلة فارغة'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      if (navigator.canPop()) {
                        navigator.pop();
                      } else {
                        AppShell.goTo(context, ShellTab.home);
                      }
                    },
                    child: const Text('تسوق هسه'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 16),
              // آخر عنصر: عروض تناسب السلة (مثل عقود الزواج ويا بورد الزواج).
              itemCount: cart.items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == cart.items.length) return const SmartOffers(cartOnly: true);
                final item = cart.items[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 64,
                          child: ProductImage(
                            product: item.product,
                            iconSize: 32,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name, style: theme.textTheme.titleMedium),
                              if (item.note.isNotEmpty)
                                Text(
                                  '📝 ${item.note}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              if (item.imageUrl.isNotEmpty || item.voiceUrl.isNotEmpty)
                                Text(
                                  [
                                    if (item.imageUrl.isNotEmpty) '🖼️ صورة',
                                    if (item.voiceUrl.isNotEmpty) '🎤 فويس',
                                  ].join('  '),
                                  style: theme.textTheme.bodySmall,
                                ),
                              Text(formatPrice(item.total)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'نقص',
                          onPressed: () => cart.decrement(item),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${item.quantity}', style: theme.textTheme.titleMedium),
                        IconButton(
                          tooltip: 'زيد',
                          onPressed: () => cart.increment(item),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('المجموع', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Text(
                          formatPrice(cart.total),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '+ أجور التوصيل حسب المحافظة (تبين بإكمال الطلب). الاستلام من المحل بلا أجور.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                        ),
                        child: const Text('إكمال الطلب'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
