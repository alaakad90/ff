// الطلبات بالسيرفر: حساب السعر (quote)، وإنشاء الطلب (place) بمعاملة وحدة ذرية،
// ومتابعة طلب الزائر برقم الطلب ومفتاح المتابعة.
//
// ليش بالسيرفر؟ الأسعار والخصومات والنقاط لازم تنحسب من بيانات Firestore نفسها،
// مو من التطبيق، حتى محد يكدر يغير السعر أو يستعمل كوبون أو نقاط مو إله.

import { ConflictError } from './db.js';
import { deliveryZones, findZone } from './delivery.js';
import { computeQuote, COUPON_CODE, loyaltySettings, normalizeCode, phoneKey } from './pricing.js';

export const WEEK_DAYS = ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];
const PICKUP = ['delivery', 'pickup'];
const PRODUCT_ID = /^[A-Za-z0-9_-]{1,64}$/;
export const REQUEST_ID = /^[A-Za-z0-9]{16,40}$/;
const MAX_LINES = 50;
const MAX_QUANTITY = 99;
const MAX_OPTIONS = 10;

/** خطأ يرجع للتطبيق بحالة HTTP ورسالة عربية. */
export class OrderError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const text = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');
const isUrl = (value) => typeof value === 'string' && value.length <= 1000 && /^https:\/\/[^\s]+$/.test(value);

/** يتحقق من سطور السلة. */
export function parseLines(raw) {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_LINES) {
    throw new OrderError(400, 'invalid_items', 'السلة فارغة أو كبيرة كلش');
  }
  return raw.map((line) => {
    const quantity = Number(line?.quantity);
    if (!PRODUCT_ID.test(line?.productId || '') || !Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QUANTITY) {
      throw new OrderError(400, 'invalid_items', 'منتج أو كمية غلط بالسلة');
    }
    if ((line.imageUrl && !isUrl(line.imageUrl)) || (line.voiceUrl && !isUrl(line.voiceUrl))) {
      throw new OrderError(400, 'invalid_items', 'مرفق غلط بالسلة');
    }
    const options = parseOptions(line.options);
    return {
      productId: line.productId,
      quantity,
      note: text(line.note, 500),
      imageUrl: line.imageUrl || '',
      voiceUrl: line.voiceUrl || '',
      ...(options.length ? { options } : {}),
    };
  });
}

/** اختيارات الزبون للمنتج: [{ name, value }]. نتأكد منها مقابل المنتج بالحساب (computeQuote). */
function parseOptions(raw) {
  if (raw == null) return [];
  if (!Array.isArray(raw) || raw.length > MAX_OPTIONS) throw new OrderError(400, 'invalid_items', 'خيارات غلط بالسلة');
  const names = new Set();
  return raw.map((option) => {
    const name = text(option?.name, 60);
    const value = text(option?.value, 100);
    if (!name || !value || names.has(name)) throw new OrderError(400, 'invalid_items', 'خيارات غلط بالسلة');
    names.add(name);
    return { name, value };
  });
}

export function parseCustomer(raw, pickupMethod) {
  const customer = {
    name: text(raw?.name, 100),
    phone: text(raw?.phone, 20),
    address: pickupMethod === 'delivery' ? text(raw?.address, 300) : '',
    notes: text(raw?.notes, 500),
  };
  if (!customer.name) throw new OrderError(400, 'invalid_customer', 'اكتب الاسم');
  if (customer.phone.replace(/\D/g, '').length < 10) throw new OrderError(400, 'invalid_customer', 'اكتب رقم هاتف صحيح');
  if (pickupMethod === 'delivery' && !customer.address) throw new OrderError(400, 'invalid_customer', 'اكتب العنوان');
  return customer;
}

function parseCoupon(raw) {
  const code = normalizeCode(raw);
  if (code && !COUPON_CODE.test(code)) throw new OrderError(400, 'coupon_invalid', 'الكوبون مو صحيح');
  return code;
}

/** معرّف استعمال الكوبون: بالحساب وبالهاتف، حتى الزبون ما يكرر الكوبون بحساب ثاني. */
const useKeys = (uid, phone) => [uid && `u_${uid}`, phoneKey(phone) && `p_${phoneKey(phone)}`].filter(Boolean);

/**
 * يقرا كل اللي يحتاجه الحساب (بمعاملة إذا انطت tx) ويحسب.
 * reader: db أو tx (عدهم get وquery بنفس الشكل).
 */
