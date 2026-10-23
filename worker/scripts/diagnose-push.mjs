// فحص الإشعارات: هل الطلبات وموبايلات المدير عندها توكن، وشنو يرد Firebase/آبل.
// يطبع أطوال التوكنات بس، مو التوكنات نفسها.
//   FIREBASE_SERVICE_ACCOUNT='...' node scripts/diagnose-push.mjs

import { decodeFields } from '../src/firestore.js';
import { getAccessToken } from '../src/google.js';
import { parseServiceAccount } from '../src/index.js';

const sa = parseServiceAccount(process.env.FIREBASE_SERVICE_ACCOUNT || '');
const token = await getAccessToken(sa);
const base = `https://firestore.googleapis.com/v1/projects/${sa.project_id}/databases/(default)/documents`;
const auth = { Authorization: `Bearer ${token}` };

async function push(deviceToken, validateOnly) {
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      validate_only: validateOnly,
      message: {
        token: deviceToken,
        notification: { title: '🔧 تجربة إشعار', body: 'إذا وصلك هذا، الإشعارات شغالة.' },
        apns: { payload: { aps: { sound: 'default' } } },
      },
    }),
  });
  if (response.ok) return `OK ${response.status}`;
  const body = await response.json().catch(() => ({}));
  const codes = (body.error?.details || []).map((d) => d.errorCode).filter(Boolean);
  return `FAIL ${response.status} ${body.error?.status || ''} ${codes.join(',')} ${body.error?.message || ''}`;
}

console.log('== آخر 5 طلبات ==');
const orders = await (await fetch(`${base}/orders?pageSize=5&orderBy=createdAt%20desc`, { headers: auth })).json();
for (const doc of orders.documents || []) {
  const o = decodeFields(doc.fields || {});
  const id = doc.name.split('/').pop();
  const len = (o.pushToken || '').length;
  const created = o.createdAt instanceof Date ? o.createdAt.toISOString() : '?';
  let check = '';
  if (len) check = ` | فحص التوكن: ${await push(o.pushToken, true)}`;
  console.log(`${id} | ${created} | status=${o.status} | statusNotified=${o.statusNotified || '-'} | pushToken length=${len}${check}`);
}

console.log('== موبايلات المدير (adminDevices) ==');
const admins = await (await fetch(`${base}/adminDevices?pageSize=50`, { headers: auth })).json();
const devices = admins.documents || [];
console.log(`count=${devices.length}`);
for (const doc of devices) {
  const t = decodeURIComponent(doc.name.split('/').pop());
  const d = decodeFields(doc.fields || {});
  const updated = d.updatedAt instanceof Date ? d.updatedAt.toISOString() : '?';
  console.log(`device token length=${t.length} | updatedAt=${updated} | إرسال تجربة: ${await push(t, false)}`);
}
