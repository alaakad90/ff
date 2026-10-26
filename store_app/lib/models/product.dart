class Product {
  final String id;
  final String name;
  final String description;
  final int price; // بالدينار العراقي
  final int oldPrice; // السعر قبل التخفيض (يبين مشطوب)، 0 = ماكو تخفيض
  final String categoryId;
  final String imageUrl;
  final bool available;

  const Product({
    this.id = '',
    required this.name,
    this.description = '',
    required this.price,
    this.oldPrice = 0,
    required this.categoryId,
    this.imageUrl = '',
    this.available = true,
  });

  /// عليه تخفيض: السعر القديم أكبر من الحالي.
  bool get onSale => oldPrice > price && price > 0;

  /// نسبة التخفيض، مثل 20 يعني 20%.
  int get discountPercent => onSale ? ((oldPrice - price) * 100 / oldPrice).round() : 0;

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    return Product(
      id: id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      oldPrice: (data['oldPrice'] as num?)?.toInt() ?? 0,
      categoryId: data['categoryId'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      available: data['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'price': price,
        'oldPrice': onSale ? oldPrice : 0,
        'categoryId': categoryId,
        'imageUrl': imageUrl,
        'available': available,
      };

  Product copyWith({String? id, bool? available}) {
    return Product(
      id: id ?? this.id,
      name: name,
      description: description,
      price: price,
      oldPrice: oldPrice,
      categoryId: categoryId,
      imageUrl: imageUrl,
      available: available ?? this.available,
    );
  }
}

/// السعر القديم بعد ما ينزل السعر: إذا المدير نزّل السعر وما كتب سعر قبل التخفيض،
/// ناخذ السعر اللي چان قبل. وإذا السعر رجع مثل القديم أو أكثر، يروح التخفيض.
int saleOldPrice({required int? previousPrice, required int newPrice, required int enteredOldPrice}) {
  if (enteredOldPrice > newPrice) return enteredOldPrice;
  if (enteredOldPrice == 0 && previousPrice != null && previousPrice > newPrice) return previousPrice;
  return 0;
}

/// يكتب السعر بفواصل الآلاف، مثل: 25,000 د.ع
String formatPrice(int price) {
  final digits = price.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$buffer د.ع';
}
