import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/content.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/media_uploader.dart';
import 'services/note_attachments.dart';
import 'services/order_service.dart';
import 'services/push_service.dart';
import 'services/store_repository.dart';
import 'services/visit_tracker.dart';
import 'state/cart.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // التليفون يعرض الإشعار بنفسه إذا التطبيق مسدود. إذا مفتوح، نعرضه جوة الشاشة.
  FirebaseMessaging.onMessage.listen((message) {
    final n = message.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text([n.title, n.body].whereType<String>().join('\n')),
    ));
  });
  final repository = FirestoreStoreRepository();
  final auth = FirebaseAuthService();
  // للإحصائيات: الزوار والحسابات المسجلة.
  VisitTracker(repository).track();
  auth.watchSession().listen((session) {
    if (session.signedIn) repository.recordMember(session.uid).catchError((_) {});
  });
  runApp(StoreApp(repository: repository, auth: auth));
}

final messengerKey = GlobalKey<ScaffoldMessengerState>();

class StoreApp extends StatelessWidget {
  final StoreRepository repository;
  final AuthService auth;
  final OrderNotifier? notifier;
  final MediaUploader? uploader;
  final PushService? push;
  final NoteAttachments? attachments;
  final bool showSplash;

  const StoreApp({
    super.key,
    required this.repository,
    required this.auth,
    this.notifier,
    this.uploader,
    this.push,
    this.attachments,
    this.showSplash = true,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: repository),
        Provider.value(value: auth),
        Provider.value(value: notifier ?? OrderNotifier()),
        Provider<MediaUploader>.value(value: uploader ?? SupabaseUploader()),
        Provider.value(value: push ?? const PushService()),
        Provider<NoteAttachments>.value(value: attachments ?? SupabaseNoteAttachments()),
        ChangeNotifierProvider(create: (_) => Cart()),
        StreamProvider<Session>(
          create: (_) => auth.watchSession(),
          initialData: Session.guest,
          catchError: (_, _) => Session.guest,
        ),
        // الأقسام ومعلومات المتجر تنحتاج بأكثر من صفحة، فنحملها مرة وحدة.
        StreamProvider<List<Category>>(
          create: (_) => repository.watchCategories(),
          initialData: const [],
          catchError: (_, _) => const [],
        ),
        StreamProvider<StoreInfo>(
          create: (_) => repository.watchStoreInfo(),
          initialData: const StoreInfo(),
          catchError: (_, _) => const StoreInfo(),
        ),
      ],
      child: MaterialApp(
        title: 'متجر لاكاسا',
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar', 'IQ'),
        supportedLocales: const [Locale('ar', 'IQ')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(),
        home: showSplash ? const SplashScreen(next: AppShell()) : const AppShell(),
      ),
    );
  }
}
