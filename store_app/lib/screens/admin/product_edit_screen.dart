import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/content.dart';
import '../../models/product.dart';
import '../../services/media_uploader.dart';
import '../../services/store_repository.dart';
import '../../widgets/media_url_field.dart';
import '../../widgets/price_tag.dart';
import '../../widgets/product_image.dart';
import 'content_editors.dart' show validateHttpsUrl;
import 'product_options_editor.dart';

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
  late final _oldPrice = TextEditingController(
    text: (widget.product?.onSale ?? false) ? widget.product!.oldPrice.toString() : '',
  );
  late final _imageUrl = TextEditingController(text: widget.product?.imageUrl);
  late String _categoryId = widget.product?.categoryId ?? '';
  late bool _available = widget.product?.available ?? true;
  late final _options = [for (final o in widget.product?.options ?? const <ProductOption>[]) OptionDraft.from(o)];
  bool _saving = false;

  bool get _isNew => widget.product == null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _oldPrice.dispose();
    _imageUrl.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  static int _number(String text) => int.tryParse(text.replaceAll(',', '').trim()) ?? 0;

  /// إذا نزّلت السعر وما كتبت "السعر قبل التخفيض"، السعر القديم يبين مشطوب بنفسه.
  Product get _draft {
    final price = _number(_price.text);
    return Product(
        id: widget.product?.id ?? '',
        name: _name.text.trim(),
        description: _description.text.trim(),
        price: price,
        oldPrice: saleOldPrice(
          previousPrice: widget.product?.price,
          newPrice: price,
          enteredOldPrice: _number(_oldPrice.text),
        ),
        categoryId: _categoryId,
        imageUrl: _imageUrl.text.trim(),
        available: _available,
        options: [for (final o in _options) o.toOption()],
      );
  }

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
    // اختيار مكتوب وما انضغط عليه "+": نضيفه بدال ما يضيع.
    for (final o in _options) {
      final pending = o.newChoice.text.trim();
      if (pending.isNotEmpty && !o.choices.contains(pending)) o.choices.add(pending);
      o.newChoice.clear();
    }
    setState(() {});
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
    final categories = context.watch<List<Category>>();
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
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final price = int.tryParse((v ?? '').replaceAll(',', '').trim());
                return (price == null || price <= 0) ? 'اكتب سعر صحيح' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _oldPrice,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'السعر قبل التخفيض (اختياري)',
                suffixText: 'د.ع',
                helperText: 'يبين للزبون مشطوب. إذا نزّلت السعر وتركته فارغ، ياخذ السعر القديم بنفسه.\n'
                    'حتى تشيل التخفيض: امسحه.',
                helperMaxLines: 3,
              ),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final old = int.tryParse(v!.replaceAll(',', '').trim());
                if (old == null || old < 0) return 'اكتب رقم صحيح';
                if (old <= _number(_price.text)) return 'لازم يكون أكبر من السعر الحالي';
                return null;
              },
            ),
            if (_draft.onSale)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Text('الزبون يشوف: '),
                  Expanded(child: PriceTag(product: _draft)),
                ]),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: InputDecoration(
                labelText: 'القسم',
                helperText: categories.isEmpty ? 'ضيف الأقسام بالأول من تبويب "الأقسام"' : null,
              ),
              items: [
                for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
              validator: (v) => v == null ? 'اختار القسم' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'الوصف'),
            ),
            const SizedBox(height: 12),
            MediaUrlField(
              controller: _imageUrl,
              kind: MediaKind.image,
              label: 'رابط الصورة (اختياري)',
              onChanged: () => setState(() {}),
              validator: validateHttpsUrl,
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متوفر للزباين'),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            const Divider(height: 32),
            ProductOptionsEditor(drafts: _options),
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
