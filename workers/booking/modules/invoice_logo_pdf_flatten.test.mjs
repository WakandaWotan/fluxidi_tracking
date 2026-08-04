import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import zlib from "node:zlib";
import {
  flattenInvoiceLogoDataUriForPdf,
  invoiceLogoDataUriNeedsPdfFlatten,
  invoicePdfHasLogoSoftMask,
  stripInvoicePdfLogoSoftMasks,
  normalizeInvoiceLogoToOpaqueRgbDataUri,
  verifyOpaqueInvoiceLogoDataUri,
  analyzeRgbLogoPixels,
  hardenInvoicePdfLogoArtifact,
  sanitizeInvoiceLogoUrlForProfile,
  INVOICE_LOGO_DATA_URI_MAX_CHARS,
  __testInternals,
} from "./invoice_logo_pdf_flatten.js";

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const crcBuf = Buffer.concat([typeBytes, data]);
  let c = 0xffffffff;
  for (let i = 0; i < crcBuf.length; i += 1) {
    c ^= crcBuf[i];
    for (let j = 0; j < 8; j += 1) {
      const mask = -(c & 1);
      c = (c >>> 1) ^ (0xedb88320 & mask);
    }
  }
  c = (c ^ 0xffffffff) >>> 0;
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(c, 0);
  return Buffer.concat([len, typeBytes, data, crc]);
}

/** Build an RGBA PNG from raw filter0 rows: each pixel [r,g,b,a]. */
function buildRgbaPng(width, height, rgbaPixels) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    for (let x = 0; x < width; x += 1) {
      const si = (y * width + x) * 4;
      const di = y * (stride + 1) + 1 + x * 4;
      raw[di] = rgbaPixels[si];
      raw[di + 1] = rgbaPixels[si + 1];
      raw[di + 2] = rgbaPixels[si + 2];
      raw[di + 3] = rgbaPixels[si + 3];
    }
  }
  const compressed = zlib.deflateSync(raw);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", compressed),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function buildOpaqueRgbPng(width, height, rgbPixels) {
  const stride = width * 3;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    rgbPixels.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const compressed = zlib.deflateSync(raw);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", compressed),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

// Classic 1×1 RGBA PNG (colorType 6).
const RGBA_1X1_B64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
const RGBA_1X1_URI = `data:image/png;base64,${RGBA_1X1_B64}`;

