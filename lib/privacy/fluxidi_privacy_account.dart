/// GOOGLE-PLAY-PRIVACY-READINESS-P0
///
/// Pure decisions for privacy / account surfaces and deletion-request
/// authority. No I/O, no tokens, no Mapbox, no payment.
library;

import 'fluxidi_legal_urls.dart';

/// Which actor a privacy / deletion request concerns.
enum FluxidiPrivacyAudience {
  customer,
  driver,
  business,
}

String fluxidiPrivacyAudienceLabel(FluxidiPrivacyAudience audience) {
  switch (audience) {
    case FluxidiPrivacyAudience.customer:
      return 'customer';
    case FluxidiPrivacyAudience.driver:
      return 'driver';
    case FluxidiPrivacyAudience.business:
      return 'business';
  }
}

/// Safe, non-secret query on the public deletion page so the form can
/// pre-select the request type. Never carries tokens, emails, phones or IDs.
Uri buildFluxidiAccountDeletionRequestUri({
  required FluxidiPrivacyAudience audience,
}) {
  return Uri.parse(kFluxidiAccountDeletionUrl).replace(
    queryParameters: <String, String>{
      'audience': fluxidiPrivacyAudienceLabel(audience),
    },
  );
}

/// True when [uri] is the canonical deletion host/path and contains no
/// bearer/token/secret/email/phone-style query keys.
bool isSafeFluxidiAccountDeletionUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (uri.host != 'fluxidi.com') return false;
  if (uri.path != '/pages/account-en-gegevens-verwijderen') return false;
  final forbidden = <String>{
    'token',
    'access_token',
    'refresh_token',
    'authorization',
    'bearer',
    'admin_token',
    'session',
    'password',
    'secret',
    'email',
    'phone',
    'driver_id',
    'customer_id',
    'booking_id',
    'company_id',
  };
  for (final key in uri.queryParameters.keys) {
    final lower = key.toLowerCase();
    if (forbidden.contains(lower)) return false;
    if (lower.contains('token') || lower.contains('secret')) return false;
  }
  final audience = uri.queryParameters['audience'];
  if (audience != null &&
      audience != 'customer' &&
      audience != 'driver' &&
      audience != 'business') {
    return false;
  }
  return true;
}

/// Customer / driver surfaces may always open their own deletion request.
bool mayRequestOwnAccountDeletion({
  required FluxidiPrivacyAudience audience,
}) {
  return audience == FluxidiPrivacyAudience.customer ||
      audience == FluxidiPrivacyAudience.driver;
}

/// Company-account deletion requires a verified company owner/admin session.
bool mayRequestBusinessAccountDeletion({
  required bool isCompanyOwnerOrAdmin,
}) {
  return isCompanyOwnerOrAdmin;
}

/// Normalized set of company-session role strings that constitute
/// owner-or-admin authority. Case-insensitive; both snake and camel accepted.
const Set<String> kFluxidiOwnerOrAdminRoles = <String>{
  'companyadmin',
  'company_admin',
  'admin',
  'owner',
  'company_owner',
};

