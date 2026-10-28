// المحتوى اللي يتحكم بيه صاحب المتجر من لوحة التحكم.

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
String _str(Object? v) => v as String? ?? '';

class Category {
  final String id;
  final String name;
  final String iconKey; // من category_icons.dart
  final String imageUrl; // إذا موجود يتقدم على الأيقونة
  final int order;

  const Category({
    this.id = '',
    required this.name,
    this.iconKey = 'category',
    this.imageUrl = '',
    this.order = 0,
  });

  factory Category.fromMap(String id, Map<String, dynamic> d) => Category(
        id: id,
        name: _str(d['name']),
        iconKey: d['iconKey'] as String? ?? 'category',
        imageUrl: _str(d['imageUrl']),
        order: _int(d['order']),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'iconKey': iconKey,
        'imageUrl': imageUrl,
        'order': order,
      };

  Category withId(String id) =>
      Category(id: id, name: name, iconKey: iconKey, imageUrl: imageUrl, order: order);
}

/// بنر العروض والتخفيضات بالصفحة الرئيسية.
class PromoBanner {
  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String categoryId; // لما ينضغط يفتح هذا القسم (اختياري)
  final int order;
  final bool active;

  const PromoBanner({
    this.id = '',
    this.imageUrl = '',
    required this.title,
    this.subtitle = '',
    this.categoryId = '',
    this.order = 0,
    this.active = true,
  });

  factory PromoBanner.fromMap(String id, Map<String, dynamic> d) => PromoBanner(
        id: id,
        imageUrl: _str(d['imageUrl']),
        title: _str(d['title']),
        subtitle: _str(d['subtitle']),
        categoryId: _str(d['categoryId']),
        order: _int(d['order']),
        active: d['active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'imageUrl': imageUrl,
        'title': title,
        'subtitle': subtitle,
        'categoryId': categoryId,
        'order': order,
        'active': active,
      };

  PromoBanner copyWith({String? id, bool? active}) => PromoBanner(
        id: id ?? this.id,
        imageUrl: imageUrl,
        title: title,
        subtitle: subtitle,
        categoryId: categoryId,
        order: order,
        active: active ?? this.active,
      );
}

class Reel {
  final String id;
  final String videoUrl;
  final String caption;
  final String productId; // زر "شوف المنتج" (اختياري)
  final int order;
  final bool active;

  const Reel({
    this.id = '',
    required this.videoUrl,
    this.caption = '',
    this.productId = '',
    this.order = 0,
    this.active = true,
  });

  factory Reel.fromMap(String id, Map<String, dynamic> d) => Reel(
        id: id,
        videoUrl: _str(d['videoUrl']),
        caption: _str(d['caption']),
        productId: _str(d['productId']),
        order: _int(d['order']),
        active: d['active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'videoUrl': videoUrl,
        'caption': caption,
        'productId': productId,
        'order': order,
        'active': active,
      };

  Reel copyWith({String? id, bool? active}) => Reel(
        id: id ?? this.id,
        videoUrl: videoUrl,
        caption: caption,
        productId: productId,
        order: order,
        active: active ?? this.active,
      );
}

/// معلومات صفحة "عن المتجر" وأرقام التواصل.
class StoreInfo {
  final String about;
  final String phone;
  final String whatsapp;
  final String address;
  final String hours;
  final String instagram;
  final String facebook; // رابط صفحة الفيسبوك أو اسمها

  const StoreInfo({
    this.about = '',
    this.phone = '',
    this.whatsapp = '',
    this.address = '',
    this.hours = '',
    this.instagram = '',
    this.facebook = '',
  });

  factory StoreInfo.fromMap(Map<String, dynamic> d) => StoreInfo(
        about: _str(d['about']),
        phone: _str(d['phone']),
        whatsapp: _str(d['whatsapp']),
        address: _str(d['address']),
        hours: _str(d['hours']),
        instagram: _str(d['instagram']),
        facebook: _str(d['facebook']),
      );

  Map<String, dynamic> toMap() => {
        'about': about,
        'phone': phone,
        'whatsapp': whatsapp,
        'address': address,
        'hours': hours,
        'instagram': instagram,
        'facebook': facebook,
      };
}

/// معلومات الزبون المحفوظة حتى ما يكتبها بكل طلب.
class UserProfile {
  final String name;
  final String phone;
  final String address;

  const UserProfile({this.name = '', this.phone = '', this.address = ''});

  factory UserProfile.fromMap(Map<String, dynamic> d) =>
      UserProfile(name: _str(d['name']), phone: _str(d['phone']), address: _str(d['address']));

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone, 'address': address};
}

/// رابط الفيسبوك: إذا انكتب اسم الصفحة بس، نكمله.
String facebookUrl(String value) {
  final v = value.trim();
  if (v.startsWith('http')) return v;
  return 'https://facebook.com/${v.replaceAll('@', '')}';
}
