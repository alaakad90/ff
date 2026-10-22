import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/order_service.dart';
import '../services/push_service.dart';
import '../services/store_repository.dart';
import '../state/cart.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String? _deliveryDay;
  PickupMethod _pickup = PickupMethod.delivery;
  bool _dayMissing = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// إذا الزبون مسجل دخول، نعبي معلوماته المحفوظة.
  Future<void> _prefill() async {
    final session = context.read<Session>();
    if (!session.signedIn) return;
    _name.text = session.name;
    try {
      final profile = await context.read<StoreRepository>().getProfile(session.uid);
      if (!mounted) return;
      // ما نمسح شي كتبه الزبون بينما المعلومات تتحمل.
      if (profile.name.isNotEmpty && (_name.text.isEmpty || _name.text == session.name)) {
        _name.text = profile.name;
      }
      if (_phone.text.isEmpty) _phone.text = profile.phone;
      if (_address.text.isEmpty) _address.text = profile.address;
    } catch (_) {
      // مو مشكلة، يكتبها بيده.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    setState(() => _dayMissing = _deliveryDay == null);
    if (!formOk || _deliveryDay == null) return;

    final cart = context.read<Cart>();
    final session = context.read<Session>();
    final repository = context.read<StoreRepository>();
    final notifier = context.read<OrderNotifier>();
    final push = context.read<PushService>();
    final customer = Customer(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _pickup == PickupMethod.delivery ? _address.text.trim() : '',
      notes: _notes.text.trim(),
    );
    var order = StoreOrder.fromCart(
      customer,
      cart,
      deliveryDay: _deliveryDay!,
      pickupMethod: _pickup,
      userId: session.signedIn ? session.uid : '',
    );

    setState(() => _sending = true);
    // نطلب إذن الإشعارات هنا حتى نبلغ الزبون بحالة طلبه.
    order = order.copyWithPushToken(await push.deviceToken());
    try {
      final id = await repository.placeOrder(order).timeout(const Duration(seconds: 20));
      order = order.copyWith(id: id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ما كدرنا نرسل الطلب. تأكد من الإنترنت وحاول مرة ثانية.'),
      ));
      return;
    }
    notifier.notify(order);
    if (session.signedIn) {
      repository
          .saveProfile(
            session.uid,
            UserProfile(
              name: customer.name,
              phone: customer.phone,
              address: _address.text.trim(),
            ),
          )
          .catchError((_) {});
    }
    if (!mounted) return;

    setState(() => _sending = false);
    cart.clear();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, size: 48, color: Colors.green),
        title: const Text('وصلنا طلبك'),
        content: Text(
          'راح نتصل بيك قريباً حتى نأكد الطلب.\nيوم التسليم: ${order.deliveryDay}',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('إكمال الطلب')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب اسمك' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                hintText: '07XXXXXXXXX',
                prefixIcon: Icon(Icons.phone),
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 10 ? 'اكتب رقم هاتف صحيح' : null;
              },
            ),
            const SizedBox(height: 20),
            Text('طريقة الاستلام', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<PickupMethod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: PickupMethod.delivery,
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('توصيل'),
                ),
                ButtonSegment(
                  value: PickupMethod.pickup,
                  icon: Icon(Icons.storefront_outlined),
                  label: Text('استلام من المحل'),
                ),
              ],
              selected: {_pickup},
              onSelectionChanged: (s) => setState(() => _pickup = s.first),
            ),
            if (_pickup == PickupMethod.delivery) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  hintText: 'المحافظة، المنطقة، أقرب نقطة دالة',
                  prefixIcon: Icon(Icons.location_on),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب العنوان' : null,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              _pickup == PickupMethod.delivery ? 'يوم التسليم' : 'يوم الاستلام',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in weekDays)
                  ChoiceChip(
                    label: Text(day),
                    selected: _deliveryDay == day,
                    onSelected: (_) => setState(() {
                      _deliveryDay = day;
                      _dayMissing = false;
                    }),
                  ),
              ],
            ),
            if (_dayMissing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'اختار يوم',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.note_alt_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final item in cart.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text('${item.product.name} × ${item.quantity}${item.note.isEmpty ? '' : '\n📝 ${item.note}'}${item.imageUrl.isEmpty ? '' : '\n🖼️ صورة'}${item.voiceUrl.isEmpty ? '' : '\n🎤 فويس'}')),
                            Text(formatPrice(item.total)),
                          ],
                        ),
                      ),
                    const Divider(),
                    Row(
                      children: [
                        Text('المجموع', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Text(
                          formatPrice(cart.total),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.payments_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('الدفع عند الاستلام'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _sending || cart.isEmpty ? null : _submit,
            child: _sending
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('أرسل الطلب'),
          ),
        ),
      ),
    );
  }
}