async function loadAndQuote(reader, {
  user, lines, couponCode, requestedPoints, phone, now, pickupMethod = 'delivery', zoneId = '', requireZone = false,
}) {
  const uid = user && !user.anonymous ? user.uid : '';
  const ids = [...new Set(lines.map((l) => l.productId))];
  const [productDocs, settingsDoc, walletDoc, couponDoc, deliveryDoc] = await Promise.all([
    Promise.all(ids.map((id) => reader.get(`products/${id}`))),
    reader.get('settings/loyalty'),
    uid ? reader.get(`wallets/${uid}`) : null,
    couponCode ? reader.get(`coupons/${couponCode}`) : null,
    pickupMethod === 'delivery' && zoneId ? reader.get('settings/delivery') : null,
  ]);
  // أجور التوصيل من إعدادات المتجر، مو من التطبيق. الاستلام من المحل بلا أجور.
  let zone = null;
  if (pickupMethod === 'delivery') {
    zone = zoneId ? findZone(deliveryZones(deliveryDoc?.data), zoneId) : null;
    if (!zone && (requireZone || zoneId)) throw new OrderError(400, 'invalid_zone', 'اختار المحافظة');
  }
  const products = new Map(ids.map((id, i) => [id, productDocs[i]?.data || null]));
  const loyalty = loyaltySettings(settingsDoc?.data);
  const wallet = walletDoc?.data || {};

  let couponUses = 0;
  let useDocs = [];
  let isFirstOrder = true;
  if (couponDoc) {
    const keys = useKeys(uid, phone);
    useDocs = await Promise.all(keys.map((key) => reader.get(`coupons/${couponCode}/uses/${key}`)));
    couponUses = Math.max(0, ...useDocs.map((d) => Number(d?.data.count) || 0));
    if (couponDoc.data.firstOrderOnly) isFirstOrder = await firstOrder(reader, uid, phone, wallet);
  }

  const quote = computeQuote({
    lines,
    products,
    loyalty,
    coupon: couponDoc ? couponDoc.data : null,
    couponCode,
    couponUses,
    isFirstOrder,
    uid,
    balance: Number(wallet.points) || 0,
    requestedPoints,
    now,
    deliveryFee: zone?.fee || 0,
  });
  return { quote: { ...quote, zone }, uid, loyalty, wallet, walletDoc, couponDoc, useDocs };
}

/** أول طلب للزبون؟ بالحساب وبرقم الهاتف. */
async function firstOrder(reader, uid, phone, wallet) {
  if ((Number(wallet.ordersPlaced) || 0) > 0) return false;
  const checks = [];
  if (uid) checks.push(reader.query('orders', { where: [['userId', '==', uid]], limit: 1 }));
  const key = phoneKey(phone);
  if (key) checks.push(reader.query('orders', { where: [['phoneKey', '==', key]], limit: 1 }));
  return (await Promise.all(checks)).every((rows) => rows.length === 0);
}

/** شكل الحساب اللي يرجع للتطبيق. */
export function publicQuote(quote) {
  return {
    items: quote.items.map(({ productId, name, price, quantity, options }) => (
      { productId, name, price, quantity, ...(options?.length ? { options } : {}) })),
    unavailable: quote.unavailable,
    subtotal: quote.subtotal,
    coupon: quote.coupon,
    couponError: quote.couponError,
    points: quote.points,
    maxPoints: quote.maxPoints,
    deliveryFee: quote.deliveryFee,
    deliveryCharged: quote.deliveryCharged,
    zone: quote.zone ? { id: quote.zone.id, name: quote.zone.name } : null,
    total: quote.total,
    pointsToEarn: quote.pointsToEarn,
  };
}

/** POST /api/quote: يحسب السعر بدون ما يحفظ شي. */
export async function quoteOrder(ctx, user, body) {
  const lines = parseLines(body?.items);
  const { quote, wallet } = await loadAndQuote(ctx.db, {
    user,
    lines,
    couponCode: parseCoupon(body?.coupon),
    requestedPoints: body?.points,
    phone: text(body?.phone, 20),
    now: ctx.now,
    pickupMethod: body?.pickupMethod === 'pickup' ? 'pickup' : 'delivery',
    zoneId: typeof body?.zoneId === 'string' ? body.zoneId : '',
  });
  return { ...publicQuote(quote), balance: Number(wallet.points) || 0 };
}

function randomKey(length = 24) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

/**
 * POST /api/orders: ينشئ الطلب. requestId من التطبيق يصير رقم الطلب، فإذا الزبون ضغط مرتين
 * أو النت انقطع وأعاد المحاولة، ما يتكرر الطلب (يرجع نفس الطلب).
 * expectedTotal: المبلغ اللي شافه الزبون؛ إذا تغير (سعر تغير مثلاً) نرجع 409 ويا الحساب الجديد.
 */
