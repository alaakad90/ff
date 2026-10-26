// عميل Firestore REST عام: قراءة، بحث، ومعاملات (transactions) ذرية.
// السيرفر يكتب بمفتاح الخدمة، فقواعد Firestore ما تنطبق عليه؛ كل التحقق لازم يصير هنا.
// بالاختبارات ينطى baseUrl مال المحاكي (Firestore emulator) وتوكن "owner".

import { decodeFields, decodeValue } from './firestore.js';

/** خطأ تعارض: المعاملة لازم تنعاد (أحد ثاني غيّر نفس الوثائق) أو الوثيقة موجودة. */
export class ConflictError extends Error {}

/** قيمة JS ← قيمة Firestore. الأرقام الصحيحة integerValue، وDate تصير timestamp. */
export function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  switch (typeof value) {
    case 'string': return { stringValue: value };
    case 'boolean': return { booleanValue: value };
    case 'number': return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
    case 'object': return { mapValue: { fields: encodeFields(value) } };
    default: throw new Error(`cannot encode ${typeof value}`);
  }
}

export function encodeFields(data) {
  const fields = {};
  for (const [key, value] of Object.entries(data)) {
    if (value !== undefined) fields[key] = encodeValue(value);
  }
  return fields;
}

const OPERATORS = {
  '==': 'EQUAL', '!=': 'NOT_EQUAL', '<': 'LESS_THAN', '<=': 'LESS_THAN_OR_EQUAL',
  '>': 'GREATER_THAN', '>=': 'GREATER_THAN_OR_EQUAL', 'array-contains': 'ARRAY_CONTAINS', in: 'IN',
};

function isConflict(status, body) {
  return status === 409 || /ABORTED|FAILED_PRECONDITION|ALREADY_EXISTS/.test(body);
}

export function createDb({ projectId, token, fetchImpl = fetch, baseUrl = 'https://firestore.googleapis.com' }) {
  const root = `projects/${projectId}/databases/(default)/documents`;
  const api = `${baseUrl}/v1/${root}`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const name = (path) => `${root}/${path}`;
  const pathOf = (fullName) => fullName.slice(root.length + 1);

  async function call(url, init = {}) {
    const response = await fetchImpl(url, { ...init, headers });
    const text = await response.text();
    if (!response.ok) {
      if (isConflict(response.status, text)) throw new ConflictError(text);
      const error = new Error(`firestore ${response.status}: ${text}`);
      error.status = response.status;
      throw error;
    }
    return text ? JSON.parse(text) : {};
  }

  /**
   * يقرا وثائق بطلب واحد (batchGet، نفس اللي تستعمله مكتبات Firebase داخل المعاملات).
   * يرجع لكل مسار { id, path, data, updateTime } أو null إذا مو موجودة.
   */
  async function getAll(paths, { transaction } = {}) {
    if (!paths.length) return [];
    const rows = await call(`${api}:batchGet`, {
      method: 'POST',
      body: JSON.stringify({ documents: paths.map(name), ...(transaction ? { transaction } : {}) }),
    });
    const found = new Map();
    for (const row of rows) {
      if (row.found) found.set(pathOf(row.found.name), row.found);
    }
    return paths.map((path) => {
      const doc = found.get(path);
      return doc
        ? { id: path.split('/').pop(), path, data: decodeFields(doc.fields || {}), updateTime: doc.updateTime }
        : null;
    });
  }

  async function get(path, options) {
    return (await getAll([path], options))[0];
  }

  /** بحث بسيط: where [[field, op, value]...]، orderBy [[field, 'asc'|'desc']]، limit. */
  async function query(collection, { where = [], orderBy = [], limit } = {}, { transaction } = {}) {
    const slash = collection.lastIndexOf('/');
    const parent = slash < 0 ? api : `${api}/${collection.slice(0, slash)}`;
    const collectionId = collection.slice(slash + 1);
    const filters = where.map(([field, op, value]) => ({
      fieldFilter: { field: { fieldPath: field }, op: OPERATORS[op], value: encodeValue(value) },
    }));
    const structuredQuery = { from: [{ collectionId }] };
    if (filters.length === 1) structuredQuery.where = filters[0];
    if (filters.length > 1) structuredQuery.where = { compositeFilter: { op: 'AND', filters } };
    if (orderBy.length) {
      structuredQuery.orderBy = orderBy.map(([field, dir]) => ({
        field: { fieldPath: field }, direction: dir === 'desc' ? 'DESCENDING' : 'ASCENDING',
      }));
    }
    if (limit) structuredQuery.limit = limit;
    const rows = await call(`${parent}:runQuery`, {
      method: 'POST',
      body: JSON.stringify({ structuredQuery, ...(transaction ? { transaction } : {}) }),
    });
    return rows.filter((row) => row.document).map(({ document }) => ({
      id: document.name.split('/').pop(),
      path: pathOf(document.name),
      data: decodeFields(document.fields || {}),
      updateTime: document.updateTime,
    }));
  }

  /** كتابة وحدة بصيغة Firestore. */
  function write(op, path, data, { mask } = {}) {
    if (op === 'delete') return { delete: name(path) };
    const w = { update: { name: name(path), fields: encodeFields(data) } };
    if (op === 'create') w.currentDocument = { exists: false };
    if (op === 'update') {
      w.currentDocument = { exists: true };
      w.updateMask = { fieldPaths: mask || Object.keys(data) };
    }
    if (op === 'merge') w.updateMask = { fieldPaths: mask || Object.keys(data) };
    return w;
  }

  async function commit(writes, transaction) {
    return call(`${api}:commit`, {
      method: 'POST',
      body: JSON.stringify({ writes, ...(transaction ? { transaction } : {}) }),
    });
  }

  /**
   * يشغل fn داخل معاملة. fn تقرا بـ tx.get/tx.query وتجمع الكتابات بـ tx.set/create/update/merge/delete،
   * وكلها تنكتب سوا أو ما ينكتب شي. إذا صار تعارض تنعاد من جديد (لحد attempts مرات).
   */
  async function runTransaction(fn, { attempts = 5 } = {}) {
    let lastError;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const { transaction } = await call(`${api}:beginTransaction`, {
        method: 'POST',
        body: JSON.stringify({ options: { readWrite: {} } }),
      });
      const writes = [];
      const tx = {
        get: (path) => get(path, { transaction }),
        getAll: (paths) => getAll(paths, { transaction }),
        query: (collection, options) => query(collection, options, { transaction }),
        set: (path, data) => writes.push(write('set', path, data)),
        create: (path, data) => writes.push(write('create', path, data)),
        update: (path, data, mask) => writes.push(write('update', path, data, { mask })),
        merge: (path, data, mask) => writes.push(write('merge', path, data, { mask })),
        delete: (path) => writes.push(write('delete', path)),
      };
      let result;
      try {
        result = await fn(tx);
      } catch (error) {
        await call(`${api}:rollback`, { method: 'POST', body: JSON.stringify({ transaction }) }).catch(() => {});
        throw error;
      }
      try {
        await commit(writes, transaction);
        return result;
      } catch (error) {
        if (!(error instanceof ConflictError)) throw error;
        lastError = error;
      }
    }
    throw lastError;
  }

  return {
    projectId, name, get, getAll, query, commit, write, runTransaction,
    /** كتابة وحدة خارج المعاملة. */
    async apply(op, path, data, options) {
      await commit([write(op, path, data, options)]);
    },
  };
}

export { decodeFields, decodeValue };
