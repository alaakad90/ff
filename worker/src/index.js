// سيرفر متجر لاكاسا.
//
// POST /notify-order   { "orderId": "..." }
//   التطبيق يناديه بعد ما يحفظ الطلب بـ Firestore. السيرفر يقرا الطلب بنفسه،
//   ويدز رسالة التليجرام مرة وحدة بس، وللطلبات الجديدة بس. هيج توكن البوت
//   ما يكون داخل التطبيق، ومحد يكدر يدز رسائل وهمية.
//
// POST /notify-status  { "orderId": "..." }
//   لوحة التحكم تناديه بعد ما تغير حالة الطلب. السيرفر يقرا الحالة بنفسه ويرسل إشعار
//   لتليفون الزبون مرة وحدة لكل حالة. محد يكدر يغير الحالة غير المدير (قواعد Firestore)،
//   فمناداته من غير مكان ما ترسل شي جديد.

import { bearer, verifyIdToken } from './auth.js';
import { MAX_ORDER_AGE_MS } from './config.js';
import { createDb } from './db.js';
import {
  claimOrder, decodeFields, deleteAdminDevice, getOrder, listAdminDevices, releaseOrder, setStatusNotified,
} from './firestore.js';
import { getAccessToken } from './google.js';
import {
  OrderError, placeOrder, quoteOrder, trackOrder,
} from './orders.js';
import { privacyPage, supportPage } from './pages.js';
import { newOrderMessage, sendPush, statusMessage } from './push.js';
import { applyReferral, referralCode } from './referrals.js';
import { setOrderStatus } from './rewards.js';
import { buildMessage, sendTelegram } from './telegram.js';


const ORDER_ID = /^[A-Za-z0-9]{1,64}$/;

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });

/** يقبل ملف المفتاح حتى لو انلصق بدون { و } أو ويا BOM. */
export function parseServiceAccount(raw) {
  let text = raw.replace(/^\uFEFF/, '').trim();
  if (text.startsWith('"')) text = `{${text.replace(/,$/, '')}}`;
  return JSON.parse(text);
}

export async function notifyOrder(orderId, env, { fetchImpl = fetch, now = new Date(Date.now()) } = {}) {
  const serviceAccount = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);
  const projectId = serviceAccount.project_id;
  const token = await getAccessToken(serviceAccount, fetchImpl, now.getTime());

  const order = await getOrder({ projectId, token, orderId, fetchImpl });
  if (!order) return json(404, { error: 'order not found' });
  if (order.data.notifiedAt) return json(200, { ok: true, alreadyNotified: true });

  const createdAt = order.data.createdAt;
  if (!(createdAt instanceof Date) || now.getTime() - createdAt.getTime() > MAX_ORDER_AGE_MS) {
    return json(409, { error: 'order too old' });
  }

  const claimed = await claimOrder({ projectId, token, orderId, updateTime: order.updateTime, fetchImpl, now });
  if (!claimed) return json(200, { ok: true, alreadyNotified: true });

  try {
    await sendTelegram({
      botToken: env.BOT_TOKEN,
      chatId: env.CHAT_ID,
      text: buildMessage(orderId, order.data),
      fetchImpl,
    });
  } catch (error) {
    // نرجع الطلب مثل ما كان حتى المحاولة الجاية تكدر تدز.
    await releaseOrder({ projectId, token, orderId, fetchImpl }).catch(() => {});
    throw error;
  }
  // الإشعار إضافة على التليجرام: إذا فشل ما نعيد رسالة التليجرام.
  await notifyAdmins({ projectId, token, order: order.data, fetchImpl }).catch((error) => {
    console.error('admin push failed', orderId, error);
  });
  return json(200, { ok: true });
}

/** يرسل "طلب جديد" لكل موبايلات صاحب المتجر، ويشيل الموبايلات اللي انمسح منها التطبيق. */
async function notifyAdmins({ projectId, token, order, fetchImpl }) {
  const devices = await listAdminDevices({ projectId, token, fetchImpl });
  const message = newOrderMessage(order);
  await Promise.all(devices.map(async (deviceToken) => {
    const result = await sendPush({ projectId, token, deviceToken, ...message, fetchImpl });
    if (result === 'unregistered') await deleteAdminDevice({ projectId, token, deviceToken, fetchImpl });
  }));
}

