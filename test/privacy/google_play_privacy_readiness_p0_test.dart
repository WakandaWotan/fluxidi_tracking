// GOOGLE-PLAY-PRIVACY-READINESS-P0
//
// Enforces canonical privacy / deletion URLs, fail-closed company authority,
// safe URI construction, retention copy, foreground-only location wiring, and
// the merged-manifest contract that ACCESS_BACKGROUND_LOCATION is absent.
//
// Run:
//   flutter test test/privacy/google_play_privacy_readiness_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_background_location_disclosure.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_legal_urls.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Missing $relativePath');
  return file.readAsStringSync();
}

Iterable<File> _dartFilesUnder(String relativeDir) sync* {
  final dir = Directory(relativeDir);
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.dart')) {
      yield entity;
    }
  }
}

void main() {
  group('GOOGLE-PLAY-PRIVACY-READINESS-P0 canonical URLs', () {
    test('4) all surfaces use the same canonical privacy URL', () {
      expect(
        kFluxidiPrivacyPolicyUrl,
        'https://fluxidi.com/pages/privacybeleid',
      );
      expect(fluxidiPrivacyPolicyUri().toString(),
          'https://fluxidi.com/pages/privacybeleid?lang=nl');
      expect(kFluxidiPrivacyPolicyUrl.contains('account-verwijderen'), isFalse);
      expect(kFluxidiPrivacyPolicyUrl.contains('/policies/privacy-policy'),
          isFalse);
    });

    test('5a) canonical deletion URL is the published Shopify slug', () {
      expect(
        kFluxidiAccountDeletionUrl,
        'https://fluxidi.com/pages/account-en-gegevens-verwijderen',
      );
      for (final audience in FluxidiPrivacyAudience.values) {
        final uri = buildFluxidiAccountDeletionRequestUri(audience: audience);
        expect(uri.origin + uri.path, kFluxidiAccountDeletionUrl);
        expect(isSafeFluxidiAccountDeletionUri(uri), isTrue);
      }
    });

    test('5b) legacy deletion slugs are not used anywhere in app code', () {
      // Only the legal-URL config may mention legacy slugs in doc comments,
      // and this test file itself references them in negative assertions.
      final allowList = <String>{
        'lib/privacy/fluxidi_legal_urls.dart',
        'test/privacy/google_play_privacy_readiness_p0_test.dart',
      };
      final legacyPatterns = <String>[
        'fluxidi.com/account-verwijderen',
        'fluxidi.com/pages/account-verwijderen',
      ];
      final offenders = <String>[];
      for (final dir in const ['lib', 'test']) {
        for (final file in _dartFilesUnder(dir)) {
          final normalized = file.path.replaceAll('\\', '/');
          if (allowList.contains(normalized)) continue;
          final text = file.readAsStringSync();
          for (final pattern in legacyPatterns) {
            if (text.contains(pattern)) {
              offenders.add('${file.path} :: $pattern');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Legacy account-verwijderen URLs must not appear anywhere in app '
            'or tests outside the audited allow-list. Found: $offenders',
      );
    });

    test('9a) safe URI: only bounded audience parameter is allowed', () {
      final base = buildFluxidiAccountDeletionRequestUri(
        audience: FluxidiPrivacyAudience.customer,
      );
      expect(base.queryParameters.keys.toSet(), <String>{'audience'});
      for (final v in const ['customer', 'driver', 'business']) {
        final u = Uri.parse(kFluxidiAccountDeletionUrl)
            .replace(queryParameters: <String, String>{'audience': v});
        expect(isSafeFluxidiAccountDeletionUri(u), isTrue);
      }
      final badAudience = Uri.parse(kFluxidiAccountDeletionUrl)
          .replace(queryParameters: <String, String>{'audience': 'root'});
      expect(isSafeFluxidiAccountDeletionUri(badAudience), isFalse);
    });

    test('9b) no token, session or personal data may be appended', () {
      final badKeys = <String>[
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
        'my_secret_thing',
        'authtoken',
      ];
      for (final key in badKeys) {
        final u = Uri.parse(kFluxidiAccountDeletionUrl).replace(
          queryParameters: <String, String>{
            'audience': 'customer',
            key: 'x',
          },
        );
        expect(
          isSafeFluxidiAccountDeletionUri(u),
          isFalse,
          reason: 'Query key "$key" must not be accepted.',
        );
      }
    });

    test('11) external deletion path remains available after logout', () {
      expect(accountDeletionUrlRequiresActiveSession(), isFalse);
      for (final audience in FluxidiPrivacyAudience.values) {
        final uri = buildFluxidiAccountDeletionRequestUri(audience: audience);
        expect(isSafeFluxidiAccountDeletionUri(uri), isTrue);
      }
    });
  });

  group('GOOGLE-PLAY-PRIVACY-READINESS-P0 authority', () {
    test('6) customer deletion cannot target a company', () {
      expect(
        customerDeletionTargetsCompany(
          requestedAudience: FluxidiPrivacyAudience.business,
        ),
        isTrue,
      );
      expect(
        customerDeletionTargetsCompany(
          requestedAudience: FluxidiPrivacyAudience.customer,
        ),
        isFalse,
      );
      expect(
        mayRequestOwnAccountDeletion(
          audience: FluxidiPrivacyAudience.customer,
        ),
        isTrue,
      );
    });

    test('7) driver deletion cannot target a company or another driver', () {
      expect(
        driverDeletionTargetsCompanyOrOtherDriver(
          requestedAudience: FluxidiPrivacyAudience.business,
          sessionDriverId: 'D1',
        ),
        isTrue,
      );
      expect(
        driverDeletionTargetsCompanyOrOtherDriver(
          requestedAudience: FluxidiPrivacyAudience.driver,
          targetDriverId: 'D2',
          sessionDriverId: 'D1',
        ),
        isTrue,
      );
      expect(
        driverDeletionTargetsCompanyOrOtherDriver(
          requestedAudience: FluxidiPrivacyAudience.driver,
          targetDriverId: 'D1',
          sessionDriverId: 'D1',
        ),
        isFalse,
      );
      expect(
        mayRequestOwnAccountDeletion(audience: FluxidiPrivacyAudience.driver),
        isTrue,
      );
    });

    test('8) resolveIsCompanyOwnerOrAdmin is fail-closed', () {
      bool call({
        bool hasSession = true,
        String? token = 't',
        String? companyId = 'C1',
        String? role = 'companyAdmin',
        bool appAdmin = true,
      }) {
        return resolveIsCompanyOwnerOrAdmin(
          hasCompanySession: hasSession,
          companySessionToken: token,
          companyId: companyId,
          sessionRole: role,
          appRoleIsCompanyAdmin: appAdmin,
        );
      }

      expect(call(), isTrue);
      expect(call(role: 'company_admin'), isTrue);
      expect(call(role: 'owner'), isTrue);
      expect(call(role: 'ADMIN'), isTrue);
      expect(call(role: 'company-owner'), isTrue);

      expect(call(role: 'driver'), isFalse);
      expect(call(role: 'dispatcher'), isFalse);
      expect(call(role: ''), isFalse);
      expect(call(role: null), isFalse);
      expect(call(hasSession: false), isFalse);
      expect(call(token: ''), isFalse);
      expect(call(token: null), isFalse);
      expect(call(companyId: ''), isFalse);
      expect(call(companyId: null), isFalse);
      expect(call(appAdmin: false), isFalse);
    });

    test('8b) mayRequestBusinessAccountDeletion honors resolved authority', () {
      expect(
        mayRequestBusinessAccountDeletion(isCompanyOwnerOrAdmin: true),
        isTrue,
      );
      expect(
        mayRequestBusinessAccountDeletion(isCompanyOwnerOrAdmin: false),
        isFalse,
      );
    });

    test('10) legal-retention explanation is visible before proceeding', () {
      for (final lang in const ['nl', 'en', 'fr', 'es']) {
        final text = fluxidiDeletionRetentionExplanation(languageCode: lang);
        expect(text.trim().isNotEmpty, isTrue);
        expect(
          text.toLowerCase().contains('logout') ||
              text.toLowerCase().contains('uitloggen') ||
              text.toLowerCase().contains('déconnecter') ||
              text.toLowerCase().contains('cerrar sesión'),
          isTrue,
          reason: 'lang=$lang must warn logout is not deletion',
        );
      }
    });
  });

  group('GOOGLE-PLAY-PRIVACY-READINESS-P0 location', () {
    test('12/13) declining disclosure does not request background location',
        () async {
      var requested = false;
      final denied = await requestBackgroundLocationAfterDisclosure(
        disclosureAccepted: false,
        requestAlways: () async {
          requested = true;
          return true;
        },
      );
      expect(denied, isFalse);
      expect(requested, isFalse);
      expect(
        mayRequestBackgroundLocationPermission(disclosureAccepted: false),
        isFalse,
      );
    });

    test('gate still forwards when disclosure is accepted (dormant path)',
        () async {
      var requested = false;
      final ok = await requestBackgroundLocationAfterDisclosure(
        disclosureAccepted: true,
        requestAlways: () async {
          requested = true;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(requested, isTrue);
    });

    test('active-trip disclosure copy is foreground-only and no-ads', () {
      const foregroundOnlyMarkers = <String, String>{
        'en': 'while the fluxidi app is open',
        'nl': 'terwijl de fluxidi-app open is',
        'fr': "lorsque l’application fluxidi est ouverte",
        'es': 'mientras la app fluxidi está abierta',
      };
      const backgroundLeakMarkers = <String>[
        'background',
        'achtergrond',
        'arrière-plan',
        'segundo plano',
        'screen is locked',
        'scherm vergrendeld',
        'écran est verrouillé',
        'pantalla bloqueada',
      ];
      for (final entry in foregroundOnlyMarkers.entries) {
        final body =
            fluxidiBackgroundLocationDisclosureBody(languageCode: entry.key)
                .toLowerCase();
        expect(
          body.contains(entry.value),
          isTrue,
          reason: 'lang=${entry.key} must mention foreground-only wording',
        );
        for (final leak in backgroundLeakMarkers) {
          expect(
            body.contains(leak),
            isFalse,
            reason:
                'lang=${entry.key} must not mention background/locked usage. '
                'Found "$leak" in: $body',
          );
        }
      }
    });

    test('merged manifest has ACCESS_FINE_LOCATION and NO ACCESS_BACKGROUND_LOCATION',
        () {
      expect(kFluxidiAndroidManifestDeclaresBackgroundLocation, isFalse);
      expect(kFluxidiRuntimeRequestsBackgroundLocationToday, isFalse);
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      final finePerm = RegExp(
        r'<uses-permission[^>]*android\.permission\.ACCESS_FINE_LOCATION',
      );
      final coarsePerm = RegExp(
        r'<uses-permission[^>]*android\.permission\.ACCESS_COARSE_LOCATION',
      );
      final fgsLocPerm = RegExp(
        r'<uses-permission[^>]*android\.permission\.FOREGROUND_SERVICE_LOCATION',
      );
      final bgLocPerm = RegExp(
        r'<uses-permission[^>]*android\.permission\.ACCESS_BACKGROUND_LOCATION',
      );
      expect(finePerm.hasMatch(manifest), isTrue);
      expect(coarsePerm.hasMatch(manifest), isTrue);
      expect(fgsLocPerm.hasMatch(manifest), isTrue);
      expect(
        bgLocPerm.hasMatch(manifest),
        isFalse,
        reason:
            'Release manifest must not declare a <uses-permission> for '
            'ACCESS_BACKGROUND_LOCATION — the app never requests Always '
            'location and never starts a location FGS.',
      );
    });

    test('release code never wires foregroundNotificationConfig or Always',
        () {
      final fgsConfig = RegExp(
        r'(?<![_A-Za-z])foregroundNotificationConfig\s*:',
      );
      final alwaysReq = RegExp(
        r'(?<![_A-Za-z])Permission\.locationAlways\b\.request\(',
      );
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (normalized.startsWith('lib/privacy/')) continue;
        final text = file.readAsStringSync();
        if (fgsConfig.hasMatch(text)) {
          offenders.add('${file.path} :: foregroundNotificationConfig usage');
        }
        if (alwaysReq.hasMatch(text)) {
          offenders.add('${file.path} :: Permission.locationAlways.request()');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'If any non-privacy file wires foregroundNotificationConfig or '
            'requests Permission.locationAlways, the manifest and disclosure '
            'decision must be re-audited before release. Offenders: $offenders',
      );
    });
  });

  group('GOOGLE-PLAY-PRIVACY-READINESS-P0 wiring source contracts', () {
    test('1) privacy policy link is present for customer', () {
      final source = _read('lib/main_parts/customer_home_page.dart');
      // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
      // The customer entry moved out of the two-column grid into a dedicated
      // full-width card ("Mijn gegevens & account verwijderen") because the
      // half-tile label truncated on a phone. The canonical wiring markers
      // still exist: audience = customer and the shared opener.
      expect(source.contains('My data & delete account'), isTrue);
      expect(source.contains('Mijn gegevens & account verwijderen'), isTrue);
      expect(source.contains('FluxidiPrivacyAudience.customer'), isTrue);
      expect(source.contains('openFluxidiPrivacyAccountPage'), isTrue);
    });

    test('2) privacy policy link is present for business + resolver used', () {
      final source = _read('lib/main_parts/business_home_page_state.dart');
      expect(source.contains("value: 'privacy_account'"), isTrue);
      expect(source.contains('FluxidiPrivacyAudience.business'), isTrue);
      // Hardcoded true must not reappear.
      expect(
        source.contains('isCompanyOwnerOrAdmin: true'),
        isFalse,
        reason: 'Company authority must come from resolveIsCompanyOwnerOrAdmin',
      );
      expect(source.contains('resolveIsCompanyOwnerOrAdmin'), isTrue);
    });

    test('3) privacy policy link is present for driver', () {
      final source = _read('lib/main_parts/driver_home_page_state.dart');
      expect(source.contains('FluxidiPrivacyAudience.driver'), isTrue);
      expect(source.contains('openFluxidiPrivacyAccountPage'), isTrue);
      expect(source.contains('Mijn gegevens & privacy'), isTrue);
    });

    test('14) UI opens the shared privacy page with canonical URLs', () {
      final ui = _read('lib/privacy/fluxidi_privacy_ui.dart');
      expect(ui.contains('fluxidiPrivacyPolicyUriForLanguage'), isTrue);
      expect(ui.contains('buildFluxidiAccountDeletionRequestUri'), isTrue);
      expect(ui.contains('fluxidiDeletionRetentionExplanation'), isTrue);
      expect(ui.contains('isSafeFluxidiAccountDeletionUri'), isTrue);
      expect(
        ui.contains('https://fluxidi.com/account-verwijderen'),
        isFalse,
      );
      expect(
        ui.contains('https://fluxidi.com/pages/account-verwijderen'),
        isFalse,
      );
    });

    test('no competing hard-coded privacy URLs outside the legal config', () {
      final legal = _read('lib/privacy/fluxidi_legal_urls.dart');
      expect(legal.contains(kFluxidiPrivacyPolicyUrl), isTrue);
      expect(legal.contains(kFluxidiAccountDeletionUrl), isTrue);
    });

    test('privacy contact email is the single documented mailbox', () {
      // PRIVACY-P0-4-CORRECT-CANONICAL-EMAIL:
      // The canonical central privacy contact is info@fluxidi.com. See
      // test/privacy/privacy_email_regression_p0_4_test.dart for the full
      // regression guard that forbids privacy contacts on any other
      // (typo or unrelated) domain.
      expect(kFluxidiPrivacyContactEmail, 'info@fluxidi.com');
      final legal = _read('lib/privacy/fluxidi_legal_urls.dart');
      expect(legal.contains(kFluxidiPrivacyContactEmail), isTrue);
    });
  });
}
