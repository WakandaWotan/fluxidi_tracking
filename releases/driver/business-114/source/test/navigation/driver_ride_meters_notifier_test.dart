import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters_notifier.dart';

// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part E — meter presentation
// notifier: publishing a fresh snapshot notifies listeners without
// requiring the enclosing State to call setState().

void main() {
  test('publish notifies listeners on distinct snapshots only', () {
    final notifier = DriverRideMetersNotifier(emptyDriverRideMetersSnapshot());
    var notifications = 0;
    notifier.addListener(() => notifications += 1);

    // Same-value publish is deduplicated.
    notifier.publish(emptyDriverRideMetersSnapshot());
    expect(notifications, 0);

    notifier.publish(const DriverRideMetersSnapshot(
      fareText: '€ 3,20',
      distanceTravelledText: '1.2 km',
      rideDurationText: '00:34',
      waitingTimeText: '00:00',
      statusText: 'Rit actief',
    ));
    expect(notifications, 1);

    // Same-value again → still no extra notify.
    notifier.publish(const DriverRideMetersSnapshot(
      fareText: '€ 3,20',
      distanceTravelledText: '1.2 km',
      rideDurationText: '00:34',
      waitingTimeText: '00:00',
      statusText: 'Rit actief',
    ));
    expect(notifications, 1);
  });

  testWidgets('ValueListenableBuilder repaints only its own subtree',
      (tester) async {
    final notifier = DriverRideMetersNotifier(emptyDriverRideMetersSnapshot());
    final parentBuilds = ValueNotifier<int>(0);
    final meterBuilds = ValueNotifier<int>(0);

    Widget parent() {
      return MaterialApp(
        home: Builder(
          builder: (_) {
            parentBuilds.value += 1;
            return Column(
              children: [
                const KeyedSubtree(
                  key: ValueKey('map_placeholder'),
                  child: SizedBox(
                    width: 10,
                    height: 10,
                    child: ColoredBox(color: Color(0xFF000000)),
                  ),
                ),
                ValueListenableBuilder<DriverRideMetersSnapshot>(
                  valueListenable: notifier,
                  builder: (context, snap, __) {
                    meterBuilds.value += 1;
                    return Text('${snap.fareText}|${snap.distanceTravelledText}');
                  },
                ),
              ],
            );
          },
        ),
      );
    }

    await tester.pumpWidget(parent());
    final parentAfterFirst = parentBuilds.value;
    final meterAfterFirst = meterBuilds.value;

    notifier.publish(const DriverRideMetersSnapshot(
      fareText: '€ 5,60',
      distanceTravelledText: '2.4 km',
      rideDurationText: '01:10',
      waitingTimeText: '00:00',
      statusText: 'Rit actief',
    ));
    await tester.pump();

    expect(parentBuilds.value, parentAfterFirst,
        reason: 'Parent Builder must NOT rebuild on meter tick.');
    expect(meterBuilds.value, greaterThan(meterAfterFirst),
        reason: 'ValueListenableBuilder subtree must rebuild on publish.');
  });
}
