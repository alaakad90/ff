// أجور التوصيل حسب المحافظة. صاحب المتجر يعدلها من لوحة التحكم (settings/delivery).
// نفس القائمة الافتراضية موجودة بالسيرفر (worker/src/delivery.js)، والسيرفر هو اللي يحسب.

class DeliveryZone {
  final String id;
  final String name;
  final int fee;
  final bool active;

  const DeliveryZone({required this.id, required this.name, required this.fee, this.active = true});

  static final idPattern = RegExp(r'^[a-z0-9-]{1,40}$');

  factory DeliveryZone.fromMap(Map<String, dynamic> d) => DeliveryZone(
        id: d['id'] as String? ?? '',
        name: d['name'] as String? ?? '',
        fee: (d['fee'] as num?)?.toInt() ?? 0,
        active: d['active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'fee': fee, 'active': active};

  DeliveryZone copyWith({String? name, int? fee, bool? active}) =>
      DeliveryZone(id: id, name: name ?? this.name, fee: fee ?? this.fee, active: active ?? this.active);
}

/// الافتراضي: الديوانية المركز 2,000، الأقضية والنواحي 4,000، وباقي المحافظات 5,000.
const defaultDeliveryZones = [
  DeliveryZone(id: 'diwaniyah-center', name: 'الديوانية - المركز', fee: 2000),
  DeliveryZone(id: 'diwaniyah-districts', name: 'الديوانية - الأقضية والنواحي', fee: 4000),
  DeliveryZone(id: 'baghdad', name: 'بغداد', fee: 5000),
  DeliveryZone(id: 'basra', name: 'البصرة', fee: 5000),
  DeliveryZone(id: 'ninawa', name: 'نينوى', fee: 5000),
  DeliveryZone(id: 'erbil', name: 'أربيل', fee: 5000),
  DeliveryZone(id: 'sulaymaniyah', name: 'السليمانية', fee: 5000),
  DeliveryZone(id: 'duhok', name: 'دهوك', fee: 5000),
  DeliveryZone(id: 'halabja', name: 'حلبجة', fee: 5000),
  DeliveryZone(id: 'kirkuk', name: 'كركوك', fee: 5000),
  DeliveryZone(id: 'anbar', name: 'الأنبار', fee: 5000),
  DeliveryZone(id: 'salahaddin', name: 'صلاح الدين', fee: 5000),
  DeliveryZone(id: 'diyala', name: 'ديالى', fee: 5000),
  DeliveryZone(id: 'babil', name: 'بابل', fee: 5000),
  DeliveryZone(id: 'karbala', name: 'كربلاء', fee: 5000),
  DeliveryZone(id: 'najaf', name: 'النجف', fee: 5000),
  DeliveryZone(id: 'wasit', name: 'واسط', fee: 5000),
  DeliveryZone(id: 'maysan', name: 'ميسان', fee: 5000),
  DeliveryZone(id: 'dhiqar', name: 'ذي قار', fee: 5000),
  DeliveryZone(id: 'muthanna', name: 'المثنى', fee: 5000),
];

/// المناطق من settings/delivery، أو الافتراضي إذا ماكو.
List<DeliveryZone> deliveryZonesFromMap(Map<String, dynamic>? data) {
  final zones = [
    for (final z in data?['zones'] as List? ?? const [])
      if (z is Map) DeliveryZone.fromMap(Map<String, dynamic>.from(z)),
  ].where((z) => z.id.isNotEmpty && z.name.isNotEmpty).toList();
  return zones.isEmpty ? defaultDeliveryZones : zones;
}

/// رقم لمنطقة جديدة يضيفها المدير (حروف إنكليزية وأرقام بس، مثل zone-1736...).
String newZoneId(Iterable<DeliveryZone> existing) {
  var n = existing.length + 1;
  while (existing.any((z) => z.id == 'zone-$n')) {
    n++;
  }
  return 'zone-$n';
}
