// إشعارات Firebase Cloud Messaging: للزبون لما المدير يغير حالة الطلب،
// ولصاحب المتجر لما يجي طلب جديد.

import { formatPrice } from './telegram.js';

/** نص الإشعار لكل حالة. الحالات اللي مو هنا (جديد، ملغي) ما ينبعث إلها إشعار. */
export function statusMessage(order) {
  const pickup = order.pickupMethod === 'pickup';
  const day = order.deliveryDay ? ` يوم التسليم: ${order.deliveryDay}.` : '';
  switch (order.status) {
    case 'confirmed':
      return { title: '✅ انقبل طلبك', body: `استلمنا طلبك وراح نبدي نجهزه.${day}` };
    case 'delivering':
      return pickup
        ? { title: '📦 طلبك جاهز', body: 'طلبك جاهز، تكدر تستلمه من المحل.' }
        : { title: '🚚 طلبك بالطريق', body: 'طلبك طلع للتوصيل وراح يوصلك قريباً.' };
    case 'done':
      return { title: '🎉 تم تسليم طلبك', body: 'شكراً لأنك تسوقت من لاكاسا!' };
    default:
      return null;
  }
}

/** إشعار صاحب المتجر بطلب جديد. */
export function newOrderMessage(order) {
  const customer = order.customer || {};
  const parts = [customer.name, formatPrice(Number(order.total) || 0), order.deliveryDay].filter(Boolean);
  return { title: '🛍️ طلب جديد', body: parts.join(' • ') };
}

/**
 * يرسل إشعار لتليفون واحد. يرجع 'sent'، أو 'unregistered' إذا التوكن ما بقى صالح
 * (الزبون مسح التطبيق مثلاً)، ويرمي خطأ لباقي المشاكل حتى نعيد المحاولة.
 */
export async function sendPush({ projectId, token, deviceToken, title, body, fetchImpl = fetch }) {
  const response = await fetchImpl(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title, body },
        android: { priority: 'HIGH', notification: { sound: 'default' } },
        apns: { payload: { aps: { sound: 'default' } } },
      },
    }),
  });
  if (response.ok) return 'sent';
  const text = await response.text();
  if (response.status === 404 || /UNREGISTERED|registration-token-not-registered/.test(text)) {
    return 'unregistered';
  }
  throw new Error(`fcm ${response.status}: ${text}`);
}
