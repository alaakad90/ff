import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/content.dart';
import '../models/order.dart';
import '../models/product.dart';

/// كل التعامل مع قاعدة البيانات يمر من هنا.
abstract class StoreRepository {
  /// [includeHidden] للوحة التحكم: يرجع حتى المخفي.
  Stream<List<Product>> watchProducts({bool includeHidden = false});
  Future<void> saveProduct(Product product); // id فارغ = منتج جديد
  Future<void> deleteProduct(String id);

  Stream<List<Category>> watchCategories();
  Future<void> saveCategory(Category category);
  Future<void> deleteCategory(String id);

  Stream<List<PromoBanner>> watchBanners({bool includeHidden = false});
  Future<void> saveBanner(PromoBanner banner);
  Future<void> deleteBanner(String id);

  Stream<List<Reel>> watchReels({bool includeHidden = false});
  Future<void> saveReel(Reel reel);
  Future<void> deleteReel(String id);

  Stream<StoreInfo> watchStoreInfo();
  Future<void> saveStoreInfo(StoreInfo info);

  Future<String> placeOrder(StoreOrder order);
  Stream<List<StoreOrder>> watchOrders();
  Stream<List<StoreOrder>> watchUserOrders(String userId);
  Future<void> setOrderStatus(String id, OrderStatus status);

  Future<UserProfile> getProfile(String userId);
  Future<void> saveProfile(String userId, UserProfile profile);
}

List<Product> _sortProducts(Iterable<Product> items) =>
    items.toList()..sort((a, b) => a.name.compareTo(b.name));

List<T> _sortByOrder<T>(Iterable<T> items, int Function(T) order) =>
    items.toList()..sort((a, b) => order(a).compareTo(order(b)));

List<StoreOrder> _newestFirst(Iterable<StoreOrder> orders) => orders.toList()
  ..sort((a, b) => (b.createdAt ?? DateTime(2100)).compareTo(a.createdAt ?? DateTime(2100)));

