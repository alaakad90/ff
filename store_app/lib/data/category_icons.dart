import 'package:flutter/material.dart';

/// الأيقونات اللي يختار منها صاحب المتجر للأقسام.
/// تنحفظ بقاعدة البيانات بالمفتاح (key) مو بالأيقونة نفسها.
const categoryIcons = <String, IconData>{
  'category': Icons.category_outlined,
  'gift': Icons.card_giftcard,
  'chair': Icons.chair_outlined,
  'table': Icons.table_restaurant_outlined,
  'bed': Icons.bed_outlined,
  'kitchen': Icons.kitchen_outlined,
  'lamp': Icons.light_outlined,
  'clock': Icons.watch_later_outlined,
  'frame': Icons.filter_frames_outlined,
  'palette': Icons.palette_outlined,
  'brush': Icons.brush_outlined,
  'carpentry': Icons.carpenter_outlined,
  'handyman': Icons.handyman_outlined,
  'resin': Icons.water_drop_outlined,
  'diamond': Icons.diamond_outlined,
  'key': Icons.key_outlined,
  'name': Icons.text_fields,
  'print3d': Icons.view_in_ar_outlined,
  'home': Icons.home_outlined,
  'flower': Icons.local_florist_outlined,
  'star': Icons.star_outline,
  'heart': Icons.favorite_border,
  'baby': Icons.child_friendly_outlined,
  'offer': Icons.local_offer_outlined,
};

IconData categoryIcon(String key) => categoryIcons[key] ?? Icons.category_outlined;
