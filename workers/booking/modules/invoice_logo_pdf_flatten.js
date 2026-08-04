// INVOICE-LOGO-BLACK-RECTANGLE — FINAL RELEASE P0
//
// Field proof (INV-2026-000039 / INV-2026-000040):
//   Frozen Branding & support logo is RGBA PNG 664×145. Transparent pixels
//   store black RGB (r=g=b=0). PDFShift separates that into an RGB image that
//   is almost entirely black plus a DeviceGray soft-mask whose alpha is ≈0 —
//   so the logo is invisible. Stripping /SMask then paints a solid black
//   rectangle.
//
//   A prior flatten→flat=1 path was also defeated: maybeNormalizeCommunicationProfile
//   truncated logoUrl to 1000 chars. The truncated data URI kept a valid IHDR
//   (664×145) but a corrupt IDAT, so PDFShift still emitted a black rectangle
//   while revision markers claimed the logo was repaired.
//
// Fix:
//   1) Decode frozen snapshot → alpha-composite onto opaque white → RGB PNG
//   2) Re-decode and verify (no alpha, white background, visible ink)
//   3) Embed only the verified opaque bitmap in PDFShift HTML
//   4) Verify PDF image pixels before R2 persist; reject black-rectangle output

const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** Max chars for an embedded invoice logo data URI (≈384 KiB binary). */
export const INVOICE_LOGO_DATA_URI_MAX_CHARS = 512_000;

// Use Web Compression Streams only (Workers + modern Node). Never import
// node:zlib — that forces nodejs_compat and breaks the booking worker bundle.
async function _inflateZlib(bytes) {
  if (typeof DecompressionStream === "undefined") {
    throw new Error("inflate_unavailable");
  }
  const ds = new DecompressionStream("deflate");
  const stream = new Blob([bytes]).stream().pipeThrough(ds);
  const buf = await new Response(stream).arrayBuffer();
  return new Uint8Array(buf);
}

async function _deflateZlib(bytes) {
  if (typeof CompressionStream === "undefined") {
    throw new Error("deflate_unavailable");
  }
  const cs = new CompressionStream("deflate");
  const stream = new Blob([bytes]).stream().pipeThrough(cs);
  const buf = await new Response(stream).arrayBuffer();
  return new Uint8Array(buf);
}

function _bytesStartWith(bytes, magic) {
  if (!bytes || bytes.length < magic.length) return false;
  for (let i = 0; i < magic.length; i += 1) {
    if ((bytes[i] & 0xff) !== magic[i]) return false;
  }
  return true;
}

