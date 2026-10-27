import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/delivery.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/device_history.dart';
import '../services/order_service.dart';
import '../services/push_service.dart';
import '../services/store_api.dart';
import '../services/store_repository.dart';
import '../state/cart.dart';

/// إكمال الطلب. [items] للطلب السريع (منتج واحد أو إعادة طلب) بدون ما نلمس السلة؛
/// إذا null ناخذ السلة.
class CheckoutScreen extends StatefulWidget {
  final List<CartItem>? items;

  const CheckoutScreen({super.key, this.items});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _couponField = TextEditingController();
  String? _deliveryDay;
  PickupMethod _pickup = PickupMethod.delivery;
  // المحافظة: أجور التوصيل حسبها (من لوحة التحكم).
  late final Stream<List<DeliveryZone>> _zones = context.read<StoreRepository>().watchDeliveryZones();
  DeliveryZone? _zone;
  bool _zoneMissing = false;
  bool _dayMissing = false;
  bool _sending = false;

  // الحساب من السيرفر (إذا موجود).
  late final StoreApi _api = context.read<StoreApi>();
  // رقم الطلب يبقى نفسه لكل المحاولات، حتى إذا الزبون ضغط مرتين ما يتكرر الطلب.
  final _requestId = newRequestId();
  String _coupon = '';
  bool _usePoints = false;
  OrderQuote? _quote;
  bool _quoting = false;
  String _quoteError = '';
  int _quoteGeneration = 0;

  bool get _quickOrder => widget.items != null;

  List<CartItem> _items(BuildContext context) => widget.items ?? context.read<Cart>().items;

  @override
  void initState() {
    super.initState();
    _prefill();
    if (_api.enabled) WidgetsBinding.instance.addPostFrameCallback((_) => _refreshQuote());
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
    _couponField.dispose();
    super.dispose();
  }

  /// يحسب السعر بالسيرفر: الأسعار الحالية والكوبون والنقاط.
  Future<void> _refreshQuote() async {
    if (_items(context).isEmpty) return;
    final generation = ++_quoteGeneration;
    setState(() {
      _quoting = true;
      _quoteError = '';
    });
    final lines = _items(context).map(OrderLine.fromCartItem).toList();
    // الهاتف حتى السيرفر يتأكد إن الكوبون ما انستعمل بنفس الرقم.
    final phone = _phone.text.trim();
    final customer = phone.isEmpty ? null : Customer(name: '-', phone: phone);
    OrderRequest request({int points = 0}) => OrderRequest(
          lines: lines,
          coupon: _coupon,
          points: points,
          customer: customer,
          pickupMethod: _pickup,
          zoneId: _zone?.id ?? '',
        );
    try {
      var quote = await _api.quote(request());
      if (_usePoints && quote.maxPoints > 0) {
        // نطلب أكثر نقاط مسموحة، والسيرفر يحسب الخصم.
        quote = await _api.quote(request(points: quote.maxPoints));
      }
      if (!mounted || generation != _quoteGeneration) return;
      setState(() {
        _quote = quote;
        if (quote.maxPoints == 0) _usePoints = false;
      });
    } on StoreApiException catch (e) {
      if (mounted && generation == _quoteGeneration) setState(() => _quoteError = e.message);
    } finally {
      if (mounted && generation == _quoteGeneration) setState(() => _quoting = false);
    }
  }

  void _setPickup(PickupMethod pickup) {
    setState(() => _pickup = pickup);
    if (_api.enabled) _refreshQuote();
  }

  /// قائمة المحافظات وأجور التوصيل لكل وحدة.
  Future<void> _pickZone(List<DeliveryZone> zones) async {
    final picked = await showModalBottomSheet<DeliveryZone>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('اختار محافظتك', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final zone in zones.where((z) => z.active))
              ListTile(
                leading: Icon(zone.id == _zone?.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(zone.name),
                trailing: Text('التوصيل ${formatPrice(zone.fee)}'),
                onTap: () => Navigator.of(context).pop(zone),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _zone = picked;
      _zoneMissing = false;
    });
    if (_api.enabled) _refreshQuote();
  }

