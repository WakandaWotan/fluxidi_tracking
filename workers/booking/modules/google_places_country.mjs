/**
 * Stay22 Europe P1B — Google Places country identity for hotel discovery.
 *
 * Explicit ISO wins. Localized labels map through this table. ISO is never
 * derived by slicing the first two letters of a country name.
 */

function normalizeCountryLabel(raw) {
  return String(raw ?? "")
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function normalizeIsoCandidate(raw) {
  const letters = String(raw ?? "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z]/g, "");
  if (letters.length !== 2) return "";
  return letters;
}

const COUNTRIES = [
  ["AL", "Albania", ["Albanië", "Albanie", "Albania"]],
  ["AD", "Andorra", ["Andorra", "Andorre"]],
  ["AT", "Austria", ["Oostenrijk", "Autriche", "Austria"]],
  ["BA", "Bosnia and Herzegovina", [
    "Bosnië en Herzegovina",
    "Bosnie-Herzégovine",
    "Bosnia y Herzegovina",
    "Bosnia",
  ]],
  ["BE", "Belgium", ["België", "Belgique", "Bélgica", "Belgie"]],
  ["BG", "Bulgaria", ["Bulgarije", "Bulgarie", "Bulgaria"]],
  ["CH", "Switzerland", ["Zwitserland", "Suisse", "Suiza"]],
  ["CY", "Cyprus", ["Cyprus", "Chypre", "Chipre"]],
  ["CZ", "Czechia", ["Tsjechië", "Tchéquie", "Chequia", "Czech Republic"]],
  ["DE", "Germany", ["Duitsland", "Allemagne", "Alemania"]],
  ["DK", "Denmark", ["Denemarken", "Danemark", "Dinamarca"]],
  ["EE", "Estonia", ["Estland", "Estonie", "Estonia"]],
  ["ES", "Spain", ["Spanje", "Espagne", "España", "Espana"]],
  ["FI", "Finland", ["Finland", "Finlande", "Finlandia"]],
  ["FR", "France", ["Frankrijk", "France", "Francia"]],
  ["GB", "United Kingdom", [
    "Verenigd Koninkrijk",
    "Royaume-Uni",
    "Reino Unido",
    "UK",
    "Great Britain",
    "Britain",
  ]],
  ["GR", "Greece", ["Griekenland", "Grèce", "Grecia"]],
  ["HR", "Croatia", ["Kroatië", "Croatie", "Croacia"]],
  ["HU", "Hungary", ["Hongarije", "Hongrie", "Hungría", "Hungria"]],
  ["IE", "Ireland", ["Ierland", "Irlande", "Irlanda"]],
  ["IS", "Iceland", ["IJsland", "Islande", "Islandia"]],
  ["IT", "Italy", ["Italië", "Italie", "Italia"]],
  ["LI", "Liechtenstein", ["Liechtenstein"]],
  ["LT", "Lithuania", ["Litouwen", "Lituanie", "Lituania"]],
  ["LU", "Luxembourg", ["Luxemburg", "Luxembourg", "Luxemburgo"]],
  ["LV", "Latvia", ["Letland", "Lettonie", "Letonia"]],
  ["MC", "Monaco", ["Monaco", "Mónaco", "Monaco"]],
  ["MD", "Moldova", ["Moldavië", "Moldavie", "Moldavia"]],
  ["ME", "Montenegro", ["Montenegro", "Monténégro"]],
  ["MK", "North Macedonia", [
    "Noord-Macedonië",
    "Macédoine du Nord",
    "Macedonia del Norte",
  ]],
  ["MT", "Malta", ["Malta", "Malte"]],
  ["NL", "Netherlands", ["Nederland", "Pays-Bas", "Países Bajos", "Paises Bajos"]],
  ["NO", "Norway", ["Noorwegen", "Norvège", "Noruega"]],
  ["PL", "Poland", ["Polen", "Pologne", "Polonia"]],
  ["PT", "Portugal", ["Portugal"]],
  ["RO", "Romania", ["Roemenië", "Roumanie", "Rumanía", "Rumania"]],
  ["RS", "Serbia", ["Servië", "Serbie", "Serbia"]],
  ["SE", "Sweden", ["Zweden", "Suède", "Suecia"]],
  ["SI", "Slovenia", ["Slovenië", "Slovénie", "Eslovenia"]],
  ["SK", "Slovakia", ["Slowakije", "Slovaquie", "Eslovaquia"]],
  ["SM", "San Marino", ["San Marino", "Saint-Marin"]],
  ["UA", "Ukraine", ["Oekraïne", "Ukraine", "Ucrania"]],
  ["VA", "Vatican City", [
    "Vaticaanstad",
    "Cité du Vatican",
    "Ciudad del Vaticano",
    "Vatican",
  ]],
  ["XK", "Kosovo", ["Kosovo"]],
];

const BY_ISO = new Map();
const BY_LABEL = new Map();

for (const [iso, english, labels] of COUNTRIES) {
  BY_ISO.set(iso, { iso, englishName: english });
  const allLabels = new Set([iso, english, ...labels]);
  for (const label of allLabels) {
    const key = normalizeCountryLabel(label);
    if (key) BY_LABEL.set(key, iso);
  }
}

export function isKnownGooglePlacesIso(iso) {
  return BY_ISO.has(normalizeIsoCandidate(iso));
}

export function resolveGooglePlacesCountry(query = {}) {
  const explicitIso = normalizeIsoCandidate(
    query.countryCode ?? query.country_code,
  );
  if (explicitIso && BY_ISO.has(explicitIso)) {
    return {
      iso: explicitIso,
      englishName: BY_ISO.get(explicitIso).englishName,
      source: "explicit_iso",
    };
  }

  const mappedIso = BY_LABEL.get(normalizeCountryLabel(query.country));
  if (mappedIso && BY_ISO.has(mappedIso)) {
    return {
      iso: mappedIso,
      englishName: BY_ISO.get(mappedIso).englishName,
      source: "legacy_label",
    };
  }

  return { iso: "", englishName: "", source: "unresolved" };
}

export function buildGooglePlacesTextQuery(query = {}) {
  const resolved = resolveGooglePlacesCountry(query);
  const country = resolved.englishName;
  const destination = String(query.destination ?? "").trim();
  const city = String(query.city ?? "").trim();
  const region = String(query.region ?? "").trim();
  const searchText = String(query.searchText ?? "").trim();
  const freeText = destination || searchText;

  const cityIsCountry =
    Boolean(city) &&
    (normalizeCountryLabel(city) === normalizeCountryLabel(country) ||
      BY_LABEL.get(normalizeCountryLabel(city)) === resolved.iso);

  const safeCity = cityIsCountry ? "" : city;

  if (freeText && country) return `hotels in ${freeText}, ${country}`.slice(0, 200);
  if (freeText) return `hotels in ${freeText}`.slice(0, 200);
  if (safeCity && region && country) {
    return `hotels in ${safeCity}, ${region}, ${country}`.slice(0, 200);
  }
  if (safeCity && country) return `hotels in ${safeCity}, ${country}`.slice(0, 200);
  if (region && country) return `hotels in ${region}, ${country}`.slice(0, 200);
  if (country) return `hotels in ${country}`.slice(0, 200);
  return "hotels in Belgium";
}

function looksLikePostalOrStreet(part) {
  const text = String(part ?? "").trim();
  if (!text) return true;
  if (/^\d+[A-Za-z]?(?:\s*-\s*\d+)?$/.test(text)) return true;
  if (/^\d{3,5}\s*-?\s*\d{0,4}$/.test(text)) return true;
  return false;
}

export function mapGooglePlacesAddressParts(address, query = {}) {
  const resolved = resolveGooglePlacesCountry(query);
  const iso = resolved.iso;
  const englishName = resolved.englishName;
  const text = String(address ?? "").trim();
  const requestedCity = String(query.city ?? "").trim();
  const requestedRegion = String(query.region ?? "").trim();
  const requestedCityIsCountry =
    Boolean(requestedCity) &&
    (BY_LABEL.get(normalizeCountryLabel(requestedCity)) === iso ||
      normalizeCountryLabel(requestedCity) === normalizeCountryLabel(englishName));

  if (!text) {
    return {
      city: requestedCityIsCountry ? "" : requestedCity,
      region: requestedRegion,
      country: iso,
    };
  }

  const parts = text
    .split(",")
    .map((part) => String(part ?? "").trim())
    .filter(Boolean);

  const isCountryPart = (part) => {
    const normalized = normalizeCountryLabel(part);
    if (!normalized) return false;
    if (iso && BY_LABEL.get(normalized) === iso) return true;
    if (englishName && normalized === normalizeCountryLabel(englishName)) {
      return true;
    }
    return false;
  };

  while (parts.length && isCountryPart(parts[parts.length - 1])) {
    parts.pop();
  }

  let locality = "";
  for (let i = parts.length - 1; i >= 0; i -= 1) {
    const cleaned = parts[i]
      .replace(/^\d{3,6}(?:\s*-\s*\d{2,4})?\s+/, "")
      .replace(/\s+\d{3,6}(?:\s*-\s*\d{2,4})?$/, "")
      .trim();
    if (!cleaned || isCountryPart(cleaned) || looksLikePostalOrStreet(cleaned)) {
      continue;
    }
    if (/^[0-9\s./-]+$/.test(cleaned)) continue;
    locality = cleaned;
    break;
  }

  if (isCountryPart(locality) || normalizeCountryLabel(locality) === normalizeCountryLabel(englishName)) {
    locality = "";
  }

  const city = requestedCityIsCountry ? locality : requestedCity || locality;
  const region = requestedRegion;

  return {
    city: city && !isCountryPart(city) ? city : "",
    region,
    country: iso,
  };
}

export function formatGooglePlacesLocationParts({ city = "", region = "", country = "" } = {}) {
  return [city, region, country]
    .map((part) => String(part ?? "").trim())
    .filter(Boolean)
    .join(", ");
}
