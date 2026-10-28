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
  no_delivery: 'كوبون التوصيل المجاني للطلبات اللي تنوصل بس',
};

export function couponMessage(code, coupon) {
  if (code === 'min_subtotal' && coupon) return `${COUPON_ERRORS.min_subtotal} (${coupon.minSubtotal} د.ع)`;
  return COUPON_ERRORS[code] || 'الكوبون مو صالح';
}

/**
 * يتحقق من الكوبون ويحسب خصمه. يرجع { amount } أو { amount, freeDelivery } أو { error }.
 * الخصم على المنتجات بس (subtotal)؛ كوبون التوصيل المجاني يشيل أجور التوصيل (deliveryFee).
 * uses: عدد مرات استعمال هذا الزبون للكوبون (بالحساب أو بالهاتف، الأكثر).
 */
export function evaluateCoupon(coupon, { subtotal, now, uid, uses = 0, isFirstOrder = true, deliveryFee = 0 }) {
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
  if (coupon.type === 'freeDelivery') {
    return deliveryFee > 0 ? { amount: deliveryFee, freeDelivery: true } : { error: 'no_delivery' };
  }

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
 * كل اختيار لازم يكون حقل موجود بالمنتج وقيمة من اختياراته، والحقول الإجبارية مختارة.
 * الطلبات القديمة (بلا أي اختيارات) تنقبل حتى لو المنتج بيه حقول: صاحب المتجر يسأل الزبون.
 */
export function validOptions(product, chosen) {
  const fields = Array.isArray(product?.options) ? product.options : [];
  for (const { name, value } of chosen) {
    const field = fields.find((f) => f?.name === name);
    if (!field || !Array.isArray(field.choices) || !field.choices.includes(value)) return false;
  }
  if (!chosen.length) return true;
  return fields.every((f) => f?.required === false || chosen.some((c) => c.name === f?.name));
}

/**
 * الحساب الكامل.
 * lines: [{ productId, quantity, note, imageUrl, voiceUrl, options }]
 * products: Map(productId → بيانات المنتج من Firestore أو null)
 * deliveryFee: أجور التوصيل للمحافظة (0 للاستلام من المحل). الكوبون والنقاط على المنتجات بس،
 * والتوصيل يبقى ثابت إلا إذا الكوبون "توصيل مجاني".
 * يرجع { items, unavailable, subtotal, coupon, couponError, points, deliveryFee, deliveryCharged,
 *        productsTotal, total, pointsToEarn, maxPoints }
 */
export function computeQuote({
  lines, products, loyalty, coupon = null, couponCode = '', couponUses = 0, isFirstOrder = true,
  uid = '', balance = 0, requestedPoints = 0, now, deliveryFee = 0,
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
    // الاختيارات لازم تكون من اللي حطها المدير للمنتج هسه (إذا تغيرت، الزبون يختار من جديد).
    if (!validOptions(product, line.options || [])) {
      unavailable.push({ productId: line.productId, name: String(product.name || ''), reason: 'options' });
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
      ...(line.options?.length ? { options: line.options } : {}),
    });
  }
  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  let couponResult = null;
  let couponError = null;
  if (couponCode) {
    const result = evaluateCoupon(coupon, { subtotal, now, uid, uses: couponUses, isFirstOrder, deliveryFee });
    if (result.error) couponError = { code: result.error, message: couponMessage(result.error, coupon) };
    else couponResult = { code: couponCode, amount: result.amount, ...(result.freeDelivery ? { freeDelivery: true } : {}) };
  }
  const productDiscount = couponResult && !couponResult.freeDelivery ? couponResult.amount : 0;
  const afterCoupon = subtotal - productDiscount;

  const maxPoints = uid ? maxRedeemablePoints(loyalty, afterCoupon, balance) : 0;
  const usedPoints = Math.min(Math.max(0, Math.trunc(Number(requestedPoints) || 0)), maxPoints);
  const points = usedPoints > 0 && usedPoints >= loyalty.minRedeemPoints
    ? { points: usedPoints, amount: Math.min(usedPoints * loyalty.pointValue, afterCoupon) }
    : null;
  const productsTotal = afterCoupon - (points?.amount || 0);
  const fee = Math.max(0, Math.trunc(Number(deliveryFee) || 0));
  const deliveryCharged = couponResult?.freeDelivery ? 0 : fee;

  return {
    items,
    unavailable,
    subtotal,
    coupon: couponResult,
    couponError,
    points,
    deliveryFee: fee,
    deliveryCharged,
    productsTotal,
    total: productsTotal + deliveryCharged,
    maxPoints,
    // النقاط على اللي ندفع للمنتجات، مو على التوصيل.
    pointsToEarn: uid ? pointsFor(loyalty, productsTotal) : 0,
  };
}
