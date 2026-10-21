import 'package:flutter/material.dart';

import '../models/product.dart';

// الأقسام ثابتة بالتطبيق. المنتجات تنقرا من Firestore.
const categories = <Category>[
  Category(id: 'gifts', name: 'هدايا', icon: Icons.card_giftcard, color: Color(0xFFB5838D)),
  Category(id: 'flowers', name: 'ورود', icon: Icons.local_florist, color: Color(0xFFE5989B)),
  Category(id: 'perfume', name: 'عطور', icon: Icons.spa, color: Color(0xFF8D6E63)),
  Category(id: 'sweets', name: 'حلويات', icon: Icons.cake, color: Color(0xFFF4A261)),
];

Category categoryOf(String id) =>
    categories.firstWhere((c) => c.id == id, orElse: () => categories.first);

/// منتجات تجريبية يكدر صاحب المتجر يضيفها من لوحة التحكم حتى يجرب.
const sampleProducts = <Product>[
  Product(
    name: 'بوكس هدية فاخر',
    description: 'بوكس مرتب بيه شموع وشوكولاتة وكارت إهداء باسم الشخص.',
    price: 35000,
    categoryId: 'gifts',
  ),
  Product(
    name: 'ساعة يد كلاسيك',
    description: 'ساعة أنيقة بتغليف هدية، تنفع للمناسبات.',
    price: 60000,
    categoryId: 'gifts',
  ),
  Product(
    name: 'باقة ورد جوري',
    description: 'باقة ورد جوري أحمر طبيعي، 12 وردة.',
    price: 25000,
    categoryId: 'flowers',
  ),
  Product(
    name: 'سلة ورد مشكل',
    description: 'سلة ورد بألوان مختلفة مع شريطة.',
    price: 40000,
    categoryId: 'flowers',
  ),
  Product(
    name: 'عطر عود',
    description: 'عطر عود شرقي، 100 مل.',
    price: 45000,
    categoryId: 'perfume',
  ),
  Product(
    name: 'عطر ورد',
    description: 'عطر نسائي برائحة الورد، 50 مل.',
    price: 30000,
    categoryId: 'perfume',
  ),
  Product(
    name: 'كيكة مناسبات',
    description: 'كيكة بالاسم والتاريخ اللي تريده، تكفي 8 أشخاص.',
    price: 28000,
    categoryId: 'sweets',
  ),
  Product(
    name: 'علبة شوكولاتة',
    description: 'شوكولاتة بلجيكية مشكلة، 24 قطعة.',
    price: 20000,
    categoryId: 'sweets',
  ),
];