  void _applyCoupon() {
    final code = _couponField.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _coupon = code);
    _refreshQuote();
  }

  void _removeCoupon() {
    _couponField.clear();
    setState(() => _coupon = '');
    _refreshQuote();
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    final needsZone = _pickup == PickupMethod.delivery && _zone == null;
    setState(() {
      _dayMissing = _deliveryDay == null;
      _zoneMissing = needsZone;
    });
    if (!formOk || _deliveryDay == null || needsZone) return;

    final quote = _quote;
    if (_api.enabled && (quote == null || quote.unavailable.isNotEmpty || quote.couponError.isNotEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(quote == null
            ? 'لحظة، دا نحسب السعر'
            : quote.unavailable.isNotEmpty
                ? 'شيل المنتجات اللي ما متوفرة أول'
                : 'الكوبون مو صالح، شيله أو غيّره'),
      ));
      if (quote == null) _refreshQuote();
      return;
    }

    final items = _items(context);
    final cart = context.read<Cart>();
    final session = context.read<Session>();
    final repository = context.read<StoreRepository>();
    final notifier = context.read<OrderNotifier>();
    final push = context.read<PushService>();
    final history = context.read<DeviceHistory>();
    final customer = Customer(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _pickup == PickupMethod.delivery ? _address.text.trim() : '',
      notes: _notes.text.trim(),
    );

    setState(() => _sending = true);
    // نطلب إذن الإشعارات هنا حتى نبلغ الزبون بحالة طلبه.
    final pushToken = await push.deviceToken();
    String orderId;
    var total = 0;
    var discount = 0;
    try {
      if (_api.enabled) {
        final placed = await _api.placeOrder(OrderRequest(
          requestId: _requestId,
          lines: items.map(OrderLine.fromCartItem).toList(),
          customer: customer,
          deliveryDay: _deliveryDay!,
          pickupMethod: _pickup,
          zoneId: _zone?.id ?? '',
          coupon: _coupon,
          points: _usePoints ? quote!.points : 0,
          expectedTotal: quote!.total,
          pushToken: pushToken,
        ));
        orderId = placed.orderId;
        total = placed.total;
        discount = placed.discount;
        if (!session.signedIn && placed.trackingKey.isNotEmpty) {
          history.addGuestOrder(placed.orderId, placed.trackingKey);
        }
      } else {
        // بدون سيرفر (نسخة تجريبية): الطريقة القديمة بدون خصومات. المحافظة تنكتب بالعنوان
        // وأجورها تنضاف للمجموع (الطلب المباشر ما يقبل حقول جديدة).
        final fee = _pickup == PickupMethod.delivery ? _zone!.fee : 0;
        final order = StoreOrder(
          customer: _pickup == PickupMethod.delivery
              ? Customer(
                  name: customer.name,
                  phone: customer.phone,
                  address: '${_zone!.name}، ${customer.address}',
                  notes: customer.notes,
                )
              : customer,
          items: items.map(OrderItem.fromCartItem).toList(),
          total: items.fold(0, (sum, item) => sum + item.total) + fee,
          deliveryDay: _deliveryDay!,
          pickupMethod: _pickup,
          userId: session.signedIn ? session.uid : '',
          pushToken: pushToken,
        );
        orderId = await repository.placeOrder(order).timeout(const Duration(seconds: 20));
        total = order.total;
        notifier.notify(order.copyWith(id: orderId));
      }
    } on StoreApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (e.quote != null) _quote = e.quote;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      if (e.quote == null && e.code != 'network') _refreshQuote();
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ما كدرنا نرسل الطلب. تأكد من الإنترنت وحاول مرة ثانية.'),
      ));
      return;
    }
    history.addPurchased(items.map((i) => i.product.id));
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
    if (!_quickOrder) cart.clear();
    final earn = quote?.pointsToEarn ?? 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, size: 48, color: Colors.green),
        title: const Text('وصلنا طلبك'),
        content: Text(
          [
            'راح نتصل بيك قريباً حتى نأكد الطلب.',
            'يوم التسليم: $_deliveryDay',
            if (discount > 0) 'وفّرت ${formatPrice(discount)} • المجموع ${formatPrice(total)}',
            if (earn > 0) 'راح تكسب $earn نقطة بعد ما تستلم الطلب ⭐',
            if (!session.signedIn && _api.enabled) 'تكدر تتابع طلبك من الحساب ← تتبع طلباتي',
          ].join('\n'),
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
    final items = widget.items ?? context.watch<Cart>().items;
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final quote = _quote;
    final localSubtotal = items.fold(0, (sum, item) => sum + item.total);
    final localFee = _pickup == PickupMethod.delivery ? (_zone?.fee ?? 0) : 0;
    // التوصيل: من السيرفر إذا موجود (مع كوبون التوصيل المجاني)، وإلا من قائمة المحافظات.
    final deliveryCharged = quote?.deliveryCharged ?? localFee;
    final serverPrice = {for (final l in quote?.items ?? const <QuoteLine>[]) l.productId: l.price};

    return Scaffold(
      appBar: AppBar(title: Text(_quickOrder ? 'طلب سريع' : 'إكمال الطلب')),
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
              onSelectionChanged: (s) => _setPickup(s.first),
            ),
            if (_pickup == PickupMethod.delivery) ...[
              const SizedBox(height: 12),
              StreamBuilder<List<DeliveryZone>>(
                stream: _zones,
                builder: (context, snapshot) {
                  final zones = snapshot.data ?? defaultDeliveryZones;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickZone(zones),
                    child: InputDecorator(
                      isEmpty: _zone == null,
                      decoration: InputDecoration(
                        labelText: 'المحافظة',
                        hintText: 'اختار محافظتك',
                        prefixIcon: const Icon(Icons.map_outlined),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        errorText: _zoneMissing ? 'اختار المحافظة' : null,
                      ),
                      child: _zone == null
                          ? null
                          : Text('${_zone!.name} • التوصيل ${formatPrice(_zone!.fee)}'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                textInputAction: TextInputAction.next,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'الحي والمنطقة وتفاصيل العنوان',
                  hintText: 'الحي، المنطقة، الشارع، أقرب نقطة دالة',
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
            if (_api.enabled) ...[
              const SizedBox(height: 20),
              _CouponField(
                controller: _couponField,
                applied: _coupon,
                error: quote?.couponError ?? '',
                busy: _quoting,
                onApply: _applyCoupon,
                onRemove: _removeCoupon,
              ),
              if (session.signedIn && quote != null && quote.maxPoints > 0)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.stars_outlined),
                  title: Text('استعمل نقاطك (عندك ${quote.balance})'),
                  subtitle: Text(_usePoints && quote.points > 0
                      ? '${quote.points} نقطة = خصم ${formatPrice(quote.pointsAmount)}'
                      : 'تكدر تستعمل لحد ${quote.maxPoints} نقطة على هذا الطلب'),
                  value: _usePoints,
                  onChanged: _quoting
                      ? null
                      : (v) {
                          setState(() => _usePoints = v);
                          _refreshQuote();
                        },
                ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text('${item.product.name} × ${item.quantity}${item.note.isEmpty ? '' : '\n📝 ${item.note}'}${item.imageUrl.isEmpty ? '' : '\n🖼️ صورة'}${item.voiceUrl.isEmpty ? '' : '\n🎤 فويس'}')),
                            if (serverPrice[item.product.id] case final price? when price != item.product.price)
                              Text(
                                '${formatPrice(price * item.quantity)}\n(السعر تحدّث)',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: theme.colorScheme.secondary),
                              )
                            else
                              Text(formatPrice(item.total)),
                          ],
                        ),
                      ),
                    if (quote != null && quote.unavailable.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'ما متوفر هسه: ${quote.unavailable.join('، ')}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    const Divider(),
                    _AmountRow(label: 'المنتجات', amount: quote?.subtotal ?? localSubtotal),
                    if (quote != null && quote.couponAmount > 0 && !quote.freeDelivery)
                      _AmountRow(label: 'كوبون ${quote.couponCode}', amount: -quote.couponAmount),
                    if (quote != null && quote.pointsAmount > 0)
                      _AmountRow(label: '${quote.points} نقطة', amount: -quote.pointsAmount),
                    // أجور التوصيل ثابتة: الخصم والنقاط ما يشملوها.
                    Row(children: [
                      const Expanded(child: Text('أجور التوصيل')),
                      Text(
                        _pickup == PickupMethod.pickup
                            ? formatPrice(0)
                            : _zone == null
                                ? 'اختار المحافظة'
                                : quote != null && quote.freeDelivery
                                    ? 'مجاني (كوبون ${quote.couponCode})'
                                    : formatPrice(deliveryCharged),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('المجموع', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        if (_quoting)
                          const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          Text(
                            formatPrice(quote?.total ?? localSubtotal + localFee),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                      ],
                    ),
                    if (quote != null && quote.pointsToEarn > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          const Icon(Icons.star_outline, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text('تكسب ${quote.pointsToEarn} نقطة بعد الاستلام')),
                        ]),
                      ),
                    if (_quoteError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Expanded(child: Text(_quoteError, style: TextStyle(color: theme.colorScheme.error))),
                          TextButton(onPressed: _refreshQuote, child: const Text('أعد المحاولة')),
                        ]),
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
            onPressed: _sending || items.isEmpty ? null : _submit,
            child: _sending
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('أرسل الطلب'),
          ),
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final int amount;

  const _AmountRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label)),
        Text(amount < 0 ? '- ${formatPrice(-amount)}' : formatPrice(amount)),
      ]);
}

class _CouponField extends StatelessWidget {
  final TextEditingController controller;
  final String applied;
  final String error;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  const _CouponField({
    required this.controller,
    required this.applied,
    required this.error,
    required this.busy,
    required this.onApply,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (applied.isNotEmpty && error.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(
          avatar: const Icon(Icons.local_offer_outlined),
          label: Text('كوبون $applied'),
          onDeleted: busy ? null : onRemove,
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'كوبون خصم (اختياري)',
              prefixIcon: const Icon(Icons.local_offer_outlined),
              errorText: error.isEmpty ? null : error,
            ),
            onSubmitted: (_) => onApply(),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton(onPressed: busy ? null : onApply, child: const Text('طبّق')),
        ),
      ],
    );
  }
}
