import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/category_icons.dart';
import '../../models/content.dart';
import '../../models/product.dart';
import '../../services/media_uploader.dart';
import '../../services/store_repository.dart';
import '../../widgets/media_url_field.dart';
import '../../widgets/product_image.dart';

String? validateHttpsUrl(String? v, {bool required = false}) {
  final url = (v ?? '').trim();
  if (url.isEmpty) return required ? 'اكتب الرابط' : null;
  return url.startsWith('https://') ? null : 'الرابط لازم يبدي بـ https://';
}

int parseOrder(String text) => int.tryParse(text.trim()) ?? 0;

/// هيكل مشترك لصفحات التعديل: نموذج، زر حفظ، وزر حذف.
class EditorScaffold extends StatefulWidget {
  final String title;
  final List<Widget> Function(BuildContext context, VoidCallback refresh) fields;
  final Future<void> Function(StoreRepository repo) onSave;
  final Future<void> Function(StoreRepository repo)? onDelete;
  final String deleteName;

  const EditorScaffold({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.onDelete,
    this.deleteName = '',
  });

  @override
  State<EditorScaffold> createState() => _EditorScaffoldState();
}

class _EditorScaffoldState extends State<EditorScaffold> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  Future<void> _run(Future<void> Function(StoreRepository) action, String error) async {
    setState(() => _saving = true);
    try {
      await action(context.read<StoreRepository>());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف؟'),
        content: Text('راح ينحذف "${widget.deleteName}" نهائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('احذف')),
        ],
      ),
    );
    if (confirmed == true && mounted) _run(widget.onDelete!, 'ما كدرنا نحذف');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onDelete != null)
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
          children: widget.fields(context, () => setState(() {})),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving
                ? null
                : () {
                    if (_formKey.currentState!.validate()) _run(widget.onSave, 'ما كدرنا نحفظ');
                  },
            child: const Text('حفظ'),
          ),
        ),
      ),
    );
  }
}

const _gap = SizedBox(height: 12);

// ───────────── قسم ─────────────

class CategoryEditScreen extends StatefulWidget {
  final Category? category;

  const CategoryEditScreen({super.key, this.category});

  @override
  State<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends State<CategoryEditScreen> {
  late final _name = TextEditingController(text: widget.category?.name);
  late final _imageUrl = TextEditingController(text: widget.category?.imageUrl);
  late final _order = TextEditingController(text: '${widget.category?.order ?? 0}');
  late String _iconKey = widget.category?.iconKey ?? 'category';

  Category get _draft => Category(
        id: widget.category?.id ?? '',
        name: _name.text.trim(),
        iconKey: _iconKey,
        imageUrl: _imageUrl.text.trim(),
        order: parseOrder(_order.text),
      );

  @override
  void dispose() {
    _name.dispose();
    _imageUrl.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final existing = widget.category;
    return EditorScaffold(
      title: existing == null ? 'قسم جديد' : 'تعديل القسم',
      deleteName: existing?.name ?? '',
      onSave: (repo) => repo.saveCategory(_draft),
      onDelete: existing == null ? null : (repo) => repo.deleteCategory(existing.id),
      fields: (context, refresh) => [
        Center(child: CategoryAvatar(category: _draft, size: 88, selected: true)),
        const SizedBox(height: 16),
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم القسم'),
          onChanged: (_) => refresh(),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب الاسم' : null,
        ),
        _gap,
        TextFormField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'الترتيب',
            helperText: 'الرقم الأصغر يطلع أول',
          ),
        ),
        const SizedBox(height: 20),
        Text('الأيقونة', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in categoryIcons.entries)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _iconKey = entry.key),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _iconKey == entry.key ? colors.secondary : Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Icon(
                    entry.value,
                    color: _iconKey == entry.key ? colors.onSecondary : colors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        MediaUrlField(
          controller: _imageUrl,
          kind: MediaKind.image,
          label: 'أو صورة بدال الأيقونة (اختياري)',
          onChanged: refresh,
          validator: validateHttpsUrl,
        ),
      ],
    );
  }
}

// ───────────── عرض (بنر) ─────────────

class BannerEditScreen extends StatefulWidget {
  final PromoBanner? banner;

