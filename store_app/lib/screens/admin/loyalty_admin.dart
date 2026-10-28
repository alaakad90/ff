import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/content.dart';
import '../../models/delivery.dart';
import '../../models/loyalty.dart';
import '../../services/store_repository.dart';
import '../../widgets/product_grid.dart';
import '../account/my_orders_screen.dart';

void _snack(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// يحفظ بالخلفية، وإذا فشل يطلع رسالة (بدون ما نستعمل context بعد الانتظار).
void _saveQuietly(BuildContext context, Future<void> future) {
  final messenger = ScaffoldMessenger.of(context);
  future.catchError((_) {
    messenger.showSnackBar(const SnackBar(content: Text('ما كدرنا نحفظ')));
  });
}

/// يسأل قبل الحذف، ويحذف، ويرجع للقائمة.
Future<void> _confirmDelete(BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() delete,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('احذف'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await delete();
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('انحذف')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('ما كدرنا نحذف')));
  }
}

int _parseInt(String text) => int.tryParse(text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

// ───────────── الكوبونات ─────────────

class CouponsTab extends StatefulWidget {
  const CouponsTab({super.key});

  @override
  State<CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends State<CouponsTab> {
  late final Stream<List<Coupon>> _coupons = context.read<StoreRepository>().watchCoupons();

  void _edit([Coupon? coupon]) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CouponEditScreen(coupon: coupon)),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('كوبون جديد'),
      ),
      body: StreamBuilder<List<Coupon>>(
        stream: _coupons,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyMessage(icon: Icons.error_outline, text: 'ما كدرنا نحمل الكوبونات');
          }
          final coupons = snapshot.data;
          if (coupons == null) return const Center(child: CircularProgressIndicator());
          if (coupons.isEmpty) {
            return const EmptyMessage(
              icon: Icons.local_offer_outlined,
              text: 'ماكو كوبونات. سوي كوبون (مثلاً EID15 خصم 15%) وانشره بالإنستغرام.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: coupons.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final c = coupons[i];
              final status = !c.active
                  ? 'موقوف'
                  : c.isExpired(now)
                      ? 'منتهي'
                      : (c.usageLimit > 0 && c.usedCount >= c.usageLimit)
                          ? 'خلص'
                          : 'شغال';
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => _edit(c),
                  leading: const Icon(Icons.local_offer_outlined),
                  title: Text('${c.code} • ${c.valueLabel}', textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start),
                  subtitle: Text([
                    status,
                    'انستعمل ${c.usedCount}${c.usageLimit > 0 ? ' من ${c.usageLimit}' : ''}',
                    if (c.assignedTo.isNotEmpty) 'شخصي',
                    if (c.endsAt != null) 'لحد ${formatOrderDate(c.endsAt)}',
                  ].join(' • ')),
                  trailing: Switch(
                    value: c.active,
                    onChanged: (v) => _saveQuietly(context, context.read<StoreRepository>().saveCoupon(c.copyWith(active: v), isNew: false)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CouponEditScreen extends StatefulWidget {
  final Coupon? coupon;

  const CouponEditScreen({super.key, this.coupon});

  @override
  State<CouponEditScreen> createState() => _CouponEditScreenState();
}

class _CouponEditScreenState extends State<CouponEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Coupon? _old = widget.coupon;
  late final _code = TextEditingController(text: _old?.code ?? '');
  late final _description = TextEditingController(text: _old?.description ?? '');
  late final _value = TextEditingController(text: _old == null ? '' : '${_old.value}');
  late final _minSubtotal = TextEditingController(text: _old == null || _old.minSubtotal == 0 ? '' : '${_old.minSubtotal}');
  late final _maxDiscount = TextEditingController(text: _old == null || _old.maxDiscount == 0 ? '' : '${_old.maxDiscount}');
  late final _usageLimit = TextEditingController(text: _old == null || _old.usageLimit == 0 ? '' : '${_old.usageLimit}');
  late final _perUser = TextEditingController(text: '${_old?.perUserLimit ?? 1}');
  late final _assignedTo = TextEditingController(text: _old?.assignedTo ?? '');
  late CouponType _type = _old?.type ?? CouponType.percent;
  late bool _active = _old?.active ?? true;
  late bool _firstOrderOnly = _old?.firstOrderOnly ?? false;
  late DateTime? _startsAt = _old?.startsAt;
  late DateTime? _endsAt = _old?.endsAt;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_code, _description, _value, _minSubtotal, _maxDiscount, _usageLimit, _perUser, _assignedTo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _startsAt : _endsAt) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startsAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        // لآخر اليوم المختار.
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startsAt != null && _endsAt != null && _endsAt!.isBefore(_startsAt!)) {
      _snack(context, 'تاريخ الانتهاء قبل البداية');
      return;
    }
    final coupon = Coupon(
      code: _code.text.trim().toUpperCase(),
      description: _description.text.trim(),
      type: _type,
      value: _type == CouponType.freeDelivery ? 0 : _parseInt(_value.text),
      minSubtotal: _parseInt(_minSubtotal.text),
      maxDiscount: _parseInt(_maxDiscount.text),
      usageLimit: _parseInt(_usageLimit.text),
      perUserLimit: _parseInt(_perUser.text),
      startsAt: _startsAt,
      endsAt: _endsAt,
      active: _active,
      assignedTo: _assignedTo.text.trim(),
      firstOrderOnly: _firstOrderOnly,
      usedCount: _old?.usedCount ?? 0,
    );
    setState(() => _saving = true);
    try {
      await context.read<StoreRepository>().saveCoupon(coupon, isNew: _old == null);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context, _old == null ? 'ما كدرنا نحفظ. يمكن الرمز مستعمل قبل.' : 'ما كدرنا نحفظ');
    }
  }

  String _date(DateTime? d) => d == null ? 'بدون' : '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    final isNew = _old == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'كوبون جديد' : 'تعديل ${_old.code}'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'حذف الكوبون',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving
                  ? null
                  : () => _confirmDelete(
                        context,
                        title: 'حذف الكوبون ${_old.code}؟',
                        message: 'الكوبون ما يشتغل بعد. الطلبات اللي استعملته تبقى مثل ما هي.\n'
                            'إذا تريد توقفه مؤقتاً، طفّي "شغال" بدال الحذف.',
                        delete: () => context.read<StoreRepository>().deleteCoupon(_old.code),
                      ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _code,
              enabled: isNew,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]'))],
              decoration: const InputDecoration(labelText: 'رمز الكوبون', hintText: 'EID15', helperText: 'إنكليزي وأرقام، من 3 لـ 24 حرف'),
              validator: (v) => Coupon.codePattern.hasMatch((v ?? '').trim().toUpperCase()) ? null : 'الرمز مو صحيح',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'وصف (يبين للزبون)', hintText: 'خصم العيد'),
            ),
            SegmentedButton<CouponType>(
              segments: [for (final t in CouponType.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            if (_type == CouponType.freeDelivery)
              const Text('يشيل أجور التوصيل بس، والمنتجات تبقى بسعرها. ما ينفع للاستلام من المحل.')
            else
              TextFormField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _type == CouponType.percent ? 'النسبة %' : 'المبلغ بالدينار'),
                validator: (v) {
                  final n = _parseInt(v ?? '');
                  if (n <= 0) return 'اكتب القيمة';
                  if (_type == CouponType.percent && n > 100) return 'النسبة لازم 100 أو أقل';
                  return null;
                },
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minSubtotal,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'أقل مبلغ للطلب (اختياري)'),
            ),
            if (_type == CouponType.percent) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxDiscount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'أعلى خصم بالدينار (اختياري)'),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _usageLimit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'كم مرة ينستعمل بالمجموع (فارغ = بلا حد)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _perUser,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'كم مرة لكل زبون (0 = بلا حد)', helperText: 'الزبون ينعرف بحسابه وبرقم هاتفه'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('يبدي: ${_date(_startsAt)}'),
                  onPressed: () => _pickDate(start: true),
                  onLongPress: () => setState(() => _startsAt = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: Text('ينتهي: ${_date(_endsAt)}'),
                  onPressed: () => _pickDate(start: false),
                  onLongPress: () => setState(() => _endsAt = null),
                ),
              ),
            ]),
            Text('اضغط مطول على التاريخ حتى تشيله', style: Theme.of(context).textTheme.bodySmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('لأول طلب بس'),
              value: _firstOrderOnly,
              onChanged: (v) => setState(() => _firstOrderOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('شغال'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('كوبون شخصي لزبون واحد (اختياري)'),
              children: [
                TextFormField(
                  controller: _assignedTo,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم حساب الزبون (UID)',
                    helperText: 'يبين بمحفظة هذا الزبون بس، ومحد غيره يكدر يستعمله',
                  ),
                ),
              ],
            ),
            if (!isNew)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('انستعمل ${_old.usedCount} مرة. العداد يحسبه السيرفر.'),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
        ),
      ),
    );
  }
}

