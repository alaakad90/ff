import 'package:flutter/material.dart';

import '../../models/product.dart';

/// حقل واحد وهو ينعدل: اسمه (مثل "اللون") واختياراته.
class OptionDraft {
  final TextEditingController name;
  final TextEditingController newChoice = TextEditingController();
  final List<String> choices;
  bool required;

  OptionDraft({String name = '', List<String>? choices, this.required = true})
      : name = TextEditingController(text: name),
        choices = choices ?? [];

  factory OptionDraft.from(ProductOption o) =>
      OptionDraft(name: o.name, choices: [...o.choices], required: o.required);

  ProductOption toOption() => ProductOption(name: name.text.trim(), choices: [...choices], required: required);

  void dispose() {
    name.dispose();
    newChoice.dispose();
  }
}

/// قسم "خيارات المنتج" بصفحة المنتج: المدير يضيف حقول ويضيف لكل حقل اختيارات.
class ProductOptionsEditor extends StatefulWidget {
  final List<OptionDraft> drafts;

  const ProductOptionsEditor({super.key, required this.drafts});

  @override
  State<ProductOptionsEditor> createState() => _ProductOptionsEditorState();
}

class _ProductOptionsEditorState extends State<ProductOptionsEditor> {
  List<OptionDraft> get _drafts => widget.drafts;

  void _addChoice(OptionDraft draft) {
    final choice = draft.newChoice.text.trim();
    if (choice.isEmpty) return;
    setState(() {
      if (!draft.choices.contains(choice)) draft.choices.add(choice);
      draft.newChoice.clear();
    });
  }

  void _removeOption(OptionDraft draft) {
    setState(() => _drafts.remove(draft));
    draft.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('خيارات المنتج', style: theme.textTheme.titleMedium),
        Text(
          'حقول يختار منها الزبون قبل ما يضيف للسلة، مثل: اللون، نوع الخط، القياس.',
          style: theme.textTheme.bodySmall,
        ),
        for (final (i, draft) in _drafts.indexed)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: draft.name,
                        decoration: InputDecoration(labelText: 'اسم الحقل ${i + 1}', hintText: 'مثلاً: اللون'),
                        validator: (v) {
                          final name = (v ?? '').trim();
                          if (name.isEmpty) return 'اكتب اسم الحقل';
                          if (_drafts.where((d) => d.name.text.trim() == name).length > 1) {
                            return 'هذا الاسم مكرر';
                          }
                          return null;
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'حذف الحقل',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeOption(draft),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final choice in draft.choices)
                        InputChip(
                          label: Text(choice),
                          onDeleted: () => setState(() => draft.choices.remove(choice)),
                        ),
                    ],
                  ),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: draft.newChoice,
                        decoration: const InputDecoration(labelText: 'اختيار جديد', hintText: 'مثلاً: أحمر'),
                        onSubmitted: (_) => _addChoice(draft),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'أضف الاختيار',
                      icon: const Icon(Icons.add),
                      onPressed: () => _addChoice(draft),
                    ),
                  ]),
                  // التحقق من وجود اختيارات: حقل مخفي حتى يطلع الخطأ ويه باقي الفورم.
                  FormField<void>(
                    validator: (_) => draft.choices.isEmpty ? 'ضيف اختيار واحد على الأقل' : null,
                    builder: (state) => state.hasError
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(state.errorText!,
                                style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                          )
                        : const SizedBox.shrink(),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('لازم الزبون يختار'),
                    value: draft.required,
                    onChanged: (v) => setState(() => draft.required = v),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.playlist_add),
          label: const Text('إضافة حقل'),
          onPressed: () => setState(() => _drafts.add(OptionDraft())),
        ),
      ],
    );
  }
}
