// سيرفر متجر لاكاسا.
//
// POST /notify-order  { "orderId": "..." }
//   التطبيق يناديه بعد ما يحفظ الطلب بـ Firestore. السيرفر يقرا الطلب بنفسه،
//   ويدز رسالة التليجرام مرة وحدة بس، وللطلبات الجديدة بس. هيج توكن البوت
//   ما يكون داخل التطبيق، ومحد يكدر يدز رسائل وهمية.

import { claimOrder, getOrder, releaseOrder } from './firestore.js';
import { getAccessToken } from './google.js';
import { buildMessage, sendTelegram } from './telegram.js';

/** الطلبات الأقدم من هيج ما ينبعث إلها إشعار (ما نعيد طلبات قديمة). */
export const MAX_ORDER_AGE_MS = 60 * 60 * 1000;

const ORDER_ID = /^[A-Za-z0-9]{1,64}$/;

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });

export async function notifyOrder(orderId, env, { fetchImpl = fetch, now = new Date(Date.now()) } = {}) {
  const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
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
  return json(200, { ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/' && request.method === 'GET') {
      return json(200, { ok: true, service: 'lacasa-store' });
    }
    if (url.pathname !== '/notify-order') return json(404, { error: 'not found' });
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
      return await notifyOrder(orderId, env);
    } catch (error) {
      console.error('notify-order failed', orderId, error);
      return json(502, { error: 'notify failed' });
    }
  },
};