export async function notifyStatus(orderId, env, { fetchImpl = fetch, now = new Date(Date.now()) } = {}) {
  const serviceAccount = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);
  const projectId = serviceAccount.project_id;
  const token = await getAccessToken(serviceAccount, fetchImpl, now.getTime());

  const order = await getOrder({ projectId, token, orderId, fetchImpl });
  if (!order) return json(404, { error: 'order not found' });
  if (order.data.pricedBy === 'server') {
    // طلب من النسخة الجديدة بس المدير غيّر الحالة من نسخة قديمة: نفس مسار السيرفر الجديد.
    const ctx = { db: createDb({ projectId, token, fetchImpl }), projectId, token, fetchImpl, now };
    return json(200, await setOrderStatus(ctx, { orderId, status: order.data.status }));
  }
  const { status, statusNotified, pushToken } = order.data;
  const message = statusMessage(order.data);
  if (!message || !pushToken) return json(200, { ok: true, skipped: true });
  if (statusNotified === status) return json(200, { ok: true, alreadyNotified: true });

  const claimed = await setStatusNotified({
    projectId, token, orderId, value: status, updateTime: order.updateTime, fetchImpl,
  });
  if (!claimed) return json(200, { ok: true, alreadyNotified: true });

  try {
    const result = await sendPush({ projectId, token, deviceToken: pushToken, ...message, fetchImpl });
    return json(200, { ok: true, ...(result === 'unregistered' ? { unregistered: true } : {}) });
  } catch (error) {
    // نرجع الحالة السابقة حتى المحاولة الجاية تكدر ترسل.
    await setStatusNotified({ projectId, token, orderId, value: statusNotified ?? null, fetchImpl }).catch(() => {});
    throw error;
  }
}

const ROUTES = { '/notify-order': notifyOrder, '/notify-status': notifyStatus };

/** يرسل رسالة التليجرام وإشعار صاحب المتجر لطلب انسوى بالسيرفر، ويعلّمه حتى ما يتكرر. */
async function announceOrder(ctx, orderId, order) {
  await sendTelegram({
    botToken: ctx.env.BOT_TOKEN, chatId: ctx.env.CHAT_ID, text: buildMessage(orderId, order), fetchImpl: ctx.fetchImpl,
  });
  await ctx.db.apply('merge', `orders/${orderId}`, { notifiedAt: ctx.now }).catch(() => {});
  const devices = await ctx.db.query('adminDevices', { limit: 50 });
  const message = newOrderMessage(order);
  await Promise.all(devices.map(async (device) => {
    const deviceToken = decodeURIComponent(device.id);
    const result = await sendPush({ projectId: ctx.projectId, token: ctx.token, deviceToken, ...message, fetchImpl: ctx.fetchImpl });
    if (result === 'unregistered') await ctx.db.apply('delete', `adminDevices/${device.id}`);
  }));
}

/** الطلب الجديد ينحفظ أول؛ التليجرام والإشعار إضافة: إذا فشلوا ما نفشّل الطلب. */
async function createOrder(ctx, user, body) {
  const result = await placeOrder(ctx, user, body);
  if (!result.duplicate) {
    await announceOrder(ctx, result.orderId, result.order).catch((error) => {
      console.error('announce failed', result.orderId, error);
    });
  }
  return {
    ok: true,
    orderId: result.orderId,
    duplicate: result.duplicate,
    trackingKey: result.order.trackingKey,
    total: result.order.total,
    subtotal: result.order.subtotal,
    discount: result.order.discount || 0,
  };
}

async function requireAdmin(ctx, user) {
  if (!user || user.anonymous || !(await ctx.db.get(`admins/${user.uid}`))) {
    throw new OrderError(403, 'forbidden', 'هذا للمدير بس');
  }
}

