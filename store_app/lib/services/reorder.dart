import '../models/order.dart';
import '../models/product.dart';
import '../state/cart.dart';

enum ReorderChange { same, cheaper, pricier, unavailable }

/// سطر من طلب قديم مقارنةً بالمنتج هسه.
class ReorderLine {
  final OrderItem item;
  final Product? product; // null إذا المنتج انحذف

  const ReorderLine(this.item, this.product);

  ReorderChange get change {
    final p = product;
    if (p == null || !p.available || p.price <= 0 || !optionsStillValid(p, item.options)) {
      return ReorderChange.unavailable;
    }
    if (p.price < item.price) return ReorderChange.cheaper;
    if (p.price > item.price) return ReorderChange.pricier;
    return ReorderChange.same;
  }

  bool get available => change != ReorderChange.unavailable;

  int get currentTotal => available ? product!.price * item.quantity : 0;
}

/// يقارن الطلب القديم بالمنتجات الحالية: الأسعار الجديدة والمنتجات اللي ما بقت متوفرة.
List<ReorderLine> planReorder(StoreOrder order, List<Product> current) {
  final byId = {for (final p in current) p.id: p};
  return [for (final item in order.items) ReorderLine(item, byId[item.productId])];
}

/// سطور السلة للمنتجات المتوفرة، بالسعر الحالي ونفس الملاحظات والمرفقات.
List<CartItem> reorderCartItems(List<ReorderLine> lines) => [
      for (final line in lines)
        if (line.available)
          CartItem(line.product!, line.item.quantity,
              note: line.item.note,
              imageUrl: line.item.imageUrl,
              voiceUrl: line.item.voiceUrl,
              options: line.item.options),
    ];

/// الاختيارات القديمة بعدها موجودة بالمنتج، والحقول الإجبارية كلها مختارة.
bool optionsStillValid(Product product, Map<String, String> chosen) {
  for (final e in chosen.entries) {
    final field = product.options.where((o) => o.name == e.key).firstOrNull;
    if (field == null || !field.choices.contains(e.value)) return false;
  }
  return product.options.every((o) => !o.required || chosen.containsKey(o.name));
}