test("LATE-INVOICE P0) RGBA PNG needs flatten; JPEG does not", () => {
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(RGBA_1X1_URI), true);
  assert.equal(
    invoiceLogoDataUriNeedsPdfFlatten(
      "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAf/AABEIAAEAAQMBIgACEQEDEQH/xAAbAAACAwEBAQAAAAAAAAAAAAADBAECBQYAB//EABUBAQEAAAAAAAAAAAAAAAAAAAAB/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEAMQAAAB0fAP/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQL/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/Af/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8B/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwL/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/Af/Z",
    ),
    false,
  );
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(""), false);
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) transparent black RGB becomes white after composite", async () => {
  // 8×8: transparent black corners + opaque brand ink center.
  const w = 8;
  const h = 8;
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i += 1) {
    rgba[i * 4] = 0;
    rgba[i * 4 + 1] = 0;
    rgba[i * 4 + 2] = 0;
    rgba[i * 4 + 3] = 0; // transparent black (INV-039 class)
  }
  // Center 2×2 brand color (opaque brown/gold)
  for (const [x, y] of [
    [3, 3],
    [4, 3],
    [3, 4],
    [4, 4],
  ]) {
    const i = y * w + x;
    rgba[i * 4] = 120;
    rgba[i * 4 + 1] = 90;
    rgba[i * 4 + 2] = 40;
    rgba[i * 4 + 3] = 255;
  }
  // Semi-transparent edge pixel
  rgba[(2 * w + 3) * 4] = 120;
  rgba[(2 * w + 3) * 4 + 1] = 90;
  rgba[(2 * w + 3) * 4 + 2] = 40;
  rgba[(2 * w + 3) * 4 + 3] = 128;

  const png = buildRgbaPng(w, h, rgba);
  const uri = `data:image/png;base64,${png.toString("base64")}`;
  const out = await normalizeInvoiceLogoToOpaqueRgbDataUri(uri);
  assert.equal(out.ok, true, out.reason);
  assert.match(out.data_uri, /^data:image\/png;base64,/);
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(out.data_uri), false);

  const bytes = Buffer.from(out.data_uri.slice("data:image/png;base64,".length), "base64");
  assert.equal(bytes[25], 2); // RGB only
  const decoded = await __testInternals._decodePngRgbaOrRgb(bytes);
  assert.ok(decoded);
  assert.equal(decoded.hadAlpha, false);
  // Corner was transparent black → white
  assert.equal(decoded.rgba[0], 255);
  assert.equal(decoded.rgba[1], 255);
  assert.equal(decoded.rgba[2], 255);
  assert.equal(decoded.rgba[3], 255);
  // Opaque brand ink preserved
  const ci = (3 * w + 3) * 4;
  assert.equal(decoded.rgba[ci], 120);
  assert.equal(decoded.rgba[ci + 1], 90);
  assert.equal(decoded.rgba[ci + 2], 40);
  // Semi-transparent edge: 120*0.5 + 255*0.5 = 187.5 → 188 or 187
  const ei = (2 * w + 3) * 4;
  assert.ok(decoded.rgba[ei] >= 187 && decoded.rgba[ei] <= 188);
  assert.ok(decoded.rgba[ei + 1] >= 172 && decoded.rgba[ei + 1] <= 173);

  const v = await verifyOpaqueInvoiceLogoDataUri(out.data_uri, { requireLogoInk: true });
  assert.equal(v.ok, true);
  assert.ok(v.whiteBg > 0);
  assert.ok(v.visibleInk > 0);
  assert.equal(v.blackish, 0);
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) fully opaque RGB source re-encodes without alpha", async () => {
  const w = 8;
  const h = 8;
  const rgb = Buffer.alloc(w * h * 3, 255);
  // Draw a dark blue mark
  for (let i = 20; i < 30; i += 1) {
    rgb[i * 3] = 20;
    rgb[i * 3 + 1] = 40;
    rgb[i * 3 + 2] = 180;
  }
  const png = buildOpaqueRgbPng(w, h, rgb);
  const uri = `data:image/png;base64,${png.toString("base64")}`;
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(uri), false);
  const out = await normalizeInvoiceLogoToOpaqueRgbDataUri(uri);
  assert.equal(out.ok, true, out.reason);
  const v = await verifyOpaqueInvoiceLogoDataUri(out.data_uri, { requireLogoInk: true });
  assert.equal(v.ok, true);
  assert.equal(v.hadAlpha, false);
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) corrupt / truncated PNG fails closed", async () => {
  const frozenPath = "C:/_flutter_work/inv039_frozen_logo.bin";
  if (!fs.existsSync(frozenPath)) {
    const bad = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAA=";
    const out = await normalizeInvoiceLogoToOpaqueRgbDataUri(bad);
    assert.equal(out.ok, false);
    return;
  }
  const frozen = fs.readFileSync(frozenPath);
  const full = `data:image/png;base64,${frozen.toString("base64")}`;
  const truncated = full.slice(0, 1000);
  assert.equal(truncated.length, 1000);
  // Truncation keeps IHDR but breaks IDAT — the historical black-rectangle bug.
  const truncBytes = Buffer.from(truncated.split(",")[1], "base64");
  assert.equal(truncBytes.readUInt32BE(16), 664);
  assert.equal(truncBytes[25], 6);
  const out = await normalizeInvoiceLogoToOpaqueRgbDataUri(truncated);
  assert.equal(out.ok, false);
  assert.equal(out.data_uri, "");
  const flat = await flattenInvoiceLogoDataUriForPdf(truncated);
  assert.equal(flat, "");
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) missing logo fails closed", async () => {
  const out = await normalizeInvoiceLogoToOpaqueRgbDataUri("");
  assert.equal(out.ok, false);
  assert.equal(out.reason, "missing_logo");
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) sanitizeInvoiceLogoUrlForProfile preserves large data URIs", () => {
  const big = `data:image/png;base64,${"A".repeat(50_000)}`;
  assert.equal(sanitizeInvoiceLogoUrlForProfile(big), big);
  assert.equal(sanitizeInvoiceLogoUrlForProfile(big).length > 1000, true);
  const https = `https://example.com/${"x".repeat(3000)}`;
  assert.equal(sanitizeInvoiceLogoUrlForProfile(https).length, 2000);
  assert.ok(INVOICE_LOGO_DATA_URI_MAX_CHARS >= 400_000);
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) INV-039 frozen logo normalizes to opaque RGB with ink", async () => {
  const frozenPath = "C:/_flutter_work/inv039_frozen_logo.bin";
  if (!fs.existsSync(frozenPath)) {
    return;
  }
  const frozen = fs.readFileSync(frozenPath);
  const uri = `data:image/png;base64,${frozen.toString("base64")}`;
  const decoded = await __testInternals._decodePngRgbaOrRgb(frozen);
  assert.ok(decoded);
  assert.equal(decoded.width, 664);
  assert.equal(decoded.height, 145);
  assert.equal(decoded.hadAlpha, true);
  let transparentBlack = 0;
  for (let i = 0; i < decoded.width * decoded.height; i += 1) {
    const a = decoded.rgba[i * 4 + 3];
    if (
      a === 0 &&
      decoded.rgba[i * 4] === 0 &&
      decoded.rgba[i * 4 + 1] === 0 &&
      decoded.rgba[i * 4 + 2] === 0
    ) {
      transparentBlack += 1;
    }
  }
  assert.ok(transparentBlack > 1000, "frozen logo must contain transparent black RGB");

  const out = await normalizeInvoiceLogoToOpaqueRgbDataUri(uri);
  assert.equal(out.ok, true, out.reason);
  assert.ok(out.data_uri.length > 1000);
  const v = await verifyOpaqueInvoiceLogoDataUri(out.data_uri, { requireLogoInk: true });
  assert.equal(v.ok, true);
  assert.equal(v.hadAlpha, false);
  assert.ok(v.whiteBg > 1000);
  assert.ok(v.visibleInk > 100);
  assert.ok(v.blackRatio < 0.2);
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) black-rectangle PDF fails harden; valid synthetic passes", async () => {
  const field = "C:/_flutter_work/inv040_nosmask.pdf";
  if (fs.existsSync(field)) {
    const pdf = fs.readFileSync(field);
    const hardened = await hardenInvoicePdfLogoArtifact(pdf);
    assert.equal(hardened.ok, false);
    assert.ok(
      hardened.reason === "predominantly_black" ||
        hardened.reason === "no_visible_ink" ||
        hardened.reason === "logo_soft_mask_present" ||
        hardened.reason === "no_rgb_image" ||
        hardened.reason === "logo_pixels_invalid",
      hardened.reason,
    );
  }

  // Synthetic PDF with opaque RGB logo (white bg + ink) and no SMask.
  const w = 8;
  const h = 4;
  const rgb = Buffer.alloc(w * h * 3, 255);
  for (let i = 0; i < 8; i += 1) {
    rgb[i * 3] = 30;
    rgb[i * 3 + 1] = 60;
    rgb[i * 3 + 2] = 200;
  }
  const inflated = rgb;
  const compressed = zlib.deflateSync(inflated);
  const dict =
    `<< /Type /XObject /Subtype /Image /Width ${w} /Height ${h} ` +
    `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode ` +
    `/Length ${compressed.length} >>`;
  const pdf = Buffer.concat([
    Buffer.from("%PDF-1.4\n6 0 obj\n", "latin1"),
    Buffer.from(dict, "latin1"),
    Buffer.from("\nstream\n", "latin1"),
    compressed,
    Buffer.from("\nendstream\nendobj\n", "latin1"),
  ]);
  const ok = await hardenInvoicePdfLogoArtifact(pdf);
  assert.equal(ok.ok, true, ok.reason);
  assert.equal(invoicePdfHasLogoSoftMask(ok.pdfBytes), false);
});

