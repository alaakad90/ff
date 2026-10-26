// الولاء: النقاط والكوبونات والدعوات والعروض الذكية.
// الأرصدة والعدادات يكتبها السيرفر بس؛ التطبيق يقراها ويعرضها.

import 'package:cloud_firestore/cloud_firestore.dart';

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
String _str(Object? v) => v as String? ?? '';
DateTime? _date(Object? v) => switch (v) {
      Timestamp t => t.toDate(),
      DateTime d => d,
      _ => null,
    };
List<String> _strings(Object? v) => (v as List? ?? const []).whereType<String>().toList();

/// إعدادات النقاط والدعوات (settings/loyalty). نفس الافتراضيات اللي بالسيرفر.
class LoyaltySettings {
  final bool enabled;
  final int pointsPer1000;
  final int pointValue;
  final int minRedeemPoints;
  final int maxRedeemPercent;
  final bool referralEnabled;
  final int referrerPoints;
  final int refereePoints;
  final int referralMinTotal;
  final int maxReferralsPerUser;
  final int referralWindowDays;

  const LoyaltySettings({
    this.enabled = true,
    this.pointsPer1000 = 1,
    this.pointValue = 50,
    this.minRedeemPoints = 100,
    this.maxRedeemPercent = 50,
    this.referralEnabled = true,
    this.referrerPoints = 200,
    this.refereePoints = 100,
    this.referralMinTotal = 25000,
    this.maxReferralsPerUser = 20,
    this.referralWindowDays = 30,
  });

  factory LoyaltySettings.fromMap(Map<String, dynamic> d) {
    const x = LoyaltySettings();
    return LoyaltySettings(
      enabled: d['enabled'] as bool? ?? x.enabled,
      pointsPer1000: _int(d['pointsPer1000'], x.pointsPer1000),
      pointValue: _int(d['pointValue'], x.pointValue),
      minRedeemPoints: _int(d['minRedeemPoints'], x.minRedeemPoints),
      maxRedeemPercent: _int(d['maxRedeemPercent'], x.maxRedeemPercent),
      referralEnabled: d['referralEnabled'] as bool? ?? x.referralEnabled,
      referrerPoints: _int(d['referrerPoints'], x.referrerPoints),
      refereePoints: _int(d['refereePoints'], x.refereePoints),
      referralMinTotal: _int(d['referralMinTotal'], x.referralMinTotal),
      maxReferralsPerUser: _int(d['maxReferralsPerUser'], x.maxReferralsPerUser),
      referralWindowDays: _int(d['referralWindowDays'], x.referralWindowDays),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'pointsPer1000': pointsPer1000,
        'pointValue': pointValue,
        'minRedeemPoints': minRedeemPoints,
        'maxRedeemPercent': maxRedeemPercent,
        'referralEnabled': referralEnabled,
        'referrerPoints': referrerPoints,
        'refereePoints': refereePoints,
        'referralMinTotal': referralMinTotal,
        'maxReferralsPerUser': maxReferralsPerUser,
        'referralWindowDays': referralWindowDays,
      };

  /// قيمة النقاط بالدينار.
  int valueOf(int points) => points * pointValue;
}

enum CouponType {
  percent('percent', 'نسبة %'),
  fixed('fixed', 'مبلغ ثابت');

  final String value;
  final String label;

  const CouponType(this.value, this.label);

  static CouponType fromValue(String? v) => values.firstWhere((t) => t.value == v, orElse: () => fixed);
}

/// كوبون خصم (coupons/{CODE}). الرمز نفسه هو رقم الوثيقة.
class Coupon {
  final String code;
  final String description;
  final CouponType type;
  final int value;
  final int minSubtotal;
  final int maxDiscount; // 0 = بلا حد
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int usageLimit; // 0 = بلا حد
  final int perUserLimit; // 0 = بلا حد
  final int usedCount; // يعدّه السيرفر
  final bool active;
  final String assignedTo; // كوبون شخصي لزبون واحد
  final bool firstOrderOnly;

  const Coupon({
    required this.code,
    this.description = '',
    this.type = CouponType.percent,
    required this.value,
    this.minSubtotal = 0,
    this.maxDiscount = 0,
    this.startsAt,
    this.endsAt,
    this.usageLimit = 0,
    this.perUserLimit = 1,
    this.usedCount = 0,
    this.active = true,
    this.assignedTo = '',
    this.firstOrderOnly = false,
  });

  static final codePattern = RegExp(r'^[A-Z0-9_-]{3,24}$');

  factory Coupon.fromMap(String code, Map<String, dynamic> d) => Coupon(
        code: code,
        description: _str(d['description']),
        type: CouponType.fromValue(d['type'] as String?),
        value: _int(d['value']),
        minSubtotal: _int(d['minSubtotal']),
        maxDiscount: _int(d['maxDiscount']),
        startsAt: _date(d['startsAt']),
        endsAt: _date(d['endsAt']),
        usageLimit: _int(d['usageLimit']),
        perUserLimit: _int(d['perUserLimit'], 1),
        usedCount: _int(d['usedCount']),
        active: d['active'] as bool? ?? true,
        assignedTo: _str(d['assignedTo']),
        firstOrderOnly: d['firstOrderOnly'] as bool? ?? false,
      );

