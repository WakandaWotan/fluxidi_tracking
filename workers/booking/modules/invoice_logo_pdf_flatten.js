// LATE-INVOICE-BILLIT-BRANDING-P0
//
// Field proof (INV-2026-000039): frozen Branding & support logo is a real RGBA
// PNG (664×145) and is stamped on the booking + document registry before PDF
// generation, but PDFShift rasterizes it to an RGB image + DeviceGray soft
// mask whose alpha is entirely zero — so the header logo is invisible.
//
// Flatten every alpha-bearing PNG onto an opaque white background before the
// data URI is handed to the invoice HTML/PDFShift path. The canonical frozen
// embed (with alpha) is left untouched for email CID / future reuse.

const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

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
  if (colorType !== 2 && colorType !== 6) return null;
  const channels = colorType === 6 ? 4 : 3;
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
      rgba[di] = unfiltered[si];
      rgba[di + 1] = unfiltered[si + 1];
      rgba[di + 2] = unfiltered[si + 2];
      rgba[di + 3] = channels === 4 ? unfiltered[si + 3] : 255;
    }
    prev = unfiltered;
  }
  return { width, height, rgba, hadAlpha: colorType === 6 };
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

/**
 * Flatten an invoice logo data URI for PDFShift.
 *
 * - RGBA/gray+alpha PNG → opaque RGB PNG on white
 * - already-opaque PNG / JPEG / other → returned unchanged
 * - unparseable → returned unchanged (fail-open to prior behavior)
 */
export async function flattenInvoiceLogoDataUriForPdf(dataUri) {
  const parsed = _fromDataUri(dataUri);
  if (!parsed) return String(dataUri || "").trim();
  if (!parsed.mime.includes("png")) {
    return String(dataUri || "").trim();
  }
  const decoded = await _decodePngRgbaOrRgb(parsed.bytes);
  if (!decoded) return String(dataUri || "").trim();
  if (!decoded.hadAlpha) return String(dataUri || "").trim();

  const { width, height, rgba } = decoded;
  const rgb = new Uint8Array(width * height * 3);
  for (let i = 0; i < width * height; i += 1) {
    const a = (rgba[i * 4 + 3] & 0xff) / 255;
    const inv = 1 - a;
    // Composite onto white so PDFShift never needs a soft mask.
    rgb[i * 3] = Math.round((rgba[i * 4] & 0xff) * a + 255 * inv);
    rgb[i * 3 + 1] = Math.round((rgba[i * 4 + 1] & 0xff) * a + 255 * inv);
    rgb[i * 3 + 2] = Math.round((rgba[i * 4 + 2] & 0xff) * a + 255 * inv);
  }
  const opaque = await _encodePngRgb(width, height, rgb);
  return `data:image/png;base64,${_toBase64(opaque)}`;
}

/**
 * True when the data URI is an alpha-bearing PNG that PDFShift has proven to
 * rasterize as an invisible soft-masked image.
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
 * XObject (INV-2026-000040: RGB logo ink present, but SMask avg α≈16 →
 * logo invisible in Fluxidi viewers while Billit's own PDF shows it).
 */
export function invoicePdfHasLogoSoftMask(pdfBytes) {
  const bytes =
    pdfBytes instanceof Uint8Array
      ? pdfBytes
      : pdfBytes
        ? new Uint8Array(pdfBytes)
        : null;
  if (!bytes || bytes.length < 32) return false;
  // Dictionaries are ASCII; streams are binary — search the raw buffer as latin1.
  let text = "";
  const limit = Math.min(bytes.length, 2_000_000);
  for (let i = 0; i < limit; i += 1) text += String.fromCharCode(bytes[i]);
  return (
    /\/Subtype\s*\/Image[\s\S]{0,400}\/SMask\s+\d+\s+0\s+R/.test(text) ||
    /\/SMask\s+\d+\s+0\s+R[\s\S]{0,400}\/Subtype\s*\/Image/.test(text)
  );
}

/**
 * Remove `/SMask N 0 R` from image dictionaries so the already-composited RGB
 * logo pixels paint fully opaque. Does not rewrite page content, totals, or
 * text — only drops the broken PDFShift alpha mask.
 */
export function stripInvoicePdfLogoSoftMasks(pdfBytes) {
  const bytes =
    pdfBytes instanceof Uint8Array
      ? pdfBytes
      : pdfBytes
        ? new Uint8Array(pdfBytes)
        : new Uint8Array(0);
  if (!bytes.length) return bytes;
  let text = "";
  for (let i = 0; i < bytes.length; i += 1) {
    text += String.fromCharCode(bytes[i] & 0xff);
  }
  if (!/\/SMask\s+\d+\s+0\s+R/.test(text)) return bytes;
  const cleaned = text.replace(/\/SMask\s+\d+\s+0\s+R/g, "");
  if (cleaned === text) return bytes;
  const out = new Uint8Array(cleaned.length);
  for (let i = 0; i < cleaned.length; i += 1) {
    out[i] = cleaned.charCodeAt(i) & 0xff;
  }
  return out;
}

export const __testInternals = {
  _decodePngRgbaOrRgb,
  _encodePngRgb,
};
