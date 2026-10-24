// RELEASE-P0 CORRECTIE — PRIVACYROUTE NA SHOPIFY-FIX
//
// Privacy policy opens the custom Fluxidi page with ?lang= selected from
// Fluxidi's own app language. Legacy /policies/privacy-policy routes must
// never reappear.
//
// Run:
//   flutter test test/privacy/privacy_policy_locale_url_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/privacy/fluxidi_legal_urls.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('RELEASE-P0 privacy policy locale URI', () {
    test('nl gives ?lang=nl', () {
      final uri = fluxidiPrivacyPolicyUriForLanguage('nl');
      expect(
        uri.toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=nl',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'fluxidi.com');
      expect(uri.path, '/pages/privacybeleid');
      expect(uri.queryParameters, {'lang': 'nl'});
    });

    test('en gives ?lang=en', () {
      expect(
        fluxidiPrivacyPolicyUriForLanguage('en').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=en',
      );
    });

    test('fr gives ?lang=fr', () {
      expect(
        fluxidiPrivacyPolicyUriForLanguage('fr').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=fr',
      );
    });

    test('es gives ?lang=es', () {
      expect(
        fluxidiPrivacyPolicyUriForLanguage('es').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=es',
      );
    });

    test('de gives ?lang=de', () {
      expect(
        fluxidiPrivacyPolicyUriForLanguage('de').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=de',
      );
    });

    test('unknown / empty falls back to ?lang=nl', () {
      expect(
        fluxidiPrivacyPolicyUriForLanguage('').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=nl',
      );
      expect(
        fluxidiPrivacyPolicyUriForLanguage('zh-CN').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=nl',
      );
      expect(
        fluxidiPrivacyPolicyUriForLanguage('   ').toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=nl',
      );
    });

    test('no privacy URL contains /policies/privacy-policy', () {
      for (final code in ['nl', 'en', 'fr', 'es', 'de', '', 'xx']) {
        final url = fluxidiPrivacyPolicyUriForLanguage(code).toString();
        expect(url.contains('/policies/privacy-policy'), isFalse, reason: url);
      }
      expect(kFluxidiPrivacyPolicyUrl.contains('/policies/privacy-policy'),
          isFalse);
      expect(fluxidiPrivacyPolicyUri().toString().contains('/policies/privacy-policy'),
          isFalse);
    });

    test('only HTTPS fluxidi.com /pages/privacybeleid?lang=… is safe', () {
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse('https://fluxidi.com/pages/privacybeleid?lang=en'),
        ),
        isTrue,
      );
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse('http://fluxidi.com/pages/privacybeleid?lang=nl'),
        ),
        isFalse,
      );
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse('https://evil.com/pages/privacybeleid?lang=nl'),
        ),
        isFalse,
      );
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse('https://fluxidi.com/pages/privacybeleid?token=abc'),
        ),
        isFalse,
      );
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse(
            'https://fluxidi.com/pages/privacybeleid?lang=en&token=x',
          ),
        ),
        isFalse,
      );
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse('https://fluxidi.com/policies/privacy-policy'),
        ),
        isFalse,
      );
      expect(
        isSafeFluxidiPrivacyPolicyUri(
          Uri.parse('https://fluxidi.com/pages/account-en-gegevens-verwijderen'),
        ),
        isFalse,
      );
    });

    test('deletion URL remains unchanged', () {
      expect(
        kFluxidiAccountDeletionUrl,
        'https://fluxidi.com/pages/account-en-gegevens-verwijderen',
      );
    });

    test('privacy contact email remains info@fluxidi.com', () {
      expect(kFluxidiPrivacyContactEmail, 'info@fluxidi.com');
    });

    test('legacy fluxidiPrivacyPolicyUri returns NL lang query', () {
      expect(
        fluxidiPrivacyPolicyUri().toString(),
        'https://fluxidi.com/pages/privacybeleid?lang=nl',
      );
    });

    test('UI source uses the language-aware helper for all audiences', () {
      final ui = _read('lib/privacy/fluxidi_privacy_ui.dart');
      expect(ui.contains('fluxidiPrivacyPolicyUriForLanguage'), isTrue);
      expect(ui.contains('fluxidiPrivacyPolicyUri()'), isFalse);
      expect(ui.contains('/policies/privacy-policy'), isFalse);
    });

    test('legal config has no legacy Shopify policy routes', () {
      final legal = _read('lib/privacy/fluxidi_legal_urls.dart');
      expect(legal.contains('/policies/privacy-policy'), isFalse);
      expect(legal.contains('kFluxidiPrivacyPolicyProvenLanguages'), isFalse);
      expect(legal.contains('/pages/privacybeleid'), isTrue);
    });
  });
}
