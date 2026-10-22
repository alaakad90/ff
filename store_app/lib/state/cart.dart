import 'package:flutter/foundation.dart';

import '../models/product.dart';

class CartItem {
  final Product product;
  final String note; // ملاحظة الزبون على هذا المنتج (اختياري)
  int quantity;

  CartItem(this.product, this.quantity, {this.note = ''});

  /// نفس المنتج بملاحظتين مختلفتين يكونن سطرين بالسلة.
  String get key => itemKey(product, note);

  static String itemKey(Product product, String note) => '${product.id}\n$note';

  int get total => product.price * quantity;
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

  void add(Product product, [int quantity = 1, String note = '']) {
    note = note.trim();
    final key = CartItem.itemKey(product, note);
    final item = _items[key];
    if (item == null) {
      _items[key] = CartItem(product, quantity, note: note);
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