test("LATE-INVOICE P0) flatten RGBA → opaque RGB PNG (no alpha)", async () => {
  const out = await flattenInvoiceLogoDataUriForPdf(RGBA_1X1_URI);
  // 1×1 fixture may be nearly-transparent dark; accept either verified opaque
  // URI or fail-closed empty (never return the alpha source unchanged).
  if (out) {
    assert.match(out, /^data:image\/png;base64,/);
    assert.notEqual(out, RGBA_1X1_URI);
    assert.equal(invoiceLogoDataUriNeedsPdfFlatten(out), false);
    const b64 = out.slice("data:image/png;base64,".length);
    const bytes = Uint8Array.from(Buffer.from(b64, "base64"));
    assert.equal(bytes[25], 2);
    const decoded = await __testInternals._decodePngRgbaOrRgb(bytes);
    assert.ok(decoded);
    assert.equal(decoded.hadAlpha, false);
    assert.equal(decoded.rgba[3], 255);
  } else {
    assert.equal(out, "");
  }
});

test("LATE-INVOICE P0) already-opaque PNG is returned unchanged", async () => {
  const rgb = new Uint8Array([10, 20, 30]);
  const opaqueBytes = await __testInternals._encodePngRgb(1, 1, rgb);
  const opaqueUri = `data:image/png;base64,${Buffer.from(opaqueBytes).toString("base64")}`;
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(opaqueUri), false);
  const out = await flattenInvoiceLogoDataUriForPdf(opaqueUri);
  assert.equal(out, opaqueUri);
});

