import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  computeQuote, DEFAULT_LOYALTY, evaluateCoupon, loyaltySettings, maxRedeemablePoints, phoneKey, pointsFor,
} from '../src/pricing.js';

const now = new Date('2026-10-26T10:00:00Z');
const products = new Map([
  ['p1', { name: 'ساعة', price: 35000, available: true }],
  ['p2', { name: 'بورد', price: 20000 }],
  ['off', { name: 'مخفي', price: 10000, available: false }],
  ['free', { name: 'بلا سعر', price: 0 }],
]);

describe('loyalty settings', () => {
  it('fills defaults and clamps bad values', () => {
    assert.deepEqual(loyaltySettings(undefined), DEFAULT_LOYALTY);
    const s = loyaltySettings({ maxRedeemPercent: 400, pointValue: -5, pointsPer1000: 'x', enabled: 'yes' });
    assert.equal(s.maxRedeemPercent, 100);
    assert.equal(s.pointValue, 0);
    assert.equal(s.pointsPer1000, DEFAULT_LOYALTY.pointsPer1000);
    assert.equal(s.enabled, true);
  });
});

describe('coupons', () => {
  const base = { subtotal: 50000, now, uid: 'u1', uses: 0 };
  it('percent with a cap, and fixed never above the subtotal', () => {
    assert.deepEqual(evaluateCoupon({ type: 'percent', value: 20, maxDiscount: 6000 }, base), { amount: 6000 });
    assert.deepEqual(evaluateCoupon({ type: 'percent', value: 500 }, base), { amount: 50000 });
    assert.deepEqual(evaluateCoupon({ type: 'fixed', value: 90000 }, base), { amount: 50000 });
  });
  it('dates, limits, first order and owner', () => {
    assert.equal(evaluateCoupon({ startsAt: new Date('2027-01-01') }, base).error, 'not_started');
    assert.equal(evaluateCoupon({ endsAt: new Date('2026-01-01') }, base).error, 'expired');
    assert.equal(evaluateCoupon({ usageLimit: 3, usedCount: 3 }, base).error, 'used_up');
    assert.equal(evaluateCoupon({}, { ...base, uses: 1 }).error, 'per_user', 'once per customer by default');
    assert.equal(evaluateCoupon({ perUserLimit: 0, type: 'fixed', value: 1 }, { ...base, uses: 9 }).amount, 1);
    assert.equal(evaluateCoupon({ firstOrderOnly: true }, { ...base, isFirstOrder: false }).error, 'first_order');
    assert.equal(evaluateCoupon({ minSubtotal: 60000 }, base).error, 'min_subtotal');
    assert.equal(evaluateCoupon({ assignedTo: 'u2' }, base).error, 'not_yours');
    assert.equal(evaluateCoupon(null, base).error, 'not_found');
  });
});

describe('points', () => {
  const loyalty = loyaltySettings({});
  it('redeem limit by percent, balance and minimum', () => {
    assert.equal(maxRedeemablePoints(loyalty, 20000, 1000), 200);
    assert.equal(maxRedeemablePoints(loyalty, 20000, 150), 150);
    assert.equal(maxRedeemablePoints(loyalty, 20000, 99), 0, 'below the minimum');
    assert.equal(maxRedeemablePoints({ ...loyalty, enabled: false }, 20000, 1000), 0);
  });
  it('earning rounds down', () => {
    assert.equal(pointsFor(loyalty, 69999), 69);
    assert.equal(pointsFor({ ...loyalty, pointsPer1000: 3 }, 10000), 30);
    assert.equal(pointsFor({ ...loyalty, enabled: false }, 10000), 0);
  });
});

describe('quote', () => {
  const loyalty = loyaltySettings({});
  it('ignores client prices, lists unavailable lines, applies coupon then points', () => {
    const q = computeQuote({
      lines: [
        { productId: 'p1', quantity: 2, note: 'اسم: علي' },
        { productId: 'p2', quantity: 1 },
        { productId: 'off', quantity: 1 },
        { productId: 'free', quantity: 1 },
        { productId: 'missing', quantity: 1 },
      ],
      products,
      loyalty,
      coupon: { type: 'fixed', value: 10000 },
      couponCode: 'SAVE',
      uid: 'u1',
      balance: 1000,
      requestedPoints: 1000,
      now,
    });
    assert.equal(q.subtotal, 90000);
    assert.deepEqual(q.unavailable.map((u) => u.productId), ['off', 'free', 'missing']);
    assert.equal(q.items[0].note, 'اسم: علي');
    assert.deepEqual(q.coupon, { code: 'SAVE', amount: 10000 });
    assert.deepEqual(q.points, { points: 800, amount: 40000 }); // 50% من 80000
    assert.equal(q.total, 40000);
    assert.equal(q.pointsToEarn, 40);
  });
  it('a guest gets no points and a bad coupon is reported', () => {
    const q = computeQuote({
      lines: [{ productId: 'p2', quantity: 1 }], products, loyalty, couponCode: 'NOPE', requestedPoints: 500, balance: 500, now,
    });
    assert.equal(q.points, null);
    assert.equal(q.couponError.code, 'not_found');
    assert.equal(q.total, 20000);
  });
});

it('phone keys match local and international formats', () => {
  assert.equal(phoneKey('0770 123 4567'), '7701234567');
  assert.equal(phoneKey('+9647701234567'), '7701234567');
  assert.equal(phoneKey('123'), '123');
});