StoreOrder _orderFromMap(String id, Map<String, dynamic> data) => StoreOrder(
      id: id,
      customer: Customer.fromMap(Map<String, dynamic>.from(data['customer'] as Map? ?? {})),
      items: (data['items'] as List? ?? [])
          .map((i) => OrderItem.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList(),
      total: (data['total'] as num?)?.toInt() ?? 0,
      deliveryDay: data['deliveryDay'] as String? ?? '',
      pickupMethod: PickupMethod.fromValue(data['pickupMethod'] as String?),
      userId: data['userId'] as String? ?? '',
      status: OrderStatus.fromValue(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );

class FirestoreStoreRepository implements StoreRepository {
  final FirebaseFirestore _db;

  FirestoreStoreRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String name) => _db.collection(name);

  Stream<List<T>> _watch<T>(
    String collection,
    T Function(String id, Map<String, dynamic> data) fromMap, {
    bool activeOnly = false,
  }) {
    Query<Map<String, dynamic>> query = _col(collection);
    if (activeOnly) query = query.where('active', isEqualTo: true);
    return query.snapshots().map((s) => s.docs.map((d) => fromMap(d.id, d.data())).toList());
  }

  Future<void> _save(String collection, String id, Map<String, dynamic> data) async {
    if (id.isEmpty) {
      await _col(collection).add(data);
    } else {
      await _col(collection).doc(id).set(data);
    }
  }

  @override
  Stream<List<Product>> watchProducts({bool includeHidden = false}) {
    Query<Map<String, dynamic>> query = _col('products');
    if (!includeHidden) query = query.where('available', isEqualTo: true);
    return query
        .snapshots()
        .map((s) => _sortProducts(s.docs.map((d) => Product.fromMap(d.id, d.data()))));
  }

  @override
  Future<void> saveProduct(Product p) => _save('products', p.id, p.toMap());

  @override
  Future<void> deleteProduct(String id) => _col('products').doc(id).delete();

  @override
  Stream<List<Category>> watchCategories() =>
      _watch('categories', Category.fromMap).map((l) => _sortByOrder(l, (c) => c.order));

  @override
  Future<void> saveCategory(Category c) => _save('categories', c.id, c.toMap());

  @override
  Future<void> deleteCategory(String id) => _col('categories').doc(id).delete();

  @override
  Stream<List<PromoBanner>> watchBanners({bool includeHidden = false}) =>
      _watch('banners', PromoBanner.fromMap, activeOnly: !includeHidden)
          .map((l) => _sortByOrder(l, (b) => b.order));

  @override
  Future<void> saveBanner(PromoBanner b) => _save('banners', b.id, b.toMap());

  @override
  Future<void> deleteBanner(String id) => _col('banners').doc(id).delete();

  @override
  Stream<List<Reel>> watchReels({bool includeHidden = false}) =>
      _watch('reels', Reel.fromMap, activeOnly: !includeHidden)
          .map((l) => _sortByOrder(l, (r) => r.order));

  @override
  Future<void> saveReel(Reel r) => _save('reels', r.id, r.toMap());

  @override
  Future<void> deleteReel(String id) => _col('reels').doc(id).delete();

  @override
  Stream<StoreInfo> watchStoreInfo() => _col('settings')
      .doc('store')
      .snapshots()
      .map((d) => StoreInfo.fromMap(d.data() ?? const {}));

  @override
  Future<void> saveStoreInfo(StoreInfo info) => _col('settings').doc('store').set(info.toMap());

  @override
  Future<String> placeOrder(StoreOrder order) async {
    final data = {
      'customer': order.customer.toMap(),
      'items': order.items.map((i) => i.toMap()).toList(),
      'total': order.total,
      'deliveryDay': order.deliveryDay,
      'pickupMethod': order.pickupMethod.value,
      if (order.userId.isNotEmpty) 'userId': order.userId,
      'status': OrderStatus.pending.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final doc = await _col('orders').add({
        ...data,
        if (order.pushToken.isNotEmpty) 'pushToken': order.pushToken,
      });
      return doc.id;
    } on FirebaseException catch (e) {
      // إذا قواعد Firestore بعدها القديمة (ما تعرف pushToken)، الطلب يوصل بدون إشعارات.
      if (e.code != 'permission-denied' || order.pushToken.isEmpty) rethrow;
      final doc = await _col('orders').add(data);
      return doc.id;
    }
  }

  @override
  Stream<List<StoreOrder>> watchOrders() => _col('orders')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map((d) => _orderFromMap(d.id, d.data())).toList());

  // بدون orderBy حتى ما نحتاج index مركب. نرتبها بالتطبيق.
  @override
  Stream<List<StoreOrder>> watchUserOrders(String userId) => _col('orders')
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((s) => _newestFirst(s.docs.map((d) => _orderFromMap(d.id, d.data()))));

  @override
  Future<void> setOrderStatus(String id, OrderStatus status) =>
      _col('orders').doc(id).update({'status': status.value});

  @override
  Future<UserProfile> getProfile(String userId) async {
    final doc = await _col('users').doc(userId).get();
    return UserProfile.fromMap(doc.data() ?? const {});
  }

  @override
  Future<void> saveProfile(String userId, UserProfile profile) =>
      _col('users').doc(userId).set(profile.toMap());
}

/// نسخة بالذاكرة للاختبارات.
class InMemoryStoreRepository implements StoreRepository {
  final _products = <String, Product>{};
  final _categories = <String, Category>{};
  final _banners = <String, PromoBanner>{};
  final _reels = <String, Reel>{};
  final _orders = <String, StoreOrder>{};
  final _profiles = <String, UserProfile>{};
  var _info = const StoreInfo();
  final _changes = StreamController<void>.broadcast();
  var _nextId = 1;

