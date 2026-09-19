// Whether an edited return address still belongs to its resolved pin.
//
// The airport return address used to drop its coordinates on every keystroke.
// Without `return_to_lat`/`return_to_lng` the worker has to compare the return
// leg on text alone, and a legitimate rewrite — "9688 Louise-Marie" into
// "9688 Maarkedal" — then fails, which answers HTTP 422 for a trip that has a
// perfectly good fixed fare.
//
// The anchor here is the same one the worker uses: postcode plus house number,
// with the street word as the guard. Same anchor means same place, so the pin
// stays. A different street, house number or postcode drops it, and the
// customer has to pick the address again.

/// Postcode as written in a free-text Belgian address, or `''`.
String airportReturnPostcodeOf(String rawAddress) {
  final text = rawAddress.trim();
  if (text.isEmpty) return '';
  final match = RegExp(
    r'(?:^|[,\s])([1-9]\d{3})(?:\s?[A-Za-z]{2})?(?=$|[,\s])',
  ).firstMatch(text);
  return (match?.group(1) ?? '').trim();
}

/// House number as written, e.g. `48a` for "Koekamerstraat 48A, 9688".
/// A four-digit group is a postcode, never a house number.
String airportReturnHouseNumberOf(String rawAddress) {
  final postcode = airportReturnPostcodeOf(rawAddress);
  for (final match in RegExp(
    r'(?:^|[,\s])(\d{1,4}[A-Za-z]?)(?=$|[,\s])',
  ).allMatches(rawAddress)) {
    final token = (match.group(1) ?? '').trim();
    if (token.isEmpty) continue;
    if (token.toLowerCase() == postcode.toLowerCase()) continue;
    if (RegExp(r'^\d{4}$').hasMatch(token)) continue;
    return token.toLowerCase();
  }
  return '';
}

/// First alphabetic word of an address, lowercased. Ties a kept pin to the
/// same street.
String airportReturnStreetWordOf(String rawAddress) {
  for (final token in rawAddress.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (token.isEmpty) continue;
    if (RegExp(r'^\d').hasMatch(token)) continue;
    return token;
  }
  return '';
}

/// True when [edited] still names the place [anchor] was resolved for.
bool airportReturnEditKeepsPin({
  required String anchor,
  required String edited,
}) {
  final anchorText = anchor.trim();
  final editedText = edited.trim();
  if (anchorText.isEmpty || editedText.isEmpty) return false;

  final anchorPostcode = airportReturnPostcodeOf(anchorText);
  if (anchorPostcode.isEmpty) return false;
  if (anchorPostcode != airportReturnPostcodeOf(editedText)) return false;

  final anchorHouse = airportReturnHouseNumberOf(anchorText);
  if (anchorHouse.isEmpty) return false;
  if (anchorHouse != airportReturnHouseNumberOf(editedText)) return false;

  final anchorStreet = airportReturnStreetWordOf(anchorText);
  if (anchorStreet.isEmpty) return false;
  return anchorStreet == airportReturnStreetWordOf(editedText);
}
