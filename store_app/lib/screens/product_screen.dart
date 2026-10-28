import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/product.dart';
import '../services/contact.dart';
import '../state/cart.dart';
import '../widgets/cart_button.dart';
import '../widgets/note_attachments_field.dart';
import '../widgets/product_grid.dart';
import '../widgets/price_tag.dart';
import '../widgets/product_image.dart';
import 'checkout_screen.dart';

class ProductScreen extends StatefulWidget {
  final Product product;

  const ProductScreen({super.key, required this.product});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  int _quantity = 1;
  final _note = TextEditingController();
  String _imageUrl = '';
  String _voiceUrl = '';
  bool _attaching = false;
  final Map<String, String> _selected = {}; // اختيارات الزبون: اسم الحقل → الاختيار

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// الاختيارات بنفس ترتيب حقول المنتج. إذا حقل إجباري ما مختار، ينبه الزبون ويرجع null.
  Map<String, String>? _chosenOptions() {
    for (final option in widget.product.options) {
      if (option.required && !_selected.containsKey(option.name)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('اختار ${option.name}')));
        return null;
      }
    }
    return {
      for (final option in widget.product.options)
        if (_selected[option.name] != null) option.name: _selected[option.name]!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final theme = Theme.of(context);
    final whatsapp = context.watch<StoreInfo>().whatsapp;

    return Scaffold(
      appBar: AppBar(actions: const [CartButton()]),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: ProductImage(product: product, iconSize: 120, hero: true),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                PriceTag(
                  product: product,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(product.description, style: theme.textTheme.bodyLarge),
                for (final option in product.options) ...[
                  const SizedBox(height: 16),
                  Text(option.required ? option.name : '${option.name} (اختياري)',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in option.choices)
                        ChoiceChip(
                          label: Text(option.extraFor(choice) > 0
                              ? '$choice (+${formatPrice(option.extraFor(choice))})'
                              : choice),
                          selected: _selected[option.name] == choice,
                          onSelected: (on) => setState(() {
                            if (on) {
                              _selected[option.name] = choice;
                            } else {
                              _selected.remove(option.name);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
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
                const SizedBox(height: 16),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات على المنتج (اختياري)',
                    hintText: 'مثلاً: اللون، القياس، كتابة اسم...',
                    prefixIcon: Icon(Icons.note_alt_outlined),
                  ),
                ),
                NoteAttachmentsField(
                  imageUrl: _imageUrl,
                  voiceUrl: _voiceUrl,
                  onChanged: ({required imageUrl, required voiceUrl}) => setState(() {
                    _imageUrl = imageUrl;
                    _voiceUrl = voiceUrl;
                  }),
                  onBusy: (busy) => setState(() => _attaching = busy),
                ),
                if (whatsapp.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF128C7E),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('اسأل الإدارة بالواتساب'),
                    onPressed: () => openWhatsapp(
                      whatsapp,
                      message: 'مرحبا، عندي سؤال عن: ${product.name} (${formatPrice(product.price)})',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text('أضف للسلة • ${formatPrice(product.priceWith(_selected) * _quantity)}'),
                  onPressed: _attaching
                      ? null
                      : () {
                          final options = _chosenOptions();
                          if (options == null) return;
                          context.read<Cart>().add(product, _quantity, _note.text, _imageUrl, _voiceUrl, options);
                          Navigator.of(context).pop();
                          showAddedToCart(context, product);
                        },
                ),
              ),
              const SizedBox(width: 8),
              // طلب سريع: هذا المنتج بس، بدون ما يتغير شي بالسلة.
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bolt),
                  label: const Text('اطلب الآن'),
                  onPressed: _attaching
                      ? null
                      : () {
                          final options = _chosenOptions();
                          if (options == null) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CheckoutScreen(items: [
                              CartItem(product, _quantity,
                                  note: _note.text.trim(),
                                  imageUrl: _imageUrl,
                                  voiceUrl: _voiceUrl,
                                  options: options),
                            ]),
                          ));
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
