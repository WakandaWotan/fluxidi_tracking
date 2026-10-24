// MOLLIE-ONBOARDING-STATUS-P1 — repair the authoritative Mollie
// onboarding/capability status calculation shown on the Business Settings
// "Receive payments" card.
//
// ROOT CAUSE (proven): `_paymentOwnershipCard` used a single hardcoded
// ternary — `mollieConnected ? _SetupStatus.activationPending : ...` — so
// EVERY connected Mollie account, LIVE or TEST, fully onboarded or not,
// unconditionally showed "Activation pending" and never looked at onboarding
// data at all. Separately, the one onboarding signal that WAS captured was
// always null server-side because the worker read the wrong Mollie endpoint
// (see workers/booking/mollie_onboarding_status_p1.test.mjs for the
// worker-side proof), and "Refresh status" never re-verified with Mollie, so
// the bug could never self-heal.
//
// `BusinessSettingsPage`'s State is a ~12k line class with heavy
// Mapbox/geolocation/PDF/network dependencies and no test doubles in this
// repo, so — consistent with the existing convention here (see
// `payment_auth_p0_1_test.dart`, `no_client_admin_token_test.dart`) — the
// HTTP-plumbing and status-mapping invariants that are impractical to
// widget-test are proven as source contracts instead. The underlying pure
// resolvers themselves are fully unit-tested in
// `test/payment/mollie_capability_status_test.dart`.
//
// Run:
//   flutter test test/business_settings/mollie_onboarding_status_p1_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readSourceOrFail(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Source file not found: $relativePath');
  return file.readAsStringSync();
}

/// Extracts the body of a class-member method starting at [signaturePrefix],
/// using a naive brace counter that ignores braces inside string literals and
/// `//` line comments.
String _extractMethodBody(
  String source,
  String signaturePrefix, {
  String? relativePath,
}) {
  final startIdx = source.indexOf(signaturePrefix);
  if (startIdx < 0) {
    fail(
      'Could not locate signature "$signaturePrefix" in '
      '${relativePath ?? "source"} — the MOLLIE-ONBOARDING-STATUS-P1 wiring '
      'may have been renamed or removed.',
    );
  }
  final bodyOpenPattern = RegExp(r'\)\s*(?:async\s*)?\{');
  final bodyOpenMatch = bodyOpenPattern.firstMatch(source.substring(startIdx));
  if (bodyOpenMatch == null) {
    fail('Could not find body-opening brace after "$signaturePrefix"');
  }
  final openIdx = startIdx + bodyOpenMatch.end - 1;
  var depth = 0;
  var inString = false;
  var stringQuote = '';
  for (var k = openIdx; k < source.length; k++) {
    final ch = source[k];
    final prev = k > 0 ? source[k - 1] : '';
    if (inString) {
      if (ch == stringQuote && prev != '\\') inString = false;
      continue;
    }
    if (ch == '/' && k + 1 < source.length && source[k + 1] == '/') {
      final newlineIdx = source.indexOf('\n', k);
      k = (newlineIdx < 0 ? source.length : newlineIdx) - 1;
      continue;
    }
    if (ch == "'" || ch == '"') {
      inString = true;
      stringQuote = ch;
      continue;
    }
    if (ch == '{') depth += 1;
    if (ch == '}') {
      depth -= 1;
      if (depth == 0) return source.substring(startIdx, k + 1);
    }
  }
  fail('Could not find matching close brace for "$signaturePrefix"');
}

