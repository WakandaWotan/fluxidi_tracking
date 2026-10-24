import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/ride/pickup_timing_attention.dart';

void main() {
  final now = DateTime.utc(2026, 10, 3, 12), pickup = '2026-10-03T11:00:00Z';
  final record = <String, dynamic>{
    'status': 'PLANNED',
    'pickup_iso': pickup,
    'dispatch_timing_attention': {
      'reason': 'pickup_overdue',
      'leg_types': ['outbound'],
      'scheduled_pickups': {'outbound': pickup},
    },
  };
  test(
    'only unresolved missed pickup is visible, never an active or completed ride or old schedule',
    () {
      expect(hasPickupTimingAttention(record, now: now), true);
      for (final patch in [
        {'status': 'IN_PROGRESS'},
        {'status': 'NO_SHOW'},
        {
          'status': 'CANCELLED',
          'operational_legs': [
            {'leg_type': 'outbound', 'status': 'PLANNED', 'pickup_iso': pickup},
          ],
        },
        {'customer_tracking_phase': 'in_progress'},
        {'pickup_iso': '2026-10-03T13:00:00Z'},
        {
          'trip': {'started_at': pickup},
        },
      ])
        expect(
          hasPickupTimingAttention({...record, ...patch}, now: now),
          false,
        );
      expect(
        hasPickupTimingAttention(record, legType: 'return', now: now),
        false,
      );
    },
  );
  for (final lang in AppLanguage.values)
    testWidgets('planner message wraps on phone with large text ${lang.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SizedBox(
                width: 320,
                child: PickupTimingAttentionBanner(
                  record: record,
                  language: lang,
                  now: now,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(kPickupTimingAttention.of(lang)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
}
