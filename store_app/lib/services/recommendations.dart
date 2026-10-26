import '../models/loyalty.dart';
import '../models/product.dart';

/// مجموعة اقتراحات بعنوان، مثل "كمّل فرحتكم: عقود الزواج".
class RecommendationGroup {
  final String title;
  final List<Product> products;

  const RecommendationGroup(this.title, this.products);
}

/// يوحّد الكتابة العربية حتى "زواج" تطابق "الزواج" و"أ/إ/آ" تطابق "ا"، "ة" تطابق "ه"، "ى" تطابق "ي".
String normalizeArabic(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[ً-ْـ]'), '') // التشكيل والتطويل
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .trim();

bool _hasKeyword(Product product, List<String> keywords) {
  if (keywords.isEmpty) return false;
  final name = normalizeArabic('${product.name} ${product.description}');
  return keywords.map(normalizeArabic).where((k) => k.isNotEmpty).any(name.contains);
}

bool _matchesTrigger(RecommendationRule rule, Product product) =>
    rule.triggerProductIds.contains(product.id) ||
    rule.triggerCategoryIds.contains(product.categoryId) ||
    _hasKeyword(product, rule.triggerKeywords);

bool _matchesTarget(RecommendationRule rule, Product product) =>
    rule.targetProductIds.contains(product.id) ||
    rule.targetCategoryIds.contains(product.categoryId) ||
    _hasKeyword(product, rule.targetKeywords);

/// العروض الذكية حسب مشتريات الزبون وسلته.
///
/// [basis]: المنتجات اللي طلبها الزبون أو بسلته، الأحدث أول.
/// القواعد اللي يحطها صاحب المتجر تتقدم (مثل: بورد زواج ← عقود الزواج).
/// إذا ماكو قاعدة تنطبق، نقترح منتجات ثانية من نفس أقسام اللي طلبه.
/// ما نقترح شي بالسلة أو انطلب قبل، ولا شي مخفي.
List<RecommendationGroup> recommend({
  required List<Product> catalog,
  required List<RecommendationRule> rules,
  required List<Product> basis,
  Set<String> exclude = const {},
  int perGroup = 8,
  int maxGroups = 3,
}) {
  if (basis.isEmpty) return const [];
  final skip = {...exclude, ...basis.map((p) => p.id)};
  final available = catalog.where((p) => p.available && !skip.contains(p.id)).toList();
  final groups = <RecommendationGroup>[];
  final shown = <String>{};

  final active = rules.where((r) => r.active).toList()..sort((a, b) => a.order.compareTo(b.order));
  for (final rule in active) {
    if (groups.length >= maxGroups) break;
    if (!basis.any((p) => _matchesTrigger(rule, p))) continue;
    final picks = available.where((p) => !shown.contains(p.id) && _matchesTarget(rule, p)).take(perGroup).toList();
    if (picks.isEmpty) continue;
    shown.addAll(picks.map((p) => p.id));
    groups.add(RecommendationGroup(rule.title.isEmpty ? 'مقترحة لك' : rule.title, picks));
  }

  if (groups.isEmpty) {
    final categories = basis.map((p) => p.categoryId).where((c) => c.isNotEmpty).toSet();
    final picks = available.where((p) => categories.contains(p.categoryId)).take(perGroup).toList();
    if (picks.isNotEmpty) groups.add(RecommendationGroup('مقترحة لك', picks));
  }
  return groups;
}