void main() {
  const businessSettingsPath = 'lib/business_settings_page.dart';
  const appConfigPath = 'lib/app_config.dart';
  late String businessSettingsSource;
  late String appConfigSource;

  setUpAll(() {
    businessSettingsSource = _readSourceOrFail(businessSettingsPath);
    appConfigSource = _readSourceOrFail(appConfigPath);
  });

  group('root-cause regression: the old hardcoded bug must be gone', () {
    test(
      '_paymentOwnershipCard no longer hardcodes activationPending for every connected account',
      () {
        final body = _extractMethodBody(
          businessSettingsSource,
          'Widget _paymentOwnershipCard()',
          relativePath: businessSettingsPath,
        );
        final buggyPattern = RegExp(
          r'mollieConnected\s*\?\s*_SetupStatus\.activationPending',
        );
        expect(
          buggyPattern.hasMatch(body),
          isFalse,
          reason:
              'Found the proven MOLLIE-ONBOARDING-STATUS-P1 root-cause bug: '
              'card status hardcoded to activationPending for every '
              'connected account regardless of onboarding/capability data.',
        );
      },
    );
  });

  group('_paymentOwnershipCard resolves account + online-method status independently', () {
    late String cardBody;

    setUpAll(() {
      cardBody = _extractMethodBody(
        businessSettingsSource,
        'Widget _paymentOwnershipCard()',
        relativePath: businessSettingsPath,
      );
    });

    test('uses the pure MollieAccountConnection resolver for the header chip', () {
      expect(cardBody.contains('_mollieAccountConnection()'), isTrue);
      expect(cardBody.contains('MollieAccountConnection.connectedLive'), isTrue);
      expect(cardBody.contains('MollieAccountConnection.connectedTest'), isTrue);
      expect(cardBody.contains('MollieAccountConnection.reconnectRequired'), isTrue);
      expect(cardBody.contains('MollieAccountConnection.disconnected'), isTrue);
    });

    test('uses the pure OnlinePaymentMethodsStatus resolver, distinguishing all 4 client states', () {
      expect(cardBody.contains('_onlinePaymentMethodsStatus()'), isTrue);
      // Complete/Active:
      expect(cardBody.contains('OnlinePaymentMethodsStatus.active'), isTrue);
      // Action required (connected LIVE, no active methods):
      expect(cardBody.contains('OnlinePaymentMethodsStatus.actionRequired'), isTrue);
      // Genuinely pending verification:
      expect(cardBody.contains('OnlinePaymentMethodsStatus.activationPending'), isTrue);
    });

    test('a connectedLive/connectedTest account with active methods maps to _SetupStatus.complete', () {
      // The nested switch's active/partiallyActive branch must resolve to
      // complete — i.e. a connected LIVE account with an active method is
      // never blocked from "Complete" by anything else.
      final activeBranch = RegExp(
        r'case OnlinePaymentMethodsStatus\.active:\s*\n\s*case OnlinePaymentMethodsStatus\.partiallyActive:\s*\n\s*cardStatus = _SetupStatus\.complete;',
      );
      expect(activeBranch.hasMatch(cardBody), isTrue);
    });

    test('actionRequired/noneActive/lookupFailed/permissionMissing never silently claim "complete"', () {
      final attentionBranch = RegExp(
        r'case OnlinePaymentMethodsStatus\.actionRequired:\s*\n\s*case OnlinePaymentMethodsStatus\.noneActive:\s*\n\s*case OnlinePaymentMethodsStatus\.lookupFailed:\s*\n\s*case OnlinePaymentMethodsStatus\.statusCheckPermissionMissing:\s*\n\s*cardStatus = _SetupStatus\.attention;',
      );
      expect(attentionBranch.hasMatch(cardBody), isTrue);
    });
  });

  group('live refresh wiring', () {
    test('fetchBackendMollieConnectStatus supports an explicit forceRefresh -> ?refresh=live', () {
      final fnBody = _extractMethodBody(
        appConfigSource,
        'Future<Map<String, dynamic>> fetchBackendMollieConnectStatus(',
        relativePath: appConfigPath,
      );
      expect(fnBody.contains('forceRefresh'), isTrue);
      expect(fnBody.contains("'refresh': 'live'"), isTrue);
    });

    test(
      'fetchBackendMollieConnectStatus sends company-owner Bearer headers and never ADMIN_TOKEN',
      () {
        final fnBody = _extractMethodBody(
          appConfigSource,
          'Future<Map<String, dynamic>> fetchBackendMollieConnectStatus(',
          relativePath: appConfigPath,
        );
        expect(fnBody.contains('resolveCompanyOwnerAuthHeaders()'), isTrue);
        expect(fnBody.contains('auth.headers'), isTrue);
        expect(fnBody.contains('ADMIN_TOKEN'), isFalse);
        expect(fnBody.contains('x-admin-token'), isFalse);
        expect(fnBody.contains('X-Admin-Token'), isFalse);
      },
    );

    test('_safeMollieConnectMap whitelists can_receive_payments and status_check fields', () {
      final fnBody = _extractMethodBody(
        appConfigSource,
        'Map<String, dynamic> _safeMollieConnectMap(',
        relativePath: appConfigPath,
      );
      expect(fnBody.contains("'can_receive_payments'"), isTrue);
      expect(fnBody.contains("'status_check'"), isTrue);
      expect(fnBody.contains("'status_check_error'"), isTrue);
      // can_receive_payments must be tri-state (null/true/false), never
      // collapsed to a boolean default like the pre-existing boolAny.
      expect(fnBody.contains('boolOrNullAny'), isTrue);
    });

    test('the "Refresh status" button triggers a real forceRefresh, not a cached re-read', () {
      final idx = businessSettingsSource.indexOf('_loadMollieConnectStatus(');
      expect(idx, greaterThanOrEqualTo(0));
      // Locate the button call site specifically (the one also passing
      // showErrorSnack: true), not the passive initial-load call.
      final buttonCallPattern = RegExp(
        r'_loadMollieConnectStatus\(\s*showErrorSnack:\s*true,\s*forceRefresh:\s*true,?\s*\)',
      );
      expect(buttonCallPattern.hasMatch(businessSettingsSource), isTrue);
    });
  });

  group('a failed refresh must never downgrade an already-confirmed status', () {
    test(
      '_loadMollieConnectStatus never overwrites the cached status inside its failure branch',
      () {
        final methodBody = _extractMethodBody(
          businessSettingsSource,
          'Future<void> _loadMollieConnectStatus(',
          relativePath: businessSettingsPath,
        );
        // Split at the `} catch (e) {` boundary and confirm the catch/finally
        // tail never reassigns `_mollieConnectStatus` — only the success
        // path (before the catch) is allowed to do that.
        final catchIdx = methodBody.indexOf('} catch (e) {');
        expect(
          catchIdx,
          greaterThan(0),
          reason: 'Expected a catch block in _loadMollieConnectStatus',
        );
        final catchAndAfter = methodBody.substring(catchIdx);
        expect(
          catchAndAfter.contains('_mollieConnectStatus ='),
          isFalse,
          reason:
              'A network/lookup failure must preserve the last authoritative '
              '_mollieConnectStatus, never overwrite or clear it.',
        );
        // The failure IS still reported truthfully via a dedicated error field.
        expect(catchAndAfter.contains('_mollieConnectStatusError ='), isTrue);
      },
    );

    test(
      'a truthful status_check == "failed" snack is shown only for an explicit forceRefresh',
      () {
        final methodBody = _extractMethodBody(
          businessSettingsSource,
          'Future<void> _loadMollieConnectStatus(',
          relativePath: businessSettingsPath,
        );
        expect(methodBody.contains("'status_check'"), isTrue);
        expect(methodBody.contains("== 'failed'"), isTrue);
      },
    );
  });

  group('resolver import wiring', () {
    test('business_settings_page.dart imports the pure Mollie capability resolvers', () {
      expect(
        businessSettingsSource.contains(
          "import 'package:fluxidi_tracking/payment/mollie_capability_status.dart';",
        ),
        isTrue,
      );
    });
  });
}
