import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_host.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_controller.dart';
import 'package:fluxidi_tracking/driver/driver_ride_decision_memory.dart';

ActiveDriverSession actor(
  String driver, {
  String tenant = 'tenant',
  String token = 'token',
}) => ActiveDriverSession(
  driverId: driver,
  employeeNumber: '',
  fullName: driver,
  phone: '',
  loggedInAt: '',
  updatedAt: '',
  tenantId: tenant,
  companyId: 'company',
  assignedVehicleId: 'vehicle',
  driverSessionToken: token,
  linkMethod: 'public_driver_login',
);

http.Response offers({bool empty = false, int? pollAfterMs}) => http.Response(
  jsonEncode({
    'ok': true,
    'vehicle_id': 'vehicle',
    if (pollAfterMs != null) 'poll_after_ms': pollAfterMs,
    'offers': empty
        ? []
        : [
            {
              'offer_id': 'proposal',
              'version': 4,
              'vehicle_id': 'vehicle',
              'driver_id': 'A',
              'tenant_id': 'tenant',
              'company_id': 'company',
              'human_acceptance_required': true,
              'currency': 'EUR',
              'ack_deadline_ms': DateTime.now().millisecondsSinceEpoch + 60000,
              'pickup_address': 'Fixture pickup',
              'dropoff_address': 'Fixture destination',
            },
          ],
  }),
  200,
);

