// اختبارات قواعد Firestore (store_app/firestore.rules) على المحاكي:
// القديمة لازم تبقى تشتغل، والجديدة تمنع التلاعب بالنقاط والكوبونات.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc, collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, Timestamp, updateDoc, where,
} from 'firebase/firestore';

import { HOST } from './helpers.js';

let env;
const [host, port] = HOST.split(':');

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-lacasa',
    firestore: { host, port: Number(port), rules: readFileSync('../../store_app/firestore.rules', 'utf8') },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/admin1'), { name: 'المدير' });
    await setDoc(doc(db, 'wallets/u1'), { points: 100 });
    await setDoc(doc(db, 'wallets/u1/ledger/earn-1'), { points: 100 });
    await setDoc(doc(db, 'coupons/SECRET'), { type: 'fixed', value: 1000, active: true, usedCount: 3 });
    await setDoc(doc(db, 'coupons/GIFT'), { type: 'fixed', value: 1000, active: true, usedCount: 0, assignedTo: 'u1' });
    await setDoc(doc(db, 'referrals/u2'), { referrerUid: 'u1', status: 'pending' });
    await setDoc(doc(db, 'orders/srv1'), { status: 'cancelled', pricedBy: 'server', userId: 'u1', total: 1000 });
    await setDoc(doc(db, 'orders/old1'), { status: 'new', userId: 'u1', total: 1000 });
  });
});

const as = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

const legacyOrder = (extra = {}) => ({
  customer: { name: 'علي', phone: '07701234567' },
  items: [{ productId: 'p1', name: 'x', price: 1000, quantity: 1 }],
  total: 1000,
  status: 'new',
  createdAt: serverTimestamp(),
  deliveryDay: 'الخميس',
  pickupMethod: 'delivery',
  ...extra,
});

describe('existing behaviour still works', () => {
  it('a guest places a legacy order, but cannot sneak in discount or server fields', async () => {
    await assertSucceeds(addDoc(collection(as(), 'orders'), legacyOrder()));
    await assertFails(addDoc(collection(as(), 'orders'), legacyOrder({ pricedBy: 'server' })));
    await assertFails(addDoc(collection(as(), 'orders'), legacyOrder({ discount: 500 })));
    await assertFails(addDoc(collection(as(), 'orders'), legacyOrder({ status: 'done' })));
  });

  it('the owner can turn off legacy orders once everyone has updated', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'settings/orders'), { legacyClientOrders: false }));
    await assertFails(addDoc(collection(as(), 'orders'), legacyOrder()));
  });

  it('admin changes status; a cancelled server order stays cancelled', async () => {
    await assertSucceeds(updateDoc(doc(as('admin1'), 'orders/old1'), { status: 'done' }));
    await assertFails(updateDoc(doc(as('admin1'), 'orders/srv1'), { status: 'done' }));
    await assertFails(updateDoc(doc(as('u1'), 'orders/old1'), { status: 'done' }));
    await assertFails(updateDoc(doc(as('admin1'), 'orders/old1'), { total: 1 }));
  });

  it('customers read only their own orders and profile', async () => {
    await assertSucceeds(getDoc(doc(as('u1'), 'orders/old1')));
    await assertFails(getDoc(doc(as('u2'), 'orders/old1')));
    await assertSucceeds(setDoc(doc(as('u1'), 'users/u1'), { name: 'علي', phone: '0770', address: '' }));
    await assertFails(setDoc(doc(as('u1'), 'users/u1'), { name: 'علي', points: 9999 }));
  });
});

describe('wallets and ledger', () => {
  it('only the owner (and admin) can read, nobody can write from the app', async () => {
    await assertSucceeds(getDoc(doc(as('u1'), 'wallets/u1')));
    await assertSucceeds(getDocs(collection(as('u1'), 'wallets/u1/ledger')));
    await assertSucceeds(getDoc(doc(as('admin1'), 'wallets/u1')));
    await assertFails(getDoc(doc(as('u2'), 'wallets/u1')));
    await assertFails(setDoc(doc(as('u1'), 'wallets/u1'), { points: 1000000 }));
    await assertFails(setDoc(doc(as('u1'), 'wallets/u1/ledger/x'), { points: 5 }));
    await assertFails(setDoc(doc(as('admin1'), 'wallets/u1'), { points: 5 }));
  });
});

