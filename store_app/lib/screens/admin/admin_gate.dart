import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import 'admin_home.dart';

/// يقرر شنو يبين: تسجيل الدخول، أو "مو مدير"، أو لوحة التحكم.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  late final Stream<AdminSession> _session = context.read<AuthService>().watchSession();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminSession>(
      stream: _session,
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return switch (session.status) {
          AdminStatus.signedOut => const _LoginScreen(),
          AdminStatus.notAdmin => _NotAdminScreen(session: session),
          AdminStatus.admin => AdminHome(session: session),
        };
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signIn(_email.text.trim(), _password.text);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دخول صاحب المتجر')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'الإيميل', prefixIcon: Icon(Icons.email)),
              validator: (v) => (v == null || !v.contains('@')) ? 'اكتب الإيميل' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'الباسورد', prefixIcon: Icon(Icons.lock)),
              validator: (v) => (v == null || v.isEmpty) ? 'اكتب الباسورد' : null,
              onFieldSubmitted: (_) => _signIn(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _signIn,
              child: _loading
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('دخول'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotAdminScreen extends StatelessWidget {
  final AdminSession session;

  const _NotAdminScreen({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(Icons.lock_person_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'الحساب ${session.email} مو مسجل كمدير',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'حتى تفعّله: افتح Firestore بموقع Firebase، وسوي collection بأسم admins، '
            'وضيف بيه document رقمه (Document ID) هو الرمز اللي جوه.',
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: SelectableText(session.uid, textDirection: TextDirection.ltr),
              trailing: IconButton(
                tooltip: 'نسخ',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: session.uid));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('انسخ الرمز')));
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('بعدها اطلع وارجع ادخل.'),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.read<AuthService>().signOut(),
            child: const Text('تسجيل خروج'),
          ),
        ],
      ),
    );
  }
}
