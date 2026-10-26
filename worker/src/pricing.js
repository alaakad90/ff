// حساب سعر الطلب بالسيرفر: الأسعار من Firestore، والكوبون والنقاط حسب إعدادات المتجر.
// كلها دوال بدون اتصال (pure)، حتى تنختبر بسهولة، وحتى quote وplace يحسبون نفس الحساب.

/** إعدادات الولاء الافتراضية. صاحب المتجر يغيرها من لوحة التحكم (settings/loyalty). */
export const DEFAULT_LOYALTY = Object.freeze({
  enabled: true,
  pointsPer1000: 1, // كم نقطة لكل 1000 د.ع مدفوعة (بعد الخصم)
  pointValue: 50, // قيمة النقطة الوحدة بالدينار عند الاستعمال
  minRedeemPoints: 100, // أقل عدد نقاط يكدر يستعمله
  maxRedeemPercent: 50, // أكثر نسبة من المبلغ تندفع بالنقاط
  referralEnabled: true,
  referrerPoints: 200, // للي دعا صديقه
  refereePoints: 100, // للصديق الجديد
  referralMinTotal: 25000, // أقل مبلغ لأول طلب حتى تنحسب الدعوة
  maxReferralsPerUser: 20,
  referralWindowDays: 30, // كم يوم بعد التسجيل يكدر يحط كود صديقه
});

const LIMITS = {
  pointsPer1000: [0, 1000],
  pointValue: [0, 100000],
  minRedeemPoints: [0, 1000000],
  maxRedeemPercent: [0, 100],
  referrerPoints: [0, 1000000],
  refereePoints: [0, 1000000],
  referralMinTotal: [0, 100000000],
  maxReferralsPerUser: [0, 10000],
  referralWindowDays: [0, 3650],
};

const clampInt = (value, [min, max], fallback) => {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(n)));
};

/** الإعدادات من Firestore بعد التصحيح: أي قيمة غلط ترجع للافتراضي أو للحد. */
export function loyaltySettings(raw = {}) {
  const out = { ...DEFAULT_LOYALTY };
  for (const key of ['enabled', 'referralEnabled']) {
    if (typeof raw?.[key] === 'boolean') out[key] = raw[key];
  }
  for (const [key, range] of Object.entries(LIMITS)) {
    if (raw && key in raw) out[key] = clampInt(raw[key], range, DEFAULT_LOYALTY[key]);
  }
  return out;
}

export const COUPON_CODE = /^[A-Z0-9_-]{3,24}$/;

export function normalizeCode(code) {
  return typeof code === 'string' ? code.trim().toUpperCase() : '';
}

/** آخر 10 أرقام من الهاتف، حتى 0770... و+964770... يصيرن نفس الرقم. */
export function phoneKey(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : digits;
}

const COUPON_ERRORS = {
  not_found: 'الكوبون مو صحيح',
  inactive: 'الكوبون موقوف',
  not_started: 'الكوبون بعده ما بدأ',
  expired: 'الكوبون منتهي',
  min_subtotal: 'المبلغ أقل من الحد الأدنى للكوبون',
  used_up: 'الكوبون خلص',
  per_user: 'استعملت هذا الكوبون قبل',
  first_order: 'الكوبون لأول طلب بس',
  not_yours: 'هذا الكوبون مو إلك',
  sign_in: 'سجل دخول حتى تستعمل هذا الكوبون',
};

export function couponMessage(code, coupon) {
  if (code === 'min_subtotal' && coupon) return `${COUPON_ERRORS.min_subtotal} (${coupon.minSubtotal} د.ع)`;
  return COUPON_ERRORS[code] || 'الكوبون مو صالح';
}

/**
 * يتحقق من الكوبون ويحسب خصمه. يرجع { amount } أو { error }.
 * uses: عدد مرات استعمال هذا الزبون للكوبون (بالحساب أو بالهاتف، الأكثر).
 */
