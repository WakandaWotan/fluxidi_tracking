/// GOOGLE-PLAY-PRIVACY-READINESS-P0 /
/// RELEASE-P0 CORRECTIE — PRIVACYROUTE NA SHOPIFY-FIX
///
/// Single canonical legal URL configuration for the release app.
/// Do not hardcode competing privacy or account-deletion URLs elsewhere.
library;

/// Canonical Fluxidi privacy-policy page (custom Shopify page with five
/// built-in language panels selected via `?lang=`).
///
/// Legacy Shopify product-policy locale routes are retired and must not be
/// linked from the app. Use [fluxidiPrivacyPolicyUriForLanguage] only.
const String kFluxidiPrivacyPolicyUrl =
    'https://fluxidi.com/pages/privacybeleid';

/// Path of the canonical privacy page (no query).
const String kFluxidiPrivacyPolicyPath = '/pages/privacybeleid';

/// Languages accepted by the privacy page language switcher.
const Set<String> kFluxidiPrivacyPolicyLanguages = <String>{
  'nl',
  'en',
  'fr',
  'es',
  'de',
};

/// Canonical public account-deletion request page (published Shopify page).
///
/// The legacy path `https://fluxidi.com/account-verwijderen` returns 404.
/// The intermediate `https://fluxidi.com/pages/account-verwijderen` was not
/// the published slug either. The single canonical page is:
///
///   https://fluxidi.com/pages/account-en-gegevens-verwijderen
///
/// Do not link any other slug from the app.
const String kFluxidiAccountDeletionUrl =
    'https://fluxidi.com/pages/account-en-gegevens-verwijderen';

/// PRIVACY-P0-4-CORRECT-CANONICAL-EMAIL:
/// Canonical, single-source-of-truth privacy contact mailbox used by every
/// privacy / account / deletion surface (customer, business, driver, in every
/// supported language). Do not hardcode any other privacy address in
/// `lib/privacy/`. Addresses forbidden as a privacy contact — enforced by
/// `test/privacy/privacy_email_regression_p0_4_test.dart` — are:
///   - info@fluxity.com          (domain typo — never valid)
///   - support@fluxidi.com       (not a real Fluxidi mailbox)
///   - support@fluxity.com       (not a real Fluxidi mailbox)
///   - fluxidi.booking@gmail.com (legacy operational address, never privacy)
const String kFluxidiPrivacyContactEmail = 'info@fluxidi.com';

/// Default (NL) privacy URI without relying on a caller language.
Uri fluxidiPrivacyPolicyUri() => fluxidiPrivacyPolicyUriForLanguage('nl');

/// RELEASE-P0 CORRECTIE — PRIVACYROUTE NA SHOPIFY-FIX:
/// Locale-aware privacy-policy URI driven exclusively by Fluxidi's own
/// language code (`appLanguageNotifier` / `currentLanguageCode`).
/// Never reads the device locale.
///
/// Exact mapping:
///   nl / en / fr / es / de → `/pages/privacybeleid?lang=<code>`
///   unknown / empty        → `/pages/privacybeleid?lang=nl`
///
/// Host is always `fluxidi.com`. HTTPS required. The only allowed query
/// parameter is the bounded `lang` code from [kFluxidiPrivacyPolicyLanguages].
Uri fluxidiPrivacyPolicyUriForLanguage(String languageCode) {
  final code = languageCode.trim().toLowerCase();
  final lang = kFluxidiPrivacyPolicyLanguages.contains(code) ? code : 'nl';
  return Uri(
    scheme: 'https',
    host: 'fluxidi.com',
    path: kFluxidiPrivacyPolicyPath,
    queryParameters: <String, String>{'lang': lang},
  );
}

/// True only for HTTPS `fluxidi.com` privacy page URIs with a bounded `lang`.
bool isSafeFluxidiPrivacyPolicyUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (uri.host != 'fluxidi.com') return false;
  if (uri.path != kFluxidiPrivacyPolicyPath) return false;
  if (uri.fragment.isNotEmpty) return false;
  final params = uri.queryParameters;
  if (params.length != 1 || !params.containsKey('lang')) return false;
  return kFluxidiPrivacyPolicyLanguages.contains(params['lang']);
}

Uri fluxidiAccountDeletionUri() => Uri.parse(kFluxidiAccountDeletionUrl);

Uri fluxidiPrivacyMailtoUri({required String subject}) {
  return Uri(
    scheme: 'mailto',
    path: kFluxidiPrivacyContactEmail,
    queryParameters: <String, String>{'subject': subject},
  );
}