  /// بدون usedCount: العداد يغيره السيرفر بس (قواعد Firestore تمنع غيره).
  Map<String, dynamic> toMap() => {
        'description': description,
        'type': type.value,
        'value': value,
        'minSubtotal': minSubtotal,
        'maxDiscount': maxDiscount,
        if (startsAt != null) 'startsAt': Timestamp.fromDate(startsAt!),
        if (endsAt != null) 'endsAt': Timestamp.fromDate(endsAt!),
        'usageLimit': usageLimit,
        'perUserLimit': perUserLimit,
        'active': active,
        if (assignedTo.isNotEmpty) 'assignedTo': assignedTo,
        'firstOrderOnly': firstOrderOnly,
      };

  Coupon copyWith({bool? active}) => Coupon(
        code: code,
        description: description,
        type: type,
        value: value,
        minSubtotal: minSubtotal,
        maxDiscount: maxDiscount,
        startsAt: startsAt,
        endsAt: endsAt,
        usageLimit: usageLimit,
        perUserLimit: perUserLimit,
        usedCount: usedCount,
        active: active ?? this.active,
        assignedTo: assignedTo,
        firstOrderOnly: firstOrderOnly,
      );

  /// وصف قصير: "15%" أو "5,000 د.ع".
  String get valueLabel => type == CouponType.percent ? '$value%' : '$value د.ع';

  bool isExpired(DateTime now) => endsAt != null && now.isAfter(endsAt!);
}

/// محفظة الزبون (wallets/{uid}).
class Wallet {
  final int points;
  final int lifetimeEarned;
  final int ordersPlaced;
  final String referralCode;

  const Wallet({this.points = 0, this.lifetimeEarned = 0, this.ordersPlaced = 0, this.referralCode = ''});

  factory Wallet.fromMap(Map<String, dynamic> d) => Wallet(
        points: _int(d['points']),
        lifetimeEarned: _int(d['lifetimeEarned']),
        ordersPlaced: _int(d['ordersPlaced']),
        referralCode: _str(d['referralCode']),
      );
}

/// حركة بالمحفظة: كسب، استعمال، إرجاع، دعوة...
class LedgerEntry {
  final String id;
  final String type; // earn | redeem | refund | reverse | referral
  final int points;
  final String orderId;
  final String note;
  final DateTime? createdAt;

  const LedgerEntry({
    required this.id,
    required this.type,
    required this.points,
    this.orderId = '',
    this.note = '',
    this.createdAt,
  });

  factory LedgerEntry.fromMap(String id, Map<String, dynamic> d) => LedgerEntry(
        id: id,
        type: _str(d['type']),
        points: _int(d['points']),
        orderId: _str(d['orderId']),
        note: _str(d['note']),
        createdAt: _date(d['createdAt']),
      );
}

/// دعوة صديق (referrals/{uid الصديق}).
class Referral {
  final String uid;
  final String referrerUid;
  final String status; // pending | rewarded | capped

  const Referral({required this.uid, required this.referrerUid, required this.status});

  factory Referral.fromMap(String uid, Map<String, dynamic> d) =>
      Referral(uid: uid, referrerUid: _str(d['referrerUid']), status: _str(d['status']));
}

/// عرض ذكي: "اللي يطلب كذا تبينله كذا" (recommendationRules/{id}).
/// الشرط والاقتراح يكونن بالأقسام، أو بمنتجات معينة، أو بكلمات بالاسم (مثل "زواج").
class RecommendationRule {
  final String id;
  final String title; // مثل: "كمّل فرحتكم: عقود الزواج"
  final List<String> triggerKeywords;
  final List<String> triggerCategoryIds;
  final List<String> triggerProductIds;
  final List<String> targetKeywords;
  final List<String> targetCategoryIds;
  final List<String> targetProductIds;
  final int order;
  final bool active;

  const RecommendationRule({
    this.id = '',
    required this.title,
    this.triggerKeywords = const [],
    this.triggerCategoryIds = const [],
    this.triggerProductIds = const [],
    this.targetKeywords = const [],
    this.targetCategoryIds = const [],
    this.targetProductIds = const [],
    this.order = 0,
    this.active = true,
  });

  factory RecommendationRule.fromMap(String id, Map<String, dynamic> d) => RecommendationRule(
        id: id,
        title: _str(d['title']),
        triggerKeywords: _strings(d['triggerKeywords']),
        triggerCategoryIds: _strings(d['triggerCategoryIds']),
        triggerProductIds: _strings(d['triggerProductIds']),
        targetKeywords: _strings(d['targetKeywords']),
        targetCategoryIds: _strings(d['targetCategoryIds']),
        targetProductIds: _strings(d['targetProductIds']),
        order: _int(d['order']),
        active: d['active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'triggerKeywords': triggerKeywords,
        'triggerCategoryIds': triggerCategoryIds,
        'triggerProductIds': triggerProductIds,
        'targetKeywords': targetKeywords,
        'targetCategoryIds': targetCategoryIds,
        'targetProductIds': targetProductIds,
        'order': order,
        'active': active,
      };

  RecommendationRule copyWith({String? id, bool? active}) => RecommendationRule(
        id: id ?? this.id,
        title: title,
        triggerKeywords: triggerKeywords,
        triggerCategoryIds: triggerCategoryIds,
        triggerProductIds: triggerProductIds,
        targetKeywords: targetKeywords,
        targetCategoryIds: targetCategoryIds,
        targetProductIds: targetProductIds,
        order: order,
        active: active ?? this.active,
      );
}
