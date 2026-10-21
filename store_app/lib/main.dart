import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/content.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/media_uploader.dart';
import 'services/order_service.dart';
import 'services/store_repository.dart';
import 'state/cart.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(StoreApp(
    repository: FirestoreStoreRepository(),
    auth: FirebaseAuthService(),
  ));
}

class StoreApp extends StatelessWidget {
  final StoreRepository repository;
  final AuthService auth;
  final TelegramNotifier? notifier;
  final MediaUploader? uploader;
  final bool showSplash;

  const StoreApp({
    super.key,
    required this.repository,
    required this.auth,
    this.notifier,
    this.uploader,
    this.showSplash = true,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: repository),
        Provider.value(value: auth),
        Provider.value(value: notifier ?? TelegramNotifier()),
        Provider<MediaUploader>.value(value: uploader ?? SupabaseUploader()),
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
