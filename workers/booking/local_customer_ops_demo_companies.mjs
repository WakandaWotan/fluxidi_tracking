import { deflateSync } from "node:zlib";

export const LOCAL_DEMO_COMPANIES = [
  {
    id: "demo_company_p0",
    token: "cst_local_demo_synthetic",
    code: "FLX-DEMO1",
    name: "Fluxidi Demo Cars",
    logo: { r: 18, g: 28, b: 48, barR: 212, barG: 175, barB: 55 },
  },
  {
    id: "demo_company_p1",
    token: "cst_local_demo_nocturne",
    code: "NTC-LIMO1",
    name: "Nocturne Limousines",
    logo: { r: 72, g: 16, b: 28, barR: 246, barG: 239, barB: 228 },
  },
];

function crc32(buf) {
  let c = ~0;
  for (const byte of buf) {
    c ^= byte;
    for (let i = 0; i < 8; i += 1) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function pngChunk(type, data) {
  const typeBuf = Buffer.from(type);
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const crcInput = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(crcInput));
  return Buffer.concat([len, typeBuf, data, crc]);
}

export function solidLogoPng({ r, g, b, barR, barG, barB }) {
  const w = 64;
  const h = 64;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y += 1) {
    const row = y * (w * 3 + 1);
    raw[row] = 0;
    const bar = y >= 48 && y <= 56;
    for (let x = 0; x < w; x += 1) {
      const i = row + 1 + x * 3;
      raw[i] = bar ? barR : r;
      raw[i + 1] = bar ? barG : g;
      raw[i + 2] = bar ? barB : b;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}