  const BannerEditScreen({super.key, this.banner});

  @override
  State<BannerEditScreen> createState() => _BannerEditScreenState();
}

class _BannerEditScreenState extends State<BannerEditScreen> {
  late final _title = TextEditingController(text: widget.banner?.title);
  late final _subtitle = TextEditingController(text: widget.banner?.subtitle);
  late final _imageUrl = TextEditingController(text: widget.banner?.imageUrl);
  late final _order = TextEditingController(text: '${widget.banner?.order ?? 0}');
  late String _categoryId = widget.banner?.categoryId ?? '';
  late bool _active = widget.banner?.active ?? true;

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _imageUrl.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<Category>>();
    final existing = widget.banner;
    return EditorScaffold(
      title: existing == null ? 'عرض جديد' : 'تعديل العرض',
      deleteName: existing?.title ?? '',
      onSave: (repo) => repo.saveBanner(PromoBanner(
        id: existing?.id ?? '',
        title: _title.text.trim(),
        subtitle: _subtitle.text.trim(),
        imageUrl: _imageUrl.text.trim(),
        categoryId: _categoryId,
        order: parseOrder(_order.text),
        active: _active,
      )),
      onDelete: existing == null ? null : (repo) => repo.deleteBanner(existing.id),
      fields: (context, refresh) => [
        AspectRatio(
          aspectRatio: 2.1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: NetImage(
              url: _imageUrl.text.trim(),
              placeholder: Container(
                color: Theme.of(context).colorScheme.secondaryContainer,
                alignment: Alignment.center,
                child: const Text('معاينة الصورة'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'أفضل مقاس للصورة: عرضها ضعف طولها، مثل 1200×570.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        MediaUrlField(
          controller: _imageUrl,
          kind: MediaKind.image,
          label: 'رابط الصورة',
          onChanged: refresh,
          validator: validateHttpsUrl,
        ),
        _gap,
        TextFormField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'العنوان (اختياري)', hintText: 'خصم 20%'),
        ),
        _gap,
        TextFormField(
          controller: _subtitle,
          decoration: const InputDecoration(labelText: 'نص صغير (اختياري)'),
        ),
        _gap,
        DropdownButtonFormField<String>(
          initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : '',
          decoration: const InputDecoration(labelText: 'لما ينضغط يفتح قسم'),
          items: [
            const DropdownMenuItem(value: '', child: Text('ولا شي')),
            for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => _categoryId = v ?? '',
        ),
        _gap,
        TextFormField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الترتيب', helperText: 'الرقم الأصغر يطلع أول'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ظاهر للزباين'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ],
    );
  }
}

// ───────────── فيديو (ريلز) ─────────────

class ReelEditScreen extends StatefulWidget {
  final Reel? reel;

  const ReelEditScreen({super.key, this.reel});

  @override
  State<ReelEditScreen> createState() => _ReelEditScreenState();
}

class _ReelEditScreenState extends State<ReelEditScreen> {
  late final _videoUrl = TextEditingController(text: widget.reel?.videoUrl);
  late final _caption = TextEditingController(text: widget.reel?.caption);
  late final _order = TextEditingController(text: '${widget.reel?.order ?? 0}');
  late final Stream<List<Product>> _products =
      context.read<StoreRepository>().watchProducts(includeHidden: true);
  late String _productId = widget.reel?.productId ?? '';
  late bool _active = widget.reel?.active ?? true;

