import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_repository.dart';

/// يسجل إن هذا الجهاز فتح التطبيق، مرة وحدة باليوم، حتى نحسب الزوار بالإحصائيات.
/// كل جهاز ياخذ رقم عشوائي ينحفظ بيه. ما نجمع أي معلومات شخصية.
class VisitTracker {
  static const _idKey = 'visitor_id';
  static const _dayKey = 'visitor_last_day';

  final StoreRepository repository;

  const VisitTracker(this.repository);

  /// ما يرمي أخطاء: الإحصائيات ما لازم توكف التطبيق.
  Future<void> track({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = now ?? DateTime.now();
      final today = '${date.year}-${date.month}-${date.day}';
      if (prefs.getString(_dayKey) == today) return;

      var id = prefs.getString(_idKey);
      final isNew = id == null;
      id ??= _randomId();
      await repository.recordVisit(id, isNew: isNew, platform: _platform());
      await prefs.setString(_idKey, id);
      await prefs.setString(_dayKey, today);
    } catch (_) {
      // نحاول مرة ثانية بالفتحة الجاية.
    }
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static String _platform() => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'other',
      };
}