/** مسارات /api: كلها POST وJSON، والهوية من توكن Firebase (اختياري للطلب والمتابعة). */
const API = {
  '/api/quote': (ctx, user, body) => quoteOrder(ctx, user, body),
  '/api/orders': createOrder,
  '/api/orders/track': (ctx, _user, body) => trackOrder(ctx, body),
  '/api/referral/code': (ctx, user) => referralCode(ctx, user),
  '/api/referral/apply': (ctx, user, body) => applyReferral(ctx, user, body),
  '/api/admin/order-status': async (ctx, user, body) => {
    await requireAdmin(ctx, user);
    return setOrderStatus(ctx, body);
  },
};

/** السياق الافتراضي: Firestore الحقيقي بمفتاح الخدمة. بالاختبارات ينبدل بالمحاكي. */
export async function defaultContext(env, { fetchImpl = fetch, now = Date.now() } = {}) {
  const serviceAccount = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);
  const projectId = serviceAccount.project_id;
  const token = await getAccessToken(serviceAccount, fetchImpl, now);
  return {
    env,
    projectId,
    token,
    fetchImpl,
    now: new Date(now),
    db: createDb({ projectId, token, fetchImpl }),
    verify: (idToken) => verifyIdToken(idToken, { projectId, fetchImpl, now }),
  };
}

/** يشغل مسار /api. makeContext ينبدل بالاختبارات. */
export async function handleApi(request, env, makeContext = defaultContext) {
  const url = new URL(request.url);
  const route = API[url.pathname];
  if (!route) return json(404, { error: 'not found' });
  if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
  if (!env.FIREBASE_SERVICE_ACCOUNT && makeContext === defaultContext) {
    return json(500, { error: 'server not configured' });
  }
  let body;
  try {
    const raw = await request.text();
    if (raw.length > 64 * 1024) return json(413, { error: 'too large' });
    body = raw ? JSON.parse(raw) : {};
  } catch {
    return json(400, { error: 'invalid json' });
  }
  try {
    const ctx = await makeContext(env);
    const idToken = bearer(request);
    const user = idToken ? await ctx.verify(idToken) : null;
    // توكن مرسل بس غلط أو منتهي: نرفض، حتى التطبيق يجدده بدال ما يطلب كزائر بالغلط.
    if (idToken && !user) return json(401, { error: 'invalid token', code: 'invalid_token' });
    return json(200, await route(ctx, user, body));
  } catch (error) {
    if (error instanceof OrderError) {
      return json(error.status, { error: error.message, code: error.code, ...error.extra });
    }
    console.error(`${url.pathname} failed`, error);
    return json(502, { error: 'server error', code: 'server_error' });
  }
}

const PAGES = { '/privacy': privacyPage, '/support': supportPage };

/** معلومات التواصل من إعدادات المتجر. إذا ما كدرنا نقراها، الصفحة تطلع بدونها. */
async function storeInfo(env) {
  try {
    const serviceAccount = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);
    const token = await getAccessToken(serviceAccount);
    const response = await fetch(
      `https://firestore.googleapis.com/v1/projects/${serviceAccount.project_id}/databases/(default)/documents/settings/store`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    return response.ok ? decodeFields((await response.json()).fields || {}) : {};
  } catch {
    return {};
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/' && request.method === 'GET') {
      return json(200, { ok: true, service: 'lacasa-store' });
    }
    if (url.pathname.startsWith('/api/')) return handleApi(request, env);
    const pageFor = PAGES[url.pathname];
    if (pageFor && request.method === 'GET') {
      return new Response(pageFor(await storeInfo(env)), {
        headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' },
      });
    }
    const handler = ROUTES[url.pathname];
    if (!handler) return json(404, { error: 'not found' });
    if (request.method !== 'POST') return json(405, { error: 'method not allowed' });

    let orderId;
    try {
      ({ orderId } = await request.json());
    } catch {
      return json(400, { error: 'invalid json' });
    }
    if (typeof orderId !== 'string' || !ORDER_ID.test(orderId)) {
      return json(400, { error: 'invalid orderId' });
    }
    if (!env.FIREBASE_SERVICE_ACCOUNT || !env.BOT_TOKEN || !env.CHAT_ID) {
      return json(500, { error: 'server not configured' });
    }

    try {
      return await handler(orderId, env);
    } catch (error) {
      console.error(`${url.pathname} failed`, orderId, error);
      return json(502, { error: 'notify failed' });
    }
  },
};
