import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_subscription_status_page.dart';

void main() {
  testWidgets('subscription status shows the existing profile without checkout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanySubscriptionStatusPage(
          language: AppLanguage.nl,
          profileLoader: () async => <String, dynamic>{
            'plan_code': 'starter',
            'max_vehicles': 1,
            'max_drivers': 3,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanySubscriptionStatusPageKey), findsOneWidget);
    expect(find.textContaining('starter'), findsOneWidget);
    expect(find.textContaining('Voertuiglimiet: 1'), findsOneWidget);
    expect(find.textContaining('Mollie'), findsOneWidget);
    expect(find.text('Afrekenen'), findsNothing);
  });
}
