import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;
  final Color color;

  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });
}

class Product {
  final String id;
  final String name;
  final String description;
  final int price; // بالدينار العراقي
  final String categoryId;
  final String imageUrl;
  final bool available;

  const Product({
    this.id = '',
    required this.name,
    this.description = '',
    required this.price,
    required this.categoryId,
    this.imageUrl = '',
    this.available = true,
  });

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    return Product(
      id: id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      categoryId: data['categoryId'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      available: data['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'price': price,
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
      categoryId: categoryId,
      imageUrl: imageUrl,
      available: available ?? this.available,
    );
  }
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
