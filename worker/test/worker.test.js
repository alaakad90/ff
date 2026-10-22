import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { decodeFields } from '../src/firestore.js';
import { clearTokenCache, signJwt } from '../src/google.js';
import worker, { MAX_ORDER_AGE_MS, parseServiceAccount } from '../src/index.js';
import { buildMessage, formatBaghdadTime, formatPrice } from '../src/telegram.js';

const PROJECT = 'demo-lacasa';
const NOW = new Date('2026-10-24T06:05:00Z'); // السبت 09:05 بتوقيت بغداد

async function makeServiceAccount() {
  const keys = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', keys.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${der.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return {
    publicKey: keys.publicKey,
    account: {
      project_id: PROJECT,
      client_email: 'worker@demo-lacasa.iam.gserviceaccount.com',
      private_key: pem,
      token_uri: 'https://oauth2.googleapis.com/token',
    },
  };
}

const orderFields = (overrides = {}) => ({
  customer: {
    mapValue: {
      fields: {
        name: { stringValue: 'علي' },
        phone: { stringValue: '07701234567' },
        address: { stringValue: 'بغداد، الكرادة' },
        notes: { stringValue: '' },
      },
    },
  },
  items: {
    arrayValue: {
      values: [{
        mapValue: {
          fields: {
            productId: { stringValue: 'p1' },
            name: { stringValue: 'ساعة خشب' },
            price: { integerValue: '35000' },
            quantity: { integerValue: '2' },
          },
        },
      }],
    },
  },
  total: { integerValue: '70000' },
  status: { stringValue: 'new' },
  deliveryDay: { stringValue: 'الخميس' },
  pickupMethod: { stringValue: 'delivery' },
  createdAt: { timestampValue: new Date(NOW.getTime() - 60_000).toISOString() },
  ...overrides,
});

/** Firestore وTelegram وGoogle وهميين، يسجلون كل طلب. */
function fakeBackend({
  fields = orderFields(), claimConflict = false, telegramFails = false, fcm = 200, adminDevices = [],
} = {}) {
  const calls = { telegram: [], patches: [], push: [], deleted: [] };
  const admins = [...adminDevices];
  let doc = fields ? { fields: { ...fields }, updateTime: '2026-10-24T06:04:00.000001Z' } : null;
  const fetchImpl = async (input, init = {}) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    const method = init.method || 'GET';
    if (url.host === 'oauth2.googleapis.com') {
      return Response.json({ access_token: 'ya29.fake', expires_in: 3600 });
    }
    if (url.host === 'firestore.googleapis.com') {
      assert.equal(init.headers.Authorization, 'Bearer ya29.fake');
      if (url.pathname.includes('/documents/adminDevices')) {
        if (method === 'DELETE') {
          const id = decodeURIComponent(url.pathname.split('/').pop());
          calls.deleted.push(id);
          admins.splice(admins.indexOf(id), 1);
          return Response.json({});
        }
        return Response.json({
          documents: admins.map((t) => ({ name: `projects/${PROJECT}/databases/(default)/documents/adminDevices/${t}` })),
        });
      }
      assert.match(url.pathname, new RegExp(`/projects/${PROJECT}/databases/\\(default\\)/documents/orders/`));
      if (method === 'GET') return doc ? Response.json(doc) : new Response('{}', { status: 404 });
      if (method === 'PATCH') {
        calls.patches.push({ query: Object.fromEntries(url.searchParams), body: JSON.parse(init.body) });
        if (claimConflict && url.searchParams.has('currentDocument.updateTime')) {
          return new Response('{"error":{"status":"FAILED_PRECONDITION"}}', { status: 400 });
        }
        const next = JSON.parse(init.body).fields;
        const field = url.searchParams.get('updateMask.fieldPaths');
        if (next[field]) doc.fields[field] = next[field];
        else delete doc.fields[field];
        return Response.json(doc);
      }
    }
    if (url.host === 'fcm.googleapis.com') {
      assert.equal(url.pathname, `/v1/projects/${PROJECT}/messages:send`);
      const message = JSON.parse(init.body).message;
      calls.push.push(message);
      if (message.token.startsWith('gone')) return new Response('{"error":{"status":"NOT_FOUND"}}', { status: 404 });
      if (fcm === 200) return Response.json({ name: 'projects/x/messages/1' });
      if (fcm === 404) return new Response('{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}', { status: 404 });
      return new Response('{"error":{"status":"UNAVAILABLE"}}', { status: fcm });
    }
    if (url.host === 'api.telegram.org') {
      assert.equal(url.pathname, '/botTOKEN123/sendMessage');
      if (telegramFails) return new Response('bad', { status: 502 });
      calls.telegram.push(JSON.parse(init.body));
      return Response.json({ ok: true });
    }
    throw new Error(`unexpected fetch ${method} ${url}`);
  };
  return { calls, fetchImpl, get doc() { return doc; } };
}

