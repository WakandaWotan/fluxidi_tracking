import { publicDriverPreviewFromFleet } from "./fleet_roster_availability.mjs";
// Public https portrait for a customer booking. An initial is only correct
// when none of these URLs exist. Non-https values stay off the customer page.

const PHOTO_KEYS = [
  "public_photo_url",
  "publicPhotoUrl",
  "public_portrait_url",
  "publicPortraitUrl",
  "driver_photo_url",
  "driverPhotoUrl",
  "profile_photo_url",
  "profilePhotoUrl",
  "portrait_url",
  "portraitUrl",
  "photo_url",
  "photoUrl",
];

export function httpsDriverPhotoUrl(value) {
  const text = String(value ?? "").trim();
  if (!/^https:\/\//i.test(text)) return "";
  try { const url = new URL(text); if (url.username || url.password || url.hostname === "localhost") return ""; } catch { return ""; }
  return text;
}

export function driverPhotoFromObject(entry) {
  return httpsDriverPhotoUrl(publicDriverPreviewFromFleet(entry).public_photo_url);
}

function legList(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return []
    .concat(Array.isArray(rec?.operational_legs) ? rec.operational_legs : [])
    .concat(Array.isArray(rec?.operationalLegs) ? rec.operationalLegs : [])
    .concat(Array.isArray(booking.operational_legs) ? booking.operational_legs : [])
    .concat(Array.isArray(booking.operationalLegs) ? booking.operationalLegs : []);
}

export function driverPhotoFromBookingRecord(rec) {
  if (!rec || typeof rec !== "object") return "";
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const direct = [
    rec.assigned_driver,
    rec.assignedDriver,
    booking.assigned_driver,
    booking.assignedDriver,
    rec,
    booking,
  ];
  for (const entry of direct) {
    const photo = driverPhotoFromObject(entry);
    if (photo) return photo;
  }
  for (const leg of legList(rec)) {
    if (!leg || typeof leg !== "object") continue;
    const photo =
      driverPhotoFromObject(leg.assigned_driver) ||
      driverPhotoFromObject(leg.assignedDriver) ||
      driverPhotoFromObject(leg);
    if (photo) return photo;
  }
  return "";
}

export function assignedDriverIdFromRecord(rec) {
  if (!rec || typeof rec !== "object") return "";
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const nested = rec.assigned_driver || rec.assignedDriver || booking.assigned_driver || {};
  const direct = String(
    rec.assigned_driver_id ||
      rec.assignedDriverId ||
      nested.driver_id ||
      nested.driverId ||
      nested.id ||
      booking.assigned_driver_id ||
      booking.assignedDriverId ||
      "",
  ).trim();
  if (direct) return direct;
  for (const leg of legList(rec)) {
    if (!leg || typeof leg !== "object") continue;
    const legDriver = leg.assigned_driver || leg.assignedDriver || {};
    const id = String(
      leg.assigned_driver_id || leg.assignedDriverId || legDriver.driver_id || legDriver.driverId || legDriver.id || "",
    ).trim();
    if (id) return id;
  }
  return "";
}

function stampOne(target, photo, driverId) {
  if (!target || typeof target !== "object") return;
  const ownId = assignedDriverIdFromRecord({ ...target, operational_legs: [], operationalLegs: [], booking: undefined });
  if (!ownId || ownId !== driverId) return;
  const current = target.assigned_driver && typeof target.assigned_driver === "object" ? target.assigned_driver : {};
  const next = {
    ...current,
    public_photo_enabled: true,
    public_portrait_url: photo,
    public_photo_url: photo,
    publicPhotoUrl: photo,
    driver_photo_url: photo,
    driverPhotoUrl: photo,
  };
  if (driverId && !next.driver_id && !next.driverId) next.driver_id = driverId;
  target.assigned_driver = next;
  target.assignedDriver = next;
  target.driver_photo_url = photo;
  target.driverPhotoUrl = photo;
}

export function stampDriverPhotoOnRecord(rec, photoUrl, driverId = "") {
  const photo = httpsDriverPhotoUrl(photoUrl);
  if (!rec || typeof rec !== "object" || !photo) return rec;
  const id = String(driverId || assignedDriverIdFromRecord(rec) || "").trim();
  stampOne(rec, photo, id);
  if (rec.booking && typeof rec.booking === "object") stampOne(rec.booking, photo, id);
  for (const leg of legList(rec)) stampOne(leg, photo, id);
  return rec;
}

// Re-evaluate current scoped profile permission on every authoritative read.
export function applyCurrentDriverPhotoPermissions(rec, drivers = {}) {
 const visit = (target) => {
  if (!target || typeof target !== 'object') return;
  const id = assignedDriverIdFromRecord({...target, booking:undefined, operational_legs:[],operationalLegs:[]});
  for (const obj of [target,target.assigned_driver,target.assignedDriver]) {
   if (!obj || typeof obj !== 'object') continue;
   for(const key of PHOTO_KEYS) delete obj[key];
   delete obj.public_photo_enabled; delete obj.publicPhotoEnabled;
  }
  const entry=drivers[id] || Object.values(drivers).find(d=>String(d?.driver_id ?? d?.driverId ?? '').trim()===id);
  const photo=driverPhotoFromObject(entry);
  if(id && photo) stampOne(target,photo,id);
 };
 visit(rec); visit(rec?.booking);
 for(const leg of legList(rec)) visit(leg);
 return rec;
}
