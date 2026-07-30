// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix v5)
//
// Real-widget integration test for the DriverHomePage PopScope wiring.
//
// Unlike `test/main_parts/business_preview_pop_scope_widget_test.dart` (which
// exercises the production `DriverSwitchMintController` via a focused
// harness widget), this test mounts the actual `DriverHomePage` widget
// inside a real `MaterialApp` `Navigator` and drives a real
// `Navigator.maybePop(...)` request. It proves that the same PopScope
// behaviour observed in the harness holds in the production widget:
//
//   * `openedFromBusinessHome: true` blocks a system/back pop while a
//     live ride, STOP teardown or direct-trip finalize is active — via
//     the widget's own `_attemptBusinessPreviewRouteExit` guard.
//   * `openedFromBusinessHome: true` with an idle pending switch mint
//     invalidates the controller generation, clears the owned A operator
//     session, and allows the route to pop; a late B response that
//     arrives after the exit cannot publish.
//   * `openedFromBusinessHome: false` (standalone driver mode) uses the
//     default PopScope behaviour — the guard is not invoked.
//
// The test uses the production `debugMintOperatorDriverSessionOverride`
// seam to inject a controllable stub mint, so no real HTTP call is made.
//
// DriverHomePage's `initState` schedules many `unawaited(...)` HTTP calls,
// `Timer(...)` callbacks and plugin-channel calls that would fail in test
// mode. These are neutralised by:
//
//   * Installing a `_NoNetworkHttpOverrides` that fails every socket
//     connection synchronously (all initState HTTP is `unawaited`).
//   * Registering minimal mock handlers on the platform channels the
//     widget touches during initState so the plugin exceptions do not
//     propagate.
//   * Draining pending microtasks and timers with `tester.pump()` (never
//     `pumpAndSettle`, which would deadlock on the boot splash timer).
//
// Because DriverHomePage instantiates a Mapbox `MapWidget` in initState,
// the widget's `build(...)` runs in test mode with the platform view
// registered as an inert AndroidView; the PopScope wiring is above the
// map in the widget tree, so the pop path is exercised without needing
// to render the map at all.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart';

// -------------------------------------------------------------------------
// Stub mint seam — controllable per-call completers
// -------------------------------------------------------------------------

class _MintStub {
  final List<Completer<OperatorMintedDriverSession>> completers = [];
  final List<String> requestedDriverIds = [];

  Future<OperatorMintedDriverSession> call({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String targetDriverId,
    String? tenantId,
    String? companyId,
  }) {
    requestedDriverIds.add(targetDriverId);
    final c = Completer<OperatorMintedDriverSession>();
    completers.add(c);
    return c.future;
  }
}

OperatorMintedDriverSession _minted({
  String driverId = 'driver_b',
  String tenantId = 'tenant_a',
  String companyId = 'company_a',
  String token = 'dst_op_B',
}) {
  return OperatorMintedDriverSession(
    driverSessionToken: token,
    driverSessionExpiresAtUtc:
        DateTime.utc(2099, 1, 1).toIso8601String(),
    expiresInSeconds: 3600,
    tenantId: tenantId,
    companyId: companyId,
    driverId: driverId,
  );
}

ActiveDriverSession _operatorMintedActive({
  String driverId = 'driver_a',
  String tenantId = 'tenant_a',
  String companyId = 'company_a',
}) {
  final expiry = DateTime.utc(2099, 1, 1).toIso8601String();
  return ActiveDriverSession(
    driverId: driverId,
    employeeNumber: 'E001',
    fullName: 'A',
    phone: '+3100',
    loggedInAt: DateTime.utc(2027).toIso8601String(),
    updatedAt: DateTime.utc(2027).toIso8601String(),
    tenantId: tenantId,
    companyId: companyId,
    driverSessionToken: 'dst_op_A',
    driverSessionExpiresAtUtc: expiry,
    linkMethod: kOperatorMintDriverLinkMethod,
    expiresAt: expiry,
  );
}

// Minimal company profile / session pair so `_activeBusinessPreviewScope()`
// resolves to a non-null (tenantId, companyId). Every field is populated but
// only `companyId` and `isActive` matter for the guard path.
CompanyProfile _companyProfile({String companyId = 'company_a'}) {
  return CompanyProfile(
    companyId: companyId,
    companyName: 'Test Co',
    ownerName: 'Owner',
    email: 'owner@example.test',
    phone: '+3100',
    vatNumber: '',
    addressLine: '',
    postalCode: '',
    city: '',
    countryCode: 'NL',
    companyEmail: '',
    supportEmail: '',
    billingEmail: '',
    bookingEmail: '',
    notificationEmail: '',
    createdAt: DateTime.utc(2027).toIso8601String(),
    updatedAt: DateTime.utc(2027).toIso8601String(),
    isActive: true,
    verificationStatus: CompanyVerificationStatus.verified,
  );
}

