import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/order_service.dart';
import 'services/store_repository.dart';
import 'state/cart.dart';

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

  const StoreApp({super.key, required this.repository, required this.auth, this.notifier});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF8E4A5C));

    return MultiProvider(
      providers: [
        Provider.value(value: repository),
        Provider.value(value: auth),
        Provider.value(value: notifier ?? TelegramNotifier()),
        ChangeNotifierProvider(create: (_) => Cart()),
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
        theme: ThemeData(
          colorScheme: colorScheme,
          fontFamily: 'Amiri',
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontSize: 18, fontFamily: 'Amiri'),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
