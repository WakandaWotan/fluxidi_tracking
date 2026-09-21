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

/// Cleans a value that is only a *fallback* for a missing company name.
///
/// The platform brand may never stand in for a partner that did not supply a
/// name. An explicitly published `company_name` is a real name and is kept by
/// [publicPartnerRealName], even when that name happens to be "Fluxidi".
String sanitizePublicPartnerFallbackName(String raw) {
  final name = raw.trim();
  if (name.isEmpty || isPlatformBrandPublicName(name)) return '';
  if (looksLikeInternalPartnerIdentifier(name)) return '';
  return name;
}

/// An explicitly published company name. Only internal identifiers are refused.
String publicPartnerRealName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return '';
  if (looksLikeInternalPartnerIdentifier(name)) return '';
  return name;
}

/// Tri-state truthiness for server booleans that may arrive as text.
bool? publicPartnerFlag(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) {
    if (raw == 1) return true;
    if (raw == 0) return false;
    return null;
  }
  final text = raw?.toString().trim().toLowerCase() ?? '';
  if (text.isEmpty) return null;
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

/// Authoritative bookability from nearby/profile JSON.
///
/// Fails closed: an explicit `bookable=false` wins over everything, and an
/// availability status that is present but not understood never becomes
/// bookable through the `is_active` fallback.
bool isPublicPartnerBookable(Map<String, dynamic> partner) {
  final bookable = publicPartnerFlag(
    partner['bookable'] ?? partner['isBookable'],
  );
  if (bookable != null) return bookable;

  final availability =
      (partner['availability_status'] ?? partner['availabilityStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  if (availability == 'inactive') return false;
  if (availability == 'active') return true;
  if (availability.isNotEmpty) return false;

  return publicPartnerFlag(partner['is_active'] ?? partner['isActive']) ?? false;
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