async function callWorker(body, env, backend, { method = 'POST', path = '/notify-order' } = {}) {
  const realFetch = globalThis.fetch;
  const realNow = Date.now;
  globalThis.fetch = backend.fetchImpl;
  Date.now = () => NOW.getTime();
  try {
    const request = new Request(`https://lacasa-store.example.workers.dev${path}`, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: method === 'POST' ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined,
    });
    const response = await worker.fetch(request, env);
    return { status: response.status, body: await response.json() };
  } finally {
    globalThis.fetch = realFetch;
    Date.now = realNow;
  }
}

describe('telegram message', () => {
  it('formats prices and Baghdad time', () => {
    assert.equal(formatPrice(500), '500 د.ع');
    assert.equal(formatPrice(1250000), '1,250,000 د.ع');
    assert.equal(formatBaghdadTime(NOW), 'السبت 2026/10/24 09:05');
    assert.equal(formatBaghdadTime(new Date('2026-10-23T21:30:00Z')), 'السبت 2026/10/24 00:30');
  });

  it('lists the customer, delivery day, pickup method and items', () => {
    const order = decodeFields(orderFields({
      pickupMethod: { stringValue: 'pickup' },
      createdAt: { timestampValue: NOW.toISOString() },
    }));
    const text = buildMessage('o42', order);
    assert.match(text, /رقم الطلب: o42/);
    assert.match(text, /وقت الطلب: السبت 2026\/10\/24 09:05/);
    assert.match(text, /يوم التسليم: الخميس/);
    assert.match(text, /طريقة الاستلام: استلام من المحل/);
    assert.match(text, /الاسم: علي/);
    assert.match(text, /• ساعة خشب × 2 = 70,000 د\.ع/);
    assert.match(text, /المجموع: 70,000 د\.ع/);
    assert.doesNotMatch(text, /ملاحظات|📝/);
  });

  it('shows the customer note under its product', () => {
    const text = buildMessage('o43', {
      customer: { name: 'علي', phone: '0770' },
      items: [{
        name: 'ساعة خشب',
        price: 35000,
        quantity: 1,
        note: 'اكتبوا اسم سارة',
        imageUrl: 'https://x.supabase.co/storage/v1/object/public/media/notes/u1/1-a.jpg',
        voiceUrl: 'https://x.supabase.co/storage/v1/object/public/media/notes/u1/2-b.m4a',
      }],
      total: 35000,
    });
    assert.match(text, /• ساعة خشب × 1 = 35,000 د\.ع\n {3}📝 اكتبوا اسم سارة/);
    assert.match(text, /\n {3}🖼️ صورة: https:\/\/x\.supabase\.co\/\S+\/1-a\.jpg/);
    assert.match(text, /\n {3}🎤 فويس: https:\/\/x\.supabase\.co\/\S+\/2-b\.m4a/);
  });
});

describe('google token', () => {
  it('signs a verifiable RS256 JWT for Firestore', async () => {
    const { account, publicKey } = await makeServiceAccount();
    const jwt = await signJwt(account, 1_700_000_000);
    const [header, claims, signature] = jwt.split('.');
    const decode = (s) => JSON.parse(Buffer.from(s, 'base64url').toString());
    assert.deepEqual(decode(header), { alg: 'RS256', typ: 'JWT' });
    assert.equal(decode(claims).iss, account.client_email);
    assert.equal(
      decode(claims).scope,
      'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
    );
    assert.equal(decode(claims).exp, 1_700_003_600);
    const valid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      publicKey,
      Buffer.from(signature, 'base64url'),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    assert.ok(valid);
  });
});

