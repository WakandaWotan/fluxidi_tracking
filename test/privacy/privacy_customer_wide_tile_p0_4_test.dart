// PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4
//
// The customer home page must render:
//   * exactly four "half" quick-action tiles in the two-column grid
//     (bookings, details, taxi, radar) on phone portrait — no privacy tile
//     inside the grid;
//   * one dedicated full-width Fluxidi-styled card BELOW the grid that
//     opens the shared privacy / delete-account flow with
//     FluxidiPrivacyAudience.customer;
//   * no owner/admin authority, no sessionDriverId, no business/driver copy.
//
// The card labels per language must be exactly:
//   NL: Mijn gegevens & account verwijderen
//   EN: My data & delete account
//   FR: Mes données & supprimer le compte
//   ES: Mis datos y eliminar la cuenta
//
// Run:
//   flutter test test/privacy/privacy_customer_wide_tile_p0_4_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _kSource = 'lib/main_parts/customer_home_page.dart';

String _readSource() => File(_kSource).readAsStringSync();

/// Returns the substring of [source] between the first occurrence of
/// `_customerQuickActionGrid(` (inside the build) and the matching closing
/// `);` at the same depth. Falls back to a wide window if depth-tracking
/// is impractical.
String _actionsListWindow(String source) {
  // The `actions` list in _customerQuickActionGrid begins with:
  //   final actions = <({IconData icon, String label, VoidCallback onTap})>[
  // and ends at the matching closing "];\n". We slice that window to prove
  // no privacy tile is inside it.
  final startMarker =
      "final actions = <({IconData icon, String label, VoidCallback onTap})>[";
  final startIdx = source.indexOf(startMarker);
  expect(startIdx, isNonNegative,
      reason: 'Could not locate the quick-action list in $_kSource');
  final endIdx = source.indexOf('];', startIdx);
  expect(endIdx, isNonNegative,
      reason: 'Could not locate the end of the quick-action list');
  return source.substring(startIdx, endIdx);
}

