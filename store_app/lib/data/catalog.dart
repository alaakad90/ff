import 'package:flutter/material.dart';

import '../models/product.dart';

// كتالوج تجريبي. بالمرحلة الجاية ينقل لقاعدة بيانات (Firebase)
// حتى صاحب المتجر يضيف ويعدل المنتجات بدون تحديث التطبيق.

const categories = <Category>[
  Category(id: 'gifts', name: 'هدايا', icon: Icons.card_giftcard),
  Category(id: 'flowers', name: 'ورود', icon: Icons.local_florist),
  Category(id: 'perfume', name: 'عطور', icon: Icons.spa),
  Category(id: 'sweets', name: 'حلويات', icon: Icons.cake),
];

const products = <Product>[
  Product(
    id: 'p1',
    name: 'بوكس هدية فاخر',
    description: 'بوكس مرتب بيه شموع وشوكولاتة وكارت إهداء باسم الشخص.',
    price: 35000,
    categoryId: 'gifts',
    icon: Icons.redeem,
    color: Color(0xFFB5838D),
  ),
  Product(
    id: 'p2',
    name: 'ساعة يد كلاسيك',
    description: 'ساعة أنيقة بتغليف هدية، تنفع للمناسبات.',
    price: 60000,
    categoryId: 'gifts',
    icon: Icons.watch,
    color: Color(0xFF6D6875),
  ),
  Product(
    id: 'p3',
    name: 'باقة ورد جوري',
    description: 'باقة ورد جوري أحمر طبيعي، 12 وردة.',
    price: 25000,
    categoryId: 'flowers',
    icon: Icons.local_florist,
    color: Color(0xFFE5989B),
  ),
  Product(
    id: 'p4',
    name: 'سلة ورد مشكل',
    description: 'سلة ورد بألوان مختلفة مع شريطة.',
    price: 40000,
    categoryId: 'flowers',
    icon: Icons.yard,
    color: Color(0xFFFFB4A2),
  ),
  Product(
    id: 'p5',
    name: 'عطر عود',
    description: 'عطر عود شرقي، 100 مل.',
    price: 45000,
    categoryId: 'perfume',
    icon: Icons.spa,
    color: Color(0xFF8D6E63),
  ),
  Product(
    id: 'p6',
    name: 'عطر ورد',
    description: 'عطر نسائي برائحة الورد، 50 مل.',
    price: 30000,
    categoryId: 'perfume',
    icon: Icons.water_drop,
    color: Color(0xFFCDB4DB),
  ),
  Product(
    id: 'p7',
    name: 'كيكة مناسبات',
    description: 'كيكة بالاسم والتاريخ اللي تريده، تكفي 8 أشخاص.',
    price: 28000,
    categoryId: 'sweets',
    icon: Icons.cake,
    color: Color(0xFFF4A261),
  ),
  Product(
    id: 'p8',
    name: 'علبة شوكولاتة',
    description: 'شوكولاتة بلجيكية مشكلة، 24 قطعة.',
    price: 20000,
    categoryId: 'sweets',
    icon: Icons.cookie,
    color: Color(0xFF7F5539),
  ),
];