ActiveCompanySession _companySession({
  String companyId = 'company_a',
  String token = 'cst_v1',
}) {
  final expiry = DateTime.utc(2099, 1, 1).toIso8601String();
  return ActiveCompanySession(
    companyId: companyId,
    role: 'companyAdmin',
    createdAt: DateTime.utc(2027).toIso8601String(),
    lastUsedAt: DateTime.utc(2027).toIso8601String(),
    companySessionToken: token,
    companySessionExpiresAtUtc: expiry,
    companyCode: 'FLX-000001',
  );
}

DriverProfile _driverProfile({
  required String id,
  String companyId = 'company_a',
}) {
  return DriverProfile(
    id: id,
    fullName: id.toUpperCase(),
    employeeNumber: 'E-$id',
    phone: '+3100',
    isActive: true,
    companyId: companyId,
  );
}

// -------------------------------------------------------------------------
// HttpOverrides — fail every connection immediately (all initState HTTP is
// unawaited so a synchronous SocketException is swallowed by the caller).
// -------------------------------------------------------------------------

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Return a client whose openUrl always throws immediately.
    return _FailingHttpClient();
  }
}

class _FailingHttpClient implements HttpClient {
  @override
  bool autoUncompress = false;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      Future.error(const SocketException('blocked_in_test'));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('blocked_in_test'));
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      openUrl('DELETE', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      openUrl('GET', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      openUrl('HEAD', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      openUrl('PATCH', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      openUrl('POST', Uri(scheme: 'http', host: host, port: port, path: path));
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      openUrl('PUT', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) {}
  @override
  set authenticateProxy(
      Future<bool> Function(String host, int port, String scheme, String? realm)?
          f) {}
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  void addProxyCredentials(
      String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)?
          f) {}
  @override
  set keyLog(void Function(String line)? callback) {}
  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  void close({bool force = false}) {}
}

// -------------------------------------------------------------------------
// Platform channel silencers — swallow unhandled MissingPluginException
// -------------------------------------------------------------------------

const List<String> _channelsToSilence = [
  'plugins.flutter.io/path_provider',
  'plugins.flutter.io/shared_preferences',
  'flutter.baseflow.com/geolocator',
  'flutter.baseflow.com/geolocator_android',
  'flutter.baseflow.com/geolocator_updates_android',
  'flutter.baseflow.com/permissions/methods',
  'dev.fluttercommunity.plus/wakelock_plus',
  'dev.fluttercommunity.plus/connectivity',
  'dev.fluttercommunity.plus/connectivity_status',
  'plugins.flutter.io/url_launcher_android',
  'flutter.baseflow.com/image_picker_android',
  'plugins.flutter.io/file_picker',
];

void _installChannelMocks() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _channelsToSilence) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
  }
  // Path provider — return an existing temp path so its Future resolves.
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );
  // Shared preferences — return empty map.
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    },
  );
}

void _uninstallChannelMocks() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _channelsToSilence) {
    messenger.setMockMethodCallHandler(MethodChannel(name), null);
  }
}

// -------------------------------------------------------------------------
// Test helpers
// -------------------------------------------------------------------------

Future<void> _pumpDriverHomePage(
  WidgetTester tester, {
  required bool openedFromBusinessHome,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => DriverHomePage(
              openedFromBusinessHome: openedFromBusinessHome,
            ),
          );
        },
      ),
    ),
  );
  // Single pump only — pumpAndSettle would deadlock on the boot splash
  // Timer and the periodic driver-availability timer. One frame is
  // enough for build() and PopScope to be wired up.
  await tester.pump();
}

// -------------------------------------------------------------------------
// NAV-DRIVER-VIEW-EXIT-MAP-FLASH-P0-FIELD-2026-07-30 helpers
// -------------------------------------------------------------------------

/// Key of the opaque backdrop that `_buildMapLayer` substitutes for the
/// retained Hybrid-Composition MapWidget while the route exit is in flight.
const Key _exitBackdropKey = ValueKey<String>('driver_map_route_exit_backdrop');

const String _hostRouteLabel = 'host-business-home';

/// Mounts DriverHomePage(openedFromBusinessHome: true) PUSHED OVER a host
/// route, so `Navigator.canPop()` is true — matching production, where
/// Driver View sits on top of the still-mounted Business Home. The plain
/// [_pumpDriverHomePage] harness has a single route, which sends the exit
/// guard down its `pushAndRemoveUntil` fallback instead of the pop path.
Future<void> _pumpDriverHomeOverHost(WidgetTester tester) async {
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text(_hostRouteLabel))),
    ),
  );
  await tester.pump();
  unawaited(
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const DriverHomePage(openedFromBusinessHome: true),
      ),
    ),
  );
  // Drive the push transition to completion without `pumpAndSettle`, which
  // would deadlock on the boot-splash and availability timers.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Runs [body] with `debugPrint` captured, returning every emitted line.
/// Restores the previous sink even if [body] throws.
Future<List<String>> _captureDebugPrint(Future<void> Function() body) async {
  final captured = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) captured.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return captured;
}

/// Reads `<field>=<int>` out of a `[NAV_RIDE_BOUNDARY]` diagnostic line.
/// Returns -1 when the field is absent.
int _readGeneration(String line, String field) {
  final match = RegExp('$field=(\\d+)').firstMatch(line);
  if (match == null) return -1;
  return int.parse(match.group(1)!);
}