  InMemoryStoreRepository({
    Iterable<Product> products = const [],
    Iterable<Category> categories = const [],
    Iterable<PromoBanner> banners = const [],
    StoreInfo info = const StoreInfo(),
  }) {
    for (final p in products) {
      final id = p.id.isEmpty ? _newId('p') : p.id;
      _products[id] = p.copyWith(id: id);
    }
    for (final c in categories) {
      final id = c.id.isEmpty ? _newId('c') : c.id;
      _categories[id] = c.withId(id);
    }
    for (final b in banners) {
      final id = b.id.isEmpty ? _newId('b') : b.id;
      _banners[id] = b.copyWith(id: id);
    }
    _info = info;
  }

  String _newId(String prefix) => '$prefix${_nextId++}';

  List<StoreOrder> get orders => _orders.values.toList();
  Map<String, UserProfile> get profiles => _profiles;

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  Future<void> _changed() async => _changes.add(null);

  @override
  Stream<List<Product>> watchProducts({bool includeHidden = false}) =>
      _watch(() => _sortProducts(_products.values.where((p) => includeHidden || p.available)));

  @override
  Future<void> saveProduct(Product p) {
    final id = p.id.isEmpty ? _newId('p') : p.id;
    _products[id] = p.copyWith(id: id);
    return _changed();
  }

  @override
  Future<void> deleteProduct(String id) {
    _products.remove(id);
    return _changed();
  }

  @override
  Stream<List<Category>> watchCategories() =>
      _watch(() => _sortByOrder(_categories.values, (c) => c.order));

  @override
  Future<void> saveCategory(Category c) {
    final id = c.id.isEmpty ? _newId('c') : c.id;
    _categories[id] = c.withId(id);
    return _changed();
  }

  @override
  Future<void> deleteCategory(String id) {
    _categories.remove(id);
    return _changed();
  }

  @override
  Stream<List<PromoBanner>> watchBanners({bool includeHidden = false}) => _watch(
      () => _sortByOrder(_banners.values.where((b) => includeHidden || b.active), (b) => b.order));

  @override
  Future<void> saveBanner(PromoBanner b) {
    final id = b.id.isEmpty ? _newId('b') : b.id;
    _banners[id] = b.copyWith(id: id);
    return _changed();
  }

  @override
  Future<void> deleteBanner(String id) {
    _banners.remove(id);
    return _changed();
  }

  @override
  Stream<List<Reel>> watchReels({bool includeHidden = false}) => _watch(
      () => _sortByOrder(_reels.values.where((r) => includeHidden || r.active), (r) => r.order));

  @override
  Future<void> saveReel(Reel r) {
    final id = r.id.isEmpty ? _newId('r') : r.id;
    _reels[id] = r.copyWith(id: id);
    return _changed();
  }

  @override
  Future<void> deleteReel(String id) {
    _reels.remove(id);
    return _changed();
  }

  @override
  Stream<StoreInfo> watchStoreInfo() => _watch(() => _info);

  @override
  Future<void> saveStoreInfo(StoreInfo info) {
    _info = info;
    return _changed();
  }

  @override
  Future<String> placeOrder(StoreOrder order) async {
    final id = _newId('o');
    _orders[id] = order.copyWith(id: id, createdAt: DateTime.now());
    await _changed();
    return id;
  }

  @override
  Stream<List<StoreOrder>> watchOrders() => _watch(() => _newestFirst(_orders.values));

  @override
  Stream<List<StoreOrder>> watchUserOrders(String userId) =>
      _watch(() => _newestFirst(_orders.values.where((o) => o.userId == userId)));

  @override
  Future<void> setOrderStatus(String id, OrderStatus status) {
    _orders[id] = _orders[id]!.copyWith(status: status);
    return _changed();
  }

  @override
  Future<UserProfile> getProfile(String userId) async => _profiles[userId] ?? const UserProfile();

  @override
  Future<void> saveProfile(String userId, UserProfile profile) async =>
      _profiles[userId] = profile;
}
