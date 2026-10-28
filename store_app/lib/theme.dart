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

// الوضع الليلي: خلفية فحمي، والبطاقات أفتح شوية، والأحمر نفسه.
const _darkBackground = Color(0xFF141416);
const _darkCard = Color(0xFF1F1F23);
const _darkText = Color(0xFFF2F2F2);

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final dark = brightness == Brightness.dark;
  final background = dark ? _darkBackground : brandCream;
  final card = dark ? _darkCard : Colors.white;
  final text = dark ? _darkText : brandBlack;
  // حدود خفيفة: أسود على الفاتح، أبيض على الداكن.
  Color line(double alpha) => (dark ? Colors.white : Colors.black).withValues(alpha: alpha);
  final colors = ColorScheme.fromSeed(
    seedColor: brandRed,
    brightness: brightness,
    // الأزرار الأساسية: أسود بالفاتح، وأبيض بالداكن.
    primary: text,
    onPrimary: dark ? brandBlack : Colors.white,
    secondary: brandRed,
    onSecondary: Colors.white,
    secondaryContainer: dark ? const Color(0xFF5A1A1A) : const Color(0xFFFDE4E2),
    onSecondaryContainer: dark ? const Color(0xFFFFDAD6) : const Color(0xFF7A1212),
    surface: background,
    onSurface: text,
  );

  final font = appFontFamily;
  return ThemeData(
    brightness: brightness,
    colorScheme: colors,
    fontFamily: font,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: text,
        fontFamily: font,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: line(0.06)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line(0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line(0.12)),
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
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontFamily: font,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? brandRed : text,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? brandRed : text,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: colors.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
