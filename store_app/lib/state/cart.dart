import 'package:flutter/foundation.dart';

import '../models/product.dart';

class CartItem {
  final Product product;
  final String note; // ملاحظة الزبون على هذا المنتج (اختياري)
  final String imageUrl; // صورة يرفقها الزبون ويا الملاحظة (اختياري)
  final String voiceUrl; // فويس يرفقه الزبون ويا الملاحظة (اختياري)
  final Map<String, String> options; // اختيارات الزبون، مثل {اللون: أحمر}
  int quantity;

  CartItem(this.product, this.quantity,
      {this.note = '', this.imageUrl = '', this.voiceUrl = '', this.options = const {}});

  /// نفس المنتج بملاحظتين (أو مرفقات أو اختيارات) مختلفة يكونن سطرين بالسلة.
  String get key => itemKey(product, note, imageUrl, voiceUrl, options);

  static String itemKey(Product product, String note,
          [String imageUrl = '', String voiceUrl = '', Map<String, String> options = const {}]) =>
      '${product.id}\n$note\n$imageUrl\n$voiceUrl\n${optionsLabel(options)}';

  /// سعر القطعة ويا زيادات الاختيارات.
  int get unitPrice => product.priceWith(options);

  int get total => unitPrice * quantity;
}

class Cart extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();

  int get count => _items.values.fold(0, (sum, item) => sum + item.quantity);

  int get total => _items.values.fold(0, (sum, item) => sum + item.total);

  bool get isEmpty => _items.isEmpty;

  /// الكمية بالسلة من هذا المنتج، بكل الملاحظات.
  int quantityOf(Product product) =>
      _items.values.where((item) => item.product.id == product.id).fold(0, (sum, item) => sum + item.quantity);

  void add(Product product,
      [int quantity = 1,
      String note = '',
      String imageUrl = '',
      String voiceUrl = '',
      Map<String, String> options = const {}]) {
    note = note.trim();
    final key = CartItem.itemKey(product, note, imageUrl, voiceUrl, options);
    final item = _items[key];
    if (item == null) {
      _items[key] =
          CartItem(product, quantity, note: note, imageUrl: imageUrl, voiceUrl: voiceUrl, options: options);
    } else {
      item.quantity += quantity;
    }
    notifyListeners();
  }

  void increment(CartItem item) {
    final existing = _items[item.key];
    if (existing == null) return;
    existing.quantity++;
    notifyListeners();
  }

  void decrement(CartItem item) {
    final existing = _items[item.key];
    if (existing == null) return;
    if (existing.quantity <= 1) {
      _items.remove(item.key);
    } else {
      existing.quantity--;
    }
    notifyListeners();
  }

  void remove(CartItem item) {
    _items.remove(item.key);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