// ───────────── الولاء والدعوات ─────────────

class LoyaltySettingsTab extends StatefulWidget {
  const LoyaltySettingsTab({super.key});

  @override
  State<LoyaltySettingsTab> createState() => _LoyaltySettingsTabState();
}

class _LoyaltySettingsTabState extends State<LoyaltySettingsTab> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<bool> _legacy = _repo.watchLegacyOrdersAllowed();
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  bool _enabled = true;
  bool _referralEnabled = true;
  bool _loaded = false;
  bool _saving = false;

  static const _labels = {
    'pointsPer1000': 'نقاط لكل 1,000 د.ع مدفوعة',
    'pointValue': 'قيمة النقطة بالدينار',
    'minRedeemPoints': 'أقل نقاط ينستعمل',
    'maxRedeemPercent': 'أعلى نسبة من الطلب تندفع بالنقاط %',
    'referrerPoints': 'نقاط اللي دعا صديقه',
    'refereePoints': 'نقاط الصديق الجديد',
    'referralMinTotal': 'أقل مبلغ لأول طلب حتى تنحسب الدعوة',
    'maxReferralsPerUser': 'أكثر عدد دعوات تنحسب لكل زبون',
    'referralWindowDays': 'كم يوم بعد التسجيل يكدر يحط كود صديق',
  };

  @override
  void initState() {
    super.initState();
    _repo.watchLoyalty().first.then((s) {
      if (!mounted) return;
      final map = s.toMap();
      setState(() {
        for (final key in _labels.keys) {
          _fields[key] = TextEditingController(text: '${map[key]}');
        }
        _enabled = s.enabled;
        _referralEnabled = s.referralEnabled;
        _loaded = true;
      });
    }).catchError((_) {
      if (mounted) _snack(context, 'ما كدرنا نحمل الإعدادات');
    });
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final v = {for (final e in _fields.entries) e.key: _parseInt(e.value.text)};
    final settings = LoyaltySettings.fromMap({...v, 'enabled': _enabled, 'referralEnabled': _referralEnabled});
    setState(() => _saving = true);
    try {
      await _repo.saveLoyalty(settings);
      if (mounted) _snack(context, 'انحفظت الإعدادات');
    } catch (_) {
      if (mounted) _snack(context, 'ما كدرنا نحفظ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _fields[key],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _labels[key]),
          validator: (v) {
            final n = int.tryParse((v ?? '').trim());
            if (n == null || n < 0) return 'اكتب رقم';
            if (key == 'maxRedeemPercent' && n > 100) return '100 أو أقل';
            return null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('نقاط الولاء'),
            subtitle: const Text('الزبون يكسب نقاط بعد التسليم ويستعملها خصم'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          for (final key in ['pointsPer1000', 'pointValue', 'minRedeemPoints', 'maxRedeemPercent']) _field(key),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('دعوة الأصدقاء'),
            subtitle: const Text('المكافأة بعد ما الصديق يستلم أول طلب مؤهل'),
            value: _referralEnabled,
            onChanged: (v) => setState(() => _referralEnabled = v),
          ),
          for (final key in ['referrerPoints', 'refereePoints', 'referralMinTotal', 'maxReferralsPerUser', 'referralWindowDays'])
            _field(key),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ الإعدادات')),
          const Divider(height: 32),
          StreamBuilder<bool>(
            stream: _legacy,
            builder: (context, snapshot) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('قبول طلبات النسخ القديمة من التطبيق'),
              subtitle: Text(
                'النسخ القديمة ترسل الطلب مباشرة بدون فحص الأسعار بالسيرفر وبدون نقاط. '
                'طفّيه بعد ما الزبائن يحدّثون التطبيق.',
                style: theme.textTheme.bodySmall,
              ),
              value: snapshot.data ?? true,
              onChanged: snapshot.hasData
                  ? (v) => _saveQuietly(context, _repo.setLegacyOrdersAllowed(v))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────── العروض الذكية ─────────────

/// أمثلة جاهزة من طلب صاحب المتجر: الزواج والمولود.
const exampleRules = [
  RecommendationRule(
    title: 'كمّل فرحتكم: عقود الزواج',
    triggerKeywords: ['زواج', 'عرس', 'زفاف', 'خطوبه', 'ملكه'],
    targetKeywords: ['عقد', 'عقود'],
    order: 1,
  ),
  RecommendationRule(
    title: 'هدايا استقبال المولود',
    triggerKeywords: ['مولود', 'طفل', 'بيبي', 'مواليد', 'ولاده'],
    targetKeywords: ['مولود', 'مواليد', 'بيبي', 'استقبال'],
    order: 2,
  ),
];

class RecommendationRulesTab extends StatefulWidget {
  const RecommendationRulesTab({super.key});

  @override
  State<RecommendationRulesTab> createState() => _RecommendationRulesTabState();
}

class _RecommendationRulesTabState extends State<RecommendationRulesTab> {
  late final Stream<List<RecommendationRule>> _rules =
      context.read<StoreRepository>().watchRecommendationRules(includeHidden: true);
  bool _seeding = false;

  void _edit([RecommendationRule? rule]) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecommendationRuleEditScreen(rule: rule)),
      );

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      for (final rule in exampleRules) {
        await context.read<StoreRepository>().saveRecommendationRule(rule);
      }
    } catch (_) {
      if (mounted) _snack(context, 'ما كدرنا نضيفها');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('عرض ذكي جديد'),
      ),
      body: StreamBuilder<List<RecommendationRule>>(
        stream: _rules,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyMessage(icon: Icons.error_outline, text: 'ما كدرنا نحمل العروض');
          }
          final rules = snapshot.data;
          if (rules == null) return const Center(child: CircularProgressIndicator());
          if (rules.isEmpty) {
            return EmptyMessage(
              icon: Icons.auto_awesome,
              text: 'العروض الذكية تبين للزبون منتجات تناسب اللي طلبه.\n'
                  'مثلاً: اللي يطلب بورد زواج تبينله عقود الزواج.',
              action: OutlinedButton.icon(
                onPressed: _seeding ? null : _seed,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('أضف مثال الزواج والمولود'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: rules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rules[i];
              final trigger = [...r.triggerKeywords, if (r.triggerCategoryIds.isNotEmpty) '${r.triggerCategoryIds.length} قسم'];
              final target = [...r.targetKeywords, if (r.targetCategoryIds.isNotEmpty) '${r.targetCategoryIds.length} قسم'];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => _edit(r),
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(r.title),
                  subtitle: Text('إذا طلب: ${trigger.join('، ')}\nنبينله: ${target.join('، ')}'),
                  isThreeLine: true,
                  trailing: Switch(
                    value: r.active,
                    onChanged: (v) => _saveQuietly(context, context.read<StoreRepository>().saveRecommendationRule(r.copyWith(active: v))),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RecommendationRuleEditScreen extends StatefulWidget {
  final RecommendationRule? rule;

  const RecommendationRuleEditScreen({super.key, this.rule});

  @override
  State<RecommendationRuleEditScreen> createState() => _RecommendationRuleEditScreenState();
}

class _RecommendationRuleEditScreenState extends State<RecommendationRuleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _rule = widget.rule;
  late final _title = TextEditingController(text: _rule?.title ?? '');
  late final _triggerWords = TextEditingController(text: _rule?.triggerKeywords.join('، ') ?? '');
  late final _targetWords = TextEditingController(text: _rule?.targetKeywords.join('، ') ?? '');
  late final _order = TextEditingController(text: '${_rule?.order ?? 0}');
  late final Set<String> _triggerCategories = {...?_rule?.triggerCategoryIds};
  late final Set<String> _targetCategories = {...?_rule?.targetCategoryIds};
  late bool _active = _rule?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _triggerWords, _targetWords, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  static List<String> _words(String text) =>
      text.split(RegExp(r'[,،\n]')).map((w) => w.trim()).where((w) => w.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final triggers = _words(_triggerWords.text);
    final targets = _words(_targetWords.text);
    if ((triggers.isEmpty && _triggerCategories.isEmpty) || (targets.isEmpty && _targetCategories.isEmpty)) {
      _snack(context, 'حدد شنو يطلب الزبون، وشنو نبينله');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<StoreRepository>().saveRecommendationRule(RecommendationRule(
            id: _rule?.id ?? '',
            title: _title.text.trim(),
            triggerKeywords: triggers,
            triggerCategoryIds: _triggerCategories.toList(),
            triggerProductIds: _rule?.triggerProductIds ?? const [],
            targetKeywords: targets,
            targetCategoryIds: _targetCategories.toList(),
            targetProductIds: _rule?.targetProductIds ?? const [],
            order: _parseInt(_order.text),
            active: _active,
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context, 'ما كدرنا نحفظ');
    }
  }

  Widget _categoryChips(List<Category> categories, Set<String> selected) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in categories)
            FilterChip(
              label: Text(c.name),
              selected: selected.contains(c.id),
              onSelected: (v) => setState(() => v ? selected.add(c.id) : selected.remove(c.id)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<Category>>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_rule == null ? 'عرض ذكي جديد' : 'تعديل العرض'),
        actions: [
          if (_rule != null)
            IconButton(
              tooltip: 'حذف العرض',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving
                  ? null
                  : () => _confirmDelete(
                        context,
                        title: 'حذف العرض؟',
                        message: 'راح ينحذف "${_rule.title}" وما يبين للزبائن بعد.',
                        delete: () => context.read<StoreRepository>().deleteRecommendationRule(_rule.id),
                      ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'العنوان اللي يشوفه الزبون', hintText: 'كمّل فرحتكم: عقود الزواج'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب عنوان' : null,
            ),
            const SizedBox(height: 20),
            Text('إذا الزبون طلب (أو بسلته)…', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _triggerWords,
              decoration: const InputDecoration(
                labelText: 'كلمات باسم المنتج',
                hintText: 'زواج، عرس، زفاف',
                helperText: 'افصل بفارزة. تنطبق على أي منتج اسمه بيه الكلمة',
              ),
            ),
            const SizedBox(height: 8),
            if (categories.isNotEmpty) ...[
              const Text('أو من هذني الأقسام:'),
              _categoryChips(categories, _triggerCategories),
            ],
            const SizedBox(height: 20),
            Text('…نبينله هذني المنتجات', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _targetWords,
              decoration: const InputDecoration(labelText: 'كلمات باسم المنتج', hintText: 'عقد، عقود'),
            ),
            const SizedBox(height: 8),
            if (categories.isNotEmpty) ...[
              const Text('أو من هذني الأقسام:'),
              _categoryChips(categories, _targetCategories),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _order,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الترتيب (الأصغر يبين أول)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('شغال'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
        ),
      ),
    );
  }
}

// ───────────── أجور التوصيل ─────────────

/// أجور التوصيل لكل محافظة أو قضاء. تتغير هنا وتشتغل مباشرة بدون نسخة جديدة من التطبيق.
class DeliveryFeesTab extends StatefulWidget {
  const DeliveryFeesTab({super.key});

  @override
  State<DeliveryFeesTab> createState() => _DeliveryFeesTabState();
}

class _DeliveryFeesTabState extends State<DeliveryFeesTab> {
  late final _repo = context.read<StoreRepository>();
  final _formKey = GlobalKey<FormState>();
  List<DeliveryZone>? _zones;
  final _fees = <String, TextEditingController>{};
  final _names = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repo.watchDeliveryZones().first.then(_load).catchError((_) {
      if (mounted) _snack(context, 'ما كدرنا نحمل أجور التوصيل');
    });
  }

  void _load(List<DeliveryZone> zones) {
    if (!mounted) return;
    setState(() {
      _zones = List.of(zones);
      for (final z in zones) {
        _fees[z.id] = TextEditingController(text: '${z.fee}');
        _names[z.id] = TextEditingController(text: z.name);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [..._fees.values, ..._names.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _add() {
    final id = newZoneId(_zones!);
    setState(() {
      _zones!.add(DeliveryZone(id: id, name: '', fee: 5000));
      _fees[id] = TextEditingController(text: '5000');
      _names[id] = TextEditingController();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final zones = [
      for (final z in _zones!)
        z.copyWith(name: _names[z.id]!.text.trim(), fee: int.parse(_fees[z.id]!.text.trim())),
    ];
    setState(() => _saving = true);
    try {
      await _repo.saveDeliveryZones(zones);
      if (mounted) _snack(context, 'انحفظت أجور التوصيل');
    } catch (_) {
      if (mounted) _snack(context, 'ما كدرنا نحفظ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = _zones;
    if (zones == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('حفظ أجور التوصيل'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            Text(
              'الأجور تنضاف للطلب حسب محافظة الزبون. الخصومات والنقاط ما تشملها، '
              'والاستلام من المحل بلا أجور. المنطقة الموقوفة ما تبين للزبون.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final z in zones)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _names[z.id],
                          decoration: const InputDecoration(labelText: 'المحافظة / القضاء', isDense: true),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الاسم' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _fees[z.id],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'الأجور', suffixText: 'د.ع', isDense: true),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            return n == null || n < 0 ? 'رقم' : null;
                          },
                        ),
                      ),
                      Switch(
                        value: z.active,
                        onChanged: (v) => setState(() => zones[zones.indexOf(z)] = z.copyWith(active: v)),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('أضف محافظة أو قضاء'),
            ),
          ],
        ),
      ),
    );
  }
}
