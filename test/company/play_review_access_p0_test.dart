// GOOGLE-PLAY-REVIEW-ACCESS-P0 — Flutter source contracts.
//
//   flutter test test/company/play_review_access_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GOOGLE-PLAY-REVIEW-ACCESS-P0 source contracts', () {
    late String roleEntry;
    late String appConfig;
    late String appLockGate;
    late String appLockStore;

    setUpAll(() {
      roleEntry = File('lib/main_parts/role_entry_page.dart').readAsStringSync();
      appConfig = File('lib/app_config.dart').readAsStringSync();
      appLockGate =
          File('lib/security/fluxidi_app_lock_gate_page.dart').readAsStringSync();
      appLockStore =
          File('lib/security/fluxidi_app_lock_store.dart').readAsStringSync();
    });

    test('review access API helper posts to review-access/verify only', () {
      expect(
        appConfig.contains('verifyPublicCompanyReviewAccess'),
        isTrue,
      );
      expect(
        appConfig.contains('/public/company/review-access/verify'),
        isTrue,
      );
      // Ordinary recovery endpoints remain for non-review tenants.
      expect(
        appConfig.contains('/public/company/recovery/start'),
        isTrue,
      );
      expect(
        appConfig.contains('/public/company/recovery/verify'),
        isTrue,
      );
    });

    test('Access with code UI exists and is non-prominent TextButton path', () {
      expect(roleEntry.contains('_companyReviewAccessIntent'), isTrue);
      expect(roleEntry.contains('_runCompanyReviewAccessFlow'), isTrue);
      expect(roleEntry.contains('_promptCompanyReviewAccess'), isTrue);
      expect(roleEntry.contains('Access with code'), isTrue);
      expect(roleEntry.contains('verifyPublicCompanyReviewAccess'), isTrue);
    });

    test('review auth forces CREATE NEW PIN gate like email recovery', () {
      // Recovery path already uses enforcePinGateOnEntry: true.
      expect(
        roleEntry.contains(
          'await _openVerifiedCompanySession(context, verified, true)',
        ),
        isTrue,
      );
      // Count: recovery + review-access both force the pin gate.
      final pinGateCalls = RegExp(
        r'_openVerifiedCompanySession\(\s*context,\s*verified,\s*true\s*\)',
      ).allMatches(roleEntry).length;
      expect(pinGateCalls, greaterThanOrEqualTo(2));
      expect(appLockGate.contains('setupMode'), isTrue);
      expect(appLockGate.contains('FluxidiPinUnlockPage'), isTrue);
    });

    test('review credential is not hardcoded and cannot become the local PIN', () {
      expect(roleEntry.contains('PLAY_REVIEW_ACCESS'), isFalse);
      expect(roleEntry.contains('play-review-test-access-code'), isFalse);
      // PIN store API must remain the only PIN writer; review flow must not call setPin.
      expect(roleEntry.contains('FluxidiAppLockStore'), isFalse);
      expect(roleEntry.contains('.setPin('), isFalse);
      expect(appLockStore.contains('Future<void> setPin'), isTrue);
    });

    test('no client admin / learning service tokens introduced', () {
      expect(roleEntry.contains('ADMIN_TOKEN'), isFalse);
      expect(roleEntry.contains('LEARNING_SERVICE_TOKEN'), isFalse);
      expect(
        appConfig.contains('--dart-define=ADMIN_TOKEN'),
        isFalse,
      );
    });
  });
}
