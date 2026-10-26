// التحقق من هوية الزبون: التطبيق يرسل توكن Firebase (ID token) بـ Authorization،
// والسيرفر يتأكد إنه موقّع من Google ولنفس المشروع وما منتهي.

const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let keyCache = null; // { keys: Map(kid → CryptoKey), expiresAt }

export function clearKeyCache() {
  keyCache = null;
}

function decodePart(part) {
  const base64 = part.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function publicKeys(fetchImpl, now) {
  if (keyCache && keyCache.expiresAt > now) return keyCache.keys;
  const response = await fetchImpl(JWKS_URL);
  if (!response.ok) throw new Error(`jwks ${response.status}`);
  const maxAge = Number(/max-age=(\d+)/.exec(response.headers.get('cache-control') || '')?.[1] || 3600);
  const { keys } = await response.json();
  const map = new Map();
  for (const jwk of keys) {
    map.set(jwk.kid, await crypto.subtle.importKey(
      'jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
    ));
  }
  keyCache = { keys: map, expiresAt: now + maxAge * 1000 };
  return map;
}

/**
 * يرجع { uid, email, anonymous } إذا التوكن صحيح، أو null إذا غلط أو منتهي.
 * الحساب المجهول (anonymous) يعتبر زائر: ما عنده محفظة ولا نقاط.
 */
export async function verifyIdToken(idToken, { projectId, fetchImpl = fetch, now = Date.now() }) {
  if (typeof idToken !== 'string') return null;
  const parts = idToken.split('.');
  if (parts.length !== 3) return null;
  let header;
  let claims;
  try {
    header = JSON.parse(new TextDecoder().decode(decodePart(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(decodePart(parts[1])));
  } catch {
    return null;
  }
  if (header.alg !== 'RS256' || !header.kid) return null;
  const key = (await publicKeys(fetchImpl, now)).get(header.kid);
  if (!key) return null;
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5', key, decodePart(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  const seconds = Math.floor(now / 1000);
  if (!valid
    || claims.aud !== projectId
    || claims.iss !== `https://securetoken.google.com/${projectId}`
    || typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 128
    || !(claims.exp > seconds)
    || !(claims.iat <= seconds + 300)) {
    return null;
  }
  return {
    uid: claims.sub,
    email: claims.email || '',
    anonymous: claims.firebase?.sign_in_provider === 'anonymous',
  };
}

/** التوكن من هيدر Authorization: Bearer ... */
export function bearer(request) {
  const match = /^Bearer\s+(.+)$/i.exec(request.headers.get('Authorization') || '');
  return match ? match[1].trim() : null;
}