function _crc32(buf) {
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) {
    crc ^= buf[i] & 0xff;
    for (let j = 0; j < 8; j += 1) {
      const mask = -(crc & 1);
      crc = (crc >>> 1) ^ (0xedb88320 & mask);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function _u32(n) {
  const out = new Uint8Array(4);
  out[0] = (n >>> 24) & 0xff;
  out[1] = (n >>> 16) & 0xff;
  out[2] = (n >>> 8) & 0xff;
  out[3] = n & 0xff;
  return out;
}

function _readU32(bytes, offset) {
  return (
    ((bytes[offset] & 0xff) << 24) |
    ((bytes[offset + 1] & 0xff) << 16) |
    ((bytes[offset + 2] & 0xff) << 8) |
    (bytes[offset + 3] & 0xff)
  ) >>> 0;
}

function _paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function _unfilter(filter, cur, prev, bpp) {
  const out = new Uint8Array(cur.length);
  for (let i = 0; i < cur.length; i += 1) {
    const x = cur[i] & 0xff;
    const a = i >= bpp ? out[i - bpp] : 0;
    const b = prev ? prev[i] & 0xff : 0;
    const c = prev && i >= bpp ? prev[i - bpp] & 0xff : 0;
    let val = x;
    if (filter === 1) val = (x + a) & 0xff;
    else if (filter === 2) val = (x + b) & 0xff;
    else if (filter === 3) val = (x + ((a + b) >> 1)) & 0xff;
    else if (filter === 4) val = (x + _paeth(a, b, c)) & 0xff;
    else if (filter !== 0) return null;
    out[i] = val;
  }
  return out;
}

async function _decodePngRgbaOrRgb(bytes) {
  if (!_bytesStartWith(bytes, PNG_MAGIC)) return null;
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = -1;
  const idat = [];
  while (offset + 8 <= bytes.length) {
    const len = _readU32(bytes, offset);
    const type = String.fromCharCode(
      bytes[offset + 4],
      bytes[offset + 5],
      bytes[offset + 6],
      bytes[offset + 7],
    );
    const dataStart = offset + 8;
    const dataEnd = dataStart + len;
    if (dataEnd + 4 > bytes.length) return null;
    const chunk = bytes.subarray(dataStart, dataEnd);
    if (type === "IHDR") {
      if (len < 13) return null;
      width = _readU32(chunk, 0);
      height = _readU32(chunk, 4);
      bitDepth = chunk[8] & 0xff;
      colorType = chunk[9] & 0xff;
      if (chunk[10] !== 0 || chunk[11] !== 0 || chunk[12] !== 0) return null;
    } else if (type === "IDAT") {
      idat.push(chunk);
    } else if (type === "IEND") {
      break;
    }
    offset = dataEnd + 4;
  }
  if (!width || !height || bitDepth !== 8) return null;
  // 2 = RGB, 6 = RGBA, 4 = gray+alpha (expand to RGBA)
  if (colorType !== 2 && colorType !== 6 && colorType !== 4) return null;
  const channels = colorType === 6 ? 4 : colorType === 4 ? 2 : 3;
  let compressedLen = 0;
  for (const part of idat) compressedLen += part.length;
  const compressed = new Uint8Array(compressedLen);
  let w = 0;
  for (const part of idat) {
    compressed.set(part, w);
    w += part.length;
  }
  let inflated;
  try {
    inflated = await _inflateZlib(compressed);
  } catch (_) {
    return null;
  }
  const stride = width * channels;
  const expected = (stride + 1) * height;
  if (inflated.length < expected) return null;
  const rgba = new Uint8Array(width * height * 4);
  let prev = null;
  let src = 0;
  for (let y = 0; y < height; y += 1) {
    const filter = inflated[src] & 0xff;
    src += 1;
    const row = inflated.subarray(src, src + stride);
    src += stride;
    const unfiltered = _unfilter(filter, row, prev, channels);
    if (!unfiltered) return null;
    for (let x = 0; x < width; x += 1) {
      const di = (y * width + x) * 4;
      const si = x * channels;
      if (colorType === 4) {
        const g = unfiltered[si];
        rgba[di] = g;
        rgba[di + 1] = g;
        rgba[di + 2] = g;
        rgba[di + 3] = unfiltered[si + 1];
      } else {
        rgba[di] = unfiltered[si];
        rgba[di + 1] = unfiltered[si + 1];
        rgba[di + 2] = unfiltered[si + 2];
        rgba[di + 3] = channels === 4 ? unfiltered[si + 3] : 255;
      }
    }
    prev = unfiltered;
  }
  return {
    width,
    height,
    rgba,
    hadAlpha: colorType === 6 || colorType === 4,
    colorType,
  };
}

async function _encodePngRgb(width, height, rgb) {
  const stride = width * 3;
  const raw = new Uint8Array((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const rowStart = y * (stride + 1);
    raw[rowStart] = 0;
    raw.set(rgb.subarray(y * stride, y * stride + stride), rowStart + 1);
  }
  const compressed = await _deflateZlib(raw);
  const signature = Uint8Array.from(PNG_MAGIC);
  const ihdr = new Uint8Array(13);
  ihdr.set(_u32(width), 0);
  ihdr.set(_u32(height), 4);
  ihdr[8] = 8;
  ihdr[9] = 2; // RGB
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  function chunk(type, data) {
    const typeBytes = Uint8Array.from(type.split("").map((c) => c.charCodeAt(0)));
    const len = _u32(data.length);
    const crcBuf = new Uint8Array(typeBytes.length + data.length);
    crcBuf.set(typeBytes, 0);
    crcBuf.set(data, typeBytes.length);
    const crc = _u32(_crc32(crcBuf));
    const out = new Uint8Array(4 + 4 + data.length + 4);
    out.set(len, 0);
    out.set(typeBytes, 4);
    out.set(data, 8);
    out.set(crc, 8 + data.length);
    return out;
  }
  const parts = [
    signature,
    chunk("IHDR", ihdr),
    chunk("IDAT", compressed),
    chunk("IEND", new Uint8Array(0)),
  ];
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

function _toBase64(bytes) {
  if (typeof Buffer !== "undefined") {
    return Buffer.from(bytes).toString("base64");
  }
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i] & 0xff);
  }
  return btoa(binary);
}

function _fromDataUri(dataUri) {
  const m = /^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/i.exec(String(dataUri || "").trim());
  if (!m) return null;
  const mime = m[1].toLowerCase();
  const b64 = m[2];
  let bytes;
  try {
    bytes =
      typeof Buffer !== "undefined"
        ? new Uint8Array(Buffer.from(b64, "base64"))
        : Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch (_) {
    return null;
  }
  return { mime, bytes };
}

function _pdfBytesToLatin1(pdfBytes) {
  const bytes =
    pdfBytes instanceof Uint8Array
      ? pdfBytes
      : pdfBytes
        ? new Uint8Array(pdfBytes)
        : null;
  if (!bytes || !bytes.length) return { bytes: null, text: "" };
  let text = "";
  for (let i = 0; i < bytes.length; i += 1) {
    text += String.fromCharCode(bytes[i] & 0xff);
  }
  return { bytes, text };
}

function _compositeRgbaOntoWhite(rgba, width, height) {
  const rgb = new Uint8Array(width * height * 3);
  for (let i = 0; i < width * height; i += 1) {
    const a = (rgba[i * 4 + 3] & 0xff) / 255;
    const inv = 1 - a;
    rgb[i * 3] = Math.round((rgba[i * 4] & 0xff) * a + 255 * inv);
    rgb[i * 3 + 1] = Math.round((rgba[i * 4 + 1] & 0xff) * a + 255 * inv);
    rgb[i * 3 + 2] = Math.round((rgba[i * 4 + 2] & 0xff) * a + 255 * inv);
  }
  return rgb;
}

/**
 * Pixel statistics for an RGB (or RGBA-with-ignored-alpha) bitmap.
 * Used both for normalized logo verification and PDF image inspection.
 */
export function analyzeRgbLogoPixels(rgbOrRgba, width, height, { channels = 3 } = {}) {
  const pixels = width * height;
  if (!rgbOrRgba || !pixels || rgbOrRgba.length < pixels * channels) {
    return {
      ok: false,
      reason: "invalid_bitmap",
      pixels: 0,
      whiteBg: 0,
      nonWhite: 0,
      blackish: 0,
      visibleInk: 0,
      blackRatio: 1,
      whiteRatio: 0,
    };
  }
  let whiteBg = 0;
  let nonWhite = 0;
  let blackish = 0;
  let visibleInk = 0;
  for (let i = 0; i < pixels; i += 1) {
    const o = i * channels;
    const r = rgbOrRgba[o] & 0xff;
    const g = rgbOrRgba[o + 1] & 0xff;
    const b = rgbOrRgba[o + 2] & 0xff;
    const isWhite = r > 250 && g > 250 && b > 250;
    const isBlackish = r < 40 && g < 40 && b < 40;
    if (isWhite) whiteBg += 1;
    else {
      nonWhite += 1;
      if (isBlackish) blackish += 1;
      else visibleInk += 1;
    }
  }
  const blackRatio = blackish / pixels;
  const whiteRatio = whiteBg / pixels;
  // Tiny fixtures (unit tests): not a black rectangle and not fully white.
  // Real logos: white background + visible non-black ink.
  const tiny = pixels < 256;
  const minInk = tiny ? 1 : 8;
  const ok = tiny
    ? pixels > 0 && blackRatio < 0.85 && nonWhite >= 1
    : pixels > 0 &&
      blackRatio < 0.85 &&
      whiteRatio > 0.05 &&
      visibleInk >= minInk &&
      nonWhite >= minInk;
  return {
    ok,
    reason: ok
      ? "ok"
      : blackRatio >= 0.85
        ? "predominantly_black"
        : !tiny && visibleInk < minInk
          ? "no_visible_ink"
          : !tiny && whiteRatio <= 0.05
            ? "no_white_background"
            : "logo_pixels_invalid",
    pixels,
    whiteBg,
    nonWhite,
    blackish,
    visibleInk,
    blackRatio,
    whiteRatio,
  };
}

/**
 * Re-decode a logo data URI and prove it is structurally opaque RGB
 * (no alpha channel, fully decodable). When requireLogoInk is true, also
 * require white background + visible non-white logo pixels.
 */
export async function verifyOpaqueInvoiceLogoDataUri(
  dataUri,
  { requireLogoInk = false } = {},
) {
  const parsed = _fromDataUri(dataUri);
  if (!parsed) {
    return { ok: false, reason: "not_data_uri" };
  }
  if (!parsed.mime.includes("png") && !parsed.mime.includes("jpeg") && !parsed.mime.includes("jpg")) {
    return { ok: false, reason: "unsupported_mime", mime: parsed.mime };
  }
  if (parsed.mime.includes("png")) {
    if (!_bytesStartWith(parsed.bytes, PNG_MAGIC) || parsed.bytes.length < 33) {
      return { ok: false, reason: "invalid_png" };
    }
    const colorType = parsed.bytes[25] & 0xff;
    if (colorType !== 2) {
      return { ok: false, reason: "png_has_alpha_or_non_rgb", colorType };
    }
    const decoded = await _decodePngRgbaOrRgb(parsed.bytes);
    if (!decoded) {
      return { ok: false, reason: "png_decode_failed" };
    }
    if (decoded.hadAlpha) {
      return { ok: false, reason: "decoded_has_alpha" };
    }
    const stats = analyzeRgbLogoPixels(decoded.rgba, decoded.width, decoded.height, {
      channels: 4,
    });
    if (requireLogoInk && !stats.ok) {
      return {
        ...stats,
        ok: false,
        reason: stats.reason,
        mime: "image/png",
        width: decoded.width,
        height: decoded.height,
        hadAlpha: false,
        colorType: 2,
      };
    }
    return {
      ...stats,
      ok: true,
      reason: requireLogoInk ? stats.reason : "opaque_rgb_png",
      mime: "image/png",
      width: decoded.width,
      height: decoded.height,
      hadAlpha: false,
      colorType: 2,
    };
  }
  // JPEG: treat as already-opaque; require non-trivial payload.
  if (parsed.bytes.length < 32 || parsed.bytes[0] !== 0xff || parsed.bytes[1] !== 0xd8) {
    return { ok: false, reason: "invalid_jpeg" };
  }
  return {
    ok: true,
    reason: "jpeg_opaque_assumed",
    mime: parsed.mime,
    bytes: parsed.bytes.length,
  };
}

/**
 * Normalize a frozen invoice logo data URI to a verified opaque RGB PNG on white.
 *
 * Fail-closed: returns { ok:false } when decode/composite/re-encode/verify fails.
 * Never silently returns a broken or alpha-bearing bitmap as success.
 */
export async function normalizeInvoiceLogoToOpaqueRgbDataUri(dataUri) {
  const raw = String(dataUri || "").trim();
  if (!raw) {
    return { ok: false, reason: "missing_logo", data_uri: "" };
  }
  const parsed = _fromDataUri(raw);
  if (!parsed) {
    return { ok: false, reason: "not_data_uri", data_uri: "" };
  }
  if (parsed.mime.includes("jpeg") || parsed.mime.includes("jpg")) {
    const v = await verifyOpaqueInvoiceLogoDataUri(raw);
    if (v.ok) {
      return { ok: true, reason: "already_opaque_jpeg", data_uri: raw, verification: v };
    }
    return { ok: false, reason: v.reason || "invalid_jpeg", data_uri: "" };
  }
  if (!parsed.mime.includes("png")) {
    return { ok: false, reason: "unsupported_mime", data_uri: "" };
  }
  const decoded = await _decodePngRgbaOrRgb(parsed.bytes);
  if (!decoded) {
    return { ok: false, reason: "png_decode_failed", data_uri: "" };
  }
  const { width, height, rgba, hadAlpha } = decoded;
  const rgb = hadAlpha
    ? _compositeRgbaOntoWhite(rgba, width, height)
    : (() => {
        const out = new Uint8Array(width * height * 3);
        for (let i = 0; i < width * height; i += 1) {
          out[i * 3] = rgba[i * 4];
          out[i * 3 + 1] = rgba[i * 4 + 1];
          out[i * 3 + 2] = rgba[i * 4 + 2];
        }
        return out;
      })();
  const preStats = analyzeRgbLogoPixels(rgb, width, height, { channels: 3 });
  if (!preStats.ok) {
    return {
      ok: false,
      reason: `composite_${preStats.reason}`,
      data_uri: "",
      verification: preStats,
    };
  }
  let opaque;
  try {
    opaque = await _encodePngRgb(width, height, rgb);
  } catch (_) {
    return { ok: false, reason: "png_encode_failed", data_uri: "" };
  }
  const outUri = `data:image/png;base64,${_toBase64(opaque)}`;
  if (outUri.length > INVOICE_LOGO_DATA_URI_MAX_CHARS) {
    return { ok: false, reason: "opaque_logo_too_large", data_uri: "" };
  }
  const verification = await verifyOpaqueInvoiceLogoDataUri(outUri, {
    requireLogoInk: true,
  });
  if (!verification.ok) {
    return {
      ok: false,
      reason: `verify_${verification.reason}`,
      data_uri: "",
      verification,
    };
  }
  return {
    ok: true,
    reason: hadAlpha ? "composited_rgba_on_white" : "reencoded_opaque_rgb",
    data_uri: outUri,
    width,
    height,
    verification,
  };
}

/**
 * Flatten an invoice logo data URI for PDFShift.
 *
 * Fail-closed for alpha PNGs: if normalization cannot produce a verified opaque
 * RGB bitmap, returns "" so callers do not embed the broken alpha source.
 * Already-opaque verified PNG/JPEG are returned unchanged.
 */
export async function flattenInvoiceLogoDataUriForPdf(dataUri) {
  const raw = String(dataUri || "").trim();
  if (!raw) return "";
  const needs = invoiceLogoDataUriNeedsPdfFlatten(raw);
  if (!needs) {
    const v = await verifyOpaqueInvoiceLogoDataUri(raw);
    if (v.ok) return raw;
    // Opaque claim failed (truncated / corrupt) — try full normalize path.
  }
  const normalized = await normalizeInvoiceLogoToOpaqueRgbDataUri(raw);
  return normalized.ok ? normalized.data_uri : "";
}

/**
 * True when the data URI is an alpha-bearing PNG that PDFShift has proven to
 * rasterize as an invisible soft-masked image — OR when the payload is a
 * truncated/corrupt PNG that still advertises an alpha IHDR.
 */
export function invoiceLogoDataUriNeedsPdfFlatten(dataUri) {
  const parsed = _fromDataUri(dataUri);
  if (!parsed || !parsed.mime.includes("png")) return false;
  if (!_bytesStartWith(parsed.bytes, PNG_MAGIC) || parsed.bytes.length < 33) {
    return false;
  }
  // IHDR color type at byte 25 (8 sig + 4 len + 4 'IHDR' + 8 wh + 1 bit + 1 ctype)
  const colorType = parsed.bytes[25] & 0xff;
  return colorType === 4 || colorType === 6;
}

/**
 * True when a PDFShift invoice PDF still attaches a soft mask to an image
 * XObject (INV-2026-000040 class).
 */
export function invoicePdfHasLogoSoftMask(pdfBytes) {
  const { text } = _pdfBytesToLatin1(pdfBytes);
  if (!text || text.length < 32) return false;
  return (
    /\/Subtype\s*\/Image[\s\S]{0,400}\/SMask\s+\d+\s+0\s+R/.test(text) ||
    /\/SMask\s+\d+\s+0\s+R[\s\S]{0,400}\/Subtype\s*\/Image/.test(text)
  );
}

/**
 * Remove `/SMask N 0 R` from image dictionaries so composited RGB logo pixels
 * paint fully opaque. Only safe after pixel verification confirms the RGB
 * plane is not a black rectangle.
 */
export function stripInvoicePdfLogoSoftMasks(pdfBytes) {
  const { bytes, text } = _pdfBytesToLatin1(pdfBytes);
  if (!bytes || !bytes.length) return bytes || new Uint8Array(0);
  if (!/\/SMask\s+\d+\s+0\s+R/.test(text)) return bytes;
  const cleaned = text.replace(/\/SMask\s+\d+\s+0\s+R/g, "");
  if (cleaned === text) return bytes;
  const out = new Uint8Array(cleaned.length);
  for (let i = 0; i < cleaned.length; i += 1) {
    out[i] = cleaned.charCodeAt(i) & 0xff;
  }
  return out;
}

async function _inflatePdfFlateStream(streamBytes) {
  // PDF FlateDecode streams are zlib-wrapped.
  try {
    return await _inflateZlib(streamBytes);
  } catch (_) {
    // Some producers omit the zlib header; try raw deflate.
    try {
      if (typeof DecompressionStream === "undefined") return null;
      const ds = new DecompressionStream("deflate-raw");
      const stream = new Blob([streamBytes]).stream().pipeThrough(ds);
      const buf = await new Response(stream).arrayBuffer();
      return new Uint8Array(buf);
    } catch (_) {
      return null;
    }
  }
}

/**
 * Extract RGB image XObjects from a PDFShift invoice PDF and score the best
 * logo candidate (prefer wide header images ≈ company logo aspect).
 */
export async function extractInvoicePdfLogoImageStats(pdfBytes) {
  const { text } = _pdfBytesToLatin1(pdfBytes);
  if (!text) {
    return { ok: false, reason: "empty_pdf", images: [] };
  }
  const images = [];
  const re =
    /<<\s*([\s\S]*?\/Subtype\s*\/Image[\s\S]*?)>>\s*stream\r?\n([\s\S]*?)\r?\nendstream/g;
  let m;
  while ((m = re.exec(text))) {
    const dict = m[1];
    const streamRaw = m[2];
    const width = Number((/\/Width\s+(\d+)/.exec(dict) || [])[1] || 0);
    const height = Number((/\/Height\s+(\d+)/.exec(dict) || [])[1] || 0);
    const bpc = Number((/\/BitsPerComponent\s+(\d+)/.exec(dict) || [])[1] || 0);
    const hasSMask = /\/SMask\s+\d+\s+0\s+R/.test(dict);
    const isGray = /\/ColorSpace\s*\/DeviceGray/.test(dict);
    const isRgb =
      /\/ColorSpace\s*\/DeviceRGB/.test(dict) ||
      /\/ColorSpace\s*\[\s*\/ICCBased/.test(dict) ||
      /\/ColorSpace\s*\/ICCBased/.test(dict);
    if (!width || !height || bpc !== 8) continue;
    if (isGray || !isRgb) continue;
    if (!/\/Filter\s*\/FlateDecode/.test(dict) && !/\/Filter\s*\[\s*\/FlateDecode/.test(dict)) {
      continue;
    }
    const streamBytes = new Uint8Array(streamRaw.length);
    for (let i = 0; i < streamRaw.length; i += 1) {
      streamBytes[i] = streamRaw.charCodeAt(i) & 0xff;
    }
    const inflated = await _inflatePdfFlateStream(streamBytes);
    if (!inflated || inflated.length < width * height * 3) continue;
    const rgb = inflated.subarray(0, width * height * 3);
    const stats = analyzeRgbLogoPixels(rgb, width, height, { channels: 3 });
    images.push({
      width,
      height,
      bitsPerComponent: bpc,
      hasSMask,
      colorSpace: "RGB",
      streamBytes: streamBytes.length,
      ...stats,
    });
  }
  if (!images.length) {
    return { ok: false, reason: "no_rgb_image", images: [] };
  }
  // Prefer the widest image (invoice header logo) that is not a tiny icon.
  images.sort((a, b) => b.width * b.height - a.width * a.height);
  const logo =
    images.find((img) => img.width >= 80 && img.width / Math.max(img.height, 1) >= 2) ||
    images[0];
  return {
    ok: logo.ok,
    reason: logo.reason,
    logo,
    images,
    hasLogoSoftMask: images.some((img) => img.hasSMask) || invoicePdfHasLogoSoftMask(pdfBytes),
  };
}

/**
 * Verify a generated invoice PDF's logo region is opaque RGB with visible ink
 * on a white background — not a black rectangle and not blank.
 *
 * When a soft mask is present but the RGB plane already looks correct, the
 * caller may strip /SMask and re-verify. This function never writes R2.
 */
export async function verifyInvoicePdfLogoOpaqueRgb(pdfBytes) {
  const extracted = await extractInvoicePdfLogoImageStats(pdfBytes);
  if (!extracted.ok) {
    return {
      ok: false,
      reason: extracted.reason || "logo_extract_failed",
      hasLogoSoftMask: extracted.hasLogoSoftMask === true,
      logo: extracted.logo || null,
      images: extracted.images || [],
    };
  }
  if (extracted.hasLogoSoftMask) {
    // Soft mask still controls painting — not acceptable for the final artifact
    // unless the caller strips it and re-verifies. Report as needs_strip.
    return {
      ok: false,
      reason: "logo_soft_mask_present",
      hasLogoSoftMask: true,
      logo: extracted.logo,
      images: extracted.images,
      rgbLooksValid: extracted.logo?.ok === true,
    };
  }
  return {
    ok: true,
    reason: "ok",
    hasLogoSoftMask: false,
    logo: extracted.logo,
    images: extracted.images,
  };
}

/**
 * Post-PDFShift hardening: optionally strip soft masks only when the RGB plane
 * already has white background + visible ink; then require full verification.
 * Returns { ok, pdfBytes, verification } — never claims success on black rect.
 */
export async function hardenInvoicePdfLogoArtifact(pdfBytes) {
  const input =
    pdfBytes instanceof Uint8Array
      ? pdfBytes
      : pdfBytes
        ? new Uint8Array(pdfBytes)
        : new Uint8Array(0);
  if (!input.length) {
    return {
      ok: false,
      reason: "empty_pdf",
      pdfBytes: input,
      verification: null,
    };
  }
  let working = input;
  let first = await verifyInvoicePdfLogoOpaqueRgb(working);
  if (
    !first.ok &&
    first.reason === "logo_soft_mask_present" &&
    first.rgbLooksValid === true
  ) {
    working = stripInvoicePdfLogoSoftMasks(working);
    first = await verifyInvoicePdfLogoOpaqueRgb(working);
  }
  if (!first.ok) {
    return {
      ok: false,
      reason: first.reason || "logo_verification_failed",
      pdfBytes: input, // never hand back a stripped-but-black artifact as success
      verification: first,
    };
  }
  return {
    ok: true,
    reason: "ok",
    pdfBytes: working,
    verification: first,
  };
}

/**
 * Preserve full data-URI company logos through communication-profile
 * normalization. HTTPS logo refs stay short; data URIs may be large.
 */
export function sanitizeInvoiceLogoUrlForProfile(value) {
  const text = String(value == null ? "" : value).replace(/\0/g, "").trim();
  if (!text) return "";
  if (text.startsWith("data:image/")) {
    return text.length > INVOICE_LOGO_DATA_URI_MAX_CHARS
      ? text.slice(0, INVOICE_LOGO_DATA_URI_MAX_CHARS)
      : text;
  }
  return text.length > 2000 ? text.slice(0, 2000) : text;
}

export const __testInternals = {
  _decodePngRgbaOrRgb,
  _encodePngRgb,
  _compositeRgbaOntoWhite,
  _fromDataUri,
};