export function evaluateCoupon(coupon, { subtotal, now, uid, uses = 0, isFirstOrder = true }) {
  if (!coupon) return { error: 'not_found' };
  if (coupon.active === false) return { error: 'inactive' };
  if (coupon.startsAt instanceof Date && now < coupon.startsAt) return { error: 'not_started' };
  if (coupon.endsAt instanceof Date && now > coupon.endsAt) return { error: 'expired' };
  if (coupon.assignedTo) {
    if (!uid) return { error: 'sign_in' };
    if (coupon.assignedTo !== uid) return { error: 'not_yours' };
  }
  const usageLimit = Math.max(0, Math.trunc(Number(coupon.usageLimit) || 0));
  if (usageLimit > 0 && (Number(coupon.usedCount) || 0) >= usageLimit) return { error: 'used_up' };
  const perUser = coupon.perUserLimit == null ? 1 : Math.max(0, Math.trunc(Number(coupon.perUserLimit) || 0));
  if (perUser > 0 && uses >= perUser) return { error: 'per_user' };
  if (coupon.firstOrderOnly && !isFirstOrder) return { error: 'first_order' };
  const minSubtotal = Math.max(0, Math.trunc(Number(coupon.minSubtotal) || 0));
  if (subtotal < minSubtotal) return { error: 'min_subtotal' };

  const value = Math.max(0, Math.trunc(Number(coupon.value) || 0));
  let amount = coupon.type === 'percent'
    ? Math.floor((subtotal * Math.min(value, 100)) / 100)
    : value;
  const maxDiscount = Math.max(0, Math.trunc(Number(coupon.maxDiscount) || 0));
  if (maxDiscount > 0) amount = Math.min(amount, maxDiscount);
  return { amount: Math.min(amount, subtotal) };
}

/** أكثر نقاط يكدر يستعملها على مبلغ معين. */
export function maxRedeemablePoints(loyalty, amount, balance) {
  if (!loyalty.enabled || loyalty.pointValue <= 0) return 0;
  const byPercent = Math.floor((amount * loyalty.maxRedeemPercent) / 100 / loyalty.pointValue);
  const max = Math.min(Math.max(0, balance), byPercent);
  return max >= loyalty.minRedeemPoints ? max : 0;
}

/** النقاط اللي يكسبها الزبون من مبلغ مدفوع. */
export function pointsFor(loyalty, paid) {
  if (!loyalty.enabled) return 0;
  return Math.floor((Math.max(0, paid) * loyalty.pointsPer1000) / 1000);
}

/**
 * الحساب الكامل.
 * lines: [{ productId, quantity, note, imageUrl, voiceUrl }]
 * products: Map(productId → بيانات المنتج من Firestore أو null)
 * يرجع { items, unavailable, subtotal, coupon, couponError, points, total, pointsToEarn, maxPoints }
 */
export function computeQuote({
  lines, products, loyalty, coupon = null, couponCode = '', couponUses = 0, isFirstOrder = true,
  uid = '', balance = 0, requestedPoints = 0, now,
}) {
  const items = [];
  const unavailable = [];
  for (const line of lines) {
    const product = products.get(line.productId);
    const price = Math.trunc(Number(product?.price));
    if (!product || product.available === false || !(price > 0)) {
      unavailable.push({ productId: line.productId, name: product?.name || '' });
      continue;
    }
    items.push({
      productId: line.productId,
      name: String(product.name || ''),
      price,
      quantity: line.quantity,
      ...(line.note ? { note: line.note } : {}),
      ...(line.imageUrl ? { imageUrl: line.imageUrl } : {}),
      ...(line.voiceUrl ? { voiceUrl: line.voiceUrl } : {}),
    });
  }
  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  let couponResult = null;
  let couponError = null;
  if (couponCode) {
    const result = evaluateCoupon(coupon, { subtotal, now, uid, uses: couponUses, isFirstOrder });
    if (result.error) couponError = { code: result.error, message: couponMessage(result.error, coupon) };
    else couponResult = { code: couponCode, amount: result.amount };
  }
  const afterCoupon = subtotal - (couponResult?.amount || 0);

  const maxPoints = uid ? maxRedeemablePoints(loyalty, afterCoupon, balance) : 0;
  const usedPoints = Math.min(Math.max(0, Math.trunc(Number(requestedPoints) || 0)), maxPoints);
  const points = usedPoints > 0 && usedPoints >= loyalty.minRedeemPoints
    ? { points: usedPoints, amount: Math.min(usedPoints * loyalty.pointValue, afterCoupon) }
    : null;
  const total = afterCoupon - (points?.amount || 0);

  return {
    items,
    unavailable,
    subtotal,
    coupon: couponResult,
    couponError,
    points,
    total,
    maxPoints,
    pointsToEarn: uid ? pointsFor(loyalty, total) : 0,
  };
}
