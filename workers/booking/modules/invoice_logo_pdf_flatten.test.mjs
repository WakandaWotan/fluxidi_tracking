import { test } from "node:test";
import assert from "node:assert/strict";
import {
  flattenInvoiceLogoDataUriForPdf,
  invoiceLogoDataUriNeedsPdfFlatten,
  __testInternals,
} from "./invoice_logo_pdf_flatten.js";

// Classic 1×1 RGBA PNG (colorType 6) — same family as INV-2026-000039 logo.
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

test("LATE-INVOICE P0) flatten RGBA → opaque RGB PNG (no alpha)", async () => {
  const out = await flattenInvoiceLogoDataUriForPdf(RGBA_1X1_URI);
  assert.match(out, /^data:image\/png;base64,/);
  assert.notEqual(out, RGBA_1X1_URI);
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(out), false);

  const b64 = out.slice("data:image/png;base64,".length);
  const bytes = Uint8Array.from(Buffer.from(b64, "base64"));
  // IHDR color type at byte 25 must be 2 (RGB, no alpha).
  assert.equal(bytes[25], 2);

  const decoded = await __testInternals._decodePngRgbaOrRgb(bytes);
  assert.ok(decoded);
  assert.equal(decoded.hadAlpha, false);
  assert.equal(decoded.width, 1);
  assert.equal(decoded.height, 1);
  // Flatten must yield a fully opaque pixel (no soft-mask alpha channel).
  assert.equal(decoded.rgba[3], 255);
});

test("LATE-INVOICE P0) already-opaque PNG is returned unchanged", async () => {
  // Encode a tiny opaque RGB PNG via the helper, then re-flatten.
  const rgb = new Uint8Array([10, 20, 30]);
  const opaqueBytes = await __testInternals._encodePngRgb(1, 1, rgb);
  const opaqueUri = `data:image/png;base64,${Buffer.from(opaqueBytes).toString("base64")}`;
  assert.equal(invoiceLogoDataUriNeedsPdfFlatten(opaqueUri), false);
  const out = await flattenInvoiceLogoDataUriForPdf(opaqueUri);
  assert.equal(out, opaqueUri);
});

test("LATE-INVOICE P0) semi-transparent red composites onto white", async () => {
  const zlib = await import("node:zlib");
  // Raw IDAT: filter 0 + RGBA(255,0,0,128)
  const raw = Uint8Array.from([0, 255, 0, 0, 128]);
  const compressed = zlib.deflateSync(raw);
  function chunk(type, data) {
    const typeBytes = Buffer.from(type, "ascii");
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const crcBuf = Buffer.concat([typeBytes, data]);
    // PNG CRC32
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
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8;
  ihdr[9] = 6; // RGBA
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", compressed),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  const uri = `data:image/png;base64,${png.toString("base64")}`;
  const out = await flattenInvoiceLogoDataUriForPdf(uri);
  const outBytes = Buffer.from(out.slice("data:image/png;base64,".length), "base64");
  const decoded = await __testInternals._decodePngRgbaOrRgb(outBytes);
  assert.ok(decoded);
  assert.equal(decoded.hadAlpha, false);
  assert.equal(decoded.rgba[0], 255);
  assert.equal(decoded.rgba[1], 127);
  assert.equal(decoded.rgba[2], 127);
});
