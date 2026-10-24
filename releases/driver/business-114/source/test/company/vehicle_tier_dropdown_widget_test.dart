import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/vehicle_tier_dropdown.dart';

void main() {
  testWidgets('edit dialog can open with stored star tier without asserting', (
    tester,
  ) async {
    final model = buildVehicleTierDropdownModel(
      enabledTiers: const <({String id, String label})>[
        (id: 'comfort', label: 'Comfort'),
        (id: 'private', label: 'Private'),
        (id: 'premium', label: 'Premium'),
      ],
      storedTierId: '*',
      unknownTierLabel: (id) => id == '*' ? 'Unset (*)' : id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DropdownButtonFormField<String>(
            value: model.value,
            items: [
              for (final item in model.items)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.label),
                ),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Unset (*)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Comfort').evaluate().isNotEmpty, isTrue);
    expect(find.text('Unset (*)').evaluate().isNotEmpty, isTrue);
  });
}
