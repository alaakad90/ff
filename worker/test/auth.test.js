import assert from 'node:assert/strict';
import { beforeEach, it } from 'node:test';

import { clearKeyCache, verifyIdToken } from '../src/auth.js';
import { base64url } from '../src/google.js';

const PROJECT = 'demo-lacasa';
const NOW = Date.parse('2026-10-26T10:00:00Z');

const keys = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true,
  ['sign', 'verify'],
);
const jwk = { ...(await crypto.subtle.exportKey('jwk', keys.publicKey)), kid: 'k1' };

let jwksCalls = 0;
const fetchImpl = async () => {
  jwksCalls++;
  return Response.json({ keys: [jwk] }, { headers: { 'cache-control': 'public, max-age=600' } });
};

async function token(claims = {}, header = {}) {
  const seconds = Math.floor(NOW / 1000);
  const body = {
    aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, sub: 'user1', iat: seconds - 10, exp: seconds + 3600,
    firebase: { sign_in_provider: 'password' }, ...claims,
  };
  const unsigned = `${base64url(JSON.stringify({ alg: 'RS256', kid: 'k1', ...header }))}.${base64url(JSON.stringify(body))}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keys.privateKey, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(signature)}`;
}

const verify = (t) => verifyIdToken(t, { projectId: PROJECT, fetchImpl, now: NOW });

beforeEach(() => clearKeyCache());

it('accepts a valid Firebase token and caches the keys', async () => {
  assert.deepEqual(await verify(await token({ email: 'a@b.c' })), { uid: 'user1', email: 'a@b.c', anonymous: false });
  await verify(await token());
  assert.equal(jwksCalls, 1);
});

it('marks anonymous accounts', async () => {
  assert.equal((await verify(await token({ firebase: { sign_in_provider: 'anonymous' } }))).anonymous, true);
});

it('rejects tampered, expired, foreign and malformed tokens', async () => {
  const good = await token();
  const [h, , s] = good.split('.');
  const forged = `${h}.${base64url(JSON.stringify({ aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, sub: 'admin1', iat: 0, exp: 9e9 }))}.${s}`;
  assert.equal(await verify(forged), null);
  assert.equal(await verify(await token({ exp: Math.floor(NOW / 1000) - 1 })), null);
  assert.equal(await verify(await token({ aud: 'other-project' })), null);
  assert.equal(await verify(await token({ iss: 'https://evil.example' })), null);
  assert.equal(await verify(await token({ sub: '' })), null);
  assert.equal(await verify(await token({}, { kid: 'unknown' })), null);
  assert.equal(await verify(await token({}, { alg: 'none' })), null);
  assert.equal(await verify('not.a.token'), null);
  assert.equal(await verify(null), null);
});
