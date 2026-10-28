import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/content.dart';
import '../models/delivery.dart';
import '../models/loyalty.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/stats.dart';

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
  Future<void> deleteOrder(String id);

  Future<UserProfile> getProfile(String userId);
  Future<void> saveProfile(String userId, UserProfile profile);

  /// إحصائيات: كل جهاز يفتح التطبيق يتسجل مرة باليوم، وكل حساب يتسجل أول ما يدخل.
  Future<void> recordVisit(String deviceId, {required bool isNew, required String platform});
  Future<void> recordMember(String userId);
  Future<VisitorStats> loadVisitorStats(DateTime now);

  /// موبايلات صاحب المتجر، حتى يوصلها إشعار من يجي طلب جديد.
  Future<void> registerAdminDevice(String userId, String token);

  /// المنتجات بأرقامها (حتى المخفية)، لإعادة الطلب: الأسعار الحالية والتوفر.
  Future<List<Product>> getProducts(Iterable<String> ids);

  /// طلبات من تاريخ معين (للتقارير).
  Stream<List<StoreOrder>> watchOrdersSince(DateTime from);

  // ───── الولاء ─────
  Stream<LoyaltySettings> watchLoyalty();
  Future<void> saveLoyalty(LoyaltySettings settings);

  /// هل الطلب المباشر من النسخ القديمة مسموح (settings/orders).
  Stream<bool> watchLegacyOrdersAllowed();
  Future<void> setLegacyOrdersAllowed(bool allowed);

  Stream<Wallet> watchWallet(String userId);
  Stream<List<LedgerEntry>> watchLedger(String userId);
  Stream<List<Coupon>> watchMyCoupons(String userId);
  Stream<Referral?> watchReferral(String userId);
  Stream<List<Referral>> watchInvites(String userId);

  /// المدير: كل الكوبونات. ما نحذف كوبونات، بس نوقفها (حتى تبقى بالتقارير).
  Stream<List<Coupon>> watchCoupons();
  Future<void> saveCoupon(Coupon coupon, {required bool isNew});
  Future<void> deleteCoupon(String code);

  Stream<List<RecommendationRule>> watchRecommendationRules({bool includeHidden = false});
  Future<void> saveRecommendationRule(RecommendationRule rule);
  Future<void> deleteRecommendationRule(String id);

  /// أجور التوصيل لكل محافظة/قضاء (الافتراضي إذا ما محفوظة).
  Stream<List<DeliveryZone>> watchDeliveryZones();
  Future<void> saveDeliveryZones(List<DeliveryZone> zones);
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
      subtotal: (data['subtotal'] as num?)?.toInt(),
      couponCode: (data['coupon'] as Map?)?['code'] as String? ?? '',
      couponAmount: ((data['coupon'] as Map?)?['amount'] as num?)?.toInt() ?? 0,
      pointsUsed: (data['pointsUsed'] as num?)?.toInt() ?? 0,
      pointsDiscount: (data['pointsDiscount'] as num?)?.toInt() ?? 0,
      pointsEarned: (data['pointsEarned'] as num?)?.toInt() ?? 0,
      statusHistory: [
        for (final e in data['statusHistory'] as List? ?? const [])
          if (e is Map)
            StatusEvent(OrderStatus.fromValue(e['status'] as String?), (e['at'] as Timestamp?)?.toDate()),
      ],
      pricedByServer: data['pricedBy'] == 'server',
      deliveryFee: (data['deliveryFee'] as num?)?.toInt() ?? 0,
      deliveryZone: (data['deliveryZone'] as Map?)?['name'] as String? ?? '',
      freeDelivery: (data['coupon'] as Map?)?['freeDelivery'] == true,
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
  Future<void> deleteOrder(String id) => _col('orders').doc(id).delete();

  @override
  Future<UserProfile> getProfile(String userId) async {
    final doc = await _col('users').doc(userId).get();
    return UserProfile.fromMap(doc.data() ?? const {});
  }

  @override
  Future<void> saveProfile(String userId, UserProfile profile) =>
      _col('users').doc(userId).set(profile.toMap(), SetOptions(merge: true));

  @override
  Future<void> recordVisit(String deviceId, {required bool isNew, required String platform}) async {
    final doc = _col('devices').doc(deviceId);
    if (!isNew) {
      try {
        await doc.update({'lastSeen': FieldValue.serverTimestamp()});
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow;
      }
    }
    await doc.set({
      'firstSeen': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
      'platform': platform,
    });
  }

  @override
  Future<void> recordMember(String userId) async {
    final doc = _col('users').doc(userId);
    final snap = await doc.get();
    if (snap.data()?['joinedAt'] != null) return;
    await doc.set({'joinedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  @override
  Future<VisitorStats> loadVisitorStats(DateTime now) async {
    final today = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
    final week = Timestamp.fromDate(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)));
    final devices = _col('devices');
    final counts = await Future.wait([
      devices.count().get(),
      devices.where('lastSeen', isGreaterThanOrEqualTo: today).count().get(),
      devices.where('lastSeen', isGreaterThanOrEqualTo: week).count().get(),
      _col('users').where('joinedAt', isNull: false).count().get(),
    ]);
    return VisitorStats(
      devices: counts[0].count ?? 0,
      today: counts[1].count ?? 0,
      week: counts[2].count ?? 0,
      members: counts[3].count ?? 0,
    );
  }

  @override
  Future<void> registerAdminDevice(String userId, String token) => _col('adminDevices')
      .doc(token)
      .set({'uid': userId, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<List<Product>> getProducts(Iterable<String> ids) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet().toList();
    final docs = await Future.wait(unique.map((id) => _col('products').doc(id).get()));
    return [for (final d in docs) if (d.exists) Product.fromMap(d.id, d.data()!)];
  }

  @override
  Stream<List<StoreOrder>> watchOrdersSince(DateTime from) => _col('orders')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('createdAt', descending: true)
      .limit(2000)
      .snapshots()
      .map((s) => s.docs.map((d) => _orderFromMap(d.id, d.data())).toList());

  @override
  Stream<LoyaltySettings> watchLoyalty() => _col('settings')
      .doc('loyalty')
      .snapshots()
      .map((d) => LoyaltySettings.fromMap(d.data() ?? const {}));

  @override
  Future<void> saveLoyalty(LoyaltySettings settings) => _col('settings').doc('loyalty').set(settings.toMap());

  @override
  Stream<bool> watchLegacyOrdersAllowed() => _col('settings')
      .doc('orders')
      .snapshots()
      .map((d) => d.data()?['legacyClientOrders'] as bool? ?? true);

  @override
  Future<void> setLegacyOrdersAllowed(bool allowed) =>
      _col('settings').doc('orders').set({'legacyClientOrders': allowed}, SetOptions(merge: true));

  @override
  Stream<Wallet> watchWallet(String userId) =>
      _col('wallets').doc(userId).snapshots().map((d) => Wallet.fromMap(d.data() ?? const {}));

  @override
  Stream<List<LedgerEntry>> watchLedger(String userId) => _col('wallets')
      .doc(userId)
      .collection('ledger')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map((d) => LedgerEntry.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Coupon>> watchMyCoupons(String userId) => _col('coupons')
      .where('assignedTo', isEqualTo: userId)
      .snapshots()
      .map((s) => s.docs.map((d) => Coupon.fromMap(d.id, d.data())).toList());

  @override
  Stream<Referral?> watchReferral(String userId) => _col('referrals')
      .doc(userId)
      .snapshots()
      .map((d) => d.exists ? Referral.fromMap(d.id, d.data()!) : null);

  @override
  Stream<List<Referral>> watchInvites(String userId) => _col('referrals')
      .where('referrerUid', isEqualTo: userId)
      .snapshots()
      .map((s) => s.docs.map((d) => Referral.fromMap(d.id, d.data())).toList());

  @override
  Stream<List<Coupon>> watchCoupons() => _col('coupons')
      .snapshots()
      .map((s) => s.docs.map((d) => Coupon.fromMap(d.id, d.data())).toList()..sort((a, b) => a.code.compareTo(b.code)));

  @override
  Future<void> saveCoupon(Coupon coupon, {required bool isNew}) {
    final doc = _col('coupons').doc(coupon.code);
    final data = {...coupon.toMap(), 'updatedAt': FieldValue.serverTimestamp()};
    if (isNew) return doc.set({...data, 'usedCount': 0, 'createdAt': FieldValue.serverTimestamp()});
    // التعديل ما يلمس usedCount. الحقول المحذوفة (مثل تاريخ الانتهاء) تنشال.
    return doc.update({
      ...data,
      if (coupon.startsAt == null) 'startsAt': FieldValue.delete(),
      if (coupon.endsAt == null) 'endsAt': FieldValue.delete(),
      if (coupon.assignedTo.isEmpty) 'assignedTo': FieldValue.delete(),
    });
  }

  @override
  Future<void> deleteCoupon(String code) => _col('coupons').doc(code).delete();

  @override
  Future<void> deleteRecommendationRule(String id) => _col('recommendationRules').doc(id).delete();

  @override
  Stream<List<RecommendationRule>> watchRecommendationRules({bool includeHidden = false}) =>
      _watch('recommendationRules', RecommendationRule.fromMap, activeOnly: !includeHidden)
          .map((l) => _sortByOrder(l, (r) => r.order));

  @override
  Future<void> saveRecommendationRule(RecommendationRule rule) =>
      _save('recommendationRules', rule.id, rule.toMap());

  @override
  Stream<List<DeliveryZone>> watchDeliveryZones() =>
      _col('settings').doc('delivery').snapshots().map((d) => deliveryZonesFromMap(d.data()));

  @override
  Future<void> saveDeliveryZones(List<DeliveryZone> zones) =>
      _col('settings').doc('delivery').set({'zones': zones.map((z) => z.toMap()).toList()});
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
  Future<void> deleteOrder(String id) {
    _orders.remove(id);
    return _changed();
  }

  @override
  Future<void> deleteCoupon(String code) {
    coupons.remove(code);
    return _changed();
  }

  @override
  Future<void> deleteRecommendationRule(String id) {
    rules.remove(id);
    return _changed();
  }

  @override
  Future<UserProfile> getProfile(String userId) async => _profiles[userId] ?? const UserProfile();

  @override
  Future<void> saveProfile(String userId, UserProfile profile) async =>
      _profiles[userId] = profile;

  /// deviceId ← آخر يوم فتح بيه التطبيق.
  final visits = <String, DateTime>{};
  final members = <String>{};
  final adminDevices = <String, String>{};

  @override
  Future<void> recordVisit(String deviceId, {required bool isNew, required String platform}) async =>
      visits[deviceId] = DateTime.now();

  @override
  Future<void> recordMember(String userId) async => members.add(userId);

  @override
  Future<VisitorStats> loadVisitorStats(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final week = today.subtract(const Duration(days: 6));
    return VisitorStats(
      devices: visits.length,
      today: visits.values.where((d) => !d.isBefore(today)).length,
      week: visits.values.where((d) => !d.isBefore(week)).length,
      members: members.length,
    );
  }

  @override
  Future<void> registerAdminDevice(String userId, String token) async => adminDevices[token] = userId;

  @override
  Future<List<Product>> getProducts(Iterable<String> ids) async =>
      [for (final id in ids.toSet()) ?_products[id]];

  @override
  Stream<List<StoreOrder>> watchOrdersSince(DateTime from) => _watch(() =>
      _newestFirst(_orders.values.where((o) => o.createdAt == null || !o.createdAt!.isBefore(from))));

  var loyalty = const LoyaltySettings();
  var legacyOrdersAllowed = true;
  final wallets = <String, Wallet>{};
  final ledgers = <String, List<LedgerEntry>>{};
  final coupons = <String, Coupon>{};
  final referrals = <String, Referral>{};
  final rules = <String, RecommendationRule>{};

  /// للاختبارات: طلب بكل تفاصيله (مثل اللي يكتبه السيرفر).
  Future<void> putOrder(StoreOrder order) {
    _orders[order.id] = order;
    return _changed();
  }

  @override
  Stream<LoyaltySettings> watchLoyalty() => _watch(() => loyalty);

  @override
  Future<void> saveLoyalty(LoyaltySettings settings) {
    loyalty = settings;
    return _changed();
  }

  @override
  Stream<bool> watchLegacyOrdersAllowed() => _watch(() => legacyOrdersAllowed);

  @override
  Future<void> setLegacyOrdersAllowed(bool allowed) {
    legacyOrdersAllowed = allowed;
    return _changed();
  }

  @override
  Stream<Wallet> watchWallet(String userId) => _watch(() => wallets[userId] ?? const Wallet());

  @override
  Stream<List<LedgerEntry>> watchLedger(String userId) => _watch(() => ledgers[userId] ?? const []);

  @override
  Stream<List<Coupon>> watchMyCoupons(String userId) =>
      _watch(() => coupons.values.where((c) => c.assignedTo == userId).toList());

  @override
  Stream<Referral?> watchReferral(String userId) => _watch(() => referrals[userId]);

  @override
  Stream<List<Referral>> watchInvites(String userId) =>
      _watch(() => referrals.values.where((r) => r.referrerUid == userId).toList());

  @override
  Stream<List<Coupon>> watchCoupons() =>
      _watch(() => coupons.values.toList()..sort((a, b) => a.code.compareTo(b.code)));

  @override
  Future<void> saveCoupon(Coupon coupon, {required bool isNew}) {
    final old = coupons[coupon.code];
    if (isNew && old != null) throw StateError('exists');
    coupons[coupon.code] = Coupon.fromMap(coupon.code, {...coupon.toMap(), 'usedCount': old?.usedCount ?? 0});
    return _changed();
  }

  @override
  Stream<List<RecommendationRule>> watchRecommendationRules({bool includeHidden = false}) => _watch(
      () => _sortByOrder(rules.values.where((r) => includeHidden || r.active), (r) => r.order));

  @override
  Future<void> saveRecommendationRule(RecommendationRule rule) {
    final id = rule.id.isEmpty ? _newId('rule') : rule.id;
    rules[id] = rule.copyWith(id: id);
    return _changed();
  }

  List<DeliveryZone> deliveryZones = defaultDeliveryZones;

  @override
  Stream<List<DeliveryZone>> watchDeliveryZones() => _watch(() => deliveryZones);

  @override
  Future<void> saveDeliveryZones(List<DeliveryZone> zones) {
    deliveryZones = List.of(zones);
    return _changed();
  }
}
