import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/content.dart';
import '../../services/auth_service.dart';
import '../../services/store_repository.dart';
import '../../state/theme_settings.dart';
import '../../widgets/brand_logo.dart';
import '../about_screen.dart';
import '../admin/admin_home.dart';
import 'guest_orders_screen.dart';
import 'my_orders_screen.dart';
import 'wallet_screen.dart';

/// تبويب الحساب. إذا اللي داخل مدير، تنفتح لوحة التحكم مباشرة.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return switch (session.role) {
      Role.admin => AdminHome(session: session),
      Role.customer => _CustomerAccount(session: session),
      Role.guest => const _GuestAccount(),
    };
  }
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

class _GuestAccount extends StatelessWidget {
  const _GuestAccount();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AuthForm(),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ThemeModeTile(settings: context.read<ThemeSettings>()),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('تتبع طلباتي'),
                  subtitle: const Text('الطلبات اللي سويتها من هذا الجهاز بدون حساب'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _push(context, const GuestOrdersScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('عن المتجر'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _push(context, const AboutScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerAccount extends StatelessWidget {
  final Session session;

  const _CustomerAccount({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = session.name.isEmpty ? 'أهلاً بيك' : session.name;
    return Scaffold(
      appBar: AppBar(title: const Text('الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                child: Text(
                  name.characters.first,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    Text(session.email, style: theme.textTheme.bodyMedium, textDirection: TextDirection.ltr),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('طلباتي'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _push(context, MyOrdersScreen(userId: session.uid)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('محفظتي ونقاطي'),
                  subtitle: const Text('النقاط، كوبوناتي، وادعُ صديق'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _push(context, WalletScreen(userId: session.uid)),
                ),
                const Divider(height: 1),
                ThemeModeTile(settings: context.read<ThemeSettings>()),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('معلوماتي'),
                  subtitle: const Text('الاسم والهاتف والعنوان للطلبات'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _push(context, ProfileScreen(userId: session.uid)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('عن المتجر'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _push(context, const AboutScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل خروج'),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('حذف الحساب'),
            onPressed: () => _deleteAccount(context, session),
          ),
        ],
      ),
    );
  }
}

/// يسأل الزبون يتأكد، وإذا داخل بالباسورد ياخذه منه، وبعدها يحذف الحساب.
Future<void> _deleteAccount(BuildContext context, Session session) async {
  // null يعني الزبون رجع بدون ما يحذف.
  final password = await showDialog<String>(
    context: context,
    builder: (_) => _DeleteAccountDialog(askPassword: session.usesPassword),
  );
  if (password == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final done = await context.read<AuthService>().deleteAccount(password: session.usesPassword ? password : null);
    if (done) messenger.showSnackBar(const SnackBar(content: Text('انحذف حسابك')));
  } on AuthException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('ما كدرنا نحذف الحساب. حاول مرة ثانية.')));
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  final bool askPassword;

  const _DeleteAccountDialog({required this.askPassword});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'راح ينحذف حسابك ومعلوماتك المحفوظة (الاسم والهاتف والعنوان)، وما تكدر ترجعها.\n'
              'الطلبات اللي سويتها تبقى عند المتجر حتى نكمل توصيلها وحساباتنا.',
            ),
            if (widget.askPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'اكتب الباسورد حتى نتأكد'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لا')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, _password.text),
            child: const Text('احذف'),
          ),
        ],
      );
}

/// تسجيل دخول أو حساب جديد.
class AuthForm extends StatefulWidget {
  const AuthForm({super.key});

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final repo = context.read<StoreRepository>();
    final email = _email.text.trim();
    _run(() async {
      if (_signUp) {
        final name = _name.text.trim();
        final uid = await auth.signUp(name, email, _password.text);
        await repo.saveProfile(uid, UserProfile(name: name)).catchError((_) {});
      } else {
        await auth.signIn(email, _password.text);
      }
    });
  }

  void _google() {
    final auth = context.read<AuthService>();
    final repo = context.read<StoreRepository>();
    _run(() async {
      if (!await auth.signInWithGoogle()) return;
      // نحفظ الاسم أول مرة حتى يتعبى بإكمال الطلب.
      final session = await auth.watchSession().firstWhere((s) => s.signedIn);
      final profile = await repo.getProfile(session.uid).catchError((_) => const UserProfile());
      if (profile.name.isEmpty && session.name.isNotEmpty) {
        await repo
            .saveProfile(
              session.uid,
              UserProfile(name: session.name, phone: profile.phone, address: profile.address),
            )
            .catchError((_) {});
      }
    });
  }

  void _apple() {
    final auth = context.read<AuthService>();
    final repo = context.read<StoreRepository>();
    _run(() async {
      if (!await auth.signInWithApple()) return;
      final session = await auth.watchSession().firstWhere((s) => s.signedIn);
      final profile = await repo.getProfile(session.uid).catchError((_) => const UserProfile());
      if (profile.name.isEmpty && session.name.isNotEmpty) {
        await repo
            .saveProfile(session.uid, UserProfile(name: session.name, phone: profile.phone, address: profile.address))
            .catchError((_) {});
      }
    });
  }

  void _resetPassword() {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'اكتب إيميلك بالأول، وبعدها اضغط "نسيت الباسورد"');
      return;
    }
    _run(() async {
      await context.read<AuthService>().sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('دزينا رابط تغيير الباسورد على $email')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.read<AuthService>();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandLogo(height: 72),
          const SizedBox(height: 16),
          Text(
            _signUp ? 'سوي حساب حتى تتابع طلباتك' : 'سجل دخول حتى تتابع طلباتك',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('تسجيل دخول')),
              ButtonSegment(value: true, label: Text('حساب جديد')),
            ],
            selected: {_signUp},
            onSelectionChanged: (s) => setState(() {
              _signUp = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_signUp) ...[
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب اسمك' : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'الإيميل', prefixIcon: Icon(Icons.email_outlined)),
            validator: (v) => (v == null || !v.contains('@')) ? 'اكتب الإيميل' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            textDirection: TextDirection.ltr,
            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'الباسورد',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'إخفاء' : 'إظهار',
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'اكتب الباسورد';
              if (_signUp && v.length < 6) return 'الباسورد لازم 6 أحرف أو أكثر';
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_signUp ? 'سوي الحساب' : 'دخول'),
          ),
          if (!_signUp)
            TextButton(
              onPressed: _loading ? null : _resetPassword,
              child: const Text('نسيت الباسورد؟'),
            ),
          if (auth.supportsGoogle || auth.supportsApple) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('أو', style: theme.textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 2),
          ],
          if (auth.supportsGoogle) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: Colors.white,
              ),
              onPressed: _loading ? null : _google,
              icon: const _GoogleMark(),
              label: const Text('المتابعة بحساب Google'),
            ),
          ],
          if (auth.supportsApple) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              onPressed: _loading ? null : _apple,
              icon: const Icon(Icons.apple, size: 24),
              label: const Text('المتابعة بحساب Apple'),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF4285F4),
        fontFamily: 'Roboto',
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<StoreRepository>().getProfile(widget.userId).then((p) {
      if (!mounted) return;
      setState(() {
        _name.text = p.name;
        _phone.text = p.phone;
        _address.text = p.address;
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<StoreRepository>().saveProfile(
            widget.userId,
            UserProfile(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              address: _address.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ما كدرنا نحفظ المعلومات')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معلوماتي')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب اسمك' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      hintText: '07XXXXXXXXX',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'العنوان',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _loading || _saving ? null : _save,
            child: const Text('حفظ'),
          ),
        ),
      ),
    );
  }
}
