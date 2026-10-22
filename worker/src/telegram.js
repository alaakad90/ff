// نص رسالة الطلب للتليجرام، بنفس شكل الرسالة اللي كان يدزها التطبيق.

const WEEK_DAYS = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const PICKUP_LABELS = { delivery: 'توصيل', pickup: 'استلام من المحل' };

/** السعر بفواصل الآلاف، مثل: 25,000 د.ع */
export function formatPrice(price) {
  return `${String(Math.round(price)).replace(/\B(?=(\d{3})+(?!\d))/g, ',')} د.ع`;
}

const two = (n) => String(n).padStart(2, '0');

/** وقت الطلب بتوقيت بغداد (UTC+3، ماكو توقيت صيفي). */
export function formatBaghdadTime(date) {
  const d = new Date(date.getTime() + 3 * 60 * 60 * 1000);
  return `${WEEK_DAYS[d.getUTCDay()]} ${d.getUTCFullYear()}/${two(d.getUTCMonth() + 1)}/${two(d.getUTCDate())} `
    + `${two(d.getUTCHours())}:${two(d.getUTCMinutes())}`;
}

export function buildMessage(orderId, order) {
  const customer = order.customer || {};
  const items = order.items || [];
  const lines = [
    '🛍️ طلب جديد',
    `🔖 رقم الطلب: ${orderId}`,
  ];
  if (order.createdAt instanceof Date) lines.push(`🕒 وقت الطلب: ${formatBaghdadTime(order.createdAt)}`);
  lines.push('');
  if (order.deliveryDay) lines.push(`📅 يوم التسليم: ${order.deliveryDay}`);
  lines.push(`🚚 طريقة الاستلام: ${PICKUP_LABELS[order.pickupMethod] || PICKUP_LABELS.delivery}`);
  lines.push('');
  lines.push(`👤 الاسم: ${customer.name || ''}`);
  lines.push(`📞 الهاتف: ${customer.phone || ''}`);
  if (customer.address) lines.push(`📍 العنوان: ${customer.address}`);
  if (customer.notes) lines.push(`📝 ملاحظات: ${customer.notes}`);
  lines.push('');
  lines.push('📦 المنتجات:');
  for (const item of items) {
    const quantity = Number(item.quantity) || 0;
    const price = Number(item.price) || 0;
    lines.push(`• ${item.name} × ${quantity} = ${formatPrice(price * quantity)}`);
    if (item.note) lines.push(`   📝 ${item.note}`);
  }
  lines.push('');
  lines.push(`💰 المجموع: ${formatPrice(Number(order.total) || 0)}`);
  lines.push('💵 الدفع: عند الاستلام');
  return lines.join('\n');
}

export async function sendTelegram({ botToken, chatId, text, fetchImpl = fetch }) {
  const response = await fetchImpl(`https://api.telegram.org/bot${botToken}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text }),
  });
  if (!response.ok) throw new Error(`telegram ${response.status}: ${await response.text()}`);
}
