import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_booking_link_page.dart';
import 'company_public_booking_link_fixtures.dart';

void main() {
  testWidgets('booking link shows the registered company slug URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingLinkPage(
          language: AppLanguage.nl,
          companyId: marioCompanyId,
          profileLoader: () async => bookingIdentity(),
          contextLoader: (_) async => bookingContext(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingLinkPageKey), findsOneWidget);
    expect(find.byKey(kCompanyBookingLinkUrlKey), findsOneWidget);
    expect(
      find.textContaining('https://booking.fluxidi.com/taxi-mario'),
      findsNWidgets(2),
    );
    expect(find.text('Kopieer link'), findsOneWidget);
    expect(find.textContaining('company_code='), findsNothing);
  });
}
