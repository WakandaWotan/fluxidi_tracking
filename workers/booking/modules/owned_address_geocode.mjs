/// Pick a Mapbox feature that agrees with an owned street address.
/// A competing 9600 Ronse result must not win over 9688 Schorisse/Maarkedal.
/// Postcode alone is not enough: street and house number/letter must match.
/// A street-level 48 is not a proven 48A house location.

export function queryPostcode(query) {
  const match = String(query || "").match(/\b([1-9]\d{3})\b/);
  return match ? match[1] : "";
}

export function featurePostcode(feature) {
  const context = Array.isArray(feature?.context) ? feature.context : [];
  for (const item of context) {
    const id = String(item?.id || "");
    if (id.startsWith("postcode.")) {
      const text = String(item.text || "").trim();
      const match = text.match(/\b([1-9]\d{3})\b/);
      return match ? match[1] : text;
    }
  }
  const props = feature?.properties && typeof feature.properties === "object"
    ? feature.properties
    : {};
  const fromProps = String(props.postcode || "").trim();
  const propsMatch = fromProps.match(/\b([1-9]\d{3})\b/);
  if (propsMatch) return propsMatch[1];
  const label = String(feature?.place_name || feature?.placeName || "").trim();
  const labelMatch = label.match(/\b([1-9]\d{3})\b/);
  return labelMatch ? labelMatch[1] : "";
}

function foldToken(raw) {
  return String(raw || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function parseStreetHouse(raw) {
  let text = String(raw || "").trim();
  const postcode = queryPostcode(text);
  if (postcode) {
    const index = text.indexOf(postcode);
    if (index > 0) text = text.slice(0, index);
  }
  text = text.replace(/[\s,]+$/g, "").trim();
  const matches = [...text.matchAll(/(\d+)\s*([A-Za-z])?\b/g)];
  if (!matches.length) return { street: text, number: "", letter: "" };
  const match = matches[matches.length - 1];
  const street = text
    .slice(0, match.index)
    .replace(/[\s,.\-]+$/g, "")
    .trim();
  return {
    street,
    number: match[1] || "",
    letter: (match[2] || "").toUpperCase(),
  };
}

const LOCALITY_EQUIVALENTS = {
  schorisse: new Set(["maarkedal"]),
  maarkedal: new Set(["schorisse"]),
};

export function localitiesCompatible(left, right) {
  const a = foldToken(left);
  const b = foldToken(right);
  if (!a || !b) return true;
  if (a === b || a.includes(b) || b.includes(a)) return true;
  return LOCALITY_EQUIVALENTS[a]?.has(b) === true;
}

export function featureLocality(feature) {
  const context = Array.isArray(feature?.context) ? feature.context : [];
  for (const item of context) {
    const id = String(item?.id || "");
    if (id.startsWith("place.") || id.startsWith("locality.") || id.startsWith("neighborhood.")) {
      const text = String(item.text || "").trim();
      if (text) return text;
    }
  }
  const label = String(feature?.place_name || feature?.placeName || "").trim();
  const match = label.match(/\b\d{4}\s+([^,]+)/);
  return match ? match[1].trim() : "";
}

export function streetNamesCompatible(left, right) {
  const a = foldToken(left);
  const b = foldToken(right);
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.includes(b) || b.includes(a)) return true;
  const firstA = a.split(" ")[0] || "";
  const firstB = b.split(" ")[0] || "";
  return firstA.length >= 4 && firstA === firstB;
}

export function featureAgreesWithQuery(feature, query) {
  const wanted = queryPostcode(query);
  const got = featurePostcode(feature);
  if (wanted) {
    if (!got || got !== wanted) return false;
  }
  const queryParts = parseStreetHouse(query);
  const suggestionParts = parseStreetHouse(
    feature?.place_name || feature?.placeName || feature?.text || "",
  );
  if (
    queryParts.street &&
    !streetNamesCompatible(queryParts.street, suggestionParts.street) &&
    !streetNamesCompatible(
      queryParts.street,
      feature?.place_name || feature?.placeName || "",
    )
  ) {
    return false;
  }
  if (queryParts.number) {
    if (suggestionParts.number !== queryParts.number) return false;
    if (queryParts.letter && suggestionParts.letter !== queryParts.letter) {
      return false;
    }
  }
  const queryLocality = String(query || "").match(/\b\d{4}\s+([^,]+)/);
  const suggestionLocality = featureLocality(feature);
  if (queryLocality?.[1] && suggestionLocality) {
    if (!localitiesCompatible(queryLocality[1], suggestionLocality) && wanted && got && wanted !== got) {
      return false;
    }
  }
  return true;
}

export function pickGeocodeFeature(features, query) {
  const list = Array.isArray(features)
    ? features.filter((item) => Array.isArray(item?.center) && item.center.length >= 2)
    : [];
  if (!list.length) return null;
  const queryParts = parseStreetHouse(query);
  const wanted = queryPostcode(query);
  const streetMatches = list.filter((item) => {
    const suggestionParts = parseStreetHouse(
      item?.place_name || item?.placeName || "",
    );
    if (
      queryParts.street &&
      !streetNamesCompatible(queryParts.street, suggestionParts.street) &&
      !streetNamesCompatible(
        queryParts.street,
        item?.place_name || item?.placeName || "",
      )
    ) {
      return false;
    }
    if (queryParts.number && suggestionParts.number && suggestionParts.number !== queryParts.number) {
      return false;
    }
    return true;
  });
  const streetPostcodes = new Set(
    streetMatches.map((item) => featurePostcode(item)).filter(Boolean),
  );
  if (!wanted && queryParts.street && streetPostcodes.size > 1) {
    return null;
  }
  const agreeing = list.filter((item) => featureAgreesWithQuery(item, query));
  if (agreeing.length) return agreeing[0];
  if (!queryParts.number && wanted) {
    const byPostcode = list.filter((item) => featurePostcode(item) === wanted);
    if (byPostcode.length === 1) return byPostcode[0];
  }
  if (wanted || queryParts.street || queryParts.number) return null;
  return list[0];
}
