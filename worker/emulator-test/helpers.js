// أدوات مشتركة لاختبارات المحاكي: Firestore حقيقي (emulator)، والتليجرام وFCM وهميين.

import { createDb } from '../src/db.js';
import { handleApi } from '../src/index.js';

export const PROJECT = 'demo-lacasa';
export const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8085';
export const db = createDb({ projectId: PROJECT, token: 'owner', baseUrl: `http://${HOST}` });

export const sent = { telegram: [], push: [] };

/** fetch: التليجرام وFCM وهميين، وكل شي ثاني (المحاكي) حقيقي. */
export async function fakeFetch(input, init = {}) {
  const url = new URL(typeof input === 'string' ? input : input.url);
  if (url.host === 'api.telegram.org') {
    sent.telegram.push(JSON.parse(init.body));
    return Response.json({ ok: true });
  }
  if (url.host === 'fcm.googleapis.com') {
    sent.push.push(JSON.parse(init.body).message);
    return Response.json({ name: 'projects/x/messages/1' });
  }
  return fetch(input, init);
}

/** توكنات الاختبار: "uid:<id>" حساب عادي، "anon" حساب مجهول، أي شي ثاني غلط. */
async function verify(token) {
  if (token === 'anon') return { uid: 'anon1', anonymous: true };
  if (token.startsWith('uid:')) return { uid: token.slice(4), email: '', anonymous: false };
  return null;
}

export const makeContext = async (env) => ({
  env, projectId: PROJECT, token: 'owner', fetchImpl: fakeFetch, now: new Date(), db, verify,
});

const ENV = { BOT_TOKEN: 'TOKEN123', CHAT_ID: '42' };

/** ينادي مسار /api مثل التطبيق. */
export async function api(path, body, { token } = {}) {
  const request = new Request(`https://lacasastores.com${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  const response = await handleApi(request, ENV, makeContext);
  return { status: response.status, body: await response.json() };
}

/** يمسح كل بيانات المحاكي بين الاختبارات. */
export async function reset() {
  const response = await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {
    method: 'DELETE',
  });
  if (!response.ok) throw new Error(`reset ${response.status}`);
  sent.telegram.length = 0;
  sent.push.length = 0;
}

export async function seed(docs) {
  for (const [path, data] of Object.entries(docs)) await db.apply('set', path, data);
}

let counter = 0;
export const requestId = () => `req${Date.now()}${String(counter++).padStart(6, '0')}`;

export const customer = (phone = '07701234567') => ({ name: 'علي', phone, address: 'بغداد، الكرادة' });

export function orderBody(overrides = {}) {
  return {
    requestId: requestId(),
    customer: customer(),
    items: [{ productId: 'p1', quantity: 2 }],
    deliveryDay: 'الخميس',
    // الاستلام من المحل بلا أجور توصيل، حتى أرقام الاختبارات القديمة تبقى نفسها.
    // اختبارات التوصيل تحط pickupMethod: 'delivery' ويا zoneId.
    pickupMethod: 'pickup',
    pushToken: 'device-token-1',
    ...overrides,
  };
}

/** متجر تجريبي: منتجات، إعدادات ولاء، كوبونات، ومدير. */
export async function seedStore(extra = {}) {
  await seed({
    'products/p1': { name: 'ساعة خشب', price: 35000, available: true, categoryId: 'c1' },
    'products/p2': { name: 'بورد زواج', price: 20000, available: true, categoryId: 'c2' },
    'products/p3': { name: 'مخفي', price: 10000, available: false, categoryId: 'c1' },
    'settings/loyalty': {
      enabled: true, pointsPer1000: 1, pointValue: 50, minRedeemPoints: 100, maxRedeemPercent: 50,
      referralEnabled: true, referrerPoints: 200, refereePoints: 100, referralMinTotal: 25000,
      maxReferralsPerUser: 2, referralWindowDays: 30,
    },
    'coupons/WELCOME10': { type: 'percent', value: 10, maxDiscount: 5000, perUserLimit: 1, usedCount: 0, active: true },
    'coupons/ONCE5': { type: 'fixed', value: 5000, minSubtotal: 30000, usageLimit: 1, perUserLimit: 0, usedCount: 0, active: true },
    'admins/admin1': { name: 'المدير' },
    ...extra,
  });
}
