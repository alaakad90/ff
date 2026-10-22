// قراءة وكتابة الطلبات بـ Firestore REST API.

/** يحول قيمة Firestore المكتوبة (stringValue، mapValue...) لقيمة JS عادية. */
export function decodeValue(value) {
  if (value == null) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return new Date(value.timestampValue);
  if ('nullValue' in value) return null;
  if ('mapValue' in value) return decodeFields(value.mapValue.fields || {});
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeValue);
  return null;
}

export function decodeFields(fields) {
  const out = {};
  for (const [key, value] of Object.entries(fields)) out[key] = decodeValue(value);
  return out;
}

function documentUrl(projectId, path) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`;
}

/** يرجع { data, updateTime } أو null إذا الطلب مو موجود. */
export async function getOrder({ projectId, token, orderId, fetchImpl = fetch }) {
  const response = await fetchImpl(documentUrl(projectId, `orders/${orderId}`), {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`firestore get ${response.status}: ${await response.text()}`);
  const doc = await response.json();
  return { data: decodeFields(doc.fields || {}), updateTime: doc.updateTime };
}

/**
 * يحط notifiedAt على الطلب بشرط ما تغير من وكت ما قريناه.
 * إذا طلبين وصلوا سوا، واحد بس ينجح، فالرسالة ما تنبعث مرتين.
 * يرجع false إذا غيرنا سبقنا.
 */
export async function claimOrder({ projectId, token, orderId, updateTime, fetchImpl = fetch, now = new Date() }) {
  const url = new URL(documentUrl(projectId, `orders/${orderId}`));
  url.searchParams.set('updateMask.fieldPaths', 'notifiedAt');
  url.searchParams.set('currentDocument.updateTime', updateTime);
  const response = await fetchImpl(url.toString(), {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: { notifiedAt: { timestampValue: now.toISOString() } } }),
  });
  if (response.ok) return true;
  const body = await response.text();
  // FAILED_PRECONDITION: الطلب تغير بينما احنا نشتغل، يعني طلب ثاني سبقنا.
  if (/FAILED_PRECONDITION|ABORTED/.test(body)) return false;
  throw new Error(`firestore claim ${response.status}: ${body}`);
}

/** يشيل notifiedAt حتى نكدر نعيد المحاولة إذا التليجرام فشل. */
export async function releaseOrder({ projectId, token, orderId, fetchImpl = fetch }) {
  const url = new URL(documentUrl(projectId, `orders/${orderId}`));
  url.searchParams.set('updateMask.fieldPaths', 'notifiedAt');
  await fetchImpl(url.toString(), {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: {} }),
  });
}
