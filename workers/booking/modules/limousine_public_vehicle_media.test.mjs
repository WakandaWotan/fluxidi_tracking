// Public limousine gallery contract. Run:
// node --test workers/booking/modules/limousine_public_vehicle_media.test.mjs

import test from "node:test";
import assert from "node:assert/strict";

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  LIMOUSINE_PUBLIC_GALLERY_MAX,
  attachPublicVehicleMediaFields,
  buildVehicleGalleryObjectKey,
  newVehicleGalleryMediaId,
  normalizePublicVehicleGallery,
  publicMediaObjectIdentity,
  publicVehicleMediaLeaksPrivate,
} from "./limousine_public_vehicle_media.mjs";

function httpsOnly(raw) {
  const text = String(raw || "").trim();
  return text.toLowerCase().startsWith("https://") ? text : "";
}

test("gallery keeps primary first and drops the duplicate primary", () => {
  const media = normalizePublicVehicleGallery(
    {
      photo_url: "https://cdn.example/hummer-ext.jpg",
      gallery_photo_urls: [
        "https://cdn.example/hummer-ext.jpg",
        "https://cdn.example/hummer-int.jpg",
      ],
    },
    httpsOnly,
  );
  assert.deepEqual(media.gallery_photo_urls, [
    "https://cdn.example/hummer-ext.jpg",
    "https://cdn.example/hummer-int.jpg",
  ]);
  assert.equal(media.photo_url, "https://cdn.example/hummer-ext.jpg");
  assert.equal(media.primary_photo_url, "https://cdn.example/hummer-ext.jpg");
});

test("Party Limo with two safe photos publishes two media items", () => {
  const media = normalizePublicVehicleGallery(
    {
      name: "Party Limo",
      photo_url: "https://cdn.example/party-ext.jpg",
      gallery: [
        "https://cdn.example/party-ext.jpg",
        "https://cdn.example/party-int.jpg",
      ],
    },
    httpsOnly,
  );
  assert.equal(media.gallery_photo_urls.length, 2);
  assert.equal(media.gallery_photo_urls[1], "https://cdn.example/party-int.jpg");
});

test("local URIs, tokens and private keys never become public media", () => {
  const media = normalizePublicVehicleGallery(
    {
      photo_url: "file:///tmp/limo.jpg",
      gallery_photo_urls: [
        "content://media/1",
        "https://cdn.example/ok.jpg",
        "/r2/object-key",
      ],
    },
    httpsOnly,
  );
  assert.deepEqual(media.gallery_photo_urls, ["https://cdn.example/ok.jpg"]);
  assert.equal(publicVehicleMediaLeaksPrivate(media), false);
  assert.equal(
    publicVehicleMediaLeaksPrivate({
      tenant_id: "t1",
      r2_key: "secret",
    }),
    true,
  );
});

test("gallery fields stay off taxi/airport public vehicles", () => {
  const media = normalizePublicVehicleGallery(
    {
      photo_url: "https://cdn.example/taxi.jpg",
      gallery_photo_urls: [
        "https://cdn.example/taxi.jpg",
        "https://cdn.example/taxi-int.jpg",
      ],
    },
    httpsOnly,
  );
  const attached = attachPublicVehicleMediaFields({
    serviceCategory: "taxi",
    media,
    fallbackPhotoUrl: "https://cdn.example/taxi.jpg",
  });
  assert.equal(attached.photo_url, "https://cdn.example/taxi.jpg");
  assert.equal(attached.primary_photo_url, undefined);
  assert.equal(attached.gallery_photo_urls, undefined);
  assert.equal(publicVehicleMediaLeaksPrivate(attached), false);
});

test("limousine vehicles keep ordered public gallery fields", () => {
  const media = normalizePublicVehicleGallery(
    {
      photo_url: "https://cdn.example/party-ext.jpg",
      gallery: [
        "https://cdn.example/party-ext.jpg",
        "https://cdn.example/party-int.jpg",
      ],
    },
    httpsOnly,
  );
  const attached = attachPublicVehicleMediaFields({
    serviceCategory: "limousine",
    media,
    fallbackPhotoUrl: "https://cdn.example/party-ext.jpg",
  });
  assert.deepEqual(attached.gallery_photo_urls, [
    "https://cdn.example/party-ext.jpg",
    "https://cdn.example/party-int.jpg",
  ]);
  assert.equal(attached.primary_photo_url, "https://cdn.example/party-ext.jpg");
});

