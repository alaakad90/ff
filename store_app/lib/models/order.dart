import '../state/cart.dart';

enum OrderStatus {
  pending('new', 'جديد'),
  confirmed('confirmed', 'تم التأكيد'),
  delivering('delivering', 'قيد التوصيل'),
  done('done', 'تم التسليم'),
  cancelled('cancelled', 'ملغي');

  final String value;
  final String label;

  const OrderStatus(this.value, this.label);

  static OrderStatus fromValue(String? value) =>
      values.firstWhere((s) => s.value == value, orElse: () => pending);
}

/// أيام الأسبوع تبدي من السبت، مثل التطبيق القديم.
const weekDays = ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

/// اسم اليوم بالعربي. DateTime.weekday: الإثنين = 1 ... الأحد = 7.
String weekDayName(DateTime date) => weekDays[(date.weekday + 1) % 7];

enum PickupMethod {
  delivery('delivery', 'توصيل'),
  pickup('pickup', 'استلام من المحل');

  final String value;
  final String label;

  const PickupMethod(this.value, this.label);

  static PickupMethod fromValue(String? value) =>
      values.firstWhere((m) => m.value == value, orElse: () => delivery);
}

class Customer {
  final String name;
  final String phone;
  final String address;
  final String notes;

  const Customer({
    required this.name,
    required this.phone,
    this.address = '',
    this.notes = '',
  });

  factory Customer.fromMap(Map<String, dynamic> data) => Customer(
        name: data['name'] as String? ?? '',
        phone: data['phone'] as String? ?? '',
        address: data['address'] as String? ?? '',
        notes: data['notes'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
      };
}

class OrderItem {
  final String productId;
  final String name;
  final int price;
  final int quantity;
  final String note; // ملاحظة الزبون على هذا المنتج
  final String imageUrl; // صورة مرفقة ويا الملاحظة
  final String voiceUrl; // فويس مرفق ويا الملاحظة

  const OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    this.note = '',
    this.imageUrl = '',
    this.voiceUrl = '',
  });

  bool get hasAttachments => imageUrl.isNotEmpty || voiceUrl.isNotEmpty;

  int get total => price * quantity;

  factory OrderItem.fromCartItem(CartItem item) => OrderItem(
        productId: item.product.id,
        name: item.product.name,
        price: item.product.price,
        quantity: item.quantity,
        note: item.note,
        imageUrl: item.imageUrl,
        voiceUrl: item.voiceUrl,
      );

  factory OrderItem.fromMap(Map<String, dynamic> data) => OrderItem(
        productId: data['productId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        price: (data['price'] as num?)?.toInt() ?? 0,
        quantity: (data['quantity'] as num?)?.toInt() ?? 0,
        note: data['note'] as String? ?? '',
        imageUrl: data['imageUrl'] as String? ?? '',
        voiceUrl: data['voiceUrl'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        if (note.isNotEmpty) 'note': note,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (voiceUrl.isNotEmpty) 'voiceUrl': voiceUrl,
      };
}

class StoreOrder {
  final String id;
  final Customer customer;
  final List<OrderItem> items;
  final int total;
  final String deliveryDay; // من weekDays
  final PickupMethod pickupMethod;
  final String userId; // فارغ إذا الزبون ما مسجل دخول
  final OrderStatus status;
  final DateTime? createdAt;
  final String pushToken; // توكن تليفون الزبون للإشعارات (ينكتب بس، ما ينقرا)

  const StoreOrder({
    this.id = '',
    required this.customer,
    required this.items,
    required this.total,
    this.deliveryDay = '',
    this.pickupMethod = PickupMethod.delivery,
    this.userId = '',
    this.status = OrderStatus.pending,
    this.createdAt,
    this.pushToken = '',
  });

  factory StoreOrder.fromCart(
    Customer customer,
    Cart cart, {
    required String deliveryDay,
    required PickupMethod pickupMethod,
    String userId = '',
    String pushToken = '',
  }) =>
      StoreOrder(
        customer: customer,
        items: cart.items.map(OrderItem.fromCartItem).toList(),
        total: cart.total,
        deliveryDay: deliveryDay,
        pickupMethod: pickupMethod,
        userId: userId,
        pushToken: pushToken,
      );

  StoreOrder copyWithPushToken(String token) => StoreOrder(
        id: id,
        customer: customer,
        items: items,
        total: total,
        deliveryDay: deliveryDay,
        pickupMethod: pickupMethod,
        userId: userId,
        status: status,
        createdAt: createdAt,
        pushToken: token,
      );

  StoreOrder copyWith({String? id, OrderStatus? status, DateTime? createdAt}) => StoreOrder(
        id: id ?? this.id,
        customer: customer,
        items: items,
        total: total,
        deliveryDay: deliveryDay,
        pickupMethod: pickupMethod,
        userId: userId,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        pushToken: pushToken,
      );
}