describe('coupons', () => {
  it('general codes are secret; personal coupons are visible to their owner', async () => {
    await assertFails(getDoc(doc(as('u1'), 'coupons/SECRET')));
    await assertFails(getDocs(collection(as('u1'), 'coupons')));
    await assertSucceeds(getDocs(query(collection(as('u1'), 'coupons'), where('assignedTo', '==', 'u1'))));
    await assertFails(getDoc(doc(as('u2'), 'coupons/GIFT')));
    await assertSucceeds(getDoc(doc(as('admin1'), 'coupons/SECRET')));
  });

  it('admin creates valid coupons but cannot touch the usage counter', async () => {
    const admin = as('admin1');
    const coupon = { type: 'percent', value: 15, active: true, usedCount: 0, perUserLimit: 1, endsAt: Timestamp.fromDate(new Date('2027-01-01')) };
    await assertSucceeds(setDoc(doc(admin, 'coupons/EID15'), coupon));
    await assertFails(setDoc(doc(admin, 'coupons/bad code'), coupon));
    await assertFails(setDoc(doc(admin, 'coupons/HUGE'), { ...coupon, value: 150 }));
    await assertSucceeds(setDoc(doc(admin, 'coupons/FREESHIP'), { ...coupon, type: 'freeDelivery', value: 0 }));
    await assertFails(setDoc(doc(admin, 'coupons/ZERO'), { ...coupon, type: 'fixed', value: 0 }));
    await assertFails(setDoc(doc(admin, 'coupons/WEIRD'), { ...coupon, type: 'cashback' }));
    await assertSucceeds(setDoc(doc(admin, 'settings/delivery'), { zones: [{ id: 'baghdad', name: 'بغداد', fee: 5000, active: true }] }));
    await assertFails(setDoc(doc(as('u1'), 'settings/delivery'), { zones: [] }));
    await assertFails(setDoc(doc(admin, 'coupons/STARTED'), { ...coupon, usedCount: 5 }));
    await assertFails(updateDoc(doc(admin, 'coupons/SECRET'), { usedCount: 0 }));
    await assertSucceeds(updateDoc(doc(admin, 'coupons/SECRET'), { active: false }));
    await assertFails(setDoc(doc(as('u1'), 'coupons/MINE'), coupon));
    await assertFails(deleteDoc(doc(as('u1'), 'coupons/SECRET')));
    await assertSucceeds(deleteDoc(doc(admin, 'coupons/SECRET')));
    await assertFails(getDoc(doc(as('u1'), 'coupons/SECRET/uses/u_u1')));
  });
});

describe('referrals and smart offers', () => {
  it('referrals are written by the server only', async () => {
    await assertSucceeds(getDoc(doc(as('u2'), 'referrals/u2')));
    await assertSucceeds(getDocs(query(collection(as('u1'), 'referrals'), where('referrerUid', '==', 'u1'))));
    await assertFails(getDoc(doc(as('u3'), 'referrals/u2')));
    await assertFails(setDoc(doc(as('u3'), 'referrals/u3'), { referrerUid: 'u1', status: 'rewarded' }));
    await assertFails(getDoc(doc(as('u1'), 'referralCodes/LCABCDEF')));
  });

  it('everyone reads offer rules, only the admin edits them', async () => {
    await assertSucceeds(getDocs(collection(as(), 'recommendationRules')));
    await assertFails(setDoc(doc(as('u1'), 'recommendationRules/r1'), { title: 'x' }));
    await assertSucceeds(setDoc(doc(as('admin1'), 'recommendationRules/r1'), { title: 'x' }));
    await assertFails(deleteDoc(doc(as('u1'), 'recommendationRules/r1')));
    await assertSucceeds(deleteDoc(doc(as('admin1'), 'recommendationRules/r1')));
    await assertFails(deleteDoc(doc(as('u1'), 'orders/old1')));
    await assertSucceeds(deleteDoc(doc(as('admin1'), 'orders/old1')));
    await assertSucceeds(setDoc(doc(as('admin1'), 'settings/loyalty'), { pointsPer1000: 2 }));
    await assertFails(setDoc(doc(as('u1'), 'settings/loyalty'), { pointsPer1000: 2 }));
  });
});
