import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_stable_vehicle_space.dart';

void main() {
  testWidgets('shorter and longer vehicle lists preserve the form viewport', (
    tester,
  ) async {
    final formScroll = ScrollController();
    addTearDown(formScroll.dispose);
    var retain = false;
    var vehiclesHeight = 400.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SingleChildScrollView(
                controller: formScroll,
                child: Column(
                  children: [
                    const SizedBox(height: 700),
                    CustomerBookingStableVehicleSpace(
                      key: const ValueKey('vehicles'),
                      retain: retain,
                      child: SizedBox(
                        height: vehiclesHeight,
                        child: const Text('Vehicles'),
                      ),
                    ),
                    const SizedBox(key: ValueKey('counter'), height: 50),
                    const SizedBox(height: 700),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    formScroll.jumpTo(900);
    await tester.pump();
    final top = tester.getTopLeft(find.byKey(const ValueKey('counter'))).dy;
    for (final height in [50.0, 1200.0, 20.0, 800.0, 400.0]) {
      update(() {
        retain = true;
        vehiclesHeight = height;
      });
      await tester.pump();
      expect(formScroll.offset, 900);
      expect(tester.getTopLeft(find.byKey(const ValueKey('counter'))).dy, top);
    }
  });
  testWidgets(
    'pending capacity refresh keeps old cards visible but not selectable',
    (tester) async {
      var updating = false;
      var retain = false;
      var label = 'Old car';
      var taps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return CustomerBookingStableVehicleSpace(
                  retain: retain,
                  updating: updating,
                  child: SizedBox(
                    height: 200,
                    child: TextButton(
                      onPressed: () => taps++,
                      child: Text(label),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      update(() {
        retain = true;
        updating = true;
        label = 'New car';
      });
      await tester.pump();
      expect(find.text('Old car'), findsOneWidget);
      expect(find.text('New car'), findsNothing);
      await tester.tap(find.text('Old car'), warnIfMissed: false);
      expect(taps, 0);
      update(() {
        updating = false;
      });
      await tester.pump();
      expect(find.text('New car'), findsOneWidget);
      await tester.tap(find.text('New car'));
      expect(taps, 1);
    },
  );
}
