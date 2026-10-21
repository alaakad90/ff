import 'package:flutter/foundation.dart';

import '../models/product.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem(this.product, this.quantity);

  int get total => product.price * quantity;
}

class Cart extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();

  int get count => _items.values.fold(0, (sum, item) => sum + item.quantity);

  int get total => _items.values.fold(0, (sum, item) => sum + item.total);

  bool get isEmpty => _items.isEmpty;

  int quantityOf(Product product) => _items[product.id]?.quantity ?? 0;

  void add(Product product, [int quantity = 1]) {
    final item = _items[product.id];
    if (item == null) {
      _items[product.id] = CartItem(product, quantity);
    } else {
      item.quantity += quantity;
    }
    notifyListeners();
  }

  void decrement(Product product) {
    final item = _items[product.id];
    if (item == null) return;
    if (item.quantity <= 1) {
      _items.remove(product.id);
    } else {
      item.quantity--;
    }
    notifyListeners();
  }

  void remove(Product product) {
    _items.remove(product.id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
