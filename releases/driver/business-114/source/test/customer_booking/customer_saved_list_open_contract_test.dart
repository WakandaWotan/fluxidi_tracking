import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  late String savedPage;
  late String shell;

  setUpAll(() {
    savedPage = _read('lib/main_parts/customer_saved_bookings_page.dart');
    shell = _read(
      'apps/fluxidi_customer/lib/screens/customer_shell_screen.dart',
    );
  });

  test('list open shows local bookings before server refresh', () {
    expect(savedPage, contains('phase=first_visible source=local'));
    expect(savedPage, contains('_bootstrapCustomerSessionAndMergeBookings'));
    final openIdx = savedPage.indexOf('Future<void> _openSavedBookings');
    final firstVisibleIdx = savedPage.indexOf('phase=first_visible');
    final bootstrapIdx = savedPage.indexOf(
      "reason: 'customer_saved_bookings'",
    );
    expect(openIdx, greaterThan(0));
    expect(firstVisibleIdx, greaterThan(openIdx));
    expect(bootstrapIdx, greaterThan(firstVisibleIdx));
  });

  test('list open does not wait for per-booking GET or trip overlay', () {
    final openStart = savedPage.indexOf('Future<void> _openSavedBookings');
    final openEnd = savedPage.indexOf(
      'Future<({int attempted, int refreshed, int unauthorized})>',
      openStart,
    );
    final openBody = savedPage.substring(openStart, openEnd);
    expect(openBody, isNot(contains('_overlayAuthoritativeSavedBookings')));
    expect(openBody, isNot(contains('_buildPaymentOverlayForBookings')));
    expect(openBody, isNot(contains('_customerCanonicalBookingGetUri')));
    expect(savedPage, contains('_customerCanonicalBookingGetUri'));
    expect(savedPage, contains('_customerSessionBearerHeaders'));
  });

  test('failed refresh keeps the last visible bookings', () {
    expect(
      savedPage,
      contains('De laatst bekende boekingen blijven zichtbaar'),
    );
    expect(savedPage, contains('_showingLocalCache = true'));
  });

  test('the customer shell keeps Mijn boekingen mounted', () {
    expect(shell, contains('const CustomerSavedBookingsPage()'));
    expect(shell, isNot(contains('_index == 1')));
  });
}
