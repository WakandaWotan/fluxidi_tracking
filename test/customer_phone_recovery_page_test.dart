import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_phone_recovery_page.dart';

void main() {
  testWidgets('phone login offers New customer without a code', (tester) async {
    Object? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute<Object?>(
                    builder: (_) => const CustomerPhoneRecoveryPage(),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(CustomerPhoneRecoveryPage.newCustomerKey), findsOneWidget);
    await tester.tap(find.byKey(CustomerPhoneRecoveryPage.newCustomerKey));
    await tester.pumpAndSettle();
    expect(popped, CustomerPhoneRecoveryPage.newCustomerResult);
  });
}
