// حالة الطلب والمكافآت والإشعارات.
//
// كل شي هنا "idempotent": إذا انعاد نفس الطلب مرتين (النت انقطع، المدير ضغط مرتين،
// أو التطبيق القديم والجديد نادوا سوا) النتيجة نفسها: النقاط تنضاف مرة وحدة،
// والإشعار لكل حالة ينبعث مرة وحدة بس.

import { loyaltySettings, pointsFor } from './pricing.js';
import { OrderError, REQUEST_ID } from './orders.js';
import { sendPush, statusMessage } from './push.js';

export const STATUSES = ['new', 'confirmed', 'delivering', 'done', 'cancelled'];

/** الانتقالات المسموحة لطلبات السيرفر. الملغي نهائي، حتى ما ترجع النقاط والكوبون مرتين. */
export function canMove(from, to) {
  if (!STATUSES.includes(to) || from === to) return false;
  return from !== 'cancelled';
}

const lastHistory = (order) => (order.statusHistory || []).at(-1)?.status;

/**
 * يطبق آثار الحالة الحالية على الطلب داخل المعاملة:
 * - تسليم (done): نقاط الطلب + مكافأة الدعوة إذا أول طلب مؤهل.
 * - إلغاء: ترجع النقاط المستعملة، وتنسحب النقاط المكتسبة، ويرجع استعمال الكوبون.
 * يرجع قائمة إشعارات للزبائن (مثل "كسبت نقاط").
 */
