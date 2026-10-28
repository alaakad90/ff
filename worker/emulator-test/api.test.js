// اختبارات مسارات /api على محاكي Firestore الحقيقي: الأسعار، الكوبونات، النقاط،
// منع التكرار والتلاعب، حالة الطلب والمكافآت، الدعوات، ومتابعة طلب الزائر.

import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import {
  api, customer, db, orderBody, reset, seed, seedStore, sent,
} from './helpers.js';

beforeEach(async () => {
  await reset();
  await seedStore();
});

const admin = { token: 'uid:admin1' };

describe('quote', () => {
  it('prices come from the server, and unavailable products are listed', async () => {
    const res = await api('/api/quote', {
      items: [{ productId: 'p1', quantity: 2, price: 1 }, { productId: 'p3', quantity: 1 }, { productId: 'gone', quantity: 1 }],
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.subtotal, 70000);
    assert.equal(res.body.total, 70000);
    assert.deepEqual(res.body.unavailable.map((u) => u.productId).sort(), ['gone', 'p3']);
    assert.equal(res.body.pointsToEarn, 0, 'guests do not earn points');
  });

  it('a signed-in customer sees points to earn and a coupon discount', async () => {
    const res = await api('/api/quote', { items: [{ productId: 'p1', quantity: 2 }], coupon: 'welcome10' }, { token: 'uid:u1' });
    assert.equal(res.body.coupon.amount, 5000); // 10% = 7000، والحد 5000
    assert.equal(res.body.total, 65000);
    assert.equal(res.body.pointsToEarn, 65);
  });

  it('a wrong token is rejected instead of quietly treated as a guest', async () => {
    const res = await api('/api/quote', { items: [{ productId: 'p1', quantity: 1 }] }, { token: 'forged' });
    assert.equal(res.status, 401);
  });

  it('bad input is rejected', async () => {
    for (const items of [[], [{ productId: 'p1', quantity: 0 }], [{ productId: 'p1', quantity: 1000 }], [{ productId: '../x', quantity: 1 }]]) {
      assert.equal((await api('/api/quote', { items })).status, 400);
    }
  });
});

describe('placing orders', () => {
  it('saves server prices, sends Telegram once, and a retry does not duplicate the order', async () => {
    await seed({ 'adminDevices/admin-phone': { uid: 'admin1' } });
    const body = orderBody({ items: [{ productId: 'p1', quantity: 2, price: 1, name: 'fake' }] });
    const first = await api('/api/orders', body);
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal(first.body.total, 70000);
    assert.ok(first.body.trackingKey.length >= 20);

    const saved = (await db.get(`orders/${body.requestId}`)).data;
    assert.equal(saved.items[0].price, 35000);
    assert.equal(saved.items[0].name, 'ساعة خشب');
    assert.equal(saved.pricedBy, 'server');
    assert.equal(saved.status, 'new');
    assert.equal(saved.phoneKey, '7701234567');
    assert.ok(saved.notifiedAt instanceof Date);
    assert.equal(sent.telegram.length, 1);
    assert.match(sent.telegram[0].text, /70,000 د.ع/);
    assert.equal(sent.push.length, 1, 'owner phone notified');

    const again = await api('/api/orders', body);
    assert.equal(again.status, 200);
    assert.equal(again.body.duplicate, true);
    assert.equal(again.body.orderId, body.requestId);
    assert.equal(sent.telegram.length, 1, 'no second Telegram message');
    assert.equal((await db.query('orders')).length, 1);
  });

  it('two taps at the same time still make one order', async () => {
    const body = orderBody();
    const results = await Promise.all([api('/api/orders', body), api('/api/orders', body), api('/api/orders', body)]);
    assert.ok(results.every((r) => r.status === 200), JSON.stringify(results.map((r) => r.body)));
    assert.equal(results.filter((r) => !r.body.duplicate).length, 1);
    assert.equal((await db.query('orders')).length, 1);
    assert.equal(sent.telegram.length, 1);
  });

  it('refuses when the price changed since the customer saw it', async () => {
    const res = await api('/api/orders', orderBody({ expectedTotal: 60000 }));
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'price_changed');
    assert.equal(res.body.quote.total, 70000);
    assert.equal((await db.query('orders')).length, 0);
  });

  it('refuses unavailable products', async () => {
    const res = await api('/api/orders', orderBody({ items: [{ productId: 'p3', quantity: 1 }] }));
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'unavailable');
  });

  it('keeps the chosen options on the order and in the Telegram message', async () => {
    const options = [{ name: 'اللون', value: 'أسود' }, { name: 'نوع الخط', value: 'ديواني' }];
    const res = await api('/api/orders', orderBody({ items: [{ productId: 'p4', quantity: 1, options }] }));
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const order = await db.get(`orders/${res.body.orderId}`);
    assert.deepEqual(order.data.items[0].options, options);
    const message = sent.telegram.at(-1).text;
    assert.match(message, /اللون: أسود/);
    assert.match(message, /نوع الخط: ديواني/);
  });

  it('refuses options that are not on the product, or a missing required one', async () => {
    for (const options of [
      [{ name: 'اللون', value: 'أحمر' }],
      [{ name: 'نوع الخط', value: 'كوفي' }],
      [{ name: 'القياس', value: 'كبير' }],
    ]) {
      const res = await api('/api/orders', orderBody({ items: [{ productId: 'p4', quantity: 1, options }] }));
      assert.equal(res.status, 409, JSON.stringify(options));
      assert.equal(res.body.code, 'unavailable');
      assert.equal(res.body.quote.unavailable[0].reason, 'options');
    }
    const bad = await api('/api/orders', orderBody({ items: [{ productId: 'p4', quantity: 1, options: 'أسود' }] }));
    assert.equal(bad.status, 400);
    assert.equal((await db.query('orders')).length, 0);
  });

  it('validates the customer, day and pickup method', async () => {
    assert.equal((await api('/api/orders', orderBody({ customer: { name: 'x', phone: '123' } }))).status, 400);
    assert.equal((await api('/api/orders', orderBody({ deliveryDay: 'Monday' }))).status, 400);
    assert.equal((await api('/api/orders', orderBody({
      pickupMethod: 'delivery', zoneId: 'baghdad', customer: { name: 'x', phone: '07701234567' },
    }))).status, 400, 'delivery needs an address');
    const pickup = await api('/api/orders', orderBody({ pickupMethod: 'pickup', customer: { name: 'x', phone: '07701234567' } }));
    assert.equal(pickup.status, 200);
    assert.equal((await api('/api/orders', orderBody({ requestId: 'short' }))).status, 400);
  });

  it('an order cannot reuse another customer\'s order id', async () => {
    const body = orderBody();
    assert.equal((await api('/api/orders', body, { token: 'uid:u1' })).status, 200);
    const stolen = await api('/api/orders', body, { token: 'uid:u2' });
    assert.equal(stolen.status, 409);
  });
});

