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

export function demoDriverLoginCode(company) {
  return company.id === "demo_company_p0" ? "DRVP001" : "DRVP002";
}

export function demoVehicle(company) {
  const fluxidi = company.id === "demo_company_p0";
  return {
    vehicle_id: `vh_${company.id}_1`,
    vehicleId: `vh_${company.id}_1`,
    vehicle_name: fluxidi ? "S-Klasse" : "Ghost",
    vehicleName: fluxidi ? "S-Klasse" : "Ghost",
    brand_model: fluxidi ? "Mercedes S500" : "Rolls-Royce Ghost",
    brandModel: fluxidi ? "Mercedes S500" : "Rolls-Royce Ghost",
    license_plate: fluxidi ? "1-FLX-001" : "1-NTC-001",
    licensePlate: fluxidi ? "1-FLX-001" : "1-NTC-001",
    is_active: true,
    isActive: true,
    passenger_capacity: 3,
    passengerCapacity: 3,
    tenant_id: company.id,
    company_id: company.id,
    tenantId: company.id,
    companyId: company.id,
  };
}

export function companyLinkSeedRecord(company) {
  return {
    tenant_id: company.id,
    company_id: company.id,
    company_code: company.code,
    display_name: company.name,
    country: "BE",
    linking_enabled: true,
    source: "local_customer_ops_demo",
  };
}

export function demoDriver(company) {
  const fluxidi = company.id === "demo_company_p0";
  const driverId = `drv_${company.id}_1`;
  const login = demoDriverLoginCode(company);
  return {
    driver_id: driverId,
    display_name: fluxidi ? "Karel Peeters" : "Lina Moreau",
    displayName: fluxidi ? "Karel Peeters" : "Lina Moreau",
    phone: fluxidi ? "+32470000011" : "+32470000022",
    is_active: true,
    isActive: true,
    availability_status: "available",
    availabilityStatus: "available",
    employee_number: login,
    employeeNumber: login,
    driver_code: login,
    driverCode: login,
    login_code: login,
    loginCode: login,
    agenda_color: fluxidi ? "#C9A227" : "#8C2F39",
    driver_photo_url: `/local/media/${company.id}/logo.png`,
  };
}

const EXTRA_P0_DRIVERS = [
  ["drv_demo_company_p0_2", "Amira Benali", "+32470000012", "offline", "#2F6B4F"],
  ["drv_demo_company_p0_3", "Tom Janssen", "+32470000013", "busy", "#3D5A80"],
  ["drv_demo_company_p0_4", "Lina Vermeulen", "+32470000014", "available", "#8C2F39"],
  ["drv_demo_company_p0_5", "Noah Claessens", "+32470000015", "available", "#6B4F2F"],
  ["drv_demo_company_p0_6", "Eva De Smet", "+32470000016", "paused", "#4A4A4A"],
  ["drv_demo_company_p0_7", "Samir Haddad", "+32470000017", "available", "#1F6F8B"],
  ["drv_demo_company_p0_8", "Elise Wouters", "+32470000018", "available", "#6B3FA0"],
  ["drv_demo_company_p0_9", "Ruben Maes", "+32470000019", "busy", "#C45C26"],
  ["drv_demo_company_p0_10", "Nadia El Amrani", "+32470000020", "available", "#2E7D6F"],
  ["drv_demo_company_p0_11", "Pieter Goossens", "+32470000021", "offline", "#7A3B6C"],
  ["drv_demo_company_p0_12", "Sofia Rossi", "+32470000022", "available", "#3F6B2F"],
  ["drv_demo_company_p0_13", "Daan Coppens", "+32470000023", "available", "#8B4A1B"],
  ["drv_demo_company_p0_14", "Leila Ait", "+32470000024", "available", "#2F4A6B"],
  ["drv_demo_company_p0_15", "Jonas Verbeke", "+32470000025", "paused", "#A13D5C"],
  ["drv_demo_company_p0_16", "Marta Nowak", "+32470000026", "available", "#4A6B3F"],
  ["drv_demo_company_p0_17", "Youssef Benali", "+32470000027", "available", "#5C4A8B"],
  ["drv_demo_company_p0_18", "Hanne Jacobs", "+32470000028", "available", "#8B5A2B"],
  ["drv_demo_company_p0_19", "Olivier Dupont", "+32470000029", "available", "#2F6B6B"],
  ["drv_demo_company_p0_20", "Amina Kaya", "+32470000030", "available", "#C9A227"],
];

export function extraDemoDrivers(company) {
  if (company.id !== "demo_company_p0") return [];
  return EXTRA_P0_DRIVERS.map(([id, name, phone, status, color]) => {
    const row = {
      driver_id: id,
      display_name: name,
      displayName: name,
      phone,
      is_active: true,
      isActive: true,
      availability_status: status,
      availabilityStatus: status,
      agenda_color: color,
    };
    if (id === "drv_demo_company_p0_2") {
      row.driver_photo_url = "/local/media/demo_company_p0/logo.png";
    }
    return row;
  });
}

export function mergeDemoDriverRecord(existing, seed) {
  const current = existing && typeof existing === "object" ? existing : {};
  const next = { ...current, ...seed };
  const kept = String(current.agenda_color || current.agendaColor || "").trim();
  if (kept) {
    next.agenda_color = kept;
    next.agendaColor = kept;
  }
  return next;
}

export function extraDemoVehicles(company) {
  if (company.id !== "demo_company_p0") return [];
  return [
    {
      vehicle_id: "vh_demo_company_p0_2",
      vehicleId: "vh_demo_company_p0_2",
      vehicle_name: "V-Klasse",
      vehicleName: "V-Klasse",
      brand_model: "Mercedes V250",
      brandModel: "Mercedes V250",
      license_plate: "1-FLX-002",
      licensePlate: "1-FLX-002",
      is_active: true,
      isActive: true,
      passenger_capacity: 7,
      passengerCapacity: 7,
      tenant_id: company.id,
      company_id: company.id,
    },
  ];
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