describe('POST /notify-order', () => {
  let env;
  beforeEach(async () => {
    clearTokenCache();
    const { account } = await makeServiceAccount();
    env = { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(account), BOT_TOKEN: 'TOKEN123', CHAT_ID: '-5493985592' };
  });

  it('sends one message for a new order and marks it', async () => {
    const backend = fakeBackend();
    const res = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.deepEqual(res, { status: 200, body: { ok: true } });
    assert.equal(backend.calls.telegram.length, 1);
    assert.equal(backend.calls.telegram[0].chat_id, '-5493985592');
    assert.match(backend.calls.telegram[0].text, /ساعة خشب × 2/);
    assert.equal(backend.calls.patches[0].query['updateMask.fieldPaths'], 'notifiedAt');
    assert.equal(backend.calls.patches[0].query['currentDocument.updateTime'], '2026-10-24T06:04:00.000001Z');
    assert.ok(backend.doc.fields.notifiedAt);

    // المرة الثانية ما تنبعث رسالة.
    const again = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.deepEqual(again.body, { ok: true, alreadyNotified: true });
    assert.equal(backend.calls.telegram.length, 1);
  });

  it("pushes \"new order\" to the owner's phones and forgets uninstalled ones", async () => {
    const backend = fakeBackend({ adminDevices: ['owner:phone-1', 'gone-phone'] });
    const res = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.deepEqual(res.body, { ok: true });
    assert.equal(backend.calls.telegram.length, 1);
    assert.deepEqual(backend.calls.push.map((m) => m.token).sort(), ['gone-phone', 'owner:phone-1']);
    assert.equal(backend.calls.push[0].notification.title, '🛍️ طلب جديد');
    assert.equal(backend.calls.push[0].notification.body, 'علي • 70,000 د.ع • الخميس');
    assert.deepEqual(backend.calls.deleted, ['gone-phone']);
  });

  it('still answers ok when the owner push fails after Telegram', async () => {
    const backend = fakeBackend({ adminDevices: ['owner-phone'], fcm: 500 });
    const res = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.deepEqual(res.body, { ok: true });
    assert.ok(backend.doc.fields.notifiedAt);
  });

  it('does not send when another request claimed the order first', async () => {
    const backend = fakeBackend({ claimConflict: true });
    const res = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.deepEqual(res.body, { ok: true, alreadyNotified: true });
    assert.equal(backend.calls.telegram.length, 0);
  });

  it('rejects unknown and old orders without sending', async () => {
    const missing = await callWorker({ orderId: 'nope' }, env, fakeBackend({ fields: null }));
    assert.equal(missing.status, 404);

    const oldFields = orderFields({
      createdAt: { timestampValue: new Date(NOW.getTime() - MAX_ORDER_AGE_MS - 1000).toISOString() },
    });
    const backend = fakeBackend({ fields: oldFields });
    const old = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.equal(old.status, 409);
    assert.equal(backend.calls.telegram.length, 0);
    assert.equal(backend.calls.patches.length, 0);
  });

  it('releases the claim when Telegram fails so a retry can send', async () => {
    const backend = fakeBackend({ telegramFails: true });
    const res = await callWorker({ orderId: 'abc123' }, env, backend);
    assert.equal(res.status, 502);
    assert.equal(backend.calls.patches.length, 2);
    assert.equal(backend.doc.fields.notifiedAt, undefined);
  });

  it('validates the request', async () => {
    const backend = fakeBackend();
    assert.equal((await callWorker('not json', env, backend)).status, 400);
    assert.equal((await callWorker({ orderId: '../users/x' }, env, backend)).status, 400);
    assert.equal((await callWorker({}, env, backend)).status, 400);
    assert.equal((await callWorker(null, env, backend, { method: 'GET' })).status, 405);
    assert.equal((await callWorker(null, env, backend, { method: 'GET', path: '/' })).status, 200);
    assert.equal((await callWorker({ orderId: 'abc' }, {}, backend)).status, 500);
    assert.equal(backend.calls.telegram.length, 0);
  });
});

