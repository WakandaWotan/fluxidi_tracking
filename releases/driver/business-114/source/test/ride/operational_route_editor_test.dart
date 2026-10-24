import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/ride/operational_route.dart';
import 'package:fluxidi_tracking/ride/operational_route_editor.dart';
import 'package:fluxidi_tracking/ride/operational_route_labels.dart';
import 'package:fluxidi_tracking/ride/operational_route_pending_io.dart';
import 'operational_route_test.dart' as fixture;

// Disk durability is exercised in operational_route_test; widget tests retain
// the same journal interface without real IO inside Flutter's fake clock.
class WidgetJournal extends OperationalPendingStore {
  final entries = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String key) async => entries[key];
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    entries[key] = Map.from(value);
  }

  @override
  Future<void> clear(String key) async {
    entries.remove(key);
  }
}

void main() {
  late WidgetJournal journal;
  setUp(() => journal = WidgetJournal());
  OperationalRouteApi api(http.Client client) => OperationalRouteApi(
    baseUrl: 'https://booking.test',
    bookingId: 'B',
    tenantId: 'T',
    companyId: 'C',
    actorId: 'D',
    headers: () => {'Authorization': 'Bearer session'},
    isCurrent: () => true,
    client: client,
    store: journal,
  );
  Future<void> render(
    WidgetTester tester,
    OperationalRouteApi service, {
    AppLanguage language = AppLanguage.nl,
    bool seed = false,
    double scale = 1,
  }) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(
            suggestions: [
              LimousinePlaceSuggestion(
                label: 'Nieuw adres',
                lat: 51.3,
                lon: 4.3,
              ),
            ],
          ),
    );
    addTearDown(lookup.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<OperationalRoute>(
                context: context,
                barrierDismissible: false,
                builder: (_) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: OperationalRouteEditor(
                    api: service,
                    language: language,
                    lookup: lookup,
                    now: () => DateTime.utc(2026, 10, 3, 11),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    // Real asynchronous file IO must complete outside fake widget time.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  http.Response read({bool seed = false}) => http.Response(
    jsonEncode({
      ...fixture.record(),
      if (seed) 'operational_route': fixture.route.toMap(),
    }),
    200,
  );
  testWidgets('typed address without a selected coordinate cannot be sent', (
    tester,
  ) async {
    var posts = 0;
    final service = api(
      MockClient((r) async {
        if (r.method == 'POST') posts++;
        return read();
      }),
    );
    await render(tester, service);
    await tester.enterText(
      find.byKey(const Key('operational_route_address')),
      'ab',
    );
    await tester.enterText(
      find.byKey(const Key('operational_route_minutes')),
      '15',
    );
    await tester.tap(find.byKey(const Key('operational_route_save')));
    await tester.pump();
    expect(
      find.text(kOperationalRouteInvalid.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(posts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'selected address sends one change; double tap and close cannot interrupt in-flight write',
    (tester) async {
      var posts = 0;
      Map<String, dynamic>? body;
      final gate = Completer<http.Response>();
      final service = api(
        MockClient((r) async {
          if (r.method == 'GET') return read();
          posts++;
          body = jsonDecode(r.body);
          return gate.future;
        }),
      );
      await render(tester, service);
      await tester.enterText(
        find.byKey(const Key('operational_route_address')),
        'Nieuw',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'limousine_address_suggestion_operational_destination_0',
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('operational_route_minutes')),
        '15',
      );
      await tester.tap(find.byKey(const Key('operational_route_save')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(posts, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('operational_route_save')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      expect(body!['destination'], {
        'address': 'Nieuw adres',
        'lat': 51.3,
        'lng': 4.3,
      });
      expect(
        DateTime.parse(body!['expected_end_iso']),
        DateTime.utc(2026, 10, 3, 11, 15),
      );
      gate.complete(fixture.confirmation(body!));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.byType(OperationalRouteEditor), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'closing after missing confirmation and reopening retries the exact saved body',
    (tester) async {
      final posted = <String>[];
      var failing = true;
      final client = MockClient((r) async {
        if (r.method == 'GET') return read(seed: true);
        posted.add(r.body);
        return failing
            ? http.Response('{}', 503)
            : fixture.confirmation(jsonDecode(r.body));
      });
      await render(tester, api(client));
      await tester.tap(find.byKey(const Key('operational_route_save')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(posted.length, 1);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('operational_route_minutes')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      failing = false;
      await render(tester, api(client));
      expect(
        find.text(kOperationalRoutePending.of(AppLanguage.nl)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('operational_route_save')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(posted.length, 2);
      expect(posted[0], posted[1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'continuous itinerary requires complete confirmation and sends ordered stop with wait and return departure',
    (tester) async {
      final stop = OperationalStop(
        address: 'Heen bestemming',
        latitude: 51.05,
        longitude: 3.72,
        waitSeconds: 600,
        notBefore: DateTime.utc(2026, 10, 3, 11, 5),
      );
      final complete = OperationalRoute(
        address: fixture.route.address,
        latitude: fixture.route.latitude,
        longitude: fixture.route.longitude,
        expectedEnd: fixture.route.expectedEnd,
        remainingRouteComplete: true,
        remainingStops: [stop],
      );
      Map<String, dynamic>? posted;
      final service = api(
        MockClient((request) async {
          if (request.method == 'GET')
            return http.Response(
              jsonEncode({
                ...fixture.record(),
                'return_enabled': true,
                'roundtrip_dispatch_mode': 'continuous_wait',
                'operational_route': complete.toMap(),
              }),
              200,
            );
          posted = jsonDecode(request.body);
          return http.Response(
            jsonEncode({
              'ok': true,
              'booking_id': 'B',
              'revision': 8,
              'operational_route': posted,
            }),
            200,
          );
        }),
      );
      await render(tester, service);
      final check = find.byKey(const Key('operational_itinerary_complete'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pump();
      await tester.tap(find.byKey(const Key('operational_route_save')));
      await tester.pump();
      expect(posted, isNull);
      expect(
        find.text(kOperationalItineraryInvalid.of(AppLanguage.nl)),
        findsOneWidget,
      );
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pump();
      await tester.tap(find.byKey(const Key('operational_route_save')));
      await tester.pumpAndSettle();
      expect(posted!['remaining_stops'], [stop.toMap()]);
      expect(posted!['remaining_route_complete'], true);
      expect(find.byType(OperationalRouteEditor), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final language in AppLanguage.values) {
    testWidgets(
      'editor labels and large-text phone/tablet layout ${language.name}',
      (tester) async {
        tester.view.physicalSize = language == AppLanguage.nl
            ? const Size(393, 851)
            : const Size(800, 1280);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await render(
          tester,
          api(
            MockClient(
              (_) async => http.Response(
                jsonEncode({
                  ...fixture.record(),
                  'return_enabled': true,
                  'operational_route': OperationalRoute(
                    address: fixture.route.address,
                    latitude: fixture.route.latitude,
                    longitude: fixture.route.longitude,
                    expectedEnd: fixture.route.expectedEnd,
                    remainingRouteComplete: true,
                    remainingStops: [
                      OperationalStop(
                        address: 'Tussenstop met een langer adres',
                        latitude: 51.05,
                        longitude: 3.72,
                        waitSeconds: 600,
                        notBefore: DateTime.utc(2026, 10, 3, 11),
                      ),
                    ],
                  ).toMap(),
                }),
                200,
              ),
            ),
          ),
          language: language,
          scale: 2,
        );
        expect(find.text(kOperationalRouteEdit.of(language)), findsOneWidget);
        expect(
          find.text(kOperationalRouteExplanation.of(language)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('operational_itinerary_complete')),
        );
        await tester.pump();
        expect(find.text(kOperationalComplete.of(language)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
