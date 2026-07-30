/// GOOGLE-PLAY-PRIVACY-READINESS-P0
///
/// Single canonical legal URL configuration for the release app.
/// Do not hardcode competing privacy or account-deletion URLs elsewhere.
library;

/// Live Fluxidi privacy policy (Play / in-app / web).
const String kFluxidiPrivacyPolicyUrl =
    'https://fluxidi.com/policies/privacy-policy';

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

Uri fluxidiPrivacyPolicyUri() => Uri.parse(kFluxidiPrivacyPolicyUrl);

Uri fluxidiAccountDeletionUri() => Uri.parse(kFluxidiAccountDeletionUrl);

Uri fluxidiPrivacyMailtoUri({required String subject}) {
  return Uri(
    scheme: 'mailto',
    path: kFluxidiPrivacyContactEmail,
    queryParameters: <String, String>{'subject': subject},
  );
}