describe('POST /notify-status', () => {
  let env;
  beforeEach(async () => {
    clearTokenCache();
    const { account } = await makeServiceAccount();
    env = { FIREBASE_SERVICE_ACCOUNT: JSON.stringify(account), BOT_TOKEN: 'TOKEN123', CHAT_ID: '-5493985592' };
  });
  const withStatus = (status, extra = {}) => orderFields({
    status: { stringValue: status },
    pushToken: { stringValue: 'device-token-1' },
    ...extra,
  });
  const notify = (backend) => callWorker({ orderId: 'abc123' }, env, backend, { path: '/notify-status' });

  it('sends one push per status to the customer phone', async () => {
    const backend = fakeBackend({ fields: withStatus('confirmed') });
    assert.deepEqual((await notify(backend)).body, { ok: true });
    assert.equal(backend.calls.push.length, 1);
    assert.equal(backend.calls.push[0].token, 'device-token-1');
    assert.equal(backend.calls.push[0].notification.title, '✅ انقبل طلبك');
    assert.match(backend.calls.push[0].notification.body, /يوم التسليم: الخميس/);
    assert.equal(backend.doc.fields.statusNotified.stringValue, 'confirmed');
    assert.equal(backend.calls.patches[0].query['currentDocument.updateTime'], '2026-10-24T06:04:00.000001Z');

    assert.deepEqual((await notify(backend)).body, { ok: true, alreadyNotified: true });
    assert.equal(backend.calls.push.length, 1);

    backend.doc.fields.status = { stringValue: 'delivering' };
    await notify(backend);
    assert.equal(backend.calls.push[1].notification.title, '🚚 طلبك بالطريق');
    backend.doc.fields.status = { stringValue: 'done' };
    await notify(backend);
    assert.equal(backend.calls.push[2].notification.title, '🎉 تم تسليم طلبك');
  });

  it('tells pickup customers their order is ready', async () => {
    const backend = fakeBackend({
      fields: withStatus('delivering', { pickupMethod: { stringValue: 'pickup' } }),
    });
    await notify(backend);
    assert.equal(backend.calls.push[0].notification.title, '📦 طلبك جاهز');
  });

  it('skips new and cancelled orders and orders without a phone token', async () => {
    for (const fields of [withStatus('new'), withStatus('cancelled'), orderFields({ status: { stringValue: 'done' } })]) {
      const backend = fakeBackend({ fields });
      assert.deepEqual((await notify(backend)).body, { ok: true, skipped: true });
      assert.equal(backend.calls.push.length, 0);
      assert.equal(backend.calls.patches.length, 0);
    }
  });

  it('does not send when another request claimed the status first', async () => {
    const backend = fakeBackend({ fields: withStatus('confirmed'), claimConflict: true });
    assert.deepEqual((await notify(backend)).body, { ok: true, alreadyNotified: true });
    assert.equal(backend.calls.push.length, 0);
  });

  it('puts the previous status back when FCM fails, and accepts an uninstalled app', async () => {
    const failing = fakeBackend({
      fields: withStatus('delivering', { statusNotified: { stringValue: 'confirmed' } }),
      fcm: 503,
    });
    assert.equal((await notify(failing)).status, 502);
    assert.equal(failing.doc.fields.statusNotified.stringValue, 'confirmed');

    const gone = fakeBackend({ fields: withStatus('done'), fcm: 404 });
    assert.deepEqual((await notify(gone)).body, { ok: true, unregistered: true });
    assert.equal(gone.doc.fields.statusNotified.stringValue, 'done');
  });
});

describe('parseServiceAccount', () => {
  it('accepts the key file with a BOM or without its outer braces', () => {
    const key = { type: 'service_account', project_id: 'p' };
    const text = JSON.stringify(key, null, 2);
    assert.deepEqual(parseServiceAccount(`\uFEFF${text}\n`), key);
    assert.deepEqual(parseServiceAccount(text.slice(1, -1)), key);
  });
});
