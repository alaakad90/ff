import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مظهر التطبيق اللي يختاره الزبون: حسب النظام، نهاري، أو ليلي. ينحفظ على الجهاز.
class ThemeSettings extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode;

  ThemeSettings([this._mode = ThemeMode.system]);

  ThemeMode get mode => _mode;

  /// يقرا الاختيار المحفوظ. ما يرمي أخطاء: إذا ما كدر يبقى "حسب النظام".
  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null && mode != _mode) {
        _mode = mode;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {}
  }
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'حسب النظام',
      ThemeMode.light => 'نهاري',
      ThemeMode.dark => 'ليلي',
    };

IconData themeModeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };

/// يختار المظهر من قائمة.
Future<void> pickThemeMode(BuildContext context, ThemeSettings settings) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<ThemeMode>(
          groupValue: settings.mode,
          onChanged: (mode) {
            if (mode != null) settings.setMode(mode);
            Navigator.of(context).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المظهر', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final mode in ThemeMode.values)
                RadioListTile<ThemeMode>(
                  value: mode,
                  secondary: Icon(themeModeIcon(mode)),
                  title: Text(themeModeLabel(mode)),
                ),
            ],
          ),
        ),
      ),
    );

/// زر "المظهر" بصفحة الحساب.
class ThemeModeTile extends StatelessWidget {
  final ThemeSettings settings;

  const ThemeModeTile({super.key, required this.settings});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListTile(
          leading: Icon(themeModeIcon(settings.mode)),
          title: const Text('المظهر'),
          subtitle: Text(themeModeLabel(settings.mode)),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => pickThemeMode(context, settings),
        ),
      );
}