/// Fail-closed authority check for company-account deletion.
///
/// Requires **all** of:
///   * a non-null company session;
///   * a non-empty company session bearer token;
///   * a non-empty company id on that session;
///   * a role string that normalizes into [kFluxidiOwnerOrAdminRoles];
///   * the current app role indicates the company admin surface
///     (`appRoleIsCompanyAdmin == true`).
///
/// Any missing signal returns false. This mirrors the real authority actually
/// used elsewhere in the app (`CompanySessionStore` + `AppRole.companyAdmin`)
/// without importing UI/session types here (kept pure for testability).
bool resolveIsCompanyOwnerOrAdmin({
  required bool hasCompanySession,
  required String? companySessionToken,
  required String? companyId,
  required String? sessionRole,
  required bool appRoleIsCompanyAdmin,
}) {
  if (!hasCompanySession) return false;
  if (!appRoleIsCompanyAdmin) return false;
  final token = (companySessionToken ?? '').trim();
  if (token.isEmpty) return false;
  final company = (companyId ?? '').trim();
  if (company.isEmpty) return false;
  final normalizedRole = (sessionRole ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_');
  if (normalizedRole.isEmpty) return false;
  return kFluxidiOwnerOrAdminRoles.contains(normalizedRole);
}

/// A driver must never target the tenant/company or another driver.
bool driverDeletionTargetsCompanyOrOtherDriver({
  required FluxidiPrivacyAudience requestedAudience,
  String? targetDriverId,
  String? sessionDriverId,
}) {
  if (requestedAudience == FluxidiPrivacyAudience.business) return true;
  if (requestedAudience != FluxidiPrivacyAudience.driver) return false;
  final target = (targetDriverId ?? '').trim();
  final session = (sessionDriverId ?? '').trim();
  if (target.isEmpty) return false;
  if (session.isEmpty) return true;
  return target != session;
}

/// A customer deletion request must never target a company.
bool customerDeletionTargetsCompany({
  required FluxidiPrivacyAudience requestedAudience,
}) {
  return requestedAudience == FluxidiPrivacyAudience.business;
}

/// Public deletion page remains usable without an active app session.
bool accountDeletionUrlRequiresActiveSession() => false;

/// Legal-retention explanation shown before opening the deletion page.
/// Localized NL/EN/FR/ES.
String fluxidiDeletionRetentionExplanation({required String languageCode}) {
  switch (languageCode) {
    case 'en':
      return 'Deleting an account is a verified request, not an instant erase. '
          'We may need to confirm your identity and authority. Legally required '
          'accounting, invoice, ride, compliance, fraud-prevention or legal-claim '
          'records may be retained and restricted. Logout or disabling the '
          'app does not complete deletion.';
    case 'fr':
      return 'La suppression d’un compte est une demande vérifiée, pas une '
          'effacement immédiat. Nous pouvons devoir confirmer votre identité et '
          'votre autorité. Les documents comptables, factures, courses, '
          'conformité, prévention de la fraude ou litiges légalement requis '
          'peuvent être conservés et restreints. Se déconnecter ne vaut pas '
          'suppression.';
    case 'es':
      return 'Eliminar una cuenta es una solicitud verificada, no un borrado '
          'inmediato. Puede que debamos confirmar su identidad y autoridad. '
          'Los registros contables, facturas, viajes, cumplimiento, prevención '
          'de fraude o reclamaciones legalmente obligatorios pueden conservarse '
          'y restringirse. Cerrar sesión no completa la eliminación.';
    case 'nl':
    default:
      return 'Accountverwijdering is een geverifieerd verzoek, geen onmiddellijke '
          'wisactie. We kunnen uw identiteit en bevoegdheid controleren. '
          'Wettelijk verplichte boekhoud-, factuur-, rit-, compliance-, '
          'fraudepreventie- of juridische dossiers kunnen worden bewaard en '
          'beperkt. Uitloggen of de app uitschakelen is geen voltooide '
          'verwijdering.';
  }
}

String fluxidiPrivacySectionTitle({
  required FluxidiPrivacyAudience audience,
  required String languageCode,
}) {
  switch (audience) {
    case FluxidiPrivacyAudience.customer:
      switch (languageCode) {
        case 'en':
          return 'My data & privacy';
        case 'fr':
          return 'Mes données & confidentialité';
        case 'es':
          return 'Mis datos y privacidad';
        case 'nl':
        default:
          return 'Mijn gegevens & privacy';
      }
    case FluxidiPrivacyAudience.business:
      switch (languageCode) {
        case 'en':
          return 'Privacy & account';
        case 'fr':
          return 'Confidentialité & compte';
        case 'es':
          return 'Privacidad y cuenta';
        case 'nl':
        default:
          return 'Privacy & account';
      }
    case FluxidiPrivacyAudience.driver:
      switch (languageCode) {
        case 'en':
          return 'My data & privacy';
        case 'fr':
          return 'Mes données & confidentialité';
        case 'es':
          return 'Mis datos y privacidad';
        case 'nl':
        default:
          return 'Mijn gegevens & privacy';
      }
  }
}
