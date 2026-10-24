// Public company codes as accepted by the booking Worker
// `validatePublicCompanyCode`: 4–24 of A-Z, 0-9, hyphen.

String normalizePublicCompanyCode(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

bool isValidPublicCompanyCode(String raw) {
  final code = normalizePublicCompanyCode(raw);
  if (code.length < 4 || code.length > 24) return false;
  if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(code)) return false;
  return RegExp(r'[A-Z0-9]').hasMatch(code);
}