export async function placeOrder(ctx, user, body) {
  const requestId = body?.requestId;
  if (typeof requestId !== 'string' || !REQUEST_ID.test(requestId)) {
    throw new OrderError(400, 'invalid_request', 'رقم الطلب غلط');
  }
  const pickupMethod = PICKUP.includes(body?.pickupMethod) ? body.pickupMethod : null;
  if (!pickupMethod) throw new OrderError(400, 'invalid_request', 'طريقة الاستلام غلط');
  if (!WEEK_DAYS.includes(body?.deliveryDay)) throw new OrderError(400, 'invalid_request', 'اختار يوم التسليم');
  const customer = parseCustomer(body?.customer, pickupMethod);
  const lines = parseLines(body?.items);
  const couponCode = parseCoupon(body?.coupon);
  const pushToken = typeof body?.pushToken === 'string' && body.pushToken.length <= 4096 ? body.pushToken : '';
  const zoneId = pickupMethod === 'delivery' && typeof body?.zoneId === 'string' ? body.zoneId : '';
  // النسخ القديمة من التطبيق ما ترسل محافظة: نقبل طلبها بلا أجور توصيل (وننبه صاحب المتجر)،
  // لحد ما يطفي "قبول طلبات النسخ القديمة" من لوحة التحكم.
  let zoneMissing = false;
  if (pickupMethod === 'delivery' && !zoneId) {
    const settings = await ctx.db.get('settings/orders');
    if (body?.zoneId !== undefined || settings?.data.legacyClientOrders === false) {
      throw new OrderError(400, 'invalid_zone', 'اختار المحافظة');
    }
    zoneMissing = true;
  }
  const now = ctx.now;
  const orderPath = `orders/${requestId}`;

  const place = (tx) => createInTransaction(tx, {
    user, body, requestId, orderPath, customer, lines, couponCode, pickupMethod, zoneId, zoneMissing, pushToken, now,
  });

  // إذا طلبات كثيرة سوا على نفس الكوبون أو نفس المحفظة، المعاملة ممكن تتعارض وتنعاد.
  // قبل كل إعادة نفحص الحالة الحالية بدون قفل: إذا الكوبون خلص أو النقاط تغيرت نرجع
  // السبب الصحيح فوراً، بدال ما نبقى نتزاحم على نفس الوثيقة.
  const MAX_ATTEMPTS = 4;
  let result;
  for (let attempt = 1; ; attempt++) {
    if (attempt > 1 && !(await ctx.db.get(orderPath))) {
      const { quote } = await loadAndQuote(ctx.db, {
        user, lines, couponCode, requestedPoints: body?.points, phone: customer.phone, now, pickupMethod, zoneId, requireZone: !zoneMissing,
      });
      checkQuote(quote, body);
    }
    try {
      result = await ctx.db.runTransaction(place, { attempts: 1 });
      break;
    } catch (error) {
      if (!(error instanceof ConflictError)) throw error;
      if (attempt >= MAX_ATTEMPTS) throw new OrderError(409, 'busy', 'المتجر مشغول هسه، حاول مرة ثانية');
      await new Promise((resolve) => setTimeout(resolve, 50 + Math.random() * 250 * attempt));
    }
  }

  return { orderId: requestId, ...result };
}

/** يرفض الطلب إذا الحساب ما يطابق اللي طلبه الزبون (منتج ما متوفر، كوبون، نقاط، سعر تغير). */
function checkQuote(quote, body) {
  if (quote.unavailable.length) {
    const message = quote.unavailable.every((u) => u.reason === 'options')
      ? 'خيارات بعض المنتجات تغيرت، احذفها من السلة واختارها من جديد'
      : 'بعض المنتجات ما متوفرة هسه';
    throw new OrderError(409, 'unavailable', message, { quote: publicQuote(quote) });
  }
  if (quote.couponError) {
    throw new OrderError(409, 'coupon_invalid', quote.couponError.message, { quote: publicQuote(quote) });
  }
  const requested = Math.trunc(Number(body?.points) || 0);
  if (requested > 0 && (quote.points?.points || 0) !== requested) {
    throw new OrderError(409, 'points_changed', 'رصيد النقاط تغير', { quote: publicQuote(quote) });
  }
  if (body?.expectedTotal != null && Number(body.expectedTotal) !== quote.total) {
    throw new OrderError(409, 'price_changed', 'الأسعار تغيرت، شوف المجموع الجديد', { quote: publicQuote(quote) });
  }
}