async function settle(tx, orderId, order, now) {
  const notes = [];
  const updates = {};
  if (lastHistory(order) !== order.status) {
    // التطبيق القديم يغير الحالة بدون السجل؛ نضيفها هنا حتى تبين بالمتابعة.
    updates.statusHistory = [...(order.statusHistory || []), { status: order.status, at: now }];
  }
  if (order.pricedBy !== 'server') return { updates, notes };
  const uid = order.userId || '';

  if (order.status === 'done' && uid && !order.pointsAwardedAt && !order.cancelSettledAt) {
    const loyalty = loyaltySettings((await tx.get('settings/loyalty'))?.data);
    // النقاط والدعوة على مبلغ المنتجات بس، بدون أجور التوصيل.
    const productsPaid = (Number(order.total) || 0) - (Number(order.deliveryFee) || 0);
    const earned = pointsFor(loyalty, productsPaid);
    const referral = loyalty.referralEnabled ? await tx.get(`referrals/${uid}`) : null;
    const qualifies = referral?.data.status === 'pending'
      && productsPaid >= loyalty.referralMinTotal;
    const referrerUid = qualifies ? referral.data.referrerUid : '';
    const [wallet, referrerWallet] = await Promise.all([
      tx.get(`wallets/${uid}`),
      referrerUid ? tx.get(`wallets/${referrerUid}`) : null,
    ]);

    let points = Number(wallet?.data.points) || 0;
    let lifetime = Number(wallet?.data.lifetimeEarned) || 0;
    if (earned > 0) {
      points += earned;
      lifetime += earned;
      tx.create(`wallets/${uid}/ledger/earn-${orderId}`, {
        type: 'earn', points: earned, orderId, createdAt: now, note: 'نقاط الطلب بعد التسليم',
      });
      notes.push({ uid, title: '⭐ كسبت نقاط', body: `انضافت ${earned} نقطة لمحفظتك من طلبك.` });
    }
    if (qualifies) {
      const capped = (Number(referrerWallet?.data.referralsRewarded) || 0) >= loyalty.maxReferralsPerUser;
      if (loyalty.refereePoints > 0) {
        points += loyalty.refereePoints;
        lifetime += loyalty.refereePoints;
        tx.create(`wallets/${uid}/ledger/referral-welcome`, {
          type: 'referral', points: loyalty.refereePoints, orderId, createdAt: now, note: 'هدية الدعوة',
        });
        notes.push({ uid, title: '🎁 هدية الدعوة', body: `انضافت ${loyalty.refereePoints} نقطة لأن صديقك دعاك.` });
      }
      if (!capped && loyalty.referrerPoints > 0 && referrerUid !== uid) {
        const rp = (Number(referrerWallet?.data.points) || 0) + loyalty.referrerPoints;
        const rl = (Number(referrerWallet?.data.lifetimeEarned) || 0) + loyalty.referrerPoints;
        const data = {
          points: rp,
          lifetimeEarned: rl,
          referralsRewarded: (Number(referrerWallet?.data.referralsRewarded) || 0) + 1,
          updatedAt: now,
        };
        if (referrerWallet) tx.update(`wallets/${referrerUid}`, data);
        else tx.create(`wallets/${referrerUid}`, { ...data, ordersPlaced: 0, createdAt: now });
        tx.create(`wallets/${referrerUid}/ledger/referral-${uid}`, {
          type: 'referral', points: loyalty.referrerPoints, orderId, createdAt: now, note: 'صديقك استلم أول طلب',
        });
        notes.push({ uid: referrerUid, title: '🎉 صديقك طلب', body: `انضافت ${loyalty.referrerPoints} نقطة لمحفظتك.` });
      }
      tx.update(`referrals/${uid}`, {
        status: capped ? 'capped' : 'rewarded', rewardedAt: now, orderId,
      });
    }
    const walletData = { points, lifetimeEarned: lifetime, updatedAt: now };
    if (wallet) tx.update(`wallets/${uid}`, walletData);
    else tx.create(`wallets/${uid}`, { ...walletData, ordersPlaced: 0, createdAt: now });
    updates.pointsEarned = earned;
    updates.pointsAwardedAt = now;
  }

  if (order.status === 'cancelled' && !order.cancelSettledAt) {
    const used = Number(order.pointsUsed) || 0;
    const earned = order.pointsAwardedAt ? Number(order.pointsEarned) || 0 : 0;
    if (uid && (used > 0 || earned > 0)) {
      const wallet = await tx.get(`wallets/${uid}`);
      let points = Number(wallet?.data.points) || 0;
      if (used > 0) {
        points += used;
        tx.create(`wallets/${uid}/ledger/refund-${orderId}`, {
          type: 'refund', points: used, orderId, createdAt: now, note: 'رجعت نقاط الطلب الملغي',
        });
      }
      if (earned > 0) {
        const taken = Math.min(earned, points);
        points -= taken;
        tx.create(`wallets/${uid}/ledger/reverse-${orderId}`, {
          type: 'reverse', points: -taken, orderId, createdAt: now, note: 'انسحبت نقاط الطلب الملغي',
        });
      }
      const data = { points, updatedAt: now };
      if (wallet) tx.update(`wallets/${uid}`, data);
      else tx.create(`wallets/${uid}`, { ...data, ordersPlaced: 0, lifetimeEarned: 0, createdAt: now });
    }
    if (order.coupon?.code) {
      const code = order.coupon.code;
      const keys = [uid && `u_${uid}`, order.phoneKey && `p_${order.phoneKey}`].filter(Boolean);
      const [coupon, ...uses] = await Promise.all([
        tx.get(`coupons/${code}`),
        ...keys.map((key) => tx.get(`coupons/${code}/uses/${key}`)),
      ]);
      if (coupon) {
        tx.update(`coupons/${code}`, { usedCount: Math.max(0, (Number(coupon.data.usedCount) || 0) - 1), updatedAt: now });
      }
      uses.forEach((use, i) => {
        if (use) tx.update(`coupons/${code}/uses/${keys[i]}`, { count: Math.max(0, (Number(use.data.count) || 0) - 1), updatedAt: now });
      });
    }
    updates.cancelSettledAt = now;
  }
  return { updates, notes };
}

/**
 * يغير حالة الطلب (status = null يعني بس طبّق آثار الحالة الحالية، للتطبيق القديم).
 * يرجع { order, notes, changed }.
 */
