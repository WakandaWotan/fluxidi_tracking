/// Public partner visibility rules.
///
/// These mirror the meaning used by the existing Fluxidi customer flow at
/// golden commit 9df7e7b9 (`lib/nearby/public_partner_bookability.dart` and
/// `lib/nearby/public_partner_identity.dart`). A company is never shown as
/// active or bookable unless the server says so.
library;

/// True when a value looks like an internal identifier rather than a brand.
bool looksLikeInternalPartnerIdentifier(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return false;
  final lower = raw.toLowerCase();
  if (lower.startsWith('company:')) return true;
  for (final prefix in const <String>['cmp_', 'sub_', 'cst_', 'mdt_']) {
    if (RegExp('\\b$prefix[a-z0-9._-]+').hasMatch(lower)) return true;
  }
  return false;
}

/// Fluxidi is the platform, never a partner brand fallback.
bool isPlatformBrandPublicName(String raw) {
  final name = raw.trim().toLowerCase();
  if (name.isEmpty) return false;
  return const <String>{
    'fluxidi',
    'fluxidi platform',
    'fluxidi partner',
    'partenaire fluxidi',
    'socio fluxidi',
  }.contains(name);
}

String sanitizePublicPartnerBrandName(String raw) {
  final name = raw.trim();
  if (name.isEmpty || isPlatformBrandPublicName(name)) return '';
  return name;
}

/// Authoritative bookability from nearby/profile JSON. Never assumed true.
bool isPublicPartnerBookable(Map<String, dynamic> partner) {
  final bookable = partner['bookable'];
  if (bookable == false || bookable == 'false') return false;
  if (bookable == true || bookable == 'true') return true;

  final availability =
      (partner['availability_status'] ?? partner['availabilityStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  if (availability == 'inactive') return false;
  if (availability == 'active') return true;

  return partner['is_active'] == true || partner['isActive'] == true;
}

/// Only remote https images are rendered; anything else falls back.
bool publicPartnerImageIsRenderable(String url) {
  final value = url.trim();
  if (!value.startsWith('https://')) return false;
  // The platform's own default logo is not a partner brand image.
  return !value.toLowerCase().contains('fluxidi_logo');
}

String publicPartnerInactiveMessageNl() =>
    'Dit bedrijf is momenteel niet actief en kan geen nieuwe boekingen '
    'ontvangen.';
