import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order.dart';
import '../models/product.dart';

/// كل التعامل مع قاعدة البيانات يمر من هنا.
abstract class StoreRepository {
  /// المنتجات المتوفرة للزبون. [includeHidden] للوحة التحكم.
  Stream<List<Product>> watchProducts({bool includeHidden = false});

  /// إذا id فارغ ينضاف منتج جديد، وإلا ينعدل.
  Future<void> saveProduct(Product product);

  Future<void> deleteProduct(String id);

  Future<String> placeOrder(StoreOrder order);

  Stream<List<StoreOrder>> watchOrders();

  Future<void> setOrderStatus(String id, OrderStatus status);
}

List<Product> _sortProducts(Iterable<Product> products) =>
    products.toList()..sort((a, b) => a.name.compareTo(b.name));

class FirestoreStoreRepository implements StoreRepository {
  final FirebaseFirestore _db;

  FirestoreStoreRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _products => _db.collection('products');
  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');

  @override
  Stream<List<Product>> watchProducts({bool includeHidden = false}) {
    final query = includeHidden ? _products : _products.where('available', isEqualTo: true);
    return query.snapshots().map(
          (snap) => _sortProducts(snap.docs.map((d) => Product.fromMap(d.id, d.data()))),
        );
  }

  @override
  Future<void> saveProduct(Product product) async {
    if (product.id.isEmpty) {
      await _products.add(product.toMap());
    } else {
      await _products.doc(product.id).set(product.toMap());
    }
  }

  @override
  Future<void> deleteProduct(String id) => _products.doc(id).delete();

  @override
  Future<String> placeOrder(StoreOrder order) async {
    final doc = await _orders.add({
      'customer': order.customer.toMap(),
      'items': order.items.map((i) => i.toMap()).toList(),
      'total': order.total,
      'status': OrderStatus.pending.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  @override
  Stream<List<StoreOrder>> watchOrders() {
    return _orders.orderBy('createdAt', descending: true).limit(200).snapshots().map(
          (snap) => snap.docs.map((d) {
            final data = d.data();
            return StoreOrder(
              id: d.id,
              customer: Customer.fromMap(Map<String, dynamic>.from(data['customer'] as Map? ?? {})),
              items: (data['items'] as List? ?? [])
                  .map((i) => OrderItem.fromMap(Map<String, dynamic>.from(i as Map)))
                  .toList(),
              total: (data['total'] as num?)?.toInt() ?? 0,
              status: OrderStatus.fromValue(data['status'] as String?),
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
            );
          }).toList(),
        );
  }

  @override
  Future<void> setOrderStatus(String id, OrderStatus status) =>
      _orders.doc(id).update({'status': status.value});
}

/// نسخة بالذاكرة للاختبارات.
class InMemoryStoreRepository implements StoreRepository {
  final _products = <String, Product>{};
  final _orders = <String, StoreOrder>{};
  final _changes = StreamController<void>.broadcast();
  var _nextId = 1;

  InMemoryStoreRepository({Iterable<Product> products = const []}) {
    for (final p in products) {
      final id = p.id.isEmpty ? 'p${_nextId++}' : p.id;
      _products[id] = p.copyWith(id: id);
    }
  }

  List<StoreOrder> get orders => _orders.values.toList();

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<Product>> watchProducts({bool includeHidden = false}) => _watch(
        () => _sortProducts(_products.values.where((p) => includeHidden || p.available)),
      );

  @override
  Future<void> saveProduct(Product product) async {
    final id = product.id.isEmpty ? 'p${_nextId++}' : product.id;
    _products[id] = product.copyWith(id: id);
    _changes.add(null);
  }

  @override
  Future<void> deleteProduct(String id) async {
    _products.remove(id);
    _changes.add(null);
  }

  @override
  Future<String> placeOrder(StoreOrder order) async {
    final id = 'o${_nextId++}';
    _orders[id] = order.copyWith(id: id, createdAt: DateTime.now());
    _changes.add(null);
    return id;
  }

  @override
  Stream<List<StoreOrder>> watchOrders() => _watch(() => _orders.values.toList().reversed.toList());

  @override
  Future<void> setOrderStatus(String id, OrderStatus status) async {
    _orders[id] = _orders[id]!.copyWith(status: status);
    _changes.add(null);
  }
}