export async function applyStatus(ctx, orderId, status = null) {
  const now = ctx.now;
  return ctx.db.runTransaction(async (tx) => {
    const doc = await tx.get(`orders/${orderId}`);
    if (!doc) throw new OrderError(404, 'not_found', 'الطلب مو موجود');
    let order = doc.data;
    const before = {};
    if (status) {
      if (order.status === status) {
        // نفس الحالة: ما نغير شي، بس نكمل الآثار إذا ناقصة.
      } else if (order.pricedBy === 'server' && !canMove(order.status, status)) {
        throw new OrderError(409, 'invalid_status', 'ما يصير ترجع طلب ملغي');
      } else if (!STATUSES.includes(status)) {
        throw new OrderError(400, 'invalid_status', 'حالة غلط');
      } else {
        before.status = status;
        before.statusHistory = [...(order.statusHistory || []), { status, at: now }];
        before.updatedAt = now;
        order = { ...order, ...before };
      }
    }
    const { updates, notes } = await settle(tx, orderId, order, now);
    const all = { ...before, ...updates };
    if (Object.keys(all).length) tx.update(`orders/${orderId}`, all);
    return { order: { ...order, ...all }, notes, changed: Boolean(before.status) };
  });
}

/**
 * إشعار الزبون بحالة طلبه، مرة وحدة لكل حالة (notifiedStatuses).
 * نحجز الحالة بالمعاملة قبل الإرسال؛ إذا الإرسال فشل نرجعها حتى المحاولة الجاية ترسل.
 */
export async function notifyCustomer(ctx, orderId) {
  const claim = await ctx.db.runTransaction(async (tx) => {
    const doc = await tx.get(`orders/${orderId}`);
    if (!doc) return null;
    const order = doc.data;
    const message = statusMessage(order);
    const sent = order.notifiedStatuses || (order.statusNotified ? [order.statusNotified] : []);
    if (!message || !order.pushToken || sent.includes(order.status)) return null;
    tx.update(`orders/${orderId}`, { notifiedStatuses: [...sent, order.status], statusNotified: order.status });
    return { order, message, sent };
  });
  if (!claim) return 'skipped';
  try {
    return await sendPush({
      projectId: ctx.projectId, token: ctx.token, deviceToken: claim.order.pushToken, ...claim.message, fetchImpl: ctx.fetchImpl,
    });
  } catch (error) {
    await ctx.db.apply('update', `orders/${orderId}`, {
      notifiedStatuses: claim.sent, statusNotified: claim.sent.at(-1) ?? null,
    }).catch(() => {});
    throw error;
  }
}

/** إشعارات المكافآت: على آخر موبايل طلب منه الزبون (توكن آخر طلب). */
export async function notifyRewards(ctx, notes) {
  await Promise.all(notes.map(async (note) => {
    try {
      // بدون orderBy حتى ما نحتاج index مركب بـ Firestore؛ نرتبها هنا.
      const rows = await ctx.db.query('orders', { where: [['userId', '==', note.uid]], limit: 50 });
      const latest = rows
        .filter((row) => row.data.pushToken)
        .sort((a, b) => (b.data.createdAt?.getTime?.() || 0) - (a.data.createdAt?.getTime?.() || 0))[0];
      const token = latest?.data.pushToken;
      if (!token) return;
      await sendPush({
        projectId: ctx.projectId, token: ctx.token, deviceToken: token, title: note.title, body: note.body, fetchImpl: ctx.fetchImpl,
      });
    } catch (error) {
      console.error('reward push failed', note.uid, error);
    }
  }));
}

/** POST /api/admin/order-status { orderId, status }: المدير بس. */
export async function setOrderStatus(ctx, body) {
  const { orderId, status } = body || {};
  if (typeof orderId !== 'string' || !/^[A-Za-z0-9]{1,64}$/.test(orderId)) {
    throw new OrderError(400, 'invalid_request', 'رقم الطلب غلط');
  }
  if (!STATUSES.includes(status)) throw new OrderError(400, 'invalid_status', 'حالة غلط');
  const result = await applyStatus(ctx, orderId, status);
  const [push] = await Promise.allSettled([notifyCustomer(ctx, orderId), notifyRewards(ctx, result.notes)]);
  return {
    ok: true,
    status: result.order.status,
    pointsEarned: result.order.pointsEarned ?? null,
    push: push.status === 'fulfilled' ? push.value : 'failed',
  };
}

export { REQUEST_ID };
