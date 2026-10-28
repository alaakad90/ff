class Product {
  final String id;
  final String name;
  final String description;
  final int price; // بالدينار العراقي
  final int oldPrice; // السعر قبل التخفيض (يبين مشطوب)، 0 = ماكو تخفيض
  final String categoryId;
  final String imageUrl;
  final bool available;
  final List<ProductOption> options; // حقول يختارها الزبون، مثل اللون أو نوع الخط

  const Product({
    this.id = '',
    required this.name,
    this.description = '',
    required this.price,
    this.oldPrice = 0,
    required this.categoryId,
    this.imageUrl = '',
    this.available = true,
    this.options = const [],
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
      options: [
        for (final o in data['options'] as List? ?? const [])
          if (o is Map) ProductOption.fromMap(Map<String, dynamic>.from(o)),
      ].where((o) => o.name.isNotEmpty && o.choices.isNotEmpty).toList(),
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
        'options': [for (final o in options) o.toMap()],
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
      options: options,
    );
  }
}

/// حقل يضيفه المدير للمنتج (مثل "اللون") ويا الاختيارات اللي يختار منها الزبون.
class ProductOption {
  final String name;
  final List<String> choices;
  final bool required; // الزبون لازم يختار قبل ما يضيف للسلة

  const ProductOption({required this.name, required this.choices, this.required = true});

  factory ProductOption.fromMap(Map<String, dynamic> data) => ProductOption(
        name: (data['name'] as String? ?? '').trim(),
        choices: [
          for (final c in data['choices'] as List? ?? const [])
            if (c is String && c.trim().isNotEmpty) c.trim(),
        ],
        required: data['required'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {'name': name, 'choices': choices, 'required': required};
}

/// الاختيارات بسطر واحد، مثل: اللون: أحمر، نوع الخط: كوفي
String optionsLabel(Map<String, String> options) =>
    options.entries.map((e) => '${e.key}: ${e.value}').join('، ');

/// الاختيارات من Firestore أو السيرفر: [{name, value}] بنفس الترتيب.
Map<String, String> optionsFromList(Object? raw) => {
      for (final o in raw is List ? raw : const [])
        if (o is Map && o['name'] is String && o['value'] is String) o['name'] as String: o['value'] as String,
    };

List<Map<String, String>> optionsToList(Map<String, String> options) => [
      for (final e in options.entries) {'name': e.key, 'value': e.value},
    ];

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
