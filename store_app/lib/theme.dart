import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ألوان مأخوذة من شعار La Casa 3D: أسود، أحمر، وأبيض.
// الخلفية أبيض دافي مريح للعين بدال الأبيض الصافي.
const brandBlack = Color(0xFF1C1C1E);
const brandRed = Color(0xFFD32F2F);
const brandCream = Color(0xFFF7F5F2);

/// بالآيفون نستخدم خط النظام (SF Arabic). بالأندرويد ما مسموح نضيف خط
/// Apple، فنستخدم IBM Plex Sans Arabic لأنه قريب منه وواضح.
String? get appFontFamily =>
    defaultTargetPlatform == TargetPlatform.iOS ? null : 'IBMPlexSansArabic';

ThemeData buildTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: brandRed,
    primary: brandBlack,
    onPrimary: Colors.white,
    secondary: brandRed,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFDE4E2),
    onSecondaryContainer: const Color(0xFF7A1212),
    surface: brandCream,
    onSurface: brandBlack,
  );

  final font = appFontFamily;
  return ThemeData(
    colorScheme: colors,
    fontFamily: font,
    scaffoldBackgroundColor: brandCream,
    appBarTheme: AppBarTheme(
      backgroundColor: brandCream,
      foregroundColor: brandBlack,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: brandBlack,
        fontFamily: font,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: font),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontFamily: font,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? brandRed : brandBlack,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? brandRed : brandBlack,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: colors.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
