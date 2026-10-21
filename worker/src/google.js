// توكن Google من مفتاح الخدمة (service account) حتى نقرا ونكتب بـ Firestore.
// نسوي JWT موقّع بـ RS256 وننطيه لـ Google مقابل access token.

const SCOPE = 'https://www.googleapis.com/auth/datastore';

const encoder = new TextEncoder();

export function base64url(bytes) {
  const data = typeof bytes === 'string' ? encoder.encode(bytes) : new Uint8Array(bytes);
  let binary = '';
  for (const b of data) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToDer(pem) {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return der.buffer;
}

export async function signJwt(serviceAccount, nowSeconds) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: serviceAccount.client_email,
    scope: SCOPE,
    aud: serviceAccount.token_uri || 'https://oauth2.googleapis.com/token',
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned));
  return `${unsigned}.${base64url(signature)}`;
}

// التوكن يبقى صالح ساعة، فنحتفظ بيه بين الطلبات اللي تجي لنفس النسخة من السيرفر.
let cached = null;

export function clearTokenCache() {
  cached = null;
}

export async function getAccessToken(serviceAccount, fetchImpl = fetch, now = Date.now()) {
  if (cached && cached.email === serviceAccount.client_email && cached.expiresAt - 60_000 > now) {
    return cached.token;
  }
  const assertion = await signJwt(serviceAccount, Math.floor(now / 1000));
  const response = await fetchImpl(serviceAccount.token_uri || 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });
  if (!response.ok) {
    throw new Error(`google token ${response.status}: ${await response.text()}`);
  }
  const json = await response.json();
  cached = {
    email: serviceAccount.client_email,
    token: json.access_token,
    expiresAt: now + (json.expires_in || 3600) * 1000,
  };
  return cached.token;
}