  @override
  void dispose() {
    _videoUrl.dispose();
    _caption.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.reel;
    return EditorScaffold(
      title: existing == null ? 'فيديو جديد' : 'تعديل الفيديو',
      deleteName: existing?.caption ?? 'الفيديو',
      onSave: (repo) => repo.saveReel(Reel(
        id: existing?.id ?? '',
        videoUrl: _videoUrl.text.trim(),
        caption: _caption.text.trim(),
        productId: _productId,
        order: parseOrder(_order.text),
        active: _active,
      )),
      onDelete: existing == null ? null : (repo) => repo.deleteReel(existing.id),
      fields: (context, refresh) => [
        MediaUrlField(
          controller: _videoUrl,
          kind: MediaKind.video,
          label: 'رابط الفيديو',
          helperText: 'ارفع فيديو، أو الصق رابط ريل من إنستغرام، أو رابط ملف mp4',
          validator: (v) => validateHttpsUrl(v, required: true),
        ),
        _gap,
        TextFormField(
          controller: _caption,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'الوصف (اختياري)'),
        ),
        _gap,
        StreamBuilder<List<Product>>(
          stream: _products,
          builder: (context, snapshot) {
            final products = snapshot.data ?? const <Product>[];
            return DropdownButtonFormField<String>(
              initialValue: products.any((p) => p.id == _productId) ? _productId : '',
              decoration: const InputDecoration(labelText: 'زر "شوف المنتج" (اختياري)'),
              items: [
                const DropdownMenuItem(value: '', child: Text('ولا منتج')),
                for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => _productId = v ?? '',
            );
          },
        ),
        _gap,
        TextFormField(
          controller: _order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الترتيب', helperText: 'الرقم الأصغر يطلع أول'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ظاهر للزباين'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ],
    );
  }
}

// ───────────── معلومات المتجر ─────────────

class StoreInfoEditor extends StatefulWidget {
  const StoreInfoEditor({super.key});

  @override
  State<StoreInfoEditor> createState() => _StoreInfoEditorState();
}

/// نستنى المعلومات المحفوظة تتحمل، حتى ما نحفظ فوقها حقول فارغة.
class _StoreInfoEditorState extends State<StoreInfoEditor> {
  late final Future<StoreInfo> _info = context.read<StoreRepository>().watchStoreInfo().first;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreInfo>(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('ما كدرنا نحمل معلومات المتجر'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return _StoreInfoForm(initial: snapshot.data!);
      },
    );
  }
}

class _StoreInfoForm extends StatefulWidget {
  final StoreInfo initial;

  const _StoreInfoForm({required this.initial});

  @override
  State<_StoreInfoForm> createState() => _StoreInfoFormState();
}

class _StoreInfoFormState extends State<_StoreInfoForm> {
  final _formKey = GlobalKey<FormState>();
  late final StoreInfo _initial = widget.initial;
  late final _about = TextEditingController(text: _initial.about);
  late final _phone = TextEditingController(text: _initial.phone);
  late final _whatsapp = TextEditingController(text: _initial.whatsapp);
  late final _address = TextEditingController(text: _initial.address);
  late final _hours = TextEditingController(text: _initial.hours);
  late final _instagram = TextEditingController(text: _initial.instagram);
  late final _facebook = TextEditingController(text: _initial.facebook);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_about, _phone, _whatsapp, _address, _hours, _instagram, _facebook]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<StoreRepository>().saveStoreInfo(StoreInfo(
            about: _about.text.trim(),
            phone: _phone.text.trim(),
            whatsapp: _whatsapp.text.trim(),
            address: _address.text.trim(),
            hours: _hours.text.trim(),
            instagram: _instagram.text.trim(),
            facebook: _facebook.text.trim(),
          ));
      messenger.showSnackBar(const SnackBar(content: Text('انحفظت معلومات المتجر')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('ما كدرنا نحفظ')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'هذني المعلومات تبين بصفحة "عن المتجر".',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _about,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'نبذة عن المتجر'),
          ),
          _gap,
          TextFormField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم الواتساب', hintText: '07XXXXXXXXX'),
          ),
          _gap,
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم الاتصال', hintText: '07XXXXXXXXX'),
          ),
          _gap,
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'العنوان'),
          ),
          _gap,
          TextFormField(
            controller: _hours,
            decoration: const InputDecoration(
              labelText: 'أوقات الدوام',
              hintText: 'السبت - الخميس، 10 صباحاً - 10 مساءً',
            ),
          ),
          _gap,
          TextFormField(
            controller: _instagram,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'إنستغرام', hintText: '@lacasa3d'),
          ),
          _gap,
          TextFormField(
            controller: _facebook,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'فيسبوك',
              hintText: 'https://facebook.com/lacasa3d',
              helperText: 'رابط الصفحة أو اسمها. يبين زر "تابعنا على فيسبوك" بصفحة عن المتجر',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
