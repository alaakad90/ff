// دعوة الأصدقاء: كل زبون عنده كود. الصديق الجديد يحط الكود قبل أول طلب،
// ومن يستلم أول طلب مؤهل، الاثنين ياخذون نقاط (rewards.js).
//
// منع التلاعب: ما يصير تدعو نفسك، كل حساب يقبل دعوة وحدة بس، لازم ما عنده طلبات قبل،
// ولازم يحطها خلال مدة من التسجيل، والمكافأة بس بعد التسليم الفعلي وبحد أعلى لكل داعي.

import { OrderError } from './orders.js';
import { loyaltySettings } from './pricing.js';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const REFERRAL_CODE = /^LC[A-Z2-9]{6}$/;

function newCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return `LC${Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join('')}`;
}

function requireMember(user) {
  if (!user || user.anonymous) throw new OrderError(401, 'sign_in', 'سجل دخول حتى تستعمل الدعوات');
}

/** POST /api/referral/code: كود الزبون (ينسوى أول مرة). */
export async function referralCode(ctx, user) {
  requireMember(user);
  const existing = await ctx.db.get(`wallets/${user.uid}`);
  if (existing?.data.referralCode) return { code: existing.data.referralCode };
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newCode();
    try {
      return await ctx.db.runTransaction(async (tx) => {
        const wallet = await tx.get(`wallets/${user.uid}`);
        if (wallet?.data.referralCode) return { code: wallet.data.referralCode };
        if (await tx.get(`referralCodes/${code}`)) throw new OrderError(409, 'retry', 'retry');
        tx.create(`referralCodes/${code}`, { uid: user.uid, createdAt: ctx.now });
        if (wallet) tx.update(`wallets/${user.uid}`, { referralCode: code, updatedAt: ctx.now });
        else {
          tx.create(`wallets/${user.uid}`, {
            points: 0, lifetimeEarned: 0, ordersPlaced: 0, referralCode: code, createdAt: ctx.now, updatedAt: ctx.now,
          });
        }
        return { code };
      }, { attempts: 2 });
    } catch (error) {
      if (!(error instanceof OrderError && error.code === 'retry')) throw error;
    }
  }
  throw new OrderError(503, 'busy', 'حاول مرة ثانية');
}

/** POST /api/referral/apply { code }: الصديق الجديد يحط كود اللي دعاه. */
export async function applyReferral(ctx, user, body) {
  requireMember(user);
  const code = typeof body?.code === 'string' ? body.code.trim().toUpperCase() : '';
  if (!REFERRAL_CODE.test(code)) throw new OrderError(400, 'invalid_code', 'كود الدعوة مو صحيح');
  const loyalty = loyaltySettings((await ctx.db.get('settings/loyalty'))?.data);
  if (!loyalty.referralEnabled) throw new OrderError(409, 'disabled', 'الدعوات متوقفة هسه');

  return ctx.db.runTransaction(async (tx) => {
    const [codeDoc, already, wallet, profile, orders] = await Promise.all([
      tx.get(`referralCodes/${code}`),
      tx.get(`referrals/${user.uid}`),
      tx.get(`wallets/${user.uid}`),
      tx.get(`users/${user.uid}`),
      tx.query('orders', { where: [['userId', '==', user.uid]], limit: 1 }),
    ]);
    if (!codeDoc) throw new OrderError(404, 'invalid_code', 'كود الدعوة مو صحيح');
    const referrerUid = codeDoc.data.uid;
    if (referrerUid === user.uid) throw new OrderError(409, 'self', 'ما تكدر تدعو نفسك');
    if (already) throw new OrderError(409, 'already', 'حاطّ كود دعوة قبل');
    if ((Number(wallet?.data.ordersPlaced) || 0) > 0 || orders.length) {
      throw new OrderError(409, 'not_new', 'كود الدعوة للزبائن الجدد قبل أول طلب');
    }
    const joined = profile?.data.joinedAt;
    if (joined instanceof Date && ctx.now - joined > loyalty.referralWindowDays * 86400000) {
      throw new OrderError(409, 'too_late', 'انتهت مدة إضافة كود الدعوة');
    }
    tx.create(`referrals/${user.uid}`, { referrerUid, code, status: 'pending', createdAt: ctx.now });
    return { ok: true, status: 'pending', minTotal: loyalty.referralMinTotal, refereePoints: loyalty.refereePoints };
  });
}