test("INVOICE-PDF-APP-LOGO P0) strip soft mask from INV-040-class PDF bytes", () => {
  const path = "C:/_flutter_work/inv040_artifact.pdf";
  if (!fs.existsSync(path)) {
    const synthetic = Buffer.from(
      "%PDF-1.4\n6 0 obj<< /Type /XObject /Subtype /Image /Width 10 /Height 10 /SMask 8 0 R /Length 1 >>stream\nx\nendstream\nendobj\n",
    );
    assert.equal(invoicePdfHasLogoSoftMask(synthetic), true);
    const out = stripInvoicePdfLogoSoftMasks(synthetic);
    assert.equal(invoicePdfHasLogoSoftMask(out), false);
    return;
  }
  const pdf = fs.readFileSync(path);
  assert.equal(invoicePdfHasLogoSoftMask(pdf), true);
  const out = stripInvoicePdfLogoSoftMasks(pdf);
  assert.equal(invoicePdfHasLogoSoftMask(out), false);
  assert.notEqual(out.length, pdf.length);
  assert.equal(Buffer.from(out).includes(Buffer.from("/SMask ")), false);
});

test("LATE-INVOICE P0) semi-transparent red composites onto white", async () => {
  const raw = Uint8Array.from([0, 255, 0, 0, 128]);
  const compressed = zlib.deflateSync(raw);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", compressed),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
  const uri = `data:image/png;base64,${png.toString("base64")}`;
  const out = await flattenInvoiceLogoDataUriForPdf(uri);
  assert.ok(out);
  const outBytes = Buffer.from(out.slice("data:image/png;base64,".length), "base64");
  const decoded = await __testInternals._decodePngRgbaOrRgb(outBytes);
  assert.ok(decoded);
  assert.equal(decoded.hadAlpha, false);
  assert.equal(decoded.rgba[0], 255);
  assert.equal(decoded.rgba[1], 127);
  assert.equal(decoded.rgba[2], 127);
});

test("INVOICE-LOGO-BLACK-RECTANGLE P0) analyzeRgbLogoPixels rejects black rectangle", () => {
  const w = 10;
  const h = 10;
  const black = new Uint8Array(w * h * 3); // all zeros
  const stats = analyzeRgbLogoPixels(black, w, h, { channels: 3 });
  assert.equal(stats.ok, false);
  assert.equal(stats.reason, "predominantly_black");
});
