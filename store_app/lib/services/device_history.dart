import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// طلب زائر محفوظ على هذا الجهاز حتى يتابعه بدون حساب.
class GuestOrderRef {
  final String id;
  final String key; // مفتاح المتابعة من السيرفر

  const GuestOrderRef(this.id, this.key);
}

/// اللي ينحفظ على الجهاز نفسه: طلبات الزائر، والمنتجات اللي انطلبت منه (للعروض الذكية).
abstract class DeviceHistory {
  Future<List<GuestOrderRef>> guestOrders();
  Future<void> addGuestOrder(String id, String key);
  Future<List<String>> purchasedProductIds();
  Future<void> addPurchased(Iterable<String> productIds);
}

class PrefsDeviceHistory implements DeviceHistory {
  static const _ordersKey = 'guest_orders';
  static const _productsKey = 'purchased_products';
  static const _maxOrders = 20;
  static const _maxProducts = 50;

  const PrefsDeviceHistory();

  @override
  Future<List<GuestOrderRef>> guestOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final raw in prefs.getStringList(_ordersKey) ?? const <String>[])
          if (jsonDecode(raw) case {'id': final String id, 'key': final String key}) GuestOrderRef(id, key),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addGuestOrder(String id, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_ordersKey) ?? <String>[];
      list.insert(0, jsonEncode({'id': id, 'key': key}));
      await prefs.setStringList(_ordersKey, list.take(_maxOrders).toList());
    } catch (_) {}
  }

  @override
  Future<List<String>> purchasedProductIds() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_productsKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addPurchased(Iterable<String> productIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getStringList(_productsKey) ?? const <String>[];
      final fresh = productIds.where((id) => id.isNotEmpty).toList();
      final merged = [...fresh, ...old.where((id) => !fresh.contains(id))];
      await prefs.setStringList(_productsKey, merged.take(_maxProducts).toList());
    } catch (_) {}
  }
}

/// نسخة بالذاكرة للاختبارات.
class MemoryDeviceHistory implements DeviceHistory {
  final orders = <GuestOrderRef>[];
  final products = <String>[];

  @override
  Future<List<GuestOrderRef>> guestOrders() async => List.of(orders);

  @override
  Future<void> addGuestOrder(String id, String key) async => orders.insert(0, GuestOrderRef(id, key));

  @override
  Future<List<String>> purchasedProductIds() async => List.of(products);

  @override
  Future<void> addPurchased(Iterable<String> productIds) async {
    for (final id in productIds) {
      products.remove(id);
      products.insert(0, id);
    }
  }
}
