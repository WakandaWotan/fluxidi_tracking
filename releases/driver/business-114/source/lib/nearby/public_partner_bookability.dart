/// PUBLIC-PARTNER-BOOKABILITY-P0 — customer-facing partner availability helpers.

import 'public_partner_identity.dart';

bool looksLikeInternalPartnerIdentifier(String? value) {
  final s = (value ?? '').trim();
  if (s.isEmpty) return false;
  if (s.toLowerCase().startsWith('company:')) return true;
  final lower = s.toLowerCase();
  if (RegExp(r'\bcmp_[a-z0-9._-]+').hasMatch(lower)) return true;
  if (RegExp(r'\bsub_[a-z0-9]+').hasMatch(lower)) return true;
  if (RegExp(r'\bcst_[a-z0-9]+').hasMatch(lower)) return true;
  if (RegExp(r'\bmdt_[a-z0-9]+').hasMatch(lower)) return true;
  return false;
}

/// Authoritative public bookability from nearby/profile JSON.
bool isPublicPartnerBookable(Map<String, dynamic> partner) {
  if (partner['bookable'] == false || partner['bookable'] == 'false') {
    return false;
  }
  if (partner['bookable'] == true || partner['bookable'] == 'true') {
    return true;
  }
  final availability =
      (partner['availability_status'] ?? partner['availabilityStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  if (availability == 'inactive') return false;
  if (availability == 'active') return true;
  return partner['is_active'] == true || partner['isActive'] == true;
}

String publicPartnerDisplayName(
  Map<String, dynamic> partner, {
  String fallback = '',
}) {
  for (final key in const [
    'company_name',
    'companyName',
    'public_company_code',
    'publicCompanyCode',
    'company_code',
    'companyCode',
  ]) {
    final value = (partner[key] ?? '').toString().trim();
    final name = sanitizePublicPartnerBrandName(value);
    if (name.isNotEmpty && !looksLikeInternalPartnerIdentifier(name)) {
      return name;
    }
  }
  final safeFallback = sanitizePublicPartnerBrandName(fallback);
  if (safeFallback.isNotEmpty &&
      !looksLikeInternalPartnerIdentifier(safeFallback)) {
    return safeFallback;
  }
  return '';
}

String publicPartnerInactiveBookingMessage({required String languageCode}) {
  switch (languageCode) {
    case 'en':
      return 'This company is currently inactive and cannot accept new bookings.';
    case 'fr':
      return 'Cette entreprise est actuellement inactive et ne peut pas accepter de nouvelles réservations.';
    case 'es':
      return 'Esta empresa está actualmente inactiva y no puede aceptar nuevas reservas.';
    case 'nl':
    default:
      return 'Dit bedrijf is momenteel niet actief en kan geen nieuwe boekingen ontvangen.';
  }
}
