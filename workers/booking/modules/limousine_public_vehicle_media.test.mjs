// Public limousine gallery contract. Run:
// node --test workers/booking/modules/limousine_public_vehicle_media.test.mjs

import test from "node:test";
import assert from "node:assert/strict";

import {
  LIMOUSINE_PUBLIC_GALLERY_MAX,
  attachPublicVehicleMediaFields,
  normalizePublicVehicleGallery,
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
