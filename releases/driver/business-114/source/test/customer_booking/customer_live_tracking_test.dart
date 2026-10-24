import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking_panel.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identity comes from the opened booking maps', () {
    final identity = customerLiveTrackingIdentityFromSources(
      bookingId: 'B1',
      maps: <Map<String, dynamic>>[
        <String, dynamic>{'tenant_id': 'T-book', 'company_id': 'C-book'},
        <String, dynamic>{'company_id': 'C-other', 'customer_id': 'cus_1'},
      ],
    );
    expect(identity?.tenantId, 'T-book');
    expect(identity?.companyId, 'C-book');
    expect(identity?.customerId, 'cus_1');
    expect(identity?.bookingId, 'B1');
  });

  test('arrived is not a tracking phase', () {
    expect(customerLivePhaseFromToken('arrived'), CustomerLivePhase.unknown);
  });

  test('missing session does not poll live', () async {
    final harness = _Harness(customerToken: () async => null);
    harness.bind();
    harness.foreground();
    await harness.drain();
    expect(harness.bootstraps, 1);
    expect(harness.liveGets, 0);
    expect(harness.uris.where((uri) => uri.path.contains('/track/')), isEmpty);
  });

  test('bootstrap without a token does not poll live', () async {
    final harness = _Harness(
      bootstrap: const CustomerLiveBootstrap(ok: false, error: 'not_assigned'),
    );
    harness.bind();
    harness.foreground();
    await harness.drain();
    expect(harness.liveGets, 0);
    expect(
      harness.controller.view.availability,
      CustomerLiveTrackingAvailability.unavailable,
    );
  });

  test('assigned shows the driver and no live position or eta', () async {
    final harness = _Harness(
      live: _snapshot(
        phase: 'assigned',
        feed: 'closed',
        driver: 'Kim',
        poll: 0,
        position: true,
        etaTarget: 'pickup',
      ),
    );
    harness.bind();
    harness.foreground();
    await harness.drain();
    final view = harness.controller.view;
    expect(view.snapshot.phase, CustomerLivePhase.assigned);
    expect(view.showLivePosition, isFalse);
    expect(view.showEta, isNull);
    expect(view.driverName, 'Kim');
    expect(harness.liveQuery('company_id'), 'C-book');
    expect(harness.liveQuery('tenant_id'), 'T-book');
    expect(harness.liveAuthorization, 'Bearer track-token');
    expect(harness.bootstrapAuthorization, 'Bearer customer-token');
  });

  test('en_route_pickup keeps backend position and pickup eta', () async {
    final harness = _Harness(
      live: _snapshot(
        phase: 'en_route_pickup',
        feed: 'live',
        poll: 10,
        position: true,
        etaTarget: 'pickup',
        seconds: 180,
      ),
    );
    harness.bind();
    harness.foreground();
    await harness.drain();
    expect(harness.controller.view.showLivePosition, isTrue);
    expect(harness.controller.view.showEta?.target, 'pickup');
    expect(harness.controller.view.showEta?.durationSeconds, 180);
    expect(harness.controller.liveGets, 1);
    await harness.elapse();
    expect(harness.controller.liveGets, 2);
  });

  test('in_progress keeps destination eta', () async {
    final harness = _Harness(
      live: _snapshot(
        phase: 'in_progress',
        feed: 'live',
        poll: 10,
        position: true,
        etaTarget: 'destination',
        seconds: 240,
      ),
    );
    harness.bind();
    harness.foreground();
    await harness.drain();
    expect(harness.controller.view.showEta?.target, 'destination');
    expect(harness.controller.view.snapshot.position?.latitude, 51.05);
  });

  test('terminal phases and 404 stop polling and clear position', () async {
    for (final phase in const ['stopped', 'completed', 'cancelled']) {
      final harness = _Harness(
        live: _snapshot(
          phase: phase,
          feed: 'closed',
          poll: 0,
          position: true,
          etaTarget: 'destination',
        ),
      );
      harness.bind();
      harness.foreground();
      await harness.drain();
      expect(harness.controller.view.showLivePosition, isFalse);
      expect(harness.controller.view.showEta, isNull);
      expect(
        harness.controller.view.availability,
        CustomerLiveTrackingAvailability.ended,
      );
      final before = harness.controller.liveGets;
      await harness.elapse();
      expect(harness.controller.liveGets, before);
    }

    final missing = _Harness(liveStatus: 404);
    missing.bind();
    missing.foreground();
    await missing.drain();
    expect(missing.controller.view.showLivePosition, isFalse);
    expect(missing.controller.view.showEta, isNull);
    final before = missing.controller.liveGets;
    await missing.elapse();
    expect(missing.controller.liveGets, before);
  });

  test('missing stale and closed feeds stay separate from the phase', () {
    for (final health in const ['missing', 'stale', 'closed']) {
      final snapshot = parseCustomerLiveSnapshot(<String, dynamic>{
        'tracking_phase': 'en_route_pickup',
        'feed': <String, dynamic>{'health': health},
        'position': <String, dynamic>{'latitude': 1, 'longitude': 2},
        'eta': <String, dynamic>{'target': 'pickup', 'duration_seconds': 90},
        'refresh': <String, dynamic>{'poll_after_seconds': 10},
      });
      expect(snapshot.phase, CustomerLivePhase.enRoutePickup);
      expect(snapshot.feed, customerLiveFeedFromToken(health));
      expect(snapshot.showPosition, isFalse);
      expect(snapshot.showEta, isNull);
    }
  });

  test('one live request at a time', () async {
    final harness = _Harness(hold: true);
    harness.bind();
    harness.foreground();
    await harness.untilSent(2);
    harness.controller.setForeground(true, rebootstrap: true);
    await Future<void>.delayed(Duration.zero);
    expect(
      harness.uris.where((uri) => uri.path == '/track/customer/live'),
      hasLength(1),
    );
    expect(harness.maxInFlight, 1);
    harness.release(
      CustomerLiveHttpResult(
        statusCode: 200,
        body: _snapshot(
          phase: 'en_route_pickup',
          feed: 'live',
          poll: 10,
          position: true,
          etaTarget: 'pickup',
        ),
      ),
    );
    await harness.drain();
    expect(harness.maxInFlight, 1);
  });

  test('errors back off before the next live poll', () async {
    final harness = _Harness(liveStatus: 500);
    harness.bind();
    harness.foreground();
    await harness.drain();
    expect(harness.controller.liveGets, 1);
    await harness.elapse();
    expect(harness.controller.liveGets, 2);
  });

  test('resume bootstraps again', () async {
    final harness = _Harness(
      live: _snapshot(phase: 'en_route_pickup', feed: 'live', poll: 10),
    );
    harness.bind();
    harness.foreground();
    await harness.drain();
    final boots = harness.controller.bootstraps;
    harness.controller.setForeground(false);
    harness.controller.setForeground(true, rebootstrap: true);
    await harness.drain();
    expect(harness.controller.bootstraps, greaterThan(boots));
  });

  testWidgets(
    'panel shows assigned without eta and live eta from the backend',
    (tester) async {
      const palette = CustomerThemePalette(
        background: Color(0xFF111111),
        surface: Color(0xFF222222),
        surfaceAlt: Color(0xFF333333),
        textPrimary: Color(0xFFFFFFFF),
        textMuted: Color(0xFFCCCCCC),
        gold: Color(0xFFFFD400),
        bronze: Color(0xFFAA8800),
        border: Color(0xFF444444),
        danger: Color(0xFFFF0000),
        success: Color(0xFF00FF00),
        shadow: Color(0xFF000000),
        isDark: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomerLiveTrackingPanel(
              language: AppLanguage.nl,
              palette: palette,
              mapToken: '',
              view: CustomerLiveTrackingView(
                availability: CustomerLiveTrackingAvailability.tracking,
                driverName: 'Kim',
                snapshot: CustomerLiveSnapshot(
                  phase: CustomerLivePhase.assigned,
                  feed: CustomerLiveFeedHealth.closed,
                  driverName: 'Kim',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Chauffeur toegewezen'), findsOneWidget);
      expect(find.byKey(kCustomerLiveTrackingEtaKey), findsNothing);
      expect(find.byKey(kCustomerLiveTrackingMapKey), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomerLiveTrackingPanel(
              language: AppLanguage.nl,
              palette: palette,
              mapToken: '',
              view: CustomerLiveTrackingView(
                availability: CustomerLiveTrackingAvailability.tracking,
                driverName: 'Kim',
                snapshot: CustomerLiveSnapshot(
                  phase: CustomerLivePhase.enRoutePickup,
                  feed: CustomerLiveFeedHealth.live,
                  driverName: 'Kim',
                  position: CustomerLivePoint(latitude: 51.05, longitude: 3.72),
                  eta: CustomerLiveEta(target: 'pickup', durationSeconds: 180),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Onderweg naar het ophaaladres'), findsOneWidget);
      expect(find.text('Aankomst ophaal over 3 min'), findsOneWidget);
      expect(find.byKey(kCustomerLiveTrackingMapKey), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomerLiveTrackingPanel(
              language: AppLanguage.nl,
              palette: palette,
              mapToken: '',
              view: CustomerLiveTrackingView(
                availability: CustomerLiveTrackingAvailability.tracking,
                snapshot: CustomerLiveSnapshot(
                  phase: CustomerLivePhase.inProgress,
                  feed: CustomerLiveFeedHealth.stale,
                  eta: CustomerLiveEta(
                    target: 'destination',
                    durationSeconds: 90,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Onderweg naar de bestemming'), findsOneWidget);
      expect(find.text('Positie is niet recent'), findsOneWidget);
      expect(find.byKey(kCustomerLiveTrackingEtaKey), findsNothing);
    },
  );
}

Map<String, dynamic> _snapshot({
  required String phase,
  required String feed,
  String driver = 'Kim',
  int poll = 10,
  bool position = false,
  String? etaTarget,
  int seconds = 120,
}) {
  return <String, dynamic>{
    'ok': true,
    'tracking_phase': phase,
    'feed': <String, dynamic>{'health': feed},
    'driver': <String, dynamic>{'display_name': driver},
    'vehicle': <String, dynamic>{'label': 'Berline', 'color': 'zwart'},
    'position': position
        ? <String, dynamic>{'latitude': 51.05, 'longitude': 3.72, 'heading': 12}
        : null,
    'eta': etaTarget == null
        ? null
        : <String, dynamic>{
            'target': etaTarget,
            'source': 'mapbox/driving-traffic',
            'duration_seconds': seconds,
          },
    'refresh': <String, dynamic>{'poll_after_seconds': poll},
  };
}

class _Job {
  _Job(this.callback);
  final void Function() callback;
  bool cancelled = false;
}

class _FakeTimer implements Timer {
  _FakeTimer(this._job);
  final _Job _job;
  @override
  void cancel() => _job.cancelled = true;
  @override
  bool get isActive => !_job.cancelled;
  @override
  int get tick => 0;
}

class _Harness {
  _Harness({
    this.bootstrap = const CustomerLiveBootstrap(
      ok: true,
      token: 'track-token',
      phase: CustomerLivePhase.assigned,
    ),
    this.live = const <String, dynamic>{},
    this.liveStatus = 200,
    this.hold = false,
    Future<String?> Function()? customerToken,
  }) : customerToken = customerToken ?? (() async => 'customer-token') {
    controller = CustomerLiveTrackingController(
      bookingBaseUrl: 'https://book.test',
      trackingBaseUrl: 'https://track.test',
      customerToken: this.customerToken,
      send: _send,
      schedule: (delay, callback) {
        final job = _Job(callback);
        jobs.add(job);
        return _FakeTimer(job);
      },
    );
  }

  final CustomerLiveBootstrap bootstrap;
  final Map<String, dynamic> live;
  final int liveStatus;
  final bool hold;
  final Future<String?> Function() customerToken;
  late final CustomerLiveTrackingController controller;
  final jobs = <_Job>[];
  final uris = <Uri>[];
  final authorizations = <String>[];
  int sent = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  Completer<CustomerLiveHttpResult>? held;

  int get bootstraps => controller.bootstraps;
  int get liveGets => controller.liveGets;

  void bind() {
    controller.bind(
      const CustomerLiveTrackingIdentity(
        tenantId: 'T-book',
        companyId: 'C-book',
        bookingId: 'B1',
        customerId: 'cus_1',
      ),
    );
  }

  void foreground({bool rebootstrap = false}) {
    controller.setForeground(true, rebootstrap: rebootstrap);
  }

  String? liveQuery(String key) {
    return uris
        .lastWhere((uri) => uri.path == '/track/customer/live')
        .queryParameters[key];
  }

  String get liveAuthorization => authorizations.last;
  String get bootstrapAuthorization => authorizations.first;

  Future<CustomerLiveHttpResult> _send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? jsonBody,
  }) async {
    sent += 1;
    inFlight += 1;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    uris.add(uri);
    authorizations.add(headers['Authorization'] ?? '');
    try {
      return await _respond(method: method, uri: uri, headers: headers);
    } finally {
      inFlight -= 1;
    }
  }

  Future<CustomerLiveHttpResult> _respond({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    if (hold && uri.path == '/track/customer/live' && held == null) {
      held = Completer<CustomerLiveHttpResult>();
      return held!.future;
    }
    if (uri.path.endsWith('/customer-tracking')) {
      return CustomerLiveHttpResult(
        statusCode: bootstrap.hasToken ? 200 : 404,
        body: <String, dynamic>{
          'ok': bootstrap.ok,
          'error': bootstrap.error,
          'tracking_phase': bootstrap.phase.name,
          'tracking_session': bootstrap.hasToken
              ? <String, dynamic>{
                  'token': bootstrap.token,
                  'token_type': 'Bearer',
                }
              : null,
        },
      );
    }
    return CustomerLiveHttpResult(statusCode: liveStatus, body: live);
  }

  void release(CustomerLiveHttpResult result) {
    held?.complete(result);
    held = null;
  }

  Future<void> drain() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> untilSent(int count) async {
    for (var i = 0; i < 20 && sent < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> elapse() async {
    final pending = jobs.where((job) => !job.cancelled).toList();
    jobs.clear();
    for (final job in pending) {
      if (!job.cancelled) job.callback();
    }
    await drain();
  }
}
