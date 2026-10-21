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

class Customer {
  final String name;
  final String phone;
  final String address;
  final String notes;

  const Customer({
    required this.name,
    required this.phone,
    required this.address,
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

  const OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  int get total => price * quantity;

  factory OrderItem.fromCartItem(CartItem item) => OrderItem(
        productId: item.product.id,
        name: item.product.name,
        price: item.product.price,
        quantity: item.quantity,
      );

  factory OrderItem.fromMap(Map<String, dynamic> data) => OrderItem(
        productId: data['productId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        price: (data['price'] as num?)?.toInt() ?? 0,
        quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
      };
}

class StoreOrder {
  final String id;
  final Customer customer;
  final List<OrderItem> items;
  final int total;
  final OrderStatus status;
  final DateTime? createdAt;

  const StoreOrder({
    this.id = '',
    required this.customer,
    required this.items,
    required this.total,
    this.status = OrderStatus.pending,
    this.createdAt,
  });

  factory StoreOrder.fromCart(Customer customer, Cart cart) => StoreOrder(
        customer: customer,
        items: cart.items.map(OrderItem.fromCartItem).toList(),
        total: cart.total,
      );

  StoreOrder copyWith({String? id, OrderStatus? status, DateTime? createdAt}) => StoreOrder(
        id: id ?? this.id,
        customer: customer,
        items: items,
        total: total,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}
