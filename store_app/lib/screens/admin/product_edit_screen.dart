import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../models/product.dart';
import '../../services/store_repository.dart';
import '../../widgets/product_image.dart';

class ProductEditScreen extends StatefulWidget {
  /// null يعني منتج جديد.
  final Product? product;

  const ProductEditScreen({super.key, this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _description = TextEditingController(text: widget.product?.description);
  late final _price = TextEditingController(text: widget.product?.price.toString());
  late final _imageUrl = TextEditingController(text: widget.product?.imageUrl);
  late String _categoryId = widget.product?.categoryId ?? categories.first.id;
  late bool _available = widget.product?.available ?? true;
  bool _saving = false;

  bool get _isNew => widget.product == null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Product get _draft => Product(
        id: widget.product?.id ?? '',
        name: _name.text.trim(),
        description: _description.text.trim(),
        price: int.tryParse(_price.text.replaceAll(',', '').trim()) ?? 0,
        categoryId: _categoryId,
        imageUrl: _imageUrl.text.trim(),
        available: _available,
      );

  Future<void> _run(Future<void> Function() action, String error) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _run(() => context.read<StoreRepository>().saveProduct(_draft), 'ما كدرنا نحفظ المنتج');
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المنتج؟'),
        content: Text('راح ينحذف "${widget.product!.name}" نهائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('احذف')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _run(
      () => context.read<StoreRepository>().deleteProduct(widget.product!.id),
      'ما كدرنا نحذف المنتج',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'منتج جديد' : 'تعديل المنتج'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 1.6,
              child: ProductImage(
                product: _draft,
                iconSize: 64,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب الاسم' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر', suffixText: 'د.ع'),
              validator: (v) {
                final price = int.tryParse((v ?? '').replaceAll(',', '').trim());
                return (price == null || price <= 0) ? 'اكتب سعر صحيح' : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'القسم'),
              items: [
                for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'الوصف'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imageUrl,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رابط الصورة (اختياري)',
                hintText: 'https://...',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final url = (v ?? '').trim();
                return url.isEmpty || url.startsWith('https://') ? null : 'الرابط لازم يبدي بـ https://';
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متوفر للزباين'),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('حفظ'),
          ),
        ),
      ),
    );
  }
}
