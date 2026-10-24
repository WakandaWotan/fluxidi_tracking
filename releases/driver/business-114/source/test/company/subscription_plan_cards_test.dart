import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/subscription_plan_cards.dart';

void main() {
  for (final language in ['nl', 'en', 'fr', 'es']) {
    for (final width in [360.0, 900.0]) {
      testWidgets(
        'plan comparison $language at $width remains readable at enlarged text',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(1.5),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: SubscriptionPlanCards(
                      languageCode: language,
                      accent: Colors.amber,
                      textColor: Colors.white,
                      secondaryTextColor: Colors.white70,
                      currentPlanCode: 'smart',
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('€69'), findsOneWidget);
          expect(find.text('€89'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('subscription_plan_smart')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          // Comparing plans must never launch a checkout or charge an account.
          expect(find.byType(ElevatedButton), findsNothing);
        },
      );
    }
  }
}
