// Chiron nummerplaat on the wire: A-Z0-9 only. Never pad a short plate.

String? chironOfficialKentekenplaatWire(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final alnum = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return alnum.isEmpty ? null : alnum;
}

/// CH1211: Chiron rejects plates shorter than 7 alphanumeric characters.
bool chironOfficialPlateMeetsCh1211(String? value) {
  final wire = chironOfficialKentekenplaatWire(value);
  return wire != null && wire.length >= 7;
}

/// Prefer the fleet plate when the event/booking plate would fail CH1211.
/// Never invent characters to reach length 7.
String? chironPreferredKentekenplaat({
  String? eventPlate,
  String? fleetPlate,
}) {
  final event = (eventPlate ?? '').trim();
  final fleet = (fleetPlate ?? '').trim();
  if (chironOfficialPlateMeetsCh1211(event)) return event;
  if (chironOfficialPlateMeetsCh1211(fleet)) return fleet;
  if (event.isNotEmpty) return event;
  if (fleet.isNotEmpty) return fleet;
  return null;
}