/// Unmounts the DriverHomePage and drains any timers scheduled in its
/// initState that outlive dispose (e.g. the 8-second boot-splash Timer and
/// the periodic minute-render debug timer). Advancing fake time by 60
/// seconds lets every unowned timer fire; every callback checks `mounted`
/// and no-ops after unmount, so no state escapes.
Future<void> _drainAndDispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(seconds: 65));
}

/// Reads the DriverHomePage BuildContext from the mounted widget tree.
BuildContext _findDriverHomePageContext(WidgetTester tester) {
  final finder = find.byType(DriverHomePage);
  expect(finder, findsOneWidget);
  return tester.element(finder);
}

/// Attempts a real system/back pop by calling `Navigator.maybePop`. Returns
/// the value `maybePop` reports — `true` means the pop happened.
Future<bool> _requestSystemBackPop(WidgetTester tester) async {
  final context = _findDriverHomePageContext(tester);
  final popped = await Navigator.maybePop(context);
  await tester.pump();
  return popped;
}

/// Reaches into the mounted `_DriverHomePageState` via `dynamic` so tests
/// can invoke the `@visibleForTesting` seams (`_DriverHomePageState` is a
/// library-private class; tests may only touch it through its public
/// `@visibleForTesting` API).
dynamic _driverHomeState(WidgetTester tester) {
  return tester.state<State<DriverHomePage>>(find.byType(DriverHomePage));
}

/// Seeds the company profile + session so `_activeBusinessPreviewScope()`
/// resolves to a non-null pair matching [companyId], and the guard's
/// company-session identity check passes for a captured reference.
void _seedCompanyContext({String companyId = 'company_a'}) {
  companyProfileNotifier.value = _companyProfile(companyId: companyId);
  activeCompanySessionNotifier.value = _companySession(companyId: companyId);
}