describe('coupons', () => {
  it('a coupon is used once per phone, even as a guest with another name', async () => {
    const first = await api('/api/orders', orderBody({ coupon: 'WELCOME10' }));
    assert.equal(first.status, 200);
    assert.equal(first.body.discount, 5000);
    const second = await api('/api/orders', orderBody({ coupon: 'WELCOME10', customer: { ...customer('+964 770 123 4567'), name: 'غيره' } }));
    assert.equal(second.status, 409);
    assert.equal(second.body.code, 'coupon_invalid');
    assert.equal((await db.get('coupons/WELCOME10')).data.usedCount, 1);
  });

  it('a coupon with one use left goes to exactly one of many parallel orders', async () => {
    const bodies = Array.from({ length: 15 }, (_, i) => orderBody({ coupon: 'ONCE5', customer: customer(`07700000${String(i).padStart(3, '0')}`) }));
    const results = await Promise.all(bodies.map((b) => api('/api/orders', b)));
    assert.equal(results.filter((r) => r.status === 200).length, 1, JSON.stringify(results.map((r) => r.body.code)));
    assert.ok(results.filter((r) => r.status !== 200).every((r) => r.body.code === 'coupon_invalid'));
    assert.equal((await db.get('coupons/ONCE5')).data.usedCount, 1);
  });

  it('expired, inactive, minimum and personal coupons', async () => {
    await seed({
      'coupons/OLD': { type: 'fixed', value: 1000, endsAt: new Date(Date.now() - 1000), usedCount: 0, active: true },
      'coupons/OFF': { type: 'fixed', value: 1000, usedCount: 0, active: false },
      'coupons/MINE': { type: 'fixed', value: 3000, usedCount: 0, active: true, assignedTo: 'u1' },
    });
    const quote = (coupon, token, items = [{ productId: 'p1', quantity: 1 }]) => api('/api/quote', { items, coupon }, { token });
    assert.equal((await quote('OLD')).body.couponError.code, 'expired');
    assert.equal((await quote('OFF')).body.couponError.code, 'inactive');
    assert.equal((await quote('ONCE5', undefined, [{ productId: 'p2', quantity: 1 }])).body.couponError.code, 'min_subtotal');
    assert.equal((await quote('MINE')).body.couponError.code, 'sign_in');
    assert.equal((await quote('MINE', 'uid:u2')).body.couponError.code, 'not_yours');
    assert.equal((await quote('MINE', 'uid:u1')).body.coupon.amount, 3000);
    assert.equal((await quote('NOPE')).body.couponError.code, 'not_found');
  });
});

