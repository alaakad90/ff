// أجور التوصيل حسب المحافظة. صاحب المتجر يعدلها من لوحة التحكم (settings/delivery)،
// وإذا ما محفوظة نستعمل الافتراضي. نفس القائمة موجودة بالتطبيق (lib/models/delivery.dart).

export const DEFAULT_ZONES = Object.freeze([
  { id: 'diwaniyah-center', name: 'الديوانية - المركز', fee: 2000 },
  { id: 'diwaniyah-districts', name: 'الديوانية - الأقضية والنواحي', fee: 4000 },
  { id: 'baghdad', name: 'بغداد', fee: 5000 },
  { id: 'basra', name: 'البصرة', fee: 5000 },
  { id: 'ninawa', name: 'نينوى', fee: 5000 },
  { id: 'erbil', name: 'أربيل', fee: 5000 },
  { id: 'sulaymaniyah', name: 'السليمانية', fee: 5000 },
  { id: 'duhok', name: 'دهوك', fee: 5000 },
  { id: 'halabja', name: 'حلبجة', fee: 5000 },
  { id: 'kirkuk', name: 'كركوك', fee: 5000 },
  { id: 'anbar', name: 'الأنبار', fee: 5000 },
  { id: 'salahaddin', name: 'صلاح الدين', fee: 5000 },
  { id: 'diyala', name: 'ديالى', fee: 5000 },
  { id: 'babil', name: 'بابل', fee: 5000 },
  { id: 'karbala', name: 'كربلاء', fee: 5000 },
  { id: 'najaf', name: 'النجف', fee: 5000 },
  { id: 'wasit', name: 'واسط', fee: 5000 },
  { id: 'maysan', name: 'ميسان', fee: 5000 },
  { id: 'dhiqar', name: 'ذي قار', fee: 5000 },
  { id: 'muthanna', name: 'المثنى', fee: 5000 },
].map((zone) => Object.freeze({ ...zone, active: true })));

const ZONE_ID = /^[a-z0-9-]{1,40}$/;
const MAX_FEE = 1000000;

/** المناطق من Firestore بعد التصحيح. أي منطقة غلط تنشال؛ إذا ماكو شي صحيح نرجع الافتراضي. */
export function deliveryZones(raw) {
  const zones = [];
  const seen = new Set();
  for (const zone of Array.isArray(raw?.zones) ? raw.zones : []) {
    const fee = Math.trunc(Number(zone?.fee));
    const name = typeof zone?.name === 'string' ? zone.name.trim().slice(0, 60) : '';
    if (!ZONE_ID.test(zone?.id || '') || seen.has(zone.id) || !name || !(fee >= 0 && fee <= MAX_FEE)) continue;
    seen.add(zone.id);
    zones.push({ id: zone.id, name, fee, active: zone.active !== false });
  }
  return zones.length ? zones : DEFAULT_ZONES.map((z) => ({ ...z }));
}

/** المنطقة المفعلة بهذا الرقم، أو null. */
export function findZone(zones, id) {
  return zones.find((zone) => zone.id === id && zone.active) || null;
}
