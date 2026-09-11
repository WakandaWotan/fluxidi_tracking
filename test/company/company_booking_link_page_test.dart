import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_booking_link_page.dart';

void main() {
  testWidgets('booking link shows the existing public company URL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyBookingLinkPage(
          language: AppLanguage.nl,
          profileLoader: () async => <String, dynamic>{
            'public_company_code': 'FLX-99001',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingLinkPageKey), findsOneWidget);
    expect(find.byKey(kCompanyBookingLinkUrlKey), findsOneWidget);
    expect(find.textContaining('company_code=FLX-99001'), findsOneWidget);
    expect(find.text('Link kopiëren'), findsOneWidget);
  });
}
