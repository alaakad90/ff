import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/loyalty.dart';
import '../../models/product.dart';
import '../../services/contact.dart';
import '../../services/store_api.dart';
import '../../services/store_repository.dart';
import 'my_orders_screen.dart';

/// محفظة الزبون: النقاط وقيمتها، الكوبونات الخاصة بيه، دعوة الأصدقاء، وحركات النقاط.
class WalletScreen extends StatefulWidget {
  final String userId;

  const WalletScreen({super.key, required this.userId});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<Wallet> _wallet = _repo.watchWallet(widget.userId);
  late final Stream<LoyaltySettings> _settings = _repo.watchLoyalty();
  late final Stream<List<LedgerEntry>> _ledger = _repo.watchLedger(widget.userId);
  late final Stream<List<Coupon>> _coupons = _repo.watchMyCoupons(widget.userId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('محفظتي')),
      body: StreamBuilder<LoyaltySettings>(
        stream: _settings,
        builder: (context, settingsSnap) {
          final settings = settingsSnap.data ?? const LoyaltySettings();
          return StreamBuilder<Wallet>(
            stream: _wallet,
            builder: (context, walletSnap) {
              final wallet = walletSnap.data ?? const Wallet();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (settings.enabled)
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          const Icon(Icons.stars, size: 40),
                          const SizedBox(height: 8),
                          Text('${wallet.points}',
                              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text('نقطة • قيمتها ${formatPrice(settings.valueOf(wallet.points))}'),
                          const SizedBox(height: 8),
                          Text(
                            'تكسب ${settings.pointsPer1000} نقطة لكل 1,000 د.ع بعد ما تستلم طلبك، '
                            'وتستعملها خصم بإكمال الطلب (من ${settings.minRedeemPoints} نقطة).',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ]),
                      ),
                    ),
                  StreamBuilder<List<Coupon>>(
                    stream: _coupons,
                    builder: (context, snapshot) {
                      final now = DateTime.now();
                      final coupons = (snapshot.data ?? const <Coupon>[])
                          .where((c) => c.active && !c.isExpired(now) && (c.usageLimit == 0 || c.usedCount < c.usageLimit))
                          .toList();
                      if (coupons.isEmpty) return const SizedBox.shrink();
                      return _Section(
                        title: 'كوبوناتي',
                        child: Column(children: [
                          for (final c in coupons)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.local_offer_outlined),
                              title: Text('${c.code} • ${c.valueLabel}'),
                              subtitle: Text([
                                if (c.description.isNotEmpty) c.description,
                                if (c.minSubtotal > 0) 'للطلبات من ${formatPrice(c.minSubtotal)}',
                                if (c.endsAt != null) 'لحد ${formatOrderDate(c.endsAt)}',
                              ].join(' • ')),
                              trailing: IconButton(
                                tooltip: 'انسخ',
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copy(context, c.code),
                              ),
                            ),
                        ]),
                      );
                    },
                  ),
                  if (settings.referralEnabled) _ReferralSection(userId: widget.userId, wallet: wallet, settings: settings),
                  StreamBuilder<List<LedgerEntry>>(
                    stream: _ledger,
                    builder: (context, snapshot) {
                      final entries = snapshot.data ?? const <LedgerEntry>[];
                      if (entries.isEmpty) return const SizedBox.shrink();
                      return _Section(
                        title: 'حركات النقاط',
                        child: Column(children: [
                          for (final e in entries)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(e.points >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                                  color: e.points >= 0 ? Colors.green.shade700 : theme.colorScheme.error),
                              title: Text(e.note.isEmpty ? e.type : e.note),
                              subtitle: Text(formatOrderDate(e.createdAt)),
                              trailing: Text(e.points >= 0 ? '+${e.points}' : '${e.points}',
                                  style: theme.textTheme.titleMedium),
                            ),
                        ]),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('انسخ: $text')));
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}

/// دعوة الأصدقاء: كود الزبون ومشاركته، وإضافة كود صديق (للجدد قبل أول طلب).
class _ReferralSection extends StatefulWidget {
  final String userId;
  final Wallet wallet;
  final LoyaltySettings settings;

  const _ReferralSection({required this.userId, required this.wallet, required this.settings});

  @override
  State<_ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends State<_ReferralSection> {
  late final _repo = context.read<StoreRepository>();
  late final Stream<Referral?> _myReferral = _repo.watchReferral(widget.userId);
  late final Stream<List<Referral>> _invites = _repo.watchInvites(widget.userId);
  final _friendCode = TextEditingController();
  String _code = '';
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _friendCode.dispose();
    super.dispose();
  }

  Future<void> _getCode() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final code = await context.read<StoreApi>().referralCode();
      if (mounted) setState(() => _code = code);
    } on StoreApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final code = _friendCode.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await context.read<StoreApi>().applyReferral(code);
      if (!mounted) return;
      _friendCode.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('انضاف كود صديقك. من تستلم أول طلب (من ${formatPrice(widget.settings.referralMinTotal)}) '
            'تاخذ ${widget.settings.refereePoints} نقطة هدية'),
      ));
    } on StoreApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final code = _code.isNotEmpty ? _code : widget.wallet.referralCode;
    final shareText = 'جرب متجر لاكاسا للهدايا والتحف 🎁 حط كود الدعوة $code بحسابك وتاخذ '
        '${settings.refereePoints} نقطة هدية بعد أول طلب: https://lacasastores.com';
    return _Section(
      title: 'ادعُ صديق',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('من يستلم صديقك أول طلب (من ${formatPrice(settings.referralMinTotal)})، '
            'تاخذ ${settings.referrerPoints} نقطة وهو ياخذ ${settings.refereePoints} نقطة.'),
        const SizedBox(height: 12),
        if (code.isEmpty)
          OutlinedButton.icon(
            onPressed: _busy ? null : _getCode,
            icon: const Icon(Icons.card_giftcard),
            label: const Text('اعرض كود الدعوة مالتي'),
          )
        else
          Row(children: [
            Expanded(
              child: SelectableText(code,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 2)),
            ),
            IconButton(tooltip: 'انسخ', icon: const Icon(Icons.copy), onPressed: () => _copy(context, code)),
            IconButton(
              tooltip: 'شارك بالواتساب',
              icon: const Icon(Icons.share),
              onPressed: () => openLink(Uri.https('wa.me', '/', {'text': shareText}).toString()),
            ),
          ]),
        StreamBuilder<List<Referral>>(
          stream: _invites,
          builder: (context, snapshot) {
            final invites = snapshot.data ?? const <Referral>[];
            if (invites.isEmpty) return const SizedBox.shrink();
            final rewarded = invites.where((r) => r.status == 'rewarded').length;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('أصدقاء استعملوا كودك: ${invites.length} • انحسبوا: $rewarded'),
            );
          },
        ),
        StreamBuilder<Referral?>(
          stream: _myReferral,
          builder: (context, snapshot) {
            final mine = snapshot.data;
            if (mine != null) {
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(mine.status == 'pending'
                    ? '✔️ حاطّ كود صديق. الهدية توصلك بعد أول طلب.'
                    : '✔️ وصلتك هدية الدعوة.'),
              );
            }
            if (widget.wallet.ordersPlaced > 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: _friendCode,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'عندك كود من صديق؟', hintText: 'LCXXXXXX'),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  // الزر بالثيم ياخذ عرض الشاشة كله؛ هنا جنب الحقل فنحدد عرضه.
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 52)),
                    onPressed: _busy ? null : _apply,
                    child: const Text('أضف'),
                  ),
                ),
              ]),
            );
          },
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ]),
    );
  }
}