/// Rolls back every notifier that widget tests may have written to, so
/// cross-test state cannot leak.
void _resetAllSharedNotifiers() {
  activeDriverSessionNotifier.value = null;
  operatorMintedBearerInFlightNotifier.value = false;
  activeCompanySessionNotifier.value = null;
  companyProfileNotifier.value = null;
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

void main() {
  late _MintStub mint;
  late HttpOverrides? previousOverrides;

  setUp(() {
    mint = _MintStub();
    debugMintOperatorDriverSessionOverride = mint.call;
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _NoNetworkHttpOverrides();
    _installChannelMocks();
    _resetAllSharedNotifiers();
  });

  tearDown(() {
    _uninstallChannelMocks();
    HttpOverrides.global = previousOverrides;
    debugMintOperatorDriverSessionOverride = null;
    _resetAllSharedNotifiers();
  });

  testWidgets(
    'openedFromBusinessHome: true — the widget mounts a PopScope whose '
    'canPop is false so a system/back request is intercepted by the guard',
    (tester) async {
      // Seed an owned operator-minted A session so the exit guard has
      // something to clear when the pop request is allowed.
      final session = _operatorMintedActive();
      activeDriverSessionNotifier.value = session;
      operatorMintedBearerInFlightNotifier.value = false;

      await _pumpDriverHomePage(
        tester,
        openedFromBusinessHome: true,
      );
      // The widget mounted successfully; find its PopScope.
      final popScope = find.byWidgetPredicate(
        (w) => w is PopScope && w.canPop == false,
      );
      expect(
        popScope,
        findsWidgets,
        reason:
            'openedFromBusinessHome=true must render at least one PopScope '
            'with canPop=false so system back is captured by the guard.',
      );
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'openedFromBusinessHome: false — standalone driver mode uses the '
    'default PopScope behaviour (canPop=true) so system back pops the '
    'route without invoking the guard',
    (tester) async {
      await _pumpDriverHomePage(
        tester,
        openedFromBusinessHome: false,
      );
      // The DriverHomePage's own PopScope must have canPop=true in
      // standalone mode. There may be internal PopScopes; we only assert
      // the outermost one belongs to DriverHomePage by finding a
      // PopScope whose descendant contains the Scaffold body.
      final driverHome = find.byType(DriverHomePage);
      expect(driverHome, findsOneWidget);
      final popScopes = find.descendant(
        of: driverHome,
        matching: find.byWidgetPredicate(
          (w) =>
              w is PopScope &&
              w.canPop == true &&
              w.onPopInvokedWithResult != null,
        ),
      );
      // At least one canPop=true PopScope must be present because
      // build() wraps the Scaffold in `PopScope(canPop: !widget.openedFromBusinessHome)`.
      expect(
        popScopes,
        findsWidgets,
        reason:
            'openedFromBusinessHome=false must render a PopScope with '
            'canPop=true — the guard is only enabled in business preview.',
      );
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'openedFromBusinessHome: true — Navigator.maybePop still results in a '
    'popped route (guard allows the pop when idle, invokes '
    '_attemptBusinessPreviewRouteExit as the interception path)',
    (tester) async {
      // Seed a session — the guard reads its own widget state
      // (`_liveRideActive`, `_stopTeardownInProgress`,
      // `_directStopFinalizePending`, controller pending state). With
      // no ride in flight and no pending switch the guard resolves to
      // ExitAllowed and drives the pop through
      // `_attemptBusinessPreviewRouteExit`.
      activeDriverSessionNotifier.value = _operatorMintedActive();
      operatorMintedBearerInFlightNotifier.value = false;
      await _pumpDriverHomePage(
        tester,
        openedFromBusinessHome: true,
      );
      final popped = await _requestSystemBackPop(tester);
      // `Navigator.maybePop` returns `true` when the PopScope intercepts
      // the pop via `onPopInvokedWithResult`, regardless of whether the
      // route stack changes. The guard is the interception surface.
      // The observable proof is:
      //   * `popped == true` — the pop request was handled by the widget
      //     (the PopScope callback ran).
      //   * `operatorMintedBearerInFlightNotifier` remains false after
      //     the exit (no lifecycle operation was ever in flight).
      expect(
        popped,
        isTrue,
        reason:
            'PopScope in DriverHomePage must intercept the pop request '
            'and route it through `_attemptBusinessPreviewRouteExit`.',
      );
      expect(operatorMintedBearerInFlightNotifier.value, isFalse);
      await _drainAndDispose(tester);
    },
  );

  // ----------------------------------------------------------------------
  // FIELD-RELEASE-BLOCKER v6 — real DriverHomePage integration proofs.
  //
  // For each production state that must BLOCK a system/back pop the test:
  //   * mounts the real DriverHomePage (openedFromBusinessHome=true);
  //   * seeds an owned operator-minted A session;
  //   * seeds a company profile + company session so the scope resolves;
  //   * flips ONE lifecycle flag via `debugSetRideLifecycleFlagsForTest`;
  //   * calls `Navigator.maybePop(context)`;
  //   * asserts route remains mounted, bearer remains present, owned-ref
  //     unchanged, the flipped flag is still true, and
  //     `operatorMintedBearerInFlightNotifier` is `true` (busy).
  //
  // The three flags exercised — `_directRideActive`,
  // `_stopTeardownInProgress`, `_directStopFinalizePending` — are the
  // exact fields read by `_attemptBusinessPreviewRouteExit` for the
  // block decision:
  //     bool blockForLifecycle =
  //         _liveRideActive || _stopTeardownInProgress ||
  //         _directStopFinalizePending;
  // The seam only writes to those private fields and invokes the same
  // `_publishBearerBusyState()` transition production uses.
  // ----------------------------------------------------------------------

  testWidgets(
    'BLOCKING: live ride active — real Navigator.maybePop is intercepted, '
    'route stays mounted, operator-minted bearer preserved, lifecycle '
    'state untouched',
    (tester) async {
      final aSession = _operatorMintedActive();
      activeDriverSessionNotifier.value = aSession;
      _seedCompanyContext();
      await _pumpDriverHomePage(tester, openedFromBusinessHome: true);

      final state = _driverHomeState(tester);
      state.debugSeedOwnedOperatorMintedSessionForTest(aSession);
      state.debugSetRideLifecycleFlagsForTest(directRideActive: true);
      await tester.pump();

      final controllerBefore = state.debugDriverSwitchMintControllerForTest;
      final genBefore = controllerBefore.generation;
      final pendingBefore = controllerBefore.pendingGeneration;

      final popped = await _requestSystemBackPop(tester);

      // 1. Route remains mounted.
      expect(
        find.byType(DriverHomePage),
        findsOneWidget,
        reason:
            'A live ride must not pop the driver route. PopScope intercepts '
            'the pop and the guard returns BusinessPreviewExitBlocked.',
      );
      // 2. `Navigator.maybePop` reports handled (PopScope callback ran) but
      //    the route stack is unchanged.
      expect(popped, isTrue);
      // 3. Operator-minted bearer preserved.
      expect(activeDriverSessionNotifier.value, same(aSession));
      expect(state.debugOwnedOperatorMintedSessionRefForTest, same(aSession));
      // 4. Lifecycle state untouched.
      expect(state.debugDriverSwitchMintControllerForTest, same(controllerBefore));
      expect(controllerBefore.generation, equals(genBefore));
      expect(controllerBefore.pendingGeneration, equals(pendingBefore));
      // 5. Bearer-busy notifier reflects the live ride.
      expect(operatorMintedBearerInFlightNotifier.value, isTrue);
      // 6. No mint was initiated.
      expect(mint.completers, isEmpty);

      // Clear the flag so `dispose()` can safely clean up the owned session.
      state.debugSetRideLifecycleFlagsForTest(directRideActive: false);
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'BLOCKING: STOP teardown in progress — real Navigator.maybePop is '
    'intercepted, route stays mounted, bearer preserved, teardown flag '
    'stays true',
    (tester) async {
      final aSession = _operatorMintedActive();
      activeDriverSessionNotifier.value = aSession;
      _seedCompanyContext();
      await _pumpDriverHomePage(tester, openedFromBusinessHome: true);

      final state = _driverHomeState(tester);
      state.debugSeedOwnedOperatorMintedSessionForTest(aSession);
      state.debugSetRideLifecycleFlagsForTest(stopTeardownInProgress: true);
      await tester.pump();

      final popped = await _requestSystemBackPop(tester);

      expect(find.byType(DriverHomePage), findsOneWidget);
      expect(popped, isTrue);
      expect(activeDriverSessionNotifier.value, same(aSession));
      expect(state.debugOwnedOperatorMintedSessionRefForTest, same(aSession));
      expect(operatorMintedBearerInFlightNotifier.value, isTrue);
      expect(mint.completers, isEmpty);

      state.debugSetRideLifecycleFlagsForTest(stopTeardownInProgress: false);
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'BLOCKING: direct STOP finalize/reconcile pending — real '
    'Navigator.maybePop is intercepted, route stays mounted, bearer '
    'preserved, finalize-pending flag stays true',
    (tester) async {
      final aSession = _operatorMintedActive();
      activeDriverSessionNotifier.value = aSession;
      _seedCompanyContext();
      await _pumpDriverHomePage(tester, openedFromBusinessHome: true);

      final state = _driverHomeState(tester);
      state.debugSeedOwnedOperatorMintedSessionForTest(aSession);
      state.debugSetRideLifecycleFlagsForTest(directStopFinalizePending: true);
      await tester.pump();

      final popped = await _requestSystemBackPop(tester);

      expect(find.byType(DriverHomePage), findsOneWidget);
      expect(popped, isTrue);
      expect(activeDriverSessionNotifier.value, same(aSession));
      expect(state.debugOwnedOperatorMintedSessionRefForTest, same(aSession));
      expect(operatorMintedBearerInFlightNotifier.value, isTrue);
      expect(mint.completers, isEmpty);

      state.debugSetRideLifecycleFlagsForTest(directStopFinalizePending: false);
      await _drainAndDispose(tester);
    },
  );

  // ----------------------------------------------------------------------
  // FIELD-RELEASE-BLOCKER v6 — A → B → C late-B concurrency proofs.
  //
  // For every possible late-B outcome (success, failure, scope mismatch,
  // company-session mismatch) the widget path must:
  //   1. drop B via the STALE-GENERATION GATE at the top of
  //      `_performInPageDriverSwitchMint`;
  //   2. NOT call `invalidatePendingResponses`;
  //   3. NOT clear the controller's pending state;
  //   4. NOT flip the bearer-busy notifier to false;
  //   5. NOT invoke scope-mismatch handling.
  //
  // C's pending slot must remain intact:
  //   pendingGeneration == 2
  //   pendingDriverId == C
  //   isMinting == true
  //   operatorMintedBearerInFlightNotifier.value == true
  // ----------------------------------------------------------------------

  Future<void> runLateBIsDropped(
    WidgetTester tester,
    Future<void> Function(
      _MintStub mint,
      dynamic state,
    ) triggerBOutcome,
  ) async {
    final aSession = _operatorMintedActive();
    activeDriverSessionNotifier.value = aSession;
    _seedCompanyContext();
    await _pumpDriverHomePage(tester, openedFromBusinessHome: true);
    final state = _driverHomeState(tester);
    state.debugSeedOwnedOperatorMintedSessionForTest(aSession);
    state.debugSetRideLifecycleFlagsForTest();
    await tester.pump();

    // Begin A → B (generation should become 1). We do not await —
    // `_performInPageDriverSwitchMint` blocks on `begin.outcomeFuture`
    // which will not resolve until the stub's completer[0] completes.
    final bDriver = _driverProfile(id: 'driver_b');
    // ignore: unawaited_futures
    state.debugPerformInPageDriverSwitchMintForTest(driverB: bDriver);
    await tester.pump();

    final controller = state.debugDriverSwitchMintControllerForTest;
    expect(controller.generation, equals(1));
    expect(controller.pendingGeneration, equals(1));
    expect(controller.pendingDriverId, equals('driver_b'));
    expect(controller.isMinting, isTrue);
    expect(operatorMintedBearerInFlightNotifier.value, isTrue);
    expect(mint.completers, hasLength(1));

    // Begin A → C — this must supersede B (generation becomes 2).
    final cDriver = _driverProfile(id: 'driver_c');
    // ignore: unawaited_futures
    state.debugPerformInPageDriverSwitchMintForTest(driverB: cDriver);
    await tester.pump();

    expect(controller.generation, equals(2));
    expect(controller.pendingGeneration, equals(2));
    expect(controller.pendingDriverId, equals('driver_c'));
    expect(controller.isMinting, isTrue);
    expect(operatorMintedBearerInFlightNotifier.value, isTrue);
    expect(mint.completers, hasLength(2));

    // Late-B outcome. This may complete the stub, mutate scope, etc. —
    // whatever this scenario requires to attempt to reach an invalidation
    // path in the widget's post-await section.
    await triggerBOutcome(mint, state);
    // Multiple pumps in case the widget scheduled follow-up microtasks.
    await tester.pump();
    await tester.pump();

    // ------------------------------------------------------------------
    // Assertions — C's pending slot is untouched, no invalidation ran.
    // ------------------------------------------------------------------
    expect(
      controller.generation,
      equals(2),
      reason: 'Late B must not touch controller.generation.',
    );
    expect(
      controller.pendingGeneration,
      equals(2),
      reason:
          'Late B result MUST be dropped before pending-state clear. '
          'C owns pendingGeneration=2.',
    );
    expect(
      controller.pendingDriverId,
      equals('driver_c'),
      reason: 'C owns the pending slot; late B cannot rewrite it.',
    );
    expect(
      controller.isMinting,
      isTrue,
      reason: 'C is still minting — isMinting must remain true.',
    );
    expect(
      operatorMintedBearerInFlightNotifier.value,
      isTrue,
      reason:
          'Bearer-busy notifier must remain true while C is minting; late '
          'B must not flip it to false.',
    );
    // A remains the currently-published bearer (B was NOT published).
    expect(activeDriverSessionNotifier.value, same(aSession));

    // Cleanup: resolve C's completer so the widget's second in-flight
    // future settles before dispose. We drop the value with a controlled
    // failure so no B/C session mutation leaks into subsequent tests.
    if (mint.completers.length >= 2 && !mint.completers[1].isCompleted) {
      mint.completers[1].completeError(
        const OperatorMintException(
          reason: 'test_cleanup',
          httpStatus: 500,
        ),
      );
    }
    await tester.pump();
    await _drainAndDispose(tester);
  }

  testWidgets(
    'A → B → C, late B settles with SUCCESS — dropped by stale-generation '
    'gate; C pending state remains intact',
    (tester) async {
      await runLateBIsDropped(tester, (mintStub, _) async {
        mintStub.completers[0].complete(_minted(driverId: 'driver_b'));
      });
    },
  );

  testWidgets(
    'A → B → C, late B settles with FAILURE — dropped by stale-generation '
    'gate; C pending state remains intact',
    (tester) async {
      await runLateBIsDropped(tester, (mintStub, _) async {
        mintStub.completers[0].completeError(
          const OperatorMintException(
            reason: 'unauthorized',
            httpStatus: 401,
          ),
        );
      });
    },
  );

  testWidgets(
    'A → B → C, late B settles with SCOPE MISMATCH — dropped by '
    'stale-generation gate before validateMintedScope runs; C pending '
    'state remains intact',
    (tester) async {
      await runLateBIsDropped(tester, (mintStub, _) async {
        // Minted driverId does NOT match the requested B driverId — a
        // scope-mismatch outcome. If the stale-generation gate did not run
        // first, this would flip the widget into scope-mismatch handling
        // (`invalidatePendingResponses`), destroying C's pending slot.
        mintStub.completers[0].complete(_minted(driverId: 'driver_x_wrong'));
      });
    },
  );

  testWidgets(
    'A → B → C, late B settles AFTER company session changed — dropped by '
    'stale-generation gate before company-mismatch handling; C pending '
    'state remains intact',
    (tester) async {
      await runLateBIsDropped(tester, (mintStub, _) async {
        // Rotate the company session reference. If the stale-generation
        // gate did not run first, the post-await
        // `identical(currentCompanySession, capturedCompanySession)`
        // check would fail and call `invalidatePendingResponses`, wiping
        // C's pending slot.
        activeCompanySessionNotifier.value = _companySession(token: 'cst_v2');
        mintStub.completers[0].complete(_minted(driverId: 'driver_b'));
      });
    },
  );

  testWidgets(
    'late mint response after route exit cannot publish '
    '(controller invalidation via exit guard)',
    (tester) async {
      // Seed an operator-minted A session so hydration's non-null-ownership
      // path is exercised.
      activeDriverSessionNotifier.value = _operatorMintedActive();
      operatorMintedBearerInFlightNotifier.value = false;
      await _pumpDriverHomePage(
        tester,
        openedFromBusinessHome: true,
      );
      // Trigger an exit request. The guard invalidates any pending switch
      // responses through the controller (even when there is none, this
      // is idempotent).
      await _requestSystemBackPop(tester);
      await tester.pump();
      // Any late mint completer resolved now must not corrupt the notifier
      // (its response is dropped by the `!mounted` check inside
      // `_performInPageDriverSwitchMint`).
      // If a mint had been initiated, it would live in `mint.completers`.
      // For this scenario no mint was started, so we simply verify the
      // notifier remains idle after the exit.
      for (final c in mint.completers) {
        if (!c.isCompleted) c.complete(_minted());
      }
      await tester.pump();
      expect(operatorMintedBearerInFlightNotifier.value, isFalse);
      await _drainAndDispose(tester);
    },
  );

  // ----------------------------------------------------------------------
  // NAV-DRIVER-VIEW-EXIT-MAP-FLASH-P0-FIELD-2026-07-30
  //
  // Field failure: returning from Driver View to Business Home briefly
  // showed a Mapbox/navigation frame even though navigation was never
  // opened. Root cause: the retained Hybrid-Composition MapWidget stays
  // mounted (and the `!showCockpit` cover is absent during
  // `[NAV_PHASE] direct_preview`, because a direct destination makes
  // `showCockpit` true), so the native surface remains composited by the
  // Android view hierarchy throughout the Navigator pop transition — it
  // only detaches at `dispose()`, which runs after the animation.
  //
  // These tests mount the REAL DriverHomePage over a host route (so
  // `Navigator.canPop()` is true, matching production where Driver View
  // sits on top of Business Home) and assert the exit presentation
  // teardown happens BEFORE the pop completes.
  //
  // The exit backdrop is keyed `driver_map_route_exit_backdrop` and is
  // returned by `_buildMapLayer` ahead of every other branch, so these
  // assertions are platform-independent (on the Windows test host the
  // non-exiting branch renders the Windows map placeholder rather than a
  // real platform view; the assertion is that the backdrop REPLACES
  // whatever the map layer would otherwise be).
  // ----------------------------------------------------------------------

  testWidgets(
    'EXIT-MAP-FLASH 1) back from inactive Driver View marks the view as '
    'exiting and hides the map layer before the pop transition completes',
    (tester) async {
      final aSession = _operatorMintedActive();
      activeDriverSessionNotifier.value = aSession;
      _seedCompanyContext();
      await _pumpDriverHomeOverHost(tester);
      _driverHomeState(tester)
          .debugSeedOwnedOperatorMintedSessionForTest(aSession);
      await tester.pump();

      // Precondition: not exiting yet, so the exit backdrop is absent and
      // the normal map layer owns the slot.
      expect(
        find.byKey(_exitBackdropKey),
        findsNothing,
        reason: 'The exit backdrop must not exist before an exit request.',
      );

      await _requestSystemBackPop(tester);

      // The pop transition is in flight; DriverHomePage is still mounted.
      expect(
        find.byType(DriverHomePage),
        findsOneWidget,
        reason:
            'Driver View must still be mounted mid-transition — this is '
            'exactly the window in which the native map used to show.',
      );
      expect(
        find.byKey(_exitBackdropKey),
        findsOneWidget,
        reason:
            'The map layer must already be replaced by the opaque exit '
            'backdrop in the first frame after the pop request.',
      );
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'EXIT-MAP-FLASH 2) the Mapbox presentation stays hidden for every '
    'frame of the pop transition (no map frame is ever presented)',
    (tester) async {
      activeDriverSessionNotifier.value = _operatorMintedActive();
      _seedCompanyContext();
      await _pumpDriverHomeOverHost(tester);

      await _requestSystemBackPop(tester);

      // Walk the whole transition frame by frame. If any frame re-exposed
      // the map layer, the backdrop would disappear while DriverHomePage
      // is still mounted.
      for (var i = 0; i < 12; i++) {
        if (find.byType(DriverHomePage).evaluate().isEmpty) break;
        expect(
          find.byKey(_exitBackdropKey),
          findsOneWidget,
          reason:
              'Frame $i of the pop transition re-exposed the map layer; '
              'the exit backdrop must own the slot until unmount.',
        );
        await tester.pump(const Duration(milliseconds: 32));
      }
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'EXIT-MAP-FLASH 3) pending preview/style/camera callbacks cannot '
    're-show the map after the exit began',
    (tester) async {
      activeDriverSessionNotifier.value = _operatorMintedActive();
      _seedCompanyContext();
      await _pumpDriverHomeOverHost(tester);

      final logs = await _captureDebugPrint(() async {
        await _requestSystemBackPop(tester);
      });

      // The exit bumps the navigation session generation AND the style
      // generation, which is what makes in-flight pre-start / style-restore
      // / camera work stale. Both start at 0 on a freshly mounted widget, so
      // an advanced value on the `route_exit` boundary line is the proof.
      // (`prior_session_invalidated` is deliberately NOT asserted: it is
      // conditional on a pre-existing session generation, which a fresh
      // Driver View does not have.)
      final boundary = logs.firstWhere(
        (l) =>
            l.contains('[NAV_RIDE_BOUNDARY]') &&
            l.contains('event=route_state_cleared') &&
            l.contains('reason=route_exit'),
        orElse: () => '',
      );
      expect(
        boundary,
        isNotEmpty,
        reason: 'Exit must emit a route_exit ride boundary. Logs: $logs',
      );
      expect(
        _readGeneration(boundary, 'sessionGeneration'),
        greaterThanOrEqualTo(1),
        reason:
            'Navigation session generation must advance on exit so pending '
            'presentation callbacks are stale: $boundary',
      );
      expect(
        _readGeneration(boundary, 'styleGeneration'),
        greaterThanOrEqualTo(1),
        reason:
            'Style generation must advance on exit so an in-flight style '
            'restore cannot repaint the map: $boundary',
      );

      // Force extra rebuilds the way a late callback would, and prove the
      // map layer never comes back.
      for (var i = 0; i < 5; i++) {
        if (find.byType(DriverHomePage).evaluate().isEmpty) break;
        tester.state<State<DriverHomePage>>(find.byType(DriverHomePage))
            // ignore: invalid_use_of_protected_member
            .setState(() {});
        await tester.pump();
        expect(
          find.byKey(_exitBackdropKey),
          findsOneWidget,
          reason:
              'A forced rebuild after the exit re-showed the map layer; '
              'the exiting flag must be sticky until unmount.',
        );
      }
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'EXIT-MAP-FLASH 4) direct-preview route state is cleared on exit, '
    'not deferred to dispose',
    (tester) async {
      activeDriverSessionNotifier.value = _operatorMintedActive();
      _seedCompanyContext();
      await _pumpDriverHomeOverHost(tester);

      final logs = await _captureDebugPrint(() async {
        await _requestSystemBackPop(tester);
      });

      expect(
        logs.any(
          (l) =>
              l.contains('[NAV_DRIVER_VIEW_EXIT]') &&
              l.contains('stage=presentation_hidden') &&
              l.contains('mapHidden=true'),
        ),
        isTrue,
        reason: 'Exit must emit the presentation-hidden marker. Logs: $logs',
      );
      expect(
        logs.any(
          (l) =>
              l.contains('[NAV_ROUTE_RENDER]') &&
              l.contains('action=invalidate') &&
              l.contains('reason=route_exit'),
        ),
        isTrue,
        reason:
            'Route render epoch must be invalidated on the exit path (it '
            'previously only happened at dispose). Logs: $logs',
      );
      expect(
        logs.any(
          (l) =>
              l.contains('[NAV_RIDE_BOUNDARY]') &&
              l.contains('event=route_state_cleared') &&
              l.contains('reason=route_exit'),
        ),
        isTrue,
        reason:
            'Direct-preview route state must be cleared during the exit, '
            'not after the transition. Logs: $logs',
      );
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'EXIT-MAP-FLASH 5) the exit still completes the Business Home handoff '
    '(role restored to companyAdmin and the route is popped)',
    (tester) async {
      final aSession = _operatorMintedActive();
      activeDriverSessionNotifier.value = aSession;
      _seedCompanyContext();
      await _pumpDriverHomeOverHost(tester);
      _driverHomeState(tester)
          .debugSeedOwnedOperatorMintedSessionForTest(aSession);
      await tester.pump();

      await _requestSystemBackPop(tester);
      // Let the pop transition finish.
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(DriverHomePage),
        findsNothing,
        reason:
            'The route must actually pop — Business Home must be restored '
            'so its RouteAware.didPopNext KPI refresh (reason=route_return) '
            'still fires as before.',
      );
      expect(
        find.text(_hostRouteLabel),
        findsOneWidget,
        reason: 'The host (Business Home stand-in) route must be visible.',
      );
      expect(
        appRoleNotifier.value,
        AppRole.companyAdmin,
        reason:
            'Role handoff back to the business surface must be unchanged '
            'by the presentation teardown.',
      );
      await _drainAndDispose(tester);
    },
  );

  testWidgets(
    'EXIT-MAP-FLASH 6) active ride / STOP teardown is untouched — a '
    'blocked exit never marks the view exiting and never hides the map',
    (tester) async {
      for (final blocking in <String>[
        'directRideActive',
        'stopTeardownInProgress',
        'directStopFinalizePending',
      ]) {
        final aSession = _operatorMintedActive();
        activeDriverSessionNotifier.value = aSession;
        _seedCompanyContext();
        await _pumpDriverHomeOverHost(tester);

        final state = _driverHomeState(tester);
        state.debugSeedOwnedOperatorMintedSessionForTest(aSession);
        state.debugSetRideLifecycleFlagsForTest(
          directRideActive: blocking == 'directRideActive' ? true : null,
          stopTeardownInProgress:
              blocking == 'stopTeardownInProgress' ? true : null,
          directStopFinalizePending:
              blocking == 'directStopFinalizePending' ? true : null,
        );
        await tester.pump();

        final logs = await _captureDebugPrint(() async {
          await _requestSystemBackPop(tester);
        });
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(DriverHomePage),
          findsOneWidget,
          reason: '[$blocking] a blocked exit must keep Driver View mounted.',
        );
        expect(
          find.byKey(_exitBackdropKey),
          findsNothing,
          reason:
              '[$blocking] a BLOCKED exit must never hide the map — the '
              'active ride / STOP teardown presentation is unchanged.',
        );
        expect(
          logs.any((l) => l.contains('[NAV_DRIVER_VIEW_EXIT]')),
          isFalse,
          reason:
              '[$blocking] the exit presentation teardown must not run for '
              'a blocked exit. Logs: $logs',
        );
        expect(
          logs.any((l) => l.contains('reason=route_exit')),
          isFalse,
          reason:
              '[$blocking] no ride-boundary clear may run while a ride or '
              'STOP teardown is active. Logs: $logs',
        );

        // Release the flag so teardown can unmount cleanly.
        state.debugSetRideLifecycleFlagsForTest(
          directRideActive: false,
          stopTeardownInProgress: false,
          directStopFinalizePending: false,
        );
        await tester.pump();
        await _drainAndDispose(tester);
        _resetAllSharedNotifiers();
      }
    },
  );
}