void main() {
  group('PRIVACY-P0-4 customer quick-action grid keeps exactly 4 tiles', () {
    test('grid contains bookings, details, taxi, radar (in this order)', () {
      final source = _readSource();
      final window = _actionsListWindow(source);
      // The four canonical customer quick-actions must all appear inside
      // the grid definition.
      expect(window.contains('Icons.receipt_long_outlined'), isTrue,
          reason: 'Missing "Mijn boekingen" tile in the grid');
      expect(window.contains('Icons.person_outline_rounded'), isTrue,
          reason: 'Missing "Mijn gegevens" tile in the grid');
      expect(window.contains('Icons.local_taxi_outlined'), isTrue,
          reason: 'Missing "Taxi in de buurt" tile in the grid');
      expect(window.contains('Icons.app_registration_outlined'), isTrue,
          reason: 'Missing "Regio Radar" tile in the grid');

      // Ordering: bookings → details → taxi → radar.
      final orderBookings = window.indexOf('Icons.receipt_long_outlined');
      final orderDetails = window.indexOf('Icons.person_outline_rounded');
      final orderTaxi = window.indexOf('Icons.local_taxi_outlined');
      final orderRadar = window.indexOf('Icons.app_registration_outlined');
      expect(orderBookings < orderDetails, isTrue);
      expect(orderDetails < orderTaxi, isTrue);
      expect(orderTaxi < orderRadar, isTrue);
    });

    test('grid does NOT contain a privacy tile or old "Mijn gegevens & '
        'privacy" label', () {
      final source = _readSource();
      final window = _actionsListWindow(source);
      // Privacy tile has been moved out of the grid into a dedicated
      // full-width card below.
      expect(
        window.contains('Icons.privacy_tip_outlined'),
        isFalse,
        reason:
            'The privacy tile must not appear inside the quick-action grid.',
      );
      expect(
        window.contains('openFluxidiPrivacyAccountPage'),
        isFalse,
        reason:
            'The privacy opener must not be wired inside the quick-action '
            'grid — the full-width card below the grid owns it.',
      );
      expect(
        window.contains('Mijn gegevens & privacy'),
        isFalse,
        reason:
            'The old customer half-tile label must not appear inside the '
            'quick-action grid.',
      );
    });
  });

  group('PRIVACY-P0-4 dedicated full-width privacy/delete card', () {
    test('a full-width privacy/delete card widget function is defined', () {
      final source = _readSource();
      expect(source.contains('_customerPrivacyDeleteWideCard'), isTrue,
          reason:
              'A dedicated full-width customer privacy/delete card widget '
              'function must be defined.');
      // The card is invoked from the customer home build.
      expect(source.contains('_customerPrivacyDeleteWideCard(context)'),
          isTrue);
    });

    test('card labels match the required NL/EN/FR/ES copy exactly', () {
      final source = _readSource();
      expect(source.contains('Mijn gegevens & account verwijderen'), isTrue);
      expect(source.contains('My data & delete account'), isTrue);
      expect(source.contains('Mes données & supprimer le compte'), isTrue);
      expect(source.contains('Mis datos y eliminar la cuenta'), isTrue);
    });

    test('card uses Icons.privacy_tip_outlined', () {
      final source = _readSource();
      // The only remaining Icons.privacy_tip_outlined in the customer file
      // must be inside the full-width card body.
      final cardStart = source.indexOf('_customerPrivacyDeleteWideCard');
      expect(cardStart, isNonNegative);
      final cardBody = source.substring(cardStart);
      expect(cardBody.contains('Icons.privacy_tip_outlined'), isTrue,
          reason: 'Full-width privacy card must use privacy_tip_outlined');
    });

    test('card stretches to full width via SizedBox(width: double.infinity)',
        () {
      final source = _readSource();
      final cardStart = source.indexOf('_customerPrivacyDeleteWideCard');
      // Look forward for the SizedBox in the same function body.
      final cardWindow = source.substring(cardStart, cardStart + 3000);
      expect(cardWindow.contains('SizedBox(\n      width: double.infinity'),
          isTrue,
          reason:
              'The full-width privacy card must be wrapped in SizedBox(width: '
              'double.infinity) so it uses the full grid content width.');
    });

    test('card opens FluxidiPrivacyAudience.customer via the shared opener',
        () {
      final source = _readSource();
      final cardStart = source.indexOf('_customerPrivacyDeleteWideCard');
      final cardWindow = source.substring(cardStart, cardStart + 3000);
      expect(cardWindow.contains('openFluxidiPrivacyAccountPage'), isTrue);
      expect(cardWindow.contains('FluxidiPrivacyAudience.customer'), isTrue);
      // Customer entry must never pass owner/admin or driver session.
      expect(
        cardWindow.contains('isCompanyOwnerOrAdmin'),
        isFalse,
        reason: 'Customer card must not pass isCompanyOwnerOrAdmin.',
      );
      expect(
        cardWindow.contains('sessionDriverId'),
        isFalse,
        reason: 'Customer card must not pass sessionDriverId.',
      );
      // Not destructive red — must NOT reference colorScheme.error or a raw
      // red color; the card only opens the flow, it does not delete.
      expect(
        cardWindow.contains('colorScheme.error'),
        isFalse,
        reason:
            'The customer privacy card must not be destructive red — it '
            'opens the privacy/account page, it does not delete anything.',
      );
    });

    test('card is placed BELOW the quick-action grid in the build tree', () {
      final source = _readSource();
      // Use the actual call site (indented invocation inside the build) so
      // we do not accidentally match the widget's function definition,
      // which comes first in source order.
      const gridCallMarker =
          '_customerQuickActionGrid(\n                        context,';
      const cardCallMarker = '_customerPrivacyDeleteWideCard(context)';
      final gridCallIdx = source.indexOf(gridCallMarker);
      final cardCallIdx = source.indexOf(cardCallMarker);
      expect(gridCallIdx, isNonNegative,
          reason: 'Could not locate the grid call site.');
      expect(cardCallIdx, isNonNegative,
          reason: 'Could not locate the wide-card call site.');
      expect(cardCallIdx > gridCallIdx, isTrue,
          reason:
              'The full-width privacy card must be rendered under (i.e. '
              'after in source) the quick-action grid.');
    });
  });

  group('PRIVACY-P0-4 customer entry never leaks business/driver copy', () {
    test('customer entry uses only FluxidiPrivacyAudience.customer', () {
      final source = _readSource();
      // Customer home file must not reference other audiences at all —
      // business and driver flows are wired from their own home pages.
      expect(
        source.contains('FluxidiPrivacyAudience.business'),
        isFalse,
        reason:
            'The customer home page must not reference the business '
            'privacy audience.',
      );
      expect(
        source.contains('FluxidiPrivacyAudience.driver'),
        isFalse,
        reason:
            'The customer home page must not reference the driver '
            'privacy audience.',
      );
    });
  });
}