test("five vehicle uploads produce five gallery keys and never photo.jpg", () => {
  const keys = new Set();
  const hashes = new Set();
  for (let i = 0; i < 5; i += 1) {
    const bytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, i, 0x0a, 0x1a, 0x0a]);
    hashes.add(createHash("sha256").update(bytes).digest("hex"));
    const key = buildVehicleGalleryObjectKey({
      tenantId: "tenant_a",
      companyId: "company_a",
      vehicleId: "vh_hummer",
      mediaId: newVehicleGalleryMediaId(),
      ext: "jpg",
    });
    assert.match(key, /\/vehicles\/vh_hummer\/gallery\/.+\.jpg$/);
    assert.doesNotMatch(key, /\/photo\.jpg$/);
    keys.add(key);
  }
  assert.equal(keys.size, 5);
  assert.equal(hashes.size, 5);
});

test("legacy photo.jpg query aliases collapse to one public URL", () => {
  const media = normalizePublicVehicleGallery(
    {
      photo_url:
        "https://cdn.example/public/media/public-media/t/c/vehicles/vh_party/photo.png?v=1",
      gallery_photo_urls: [
        "https://cdn.example/public/media/public-media/t/c/vehicles/vh_party/photo.png?v=2",
        "https://cdn.example/public/media/public-media/t/c/vehicles/vh_party/photo.png?v=3",
      ],
    },
    httpsOnly,
  );
  assert.equal(media.gallery_photo_urls.length, 1);
  assert.equal(
    publicMediaObjectIdentity(media.gallery_photo_urls[0]).endsWith("/photo.png"),
    true,
  );
});

test("choosing a primary gallery item keeps the other unique objects", () => {
  const media = normalizePublicVehicleGallery(
    {
      primary_photo_url:
        "https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/a.jpg",
      gallery_photo_urls: [
        "https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/a.jpg?v=9",
        "https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/b.jpg",
        "https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/c.jpg",
      ],
    },
    httpsOnly,
  );
  assert.equal(media.gallery_photo_urls.length, 3);
  assert.equal(media.primary_photo_url.includes("/gallery/a.jpg"), true);
  assert.equal(
    media.gallery_photo_urls.some((url) => url.includes("/gallery/b.jpg")),
    true,
  );
});

test("public vehicle media never leaks tenant, company or object keys", () => {
  const media = normalizePublicVehicleGallery(
    {
      photo_url: "https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/a.jpg",
      gallery_photo_urls: [
        "https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/b.jpg",
      ],
      tenant_id: "should-not-copy",
    },
    httpsOnly,
  );
  assert.equal(publicVehicleMediaLeaksPrivate(media), false);
  assert.equal(JSON.stringify(media).includes("tenant_id"), false);
  assert.equal(JSON.stringify(media).includes("company_id"), false);
});

test("worker upload path writes gallery/{mediaId} instead of photo.jpg", () => {
  const worker = readFileSync(
    fileURLToPath(new URL("../fluxidi_booking_worker.js", import.meta.url)),
    "utf8",
  );
  assert.match(
    worker,
    /vehicles\/\$\{entitySeg\}\/gallery\/\$\{mediaSeg\}\.\$\{safeExt\}/,
  );
  assert.match(worker, /form\.get\("media_id"\)/);
  assert.doesNotMatch(
    worker,
    /vehicles\/\$\{entitySeg\}\/photo\.\$\{safeExt\}/,
  );
});

test("gallery is capped at ten unique HTTPS photos", () => {
  const gallery = [];
  for (let i = 0; i < 16; i += 1) {
    gallery.push(`https://cdn.example/p${i}.jpg`);
  }
  const media = normalizePublicVehicleGallery(
    { gallery_photo_urls: gallery },
    httpsOnly,
  );
  assert.equal(media.gallery_photo_urls.length, LIMOUSINE_PUBLIC_GALLERY_MAX);
  assert.equal(media.gallery_photo_urls[0], "https://cdn.example/p0.jpg");
});