void main() {
  final alerts = <String>[];
  late DriverRideAlertController hostAlerts;
  late DriverRideDecisionMemory decisionsMemory;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    hostAlerts = DriverRideAlertController();
    decisionsMemory = DriverRideDecisionMemory();
    alerts.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fluxidi/vehicle_ride_alert'),
          (call) async {
            alerts.add(call.method);
            return null;
          },
        );
  });
  tearDown(
    () { hostAlerts.dispose(); TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fluxidi/vehicle_ride_alert'),
          null,
        ); },
  );

  Future<void> open(
    WidgetTester tester,
    ValueNotifier<ActiveDriverSession?> sessions,
    Future<http.Response> Function(http.Request) handler, {
    Future<ActiveDriverSession?> Function()? load,
    bool inbox = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverRideOfferHost(
          alertController: hostAlerts,
          decisionMemory: decisionsMemory,
          baseUrl: 'https://fixture.invalid',
          inbox: inbox,
          sessionListenable: sessions,
          loadSession: load ?? () async => sessions.value,
          clientFactory: (token, vehicle) => DriverRideOfferClient(
            baseUrl: 'https://fixture.invalid',
            token: token,
            vehicleId: vehicle,
            driverId: sessions.value?.driverId,
            tenantId: sessions.value?.tenantId,
            companyId: sessions.value?.companyId,
            client: MockClient(handler),
          ),
          child: const Scaffold(body: Text('Cockpit')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    // Drain the explicit opt-in read and serialized presentation-effect queue.
    // No real time, backend polling or additional network request is added.
    for (var i = 0; i < 6; i++) { await tester.pump(); }
  }

  testWidgets(
    'actual host displays offer before receipt and never accepts automatically',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      final requests = <String>[];
      await open(tester, sessions, (request) async {
        requests.add(request.url.path.split('/').last);
        if (request.url.path.endsWith('/offers')) return offers();
        expect(find.text('Fixture pickup'), findsOneWidget);
        return http.Response('{"ok":true}', 200);
      });
      expect(find.text('Fixture destination'), findsOneWidget);
      expect(requests.take(2), ['offers', 'ack']);
      expect(requests.where((path) => path == 'ack'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );

  for (final replacement in [
    actor('B'),
    actor('A', tenant: 'other'),
    actor('A', token: 'replacement'),
  ]) {
    testWidgets(
      'identity change ${replacement.driverId}/${replacement.tenantId}/${replacement.driverSessionToken} clears old proposal immediately',
      (tester) async {
        final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
        final bodies = <Map>[];
        await open(tester, sessions, (request) async {
          bodies.add(jsonDecode(request.body) as Map);
          return request.url.path.endsWith('/offers')
              ? offers()
              : http.Response('{"ok":true}', 200);
        });
        expect(find.text('Fixture pickup'), findsOneWidget);
        sessions.value = replacement;
        await tester.pump();
        expect(find.text('Fixture pickup'), findsNothing);
        expect(bodies.where((body) => body['visible'] == false), isNotEmpty);
        await tester.pumpWidget(const SizedBox());
        sessions.dispose();
      },
    );
  }

  testWidgets(
    'late old response after chauffeur switch is withdrawn without display or ACK',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      final pending = Completer<http.Response>();
      var acks = 0;
      var withdrawn = 0;
      await open(tester, sessions, (request) async {
        final body = jsonDecode(request.body) as Map;
        if (body['visible'] == false) {
          withdrawn++;
          return offers(empty: true);
        }
        if (request.url.path.endsWith('/ack')) {
          acks++;
          return http.Response('{"ok":true}', 200);
        }
        return pending.future;
      });
      sessions.value = actor('B');
      pending.complete(offers());
      await tester.pump();
      await tester.pump();
      expect(find.text('Fixture pickup'), findsNothing);
      expect(acks, 0);
      expect(
        withdrawn,
        greaterThanOrEqualTo(2),
      ); // includes late registration cleanup
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );

  testWidgets(
    'switch during decision revalidation cannot submit old chauffeur acceptance',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      Future<ActiveDriverSession?> Function() loader = () async =>
          sessions.value;
      var decisions = 0;
      await open(tester, sessions, (request) async {
        if (request.url.path.endsWith('/decision')) decisions++;
        return request.url.path.endsWith('/offers')
            ? offers()
            : http.Response('{"ok":true}', 200);
      }, load: () => loader());
      final pending = Completer<ActiveDriverSession?>();
      loader = () => pending.future;
      await tester.ensureVisible(find.byKey(const ValueKey('accept_ride')));
      await tester.tap(find.byKey(const ValueKey('accept_ride')));
      sessions.value = actor('B');
      pending.complete(actor('A'));
      await tester.pump();
      expect(decisions, 0);
      expect(find.text('Fixture pickup'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );

  testWidgets(
    'background hides proposal and resume retrieves still pending server offer',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      var polls = 0;
      var withdrawals = 0;
      await open(tester, sessions, (request) async {
        if ((jsonDecode(request.body) as Map)['visible'] == false) {
          withdrawals++;
          return offers(empty: true);
        }
        if (request.url.path.endsWith('/offers')) {
          polls++;
          return offers();
        }
        return http.Response('{"ok":true}', 200);
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final before = polls;
      await tester.pump(const Duration(seconds: 4));
      expect(polls, before);
      expect(withdrawals, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Fixture pickup'), findsOneWidget);
      expect(polls, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );
  testWidgets(
    'working native notification owner retains background delivery without withdrawing or ACKing',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      var refreshes = 0;
      var withdrawals = 0;
      var acks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('fluxidi/vehicle_ride_alert'),
            (call) async {
              if (call.method == 'backgroundReady') return true;
              if (call.method == 'refreshOffers') {
                refreshes++;
                return true;
              }
              return null;
            },
          );
      await open(tester, sessions, (request) async {
        if ((jsonDecode(request.body) as Map)['visible'] == false)
          withdrawals++;
        if (request.url.path.endsWith('/ack')) acks++;
        return request.url.path.endsWith('/offers')
            ? offers()
            : http.Response('{"ok":true}', 200);
      });
      final before = acks;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(withdrawals, 0);
      expect(refreshes, 1);
      expect(acks, before);
      sessions.value = actor('B');
      await tester.pump();
      expect(withdrawals, 1); // a real actor switch always retires A's lease
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );

  testWidgets(
    'inbox reports actual empty response and manual retry can recover a missed pending offer',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      var empty = true;
      await open(
        tester,
        sessions,
        (request) async => request.url.path.endsWith('/offers')
            ? offers(empty: empty)
            : http.Response('{"ok":true}', 200),
        inbox: true,
      );
      expect(find.text('Geen openstaande ritaanbiedingen.'), findsOneWidget);
      empty = false;
      await tester.tap(find.text('Vernieuwen'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Fixture pickup'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );

  testWidgets(
    'personal idle delivery follows authenticated 10s hint and manual entry stays immediate',
    (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      var calls = 0;
      await open(tester, sessions, (request) async {
        if ((jsonDecode(request.body) as Map)['visible'] != false) calls++;
        return offers(empty: true, pollAfterMs: 10000);
      }, inbox: true);
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 7));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      await tester.tap(find.text('Vernieuwen'));
      await tester.pump();
      expect(calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 4);
      await tester.pumpWidget(const SizedBox());
      sessions.dispose();
    },
  );

  testWidgets('inbox network failure is not presented as an empty inbox', (
    tester,
  ) async {
    final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
    await open(
      tester,
      sessions,
      (_) async => http.Response('{"ok":false}', 503),
      inbox: true,
    );
    expect(find.textContaining('konden niet worden opgehaald'), findsOneWidget);
    expect(find.text('Geen openstaande ritaanbiedingen.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    sessions.dispose();
  });

  for (final action in ['accept', 'decline']) {
    testWidgets('actual host $action sends one scoped decision and waits for server confirmation', (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      final decisions = <Map<String, dynamic>>[];
      var decided = false;
      await open(tester, sessions, (request) async {
        expectSync(request.headers['authorization'], 'Bearer token');
        if (request.url.path.endsWith('/offers')) return offers(empty: decided);
        if (request.url.path.endsWith('/decision')) {
          decisions.add(jsonDecode(request.body) as Map<String, dynamic>);
          decided = true;
        }
        return http.Response('{"ok":true}', 200);
      });
      expect(alerts, contains('play'));
      final button = find.byKey(ValueKey('${action}_ride'));
      await tester.ensureVisible(button);await tester.tap(button);
      await tester.pump();await tester.pump();
      expect(decisions, [{'offer_id':'proposal','version':4,'action':action}]);
      expect(find.text('Fixture pickup'), findsNothing);
      expect(alerts, contains('stop'));
      expect(find.textContaining(action == 'accept' ? 'Toewijzing wordt bevestigd' : 'Rit geweigerd'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());sessions.dispose();
    });
  }

  testWidgets('Server withdrawal stops the same global alert without an extra poller', (tester) async {
    final sessions=ValueNotifier<ActiveDriverSession?>(actor('A'));var withdrawn=false;
    await open(tester,sessions,(request)async => request.url.path.endsWith('/offers')
      ? offers(empty:withdrawn):http.Response('{"ok":true}',200));
    expect(hostAlerts.active,isTrue);expect(alerts.where((v)=>v=='play'),hasLength(1));
    withdrawn=true;await tester.pump(const Duration(seconds:11));
    for(var i=0;i<8;i++){await tester.pump();}
    expect(hostAlerts.active,isFalse);expect(alerts,contains('stop'));
    expect(find.text('Fixture pickup'),findsNothing);
    await tester.pumpWidget(const SizedBox());sessions.dispose();
  });

  testWidgets('Background clears pulse; server-verified resume does not duplicate the sound', (tester) async {
    final sessions=ValueNotifier<ActiveDriverSession?>(actor('A'));
    await open(tester,sessions,(request)async => request.url.path.endsWith('/offers')
      ? offers():http.Response('{"ok":true}',200));
    expect(hostAlerts.active,isTrue);expect(alerts.where((v)=>v=='play'),hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);await tester.pump();
    expect(hostAlerts.active,isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for(var i=0;i<10;i++){await tester.pump();}
    expect(hostAlerts.active,isTrue);expect(alerts.where((v)=>v=='play'),hasLength(1));
    await tester.pumpWidget(const SizedBox());sessions.dispose();
  });

  testWidgets('uncertain acceptance blocks opposite decision and permits only the same retry', (tester) async {
    final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
    final decisions = <String>[];
    await open(tester, sessions, (request) async {
      if (request.url.path.endsWith('/offers')) return offers();
      if (request.url.path.endsWith('/decision')) {
        decisions.add((jsonDecode(request.body) as Map)['action'] as String);
        return http.Response('{"ok":false}',503);
      }
      return http.Response('{"ok":true}',200);
    });
    final accept=find.byKey(const ValueKey('accept_ride'));
    await tester.ensureVisible(accept);await tester.tap(accept);await tester.pump();await tester.pump();
    expect(decisions,['accept']);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('decline_ride'))).onPressed,isNull);
    expect(tester.widget<FilledButton>(accept).onPressed,isNotNull);
    await tester.tap(accept);await tester.pump();await tester.pump();
    expect(decisions,['accept','accept']);
    await tester.pumpWidget(const SizedBox());sessions.dispose();
  });

  testWidgets('uncertain acceptance keeps same-choice guard after background and resume', (tester) async {
    final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
    final decisions = <String>[];
    await open(tester, sessions, (request) async {
      if (request.url.path.endsWith('/offers')) return offers();
      if (request.url.path.endsWith('/decision')) {
        decisions.add((jsonDecode(request.body) as Map)['action'] as String);
        return http.Response('{"ok":false}', 503);
      }
      return http.Response('{"ok":true}', 200);
    });
    final accept = find.byKey(const ValueKey('accept_ride'));
    await tester.ensureVisible(accept); await tester.tap(accept);
    await tester.pump(); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i=0;i<10;i++) { await tester.pump(); }
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('decline_ride'))).onPressed, isNull);
    expect(decisions, ['accept']);
    await tester.pumpWidget(const SizedBox()); sessions.dispose();
  });

  testWidgets('decision completing while backgrounded cannot reappear as a fresh acceptance', (tester) async {
    final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
    final response = Completer<http.Response>();
    var decisions = 0;
    await open(tester, sessions, (request) async {
      if (request.url.path.endsWith('/offers')) return offers(); // delayed projection/old offer response
      if (request.url.path.endsWith('/decision')) { decisions++; return response.future; }
      return http.Response('{"ok":true}', 200);
    });
    final accept = find.byKey(const ValueKey('accept_ride'));
    await tester.ensureVisible(accept); await tester.tap(accept); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    response.complete(http.Response('{"ok":true,"offer":{"state":"committing"}}', 200));
    await tester.pump(); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i=0;i<10;i++) { await tester.pump(); }
    expect(find.byKey(const ValueKey('accept_ride')), findsNothing);
    expect(decisions, 1);
    await tester.pumpWidget(const SizedBox()); sessions.dispose();
  });

  for (final confirmed in [false, true]) {
    testWidgets('cockpit company cockpit remount preserves decision; confirmed=$confirmed', (tester) async {
      final sessions = ValueNotifier<ActiveDriverSession?>(actor('A'));
      var count = 0;
      final response = Completer<http.Response>();
      Future<http.Response> handler(http.Request request) async {
        if (request.url.path.endsWith('/offers')) return offers();
        if (request.url.path.endsWith('/decision')) { count++; return response.future; }
        return http.Response('{"ok":true}', 200);
      }
      await open(tester, sessions, handler);
      final accept=find.byKey(const ValueKey('accept_ride'));
      await tester.ensureVisible(accept); await tester.tap(accept); await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Company mode'))));
      await open(tester, sessions, handler);
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('decline_ride'))).onPressed, isNull);
      response.complete(http.Response(confirmed ? '{"ok":true}' : '{"ok":false}', confirmed ? 200 : 503));
      for(var i=0;i<10;i++){await tester.pump();}
      if (confirmed) {
        expect(accept, findsNothing);
      } else {
        expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
        expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('decline_ride'))).onPressed, isNull);
      }
      expect(count, 1);
      await tester.pumpWidget(const SizedBox()); sessions.dispose();
    });
  }

  testWidgets('a genuinely new server offer version remains actionable after an earlier decision', (tester) async {
    final sessions=ValueNotifier<ActiveDriverSession?>(actor('A'));
    var version=4;
    final versions=<int>[];
    Future<http.Response> handler(http.Request request) async {
      if(request.url.path.endsWith('/offers')) {
        final body=jsonDecode(offers().body) as Map<String,dynamic>;
        (body['offers'] as List).first['version']=version;
        return http.Response(jsonEncode(body),200);
      }
      if(request.url.path.endsWith('/decision'))versions.add((jsonDecode(request.body) as Map)['version'] as int);
      return http.Response('{"ok":true}',200);
    }
    await open(tester,sessions,handler);
    final accept=find.byKey(const ValueKey('accept_ride'));
    await tester.ensureVisible(accept);await tester.tap(accept);await tester.pump();await tester.pump();
    expect(accept,findsNothing);
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Company mode'))));
    version=5;
    await open(tester,sessions,handler);
    expect(tester.widget<FilledButton>(accept).onPressed,isNotNull);
    await tester.ensureVisible(accept);await tester.tap(accept);await tester.pump();await tester.pump();
    expect(versions,[4,5]);
    await tester.pumpWidget(const SizedBox());sessions.dispose();
  });

  testWidgets('offer expiring during secure session revalidation never reaches decision POST', (tester) async {
    final sessions=ValueNotifier<ActiveDriverSession?>(actor('A'));
    Future<ActiveDriverSession?> Function() loader=() async=>sessions.value;
    var decisions=0;
    final expiry=DateTime.now().millisecondsSinceEpoch+2500;
    await open(tester,sessions,(request) async {
      if(request.url.path.endsWith('/decision')) decisions++;
      if(request.url.path.endsWith('/offers')) {
        final body=jsonDecode(offers().body) as Map<String,dynamic>;
        (body['offers'] as List).first['ack_deadline_ms']=expiry;
        return http.Response(jsonEncode(body),200);
      }
      return http.Response('{"ok":true}',200);
    },load:()=>loader());
    final pending=Completer<ActiveDriverSession?>();loader=()=>pending.future;
    final accept=find.byKey(const ValueKey('accept_ride'));
    await tester.ensureVisible(accept);await tester.tap(accept);await tester.pump();
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:2600)));
    pending.complete(actor('A'));await tester.pump();await tester.pump();
    expect(decisions,0);
    expect(find.textContaining('Dit ritvoorstel is verlopen'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());sessions.dispose();
  });
}
