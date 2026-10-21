import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;

  const Category({required this.id, required this.name, required this.icon});
}

class Product {
  final String id;
  final String name;
  final String description;
  final int price; // بالدينار العراقي
  final String categoryId;
  final IconData icon;
  final Color color;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.icon,
    required this.color,
  });
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