describe('points', () => {
  beforeEach(async () => {
    await seed({ 'wallets/u1': { points: 500, lifetimeEarned: 500, ordersPlaced: 0 } });
  });

  it('redeems points within the limits and records it', async () => {
    const quote = await api('/api/quote', { items: [{ productId: 'p2', quantity: 1 }], points: 400 }, { token: 'uid:u1' });
    // 50% من 20000 = 10000 = 200 نقطة كحد أعلى.
    assert.equal(quote.body.maxPoints, 200);
    assert.deepEqual(quote.body.points, { points: 200, amount: 10000 });

    const body = orderBody({ items: [{ productId: 'p2', quantity: 1 }], points: 200, expectedTotal: 10000 });
    const res = await api('/api/orders', body, { token: 'uid:u1' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const wallet = (await db.get('wallets/u1')).data;
    assert.equal(wallet.points, 300);
    assert.equal(wallet.ordersPlaced, 1);
    const ledger = (await db.get(`wallets/u1/ledger/redeem-${body.requestId}`)).data;
    assert.equal(ledger.points, -200);
  });

  it('asking for more points than allowed is refused, not silently changed', async () => {
    const res = await api('/api/orders', orderBody({ items: [{ productId: 'p2', quantity: 1 }], points: 400 }), { token: 'uid:u1' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'points_changed');
    assert.equal((await db.get('wallets/u1')).data.points, 500);
  });

  it('the same points cannot be spent twice by parallel orders', async () => {
    await seed({ 'wallets/u1': { points: 300, ordersPlaced: 0 } });
    const bodies = [1, 2].map(() => orderBody({ items: [{ productId: 'p1', quantity: 2 }], points: 300 }));
    const results = await Promise.all(bodies.map((b) => api('/api/orders', b, { token: 'uid:u1' })));
    assert.equal(results.filter((r) => r.status === 200).length, 1, JSON.stringify(results.map((r) => r.body)));
    assert.equal((await db.get('wallets/u1')).data.points, 0);
  });

  it('guests and anonymous accounts cannot use points', async () => {
    const res = await api('/api/quote', { items: [{ productId: 'p1', quantity: 2 }], points: 200 }, { token: 'anon' });
    assert.equal(res.body.points, null);
    assert.equal(res.body.maxPoints, 0);
  });
});

describe('order status, notifications and rewards', () => {
  async function place(token = 'uid:u1', overrides = {}) {
    const body = orderBody(overrides);
    const res = await api('/api/orders', body, { token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    sent.push.length = 0;
    return body.requestId;
  }

  it('only the admin can change the status', async () => {
    const id = await place();
    assert.equal((await api('/api/admin/order-status', { orderId: id, status: 'done' }, { token: 'uid:u1' })).status, 403);
    assert.equal((await api('/api/admin/order-status', { orderId: id, status: 'done' })).status, 403);
    assert.equal((await db.get(`orders/${id}`)).data.status, 'new');
  });

  it('each status notifies the customer once, and keeps a timeline', async () => {
    const id = await place('uid:u1', { pickupMethod: 'delivery', zoneId: 'baghdad' });
    for (const status of ['confirmed', 'confirmed', 'delivering', 'confirmed']) {
      const res = await api('/api/admin/order-status', { orderId: id, status }, admin);
      assert.equal(res.status, 200, JSON.stringify(res.body));
    }
    assert.deepEqual(sent.push.map((m) => m.notification.title), ['✅ انقبل طلبك', '🚚 طلبك بالطريق']);
    const order = (await db.get(`orders/${id}`)).data;
    assert.deepEqual(order.statusHistory.map((h) => h.status), ['new', 'confirmed', 'delivering', 'confirmed']);
    assert.deepEqual(order.notifiedStatuses, ['confirmed', 'delivering']);
  });

  it('delivery earns points once, even if the admin presses twice', async () => {
    const id = await place();
    await Promise.all([
      api('/api/admin/order-status', { orderId: id, status: 'done' }, admin),
      api('/api/admin/order-status', { orderId: id, status: 'done' }, admin),
    ]);
    await api('/api/admin/order-status', { orderId: id, status: 'done' }, admin);
    const wallet = (await db.get('wallets/u1')).data;
    assert.equal(wallet.points, 70);
    assert.equal((await db.query('wallets/u1/ledger')).filter((e) => e.data.type === 'earn').length, 1);
    assert.equal(sent.push.filter((m) => m.notification.title === '🎉 تم تسليم طلبك').length, 1);
    const rewardPush = sent.push.filter((m) => m.notification.title === '⭐ كسبت نقاط');
    assert.equal(rewardPush.length, 1, 'one "points earned" notification');
    assert.equal(rewardPush[0].token, 'device-token-1');
  });

  it('cancelling gives back points and the coupon, and a cancelled order stays cancelled', async () => {
    await seed({ 'wallets/u1': { points: 500, ordersPlaced: 0 } });
    const id = await place('uid:u1', { coupon: 'WELCOME10', items: [{ productId: 'p2', quantity: 1 }], points: 180 });
    assert.equal((await db.get('wallets/u1')).data.points, 320);
    assert.equal((await db.get('coupons/WELCOME10')).data.usedCount, 1);

    assert.equal((await api('/api/admin/order-status', { orderId: id, status: 'cancelled' }, admin)).status, 200);
    assert.equal((await db.get('wallets/u1')).data.points, 500);
    assert.equal((await db.get('coupons/WELCOME10')).data.usedCount, 0);
    assert.equal((await db.get('coupons/WELCOME10/uses/u_u1')).data.count, 0);

    const reopen = await api('/api/admin/order-status', { orderId: id, status: 'done' }, admin);
    assert.equal(reopen.status, 409);
    await api('/api/admin/order-status', { orderId: id, status: 'cancelled' }, admin);
    assert.equal((await db.get('wallets/u1')).data.points, 500, 'no double refund');
  });

  it('a delivered order cancelled later takes back its points', async () => {
    const id = await place();
    await api('/api/admin/order-status', { orderId: id, status: 'done' }, admin);
    assert.equal((await db.get('wallets/u1')).data.points, 70);
    await api('/api/admin/order-status', { orderId: id, status: 'cancelled' }, admin);
    assert.equal((await db.get('wallets/u1')).data.points, 0);
  });

  it('old app orders (not priced by the server) never earn points', async () => {
    await seed({
      'orders/legacy1': {
        customer: customer(), items: [{ productId: 'p1', name: 'x', price: 1, quantity: 1 }], total: 999999999,
        status: 'new', userId: 'u1', createdAt: new Date(), deliveryDay: 'الخميس', pickupMethod: 'delivery',
      },
    });
    const res = await api('/api/admin/order-status', { orderId: 'legacy1', status: 'done' }, admin);
    assert.equal(res.status, 200);
    assert.equal(await db.get('wallets/u1'), null);
  });
});

describe('referrals', () => {
  async function codeOf(uid) {
    const res = await api('/api/referral/code', {}, { token: `uid:${uid}` });
    assert.equal(res.status, 200);
    return res.body.code;
  }

  it('the same code comes back every time', async () => {
    const code = await codeOf('a');
    assert.match(code, /^LC[A-Z2-9]{6}$/);
    assert.equal(await codeOf('a'), code);
    assert.equal((await db.get(`referralCodes/${code}`)).data.uid, 'a');
  });

  it('both friends get points after the first qualifying order is delivered', async () => {
    const code = await codeOf('a');
    assert.equal((await api('/api/referral/apply', { code }, { token: 'uid:b' })).status, 200);
    assert.equal((await api('/api/referral/apply', { code }, { token: 'uid:b' })).body.code, 'already');

    const body = orderBody({ customer: customer('07809999999') });
    assert.equal((await api('/api/orders', body, { token: 'uid:b' })).status, 200);
    await api('/api/admin/order-status', { orderId: body.requestId, status: 'done' }, admin);
    await api('/api/admin/order-status', { orderId: body.requestId, status: 'done' }, admin);

    assert.equal((await db.get('wallets/a')).data.points, 200);
    assert.equal((await db.get('wallets/b')).data.points, 70 + 100);
    assert.equal((await db.get('referrals/b')).data.status, 'rewarded');
  });

  it('a small first order does not count', async () => {
    const code = await codeOf('a');
    await api('/api/referral/apply', { code }, { token: 'uid:b' });
    const body = orderBody({ items: [{ productId: 'p2', quantity: 1 }] }); // 20000 < 25000
    await api('/api/orders', body, { token: 'uid:b' });
    await api('/api/admin/order-status', { orderId: body.requestId, status: 'done' }, admin);
    assert.equal(await db.get('wallets/a').then((w) => w?.data.points ?? 0), 0);
    assert.equal((await db.get('referrals/b')).data.status, 'pending');
  });

  it('blocks self referral, existing customers, guests and wrong codes', async () => {
    const code = await codeOf('a');
    assert.equal((await api('/api/referral/apply', { code }, { token: 'uid:a' })).body.code, 'self');
    await api('/api/orders', orderBody(), { token: 'uid:c' });
    assert.equal((await api('/api/referral/apply', { code }, { token: 'uid:c' })).body.code, 'not_new');
    assert.equal((await api('/api/referral/apply', { code })).status, 401);
    assert.equal((await api('/api/referral/apply', { code }, { token: 'anon' })).status, 401);
    assert.equal((await api('/api/referral/apply', { code: 'LCZZZZZZ' }, { token: 'uid:d' })).body.code, 'invalid_code');
    await seed({ 'users/old': { joinedAt: new Date(Date.now() - 40 * 86400000) } });
    assert.equal((await api('/api/referral/apply', { code }, { token: 'uid:old' })).body.code, 'too_late');
  });

  it('the inviter stops earning after the limit', async () => {
    const code = await codeOf('a');
    for (const friend of ['f1', 'f2', 'f3']) {
      await api('/api/referral/apply', { code }, { token: `uid:${friend}` });
      const body = orderBody();
      await api('/api/orders', body, { token: `uid:${friend}` });
      await api('/api/admin/order-status', { orderId: body.requestId, status: 'done' }, admin);
    }
    assert.equal((await db.get('wallets/a')).data.points, 400, 'limit is 2 friends');
    assert.equal((await db.get('referrals/f3')).data.status, 'capped');
  });
});

describe('delivery fees', () => {
  const delivery = (zoneId, extra = {}) => orderBody({ pickupMethod: 'delivery', zoneId, ...extra });

  it('Diwaniya center 2,000, districts 4,000, other governorates 5,000, pickup free', async () => {
    const quote = (body) => api('/api/quote', body).then((r) => r.body);
    const items = [{ productId: 'p2', quantity: 1 }]; // 20,000
    assert.deepEqual(
      [await quote({ items, pickupMethod: 'delivery', zoneId: 'diwaniyah-center' }),
        await quote({ items, pickupMethod: 'delivery', zoneId: 'diwaniyah-districts' }),
        await quote({ items, pickupMethod: 'delivery', zoneId: 'basra' }),
        await quote({ items, pickupMethod: 'pickup', zoneId: 'basra' })].map((q) => [q.deliveryFee, q.total]),
      [[2000, 22000], [4000, 24000], [5000, 25000], [0, 20000]],
    );
  });

  it('saves the zone and fee on the order and in the Telegram message', async () => {
    const body = delivery('diwaniyah-center');
    const res = await api('/api/orders', body);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.total, 72000);
    const order = (await db.get(`orders/${body.requestId}`)).data;
    assert.equal(order.deliveryFee, 2000);
    assert.deepEqual(order.deliveryZone, { id: 'diwaniyah-center', name: 'الديوانية - المركز', fee: 2000 });
    assert.equal(order.subtotal, 70000);
    assert.match(sent.telegram[0].text, /المحافظة: الديوانية - المركز/);
    assert.match(sent.telegram[0].text, /التوصيل: 2,000 د.ع/);
    assert.match(sent.telegram[0].text, /المجموع: 72,000 د.ع/);
  });

  it('old app builds (no governorate) still order, without a fee, until the owner switches them off', async () => {
    const old = orderBody({ pickupMethod: 'delivery' }); // بدون zoneId أصلاً، مثل النسخة القديمة
    const res = await api('/api/orders', old);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const order = (await db.get(`orders/${old.requestId}`)).data;
    assert.equal(order.deliveryFee, 0);
    assert.equal(order.deliveryZoneMissing, true);
    assert.match(sent.telegram[0].text, /نسخة قديمة من التطبيق/);

    await seed({ 'settings/orders': { legacyClientOrders: false } });
    const blocked = await api('/api/orders', orderBody({ pickupMethod: 'delivery' }));
    assert.equal(blocked.body.code, 'invalid_zone');
  });

  it('a delivery order needs a known, active governorate', async () => {
    await seed({ 'settings/delivery': { zones: [{ id: 'baghdad', name: 'بغداد', fee: 5000, active: false }] } });
    assert.equal((await api('/api/orders', delivery(''))).body.code, 'invalid_zone', 'new app sent an empty governorate');
    assert.equal((await api('/api/orders', delivery('mars'))).body.code, 'invalid_zone');
    assert.equal((await api('/api/orders', delivery('baghdad'))).body.code, 'invalid_zone', 'switched off');
  });

  it('the owner\'s fees from the control panel are used, not the app\'s', async () => {
    await seed({ 'settings/delivery': { zones: [
      { id: 'diwaniyah-center', name: 'الديوانية - المركز', fee: 3000, active: true },
      { id: 'afak', name: 'الديوانية - عفك', fee: 3500, active: true },
    ] } });
    const body = delivery('afak', { deliveryFee: 0, expectedTotal: 73500 });
    const res = await api('/api/orders', body);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal((await db.get(`orders/${body.requestId}`)).data.deliveryFee, 3500);
  });

  it('coupons and points discount the products only; delivery stays', async () => {
    await seed({ 'wallets/u1': { points: 1000 } });
    // 10% من 20,000 = 2,000؛ النقاط لحد 50% من 18,000 = 9,000 = 180 نقطة؛ والتوصيل 5,000 كامل.
    const q = (await api('/api/quote', {
      items: [{ productId: 'p2', quantity: 1 }], coupon: 'WELCOME10', points: 1000, pickupMethod: 'delivery', zoneId: 'basra',
    }, { token: 'uid:u1' })).body;
    assert.deepEqual([q.coupon.amount, q.points.points, q.points.amount, q.deliveryFee, q.total], [2000, 180, 9000, 5000, 14000]);
    assert.equal(q.pointsToEarn, 9, 'points are earned on the 9,000 paid for products, not on delivery');
  });

  it('a free-delivery coupon waives only the delivery fee', async () => {
    await seed({ 'coupons/FREESHIP': { type: 'freeDelivery', value: 0, usedCount: 0, active: true, perUserLimit: 1 } });
    const body = delivery('basra', { coupon: 'FREESHIP' });
    const res = await api('/api/orders', body);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.total, 70000);
    const order = (await db.get(`orders/${body.requestId}`)).data;
    assert.equal(order.deliveryFee, 0);
    assert.deepEqual(order.coupon, { code: 'FREESHIP', amount: 5000, freeDelivery: true });
    assert.match(sent.telegram[0].text, /FREESHIP: توصيل مجاني/);
    assert.equal((await db.get('coupons/FREESHIP')).data.usedCount, 1);

    const pickup = await api('/api/quote', { items: [{ productId: 'p1', quantity: 1 }], coupon: 'FREESHIP', pickupMethod: 'pickup' });
    assert.equal(pickup.body.couponError.code, 'no_delivery');
  });

  it('points on delivery orders are earned on products only', async () => {
    const body = delivery('basra');
    await api('/api/orders', body, { token: 'uid:u7' });
    await api('/api/admin/order-status', { orderId: body.requestId, status: 'done' }, admin);
    assert.equal((await db.get('wallets/u7')).data.points, 70, '70,000 of products, not 75,000');
  });
});

describe('guest tracking', () => {
  it('needs the tracking key from the order', async () => {
    const body = orderBody();
    const placed = await api('/api/orders', body);
    await api('/api/admin/order-status', { orderId: body.requestId, status: 'confirmed' }, admin);

    const wrong = await api('/api/orders/track', { orderId: body.requestId, key: 'x'.repeat(24) });
    assert.equal(wrong.status, 404);
    const res = await api('/api/orders/track', { orderId: body.requestId, key: placed.body.trackingKey });
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'confirmed');
    assert.deepEqual(res.body.statusHistory.map((h) => h.status), ['new', 'confirmed']);
    assert.equal(res.body.customer, undefined, 'no personal details');
    assert.equal(res.body.trackingKey, undefined);
  });
});