/** داخل المعاملة: يتأكد ويكتب الطلب والنقاط والكوبون سوا. */
async function createInTransaction(tx, {
  user, body, requestId, orderPath, customer, lines, couponCode, pickupMethod, zoneId, zoneMissing, pushToken, now,
}) {
  const existing = await tx.get(orderPath);
  if (existing) {
    const owner = existing.data.userId || '';
    const caller = user && !user.anonymous ? user.uid : '';
    if (existing.data.pricedBy !== 'server' || owner !== caller) {
      throw new OrderError(409, 'duplicate', 'هذا الطلب موجود');
    }
    return { duplicate: true, order: existing.data };
  }

  const loaded = await loadAndQuote(tx, {
    user, lines, couponCode, requestedPoints: body?.points, phone: customer.phone, now, pickupMethod, zoneId, requireZone: !zoneMissing,
  });
  const { quote, uid, wallet, walletDoc, couponDoc, useDocs } = loaded;
  checkQuote(quote, body);

  const order = {
    customer,
    items: quote.items,
    subtotal: quote.subtotal,
    discount: (quote.coupon?.amount || 0) + (quote.points?.amount || 0),
    ...(quote.coupon ? { coupon: quote.coupon } : {}),
    ...(quote.points ? { pointsUsed: quote.points.points, pointsDiscount: quote.points.amount } : {}),
    // أجور التوصيل اللي يدفعها (0 للاستلام أو إذا كوبون توصيل مجاني)، والمحافظة.
    deliveryFee: quote.deliveryCharged,
    ...(quote.zone ? { deliveryZone: { id: quote.zone.id, name: quote.zone.name, fee: quote.zone.fee } } : {}),
    ...(zoneMissing ? { deliveryZoneMissing: true } : {}),
    total: quote.total,
    status: 'new',
    statusHistory: [{ status: 'new', at: now }],
    createdAt: now,
    deliveryDay: body.deliveryDay,
    pickupMethod,
    ...(uid ? { userId: uid } : {}),
    ...(pushToken ? { pushToken } : {}),
    phoneKey: phoneKey(customer.phone),
    trackingKey: randomKey(),
    pricedBy: 'server',
  };
  tx.create(orderPath, order);

  if (uid) {
    const points = (Number(wallet.points) || 0) - (quote.points?.points || 0);
    const walletUpdate = {
      points,
      ordersPlaced: (Number(wallet.ordersPlaced) || 0) + 1,
      updatedAt: now,
    };
    if (walletDoc) tx.update(`wallets/${uid}`, walletUpdate);
    else tx.create(`wallets/${uid}`, { ...walletUpdate, lifetimeEarned: 0, createdAt: now });
    if (quote.points) {
      tx.create(`wallets/${uid}/ledger/redeem-${requestId}`, {
        type: 'redeem', points: -quote.points.points, orderId: requestId, createdAt: now,
        note: `خصم ${quote.points.amount} د.ع على الطلب`,
      });
    }
  }
  if (quote.coupon) {
    tx.update(`coupons/${couponCode}`, { usedCount: (Number(couponDoc.data.usedCount) || 0) + 1, updatedAt: now });
    const keys = useKeys(uid, customer.phone);
    keys.forEach((key, i) => {
      tx.set(`coupons/${couponCode}/uses/${key}`, {
        count: (Number(useDocs[i]?.data.count) || 0) + 1, lastOrderId: requestId, updatedAt: now,
      });
    });
  }
  return { duplicate: false, order };
}

/** يقارن نصين بوقت ثابت تقريباً (حتى ما ينعرف المفتاح حرف حرف من وقت الرد). */
function sameText(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** حالة الطلب للتطبيق (بدون معلومات حساسة). */
export function trackingView(orderId, order) {
  return {
    orderId,
    status: order.status,
    statusHistory: (order.statusHistory || []).map((h) => ({ status: h.status, at: h.at?.toISOString?.() || null })),
    createdAt: order.createdAt?.toISOString?.() || null,
    deliveryDay: order.deliveryDay || '',
    pickupMethod: order.pickupMethod || 'delivery',
    items: (order.items || []).map(({ productId, name, price, quantity, options }) => (
      { productId, name, price, quantity, ...(options?.length ? { options } : {}) })),
    subtotal: order.subtotal ?? order.total,
    discount: order.discount || 0,
    deliveryFee: order.deliveryFee || 0,
    deliveryZone: order.deliveryZone?.name || '',
    freeDelivery: Boolean(order.coupon?.freeDelivery),
    total: order.total,
  };
}

/** POST /api/orders/track { orderId, key }: الزائر (بدون حساب) يتابع طلبه. */
export async function trackOrder(ctx, body) {
  const orderId = body?.orderId;
  if (typeof orderId !== 'string' || !REQUEST_ID.test(orderId)) throw new OrderError(404, 'not_found', 'الطلب مو موجود');
  const doc = await ctx.db.get(`orders/${orderId}`);
  if (!doc || !sameText(doc.data.trackingKey, body?.key)) throw new OrderError(404, 'not_found', 'الطلب مو موجود');
  return trackingView(orderId, doc.data);
}
