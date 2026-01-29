import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'widgets/cockpit_widget.dart';
import 'widgets/route_marquee.dart';
final bool kIsWindows = !kIsWeb && Platform.isWindows;

/// Fluxidi brand glow color (gold).
const Color kGlow = Color(0xFFFFD54F);


/// ✅ Mapbox token for REST calls (geocoding + directions).
/// Set at run/build time:
/// flutter run --dart-define=MAPBOX_TOKEN=pk.xxx
const String kMapboxToken = "pk.eyJ1IjoiZmx1eGlkaSIsImEiOiJjbWs3NnF1d3Uwc3d1M2ZzY3NzOGw5Mmg5In0.U61dLwSIzaAduZSgeKFHNQ";


Map<String, String> _adminHeaders() {
  final t = kAdminToken.trim();
  if (t.isEmpty) return <String, String>{};
  return <String, String>{
    'Authorization': 'Bearer $t',
    'x-admin-token': t,
  };
}


void main() {
  // Mapbox REST token is optional in this build.
  // If not provided, the app will fall back to Worker-side routing where possible.
  if (kMapboxToken.trim().isEmpty) {
    // ignore: avoid_print
    print('⚠️ MAPBOX_TOKEN not set (using fallback routing).');
  }
  runApp(const FluxidiDriverApp());
}

/// ===============================
/// CONFIG
/// ===============================

/// ✅ Production default Worker base URL (NO trailing slash)
const String kWorkerBaseUrlDefault =
    'https://fluxidi-tracking-api.fluxidi.workers.dev';

/// ✅ Booking API base URL (used for pricing + route helpers).
/// Default points to the booking Worker (NOT the tracking API Worker).
const String kBookingBaseUrlDefault =
    'https://fluxidi-booking-api.fluxidi.workers.dev';

/// Optional override via dart-define (handy for staging)
/// flutter run ... --dart-define=BOOKING_BASE_URL=https://...workers.dev
const String kBookingBaseUrlOverride =
    String.fromEnvironment('BOOKING_BASE_URL', defaultValue: '');

String get kBookingBaseUrl {
  final v = kBookingBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return kBookingBaseUrlDefault;
}


/// Optional override via dart-define (handig voor staging)
/// flutter run ... --dart-define=WORKER_BASE_URL=https://...workers.dev
const String kWorkerBaseUrlOverride =
    String.fromEnvironment('WORKER_BASE_URL', defaultValue: '');

String get kWorkerBaseUrl {
  final v = kWorkerBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return kWorkerBaseUrlDefault;
}

/// Driver id (keep simple for now)
const String kDriverId = 'fluxidi_driver_01';

/// Admin token (optional) for driver actions like complete/cancel/delete.
/// Set at run/build time:
/// flutter run --dart-define=ADMIN_TOKEN=yourSecret
const String kAdminToken =
    String.fromEnvironment('ADMIN_TOKEN', defaultValue: '');

/// Endpoints (adjust if your Worker uses different paths)
const String kListBookingsPath = '/track/bookings';
const String kGetBookingPath = '/track/booking'; // returns booking + quote/pricing

// Admin endpoints (require x-admin-token if enabled in Worker)
const String kUpdateBookingStatusPath = '/track/booking/status';
const String kDeleteBookingPath = '/track/booking/delete';

const String kStartTripPath = '/track/session/start';
const String kPingPath = '/track/ping';
const String kStopTripPath = '/track/session/stop'; // optional

/// Optional: Worker route endpoint (recommended, avoids exposing Mapbox token)
/// Implement later in Worker: POST { from, to } -> { coords:[[lon,lat],...], distance_m, duration_s }
const String kWorkerRoutePath = '/track/route';

/// ===============================
/// BRANDING (Fluxidi Taxi UI)
/// ===============================

/// Put your logo in this path (recommended):
///   assets/fluxidi/fluxidi_logo.png
/// and add it to pubspec.yaml under flutter/assets.
const String kFluxidiLogoAsset = 'assets/fluxidi/fluxidi_logo.png';

/// Fluxidi Taxi colors (premium black + warm taxi yellow)
const Color kFluxidiYellow = Color(0xFFFFD400);
const Color kFluxidiYellowSoft = Color(0x33FFD400); // 20% alpha
const Color kFluxidiBlack = Color(0xFF07080B);
const Color kFluxidiPanel = Color(0xFF121318);
const Color kFluxidiCard = Color(0xFF171922);
const Color kFluxidiTextSoft = Color(0xFFB8BDC9);

class FluxidiDriverApp extends StatelessWidget {
  const FluxidiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Less dark / better contrast
    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: kFluxidiBlack,
      colorScheme: ColorScheme.dark(
        primary: kFluxidiYellow,
        secondary: kFluxidiYellow,
        surface: kFluxidiPanel,
        error: const Color(0xFFED6A5A),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
      ),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kFluxidiYellow,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: kFluxidiYellow, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) {
        return FluxidiFrame(child: child ?? const SizedBox.shrink());
      },
      home: const DriverHomePage(),
    );
  }
}


class FluxidiFrame extends StatelessWidget {
  final Widget child;
  const FluxidiFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Hard Frame A: a visible yellow HUD border that *contains* the whole UI.
    // Target: visually ~2–3mm on phone screens.
    return Container(
      color: kFluxidiBlack,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kFluxidiBlack,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: kFluxidiYellow.withOpacity(0.98), width: 3.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kFluxidiBlack,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: kFluxidiYellow.withOpacity(0.55),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingItem {
  final String bookingId;
  final String? pickupIso;
  final String? from;
  final String? to;
  final String? tier;
  final int? pax;
  final int? bags;
  final String? status;
  final num? price; // optional
  final String? currency; // optional

  // Tracking API (fluxidi-tracking-api)
  final String? sessionId;
  final String? createdAtIso;
  final double? lastLat;
  final double? lastLon;
  final String? lastPingTs;
  final num? lastSpeed;
  final num? lastHeading;

  BookingItem({
    required this.bookingId,
    this.sessionId,
    this.pickupIso,
    this.from,
    this.to,
    this.tier,
    this.pax,
    this.bags,
    this.status,
    this.price,
    this.currency,
    this.createdAtIso,
    this.lastLat,
    this.lastLon,
    this.lastPingTs,
    this.lastSpeed,
    this.lastHeading,
  });

  String get shortId {
    if (bookingId.length <= 12) return bookingId;
    return '${bookingId.substring(0, 4)}…${bookingId.substring(bookingId.length - 4)}';
  }


  static String? _extractPlaceLabel(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map<String, dynamic>) {
      // Common shapes: {address: "..."} or {label:"..."} or {text:"..."} etc.
      const keys = [
        'address',
        'label',
        'text',
        'name',
        'formatted',
        'display',
        'place_name',
        'full_address',
      ];
      for (final k in keys) {
        final vv = v[k];
        if (vv is String && vv.trim().isNotEmpty) return vv.trim();
      }

      // Sometimes nested like {pickup:{address:"..."}} already handled upstream,
      // but also allow {location:{address:"..."}} style.
      for (final nestedKey in ['location', 'place', 'geo', 'data']) {
        final nested = v[nestedKey];
        if (nested is Map<String, dynamic>) {
          for (final k in keys) {
            final vv = nested[k];
            if (vv is String && vv.trim().isNotEmpty) return vv.trim();
          }
        }
      }
    }
    return null;
  }

  
  BookingItem copyWith({
    String? bookingId,
    String? pickupIso,
    String? from,
    String? to,
    String? tier,
    int? pax,
    int? bags,
    String? status,
    num? price,
    String? currency,
    String? sessionId,
    String? createdAtIso,
    double? lastLat,
    double? lastLon,
    String? lastPingTs,
    num? lastSpeed,
    num? lastHeading,
  }) {
    return BookingItem(
      bookingId: bookingId ?? this.bookingId,
      pickupIso: pickupIso ?? this.pickupIso,
      from: from ?? this.from,
      to: to ?? this.to,
      tier: tier ?? this.tier,
      pax: pax ?? this.pax,
      bags: bags ?? this.bags,
      status: status ?? this.status,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      sessionId: sessionId ?? this.sessionId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      lastLat: lastLat ?? this.lastLat,
      lastLon: lastLon ?? this.lastLon,
      lastPingTs: lastPingTs ?? this.lastPingTs,
      lastSpeed: lastSpeed ?? this.lastSpeed,
      lastHeading: lastHeading ?? this.lastHeading,
    );
  }

factory BookingItem.fromJson(Map<String, dynamic> j) {
    // Support both booking-api payloads and tracking-api payloads.
    final lastPing = (j['last_ping'] is Map<String, dynamic>)
        ? (j['last_ping'] as Map<String, dynamic>)
        : null;

    String? pickLabel = _extractPlaceLabel(j['pickup'] ?? j['from']);
    String? dropLabel = _extractPlaceLabel(j['dropoff'] ?? j['to']);

    // Extra common field names across versions/backends
    pickLabel ??= _extractPlaceLabel(j['pickup_address'] ?? j['pickup_label'] ?? j['from_address']);
    dropLabel ??= _extractPlaceLabel(j['dropoff_address'] ?? j['dropoff_label'] ?? j['to_address']);

    // If backend already provides plain strings, prefer those
    final fromStr = (j['from'] is String) ? (j['from'] as String) : null;
    final toStr = (j['to'] is String) ? (j['to'] as String) : null;

    return BookingItem(
      bookingId: (j['booking_id'] ?? j['id'] ?? '').toString(),
      pickupIso: j['pickup_iso']?.toString(),
      from: (fromStr?.trim().isNotEmpty ?? false) ? fromStr!.trim() : (pickLabel?.trim().isNotEmpty ?? false ? pickLabel!.trim() : null),
      to: (toStr?.trim().isNotEmpty ?? false) ? toStr!.trim() : (dropLabel?.trim().isNotEmpty ?? false ? dropLabel!.trim() : null),
      tier: j['tier']?.toString(),
      pax: _toIntOrNull(j['pax'] ?? j['passengers'] ?? j['persons'] ?? j['pax_count'] ?? j['paxCount']),
      bags: _toIntOrNull(j['bags'] ?? j['luggage'] ?? j['bags_count'] ?? j['bagsCount']),
      status: j['status']?.toString(),
      price: _toNumOrNull(j['price'] ?? j['total_price'] ?? j['total']),
      currency: (j['currency'] ?? 'EUR')?.toString(),
      sessionId: j['session_id']?.toString(),
      createdAtIso: j['created_at']?.toString(),
      lastLat: _toDoubleOrNull(lastPing?['lat']),
      lastLon: _toDoubleOrNull(lastPing?['lon']),
      lastPingTs: lastPing?['ts']?.toString(),
      lastSpeed: _toNumOrNull(lastPing?['speed']),
      lastHeading: _toNumOrNull(lastPing?['heading']),
    );
  }


  static int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static num? _toNumOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

enum _CameraMode { overview, follow }


class _PlaceSuggestion {
  final String label;
  final double? lon;
  final double? lat;
  const _PlaceSuggestion({required this.label, this.lon, this.lat});
}

class _LonLat {
  final double lon;
  final double lat;
  const _LonLat(this.lon, this.lat);
}

class _UnauthorizedMapbox implements Exception {
  final String where;
  _UnauthorizedMapbox(this.where);

  @override
  String toString() => 'Mapbox unauthorized ($where)';
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> with TickerProviderStateMixin {
  DateTime? _trackingStartedAt; // tracking start timestamp
  bool _isStartingTrip = false; // UX: start button state

  // Manual (GPS-style) mode when no booking is active
  final TextEditingController _manualFromCtrl = TextEditingController();
  final TextEditingController _manualToCtrl = TextEditingController();
  // --- Manual A→B autocomplete (Mapbox Geocoding) ---
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  Timer? _fromDebounce;
  Timer? _toDebounce;
  List<_PlaceSuggestion> _fromSuggestions = <_PlaceSuggestion>[];
  List<_PlaceSuggestion> _toSuggestions = <_PlaceSuggestion>[];
  mb.Point? _manualFromPoint;
  mb.Point? _manualToPoint;


  // Ride mode (driving vs waiting)
  bool _isWaiting = false;
  DateTime? _waitStartedAt;
  Duration _waitElapsed = Duration.zero;

  // Pricing (UI-only fallback; worker remains source of truth)
  static const double _fallbackStartFee = 3.0;
  static const double _fallbackPerKm = 1.50; // placeholder until worker streams live rates
  static const double _fallbackWaitPerMin = 40.0 / 60.0; // €40/h = €0.666.../min


  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<BookingItem> _bookings = [];
  bool _loadingBookings = true;
  String? _bookingsError;

  Timer? _bookingPollTimer; // auto-refresh bookings

  // Boot splash (logo on dark background + loader)
  bool _bootSplashVisible = true;
  bool _showManualLivePanel = false; // show manual live-ride panel only when user selects it

  bool _showBootSplash = true; // alias for older/other UI refs
  bool _bootMinElapsed = false;
  bool _bootFirstLoadDone = false;
  DateTime? _bootStartedAt;


  // Active trip state
  String? _activeTripId;
  BookingItem? _activeBooking;

  // Location tracking
  StreamSubscription<geo.Position>? _posSub;
  geo.Position? _lastPos;
  geo.Position? _startPos;
  double _kmDriven = 0.0;

  // Ping status
  String _lastPing = '—';
  int _pingCount = 0;

  // Map controller
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _driverPointManager;
  mb.PointAnnotationManager? _pinsPointManager;
  mb.PolylineAnnotationManager? _routeLineManager;

  mb.PointAnnotation? _driverMarker;
  mb.PointAnnotation? _pickupPin;
  mb.PointAnnotation? _dropoffPin;
  mb.PolylineAnnotation? _routeLine;

  

  // Splash animations (premium boot feel)
  late final AnimationController _splashAnimCtrl;
  late final Animation<double> _splashPulse;

  // Active HUD pulse (only meaningful when tracking)
  late final AnimationController _activePulseCtrl;
  late final Animation<double> _activePulse;
// UI/Camera
  bool _followCar = false;
  _CameraMode _cameraMode = _CameraMode.overview;
  bool _hasSwitchedToFollow = false;

  // Route stats
  List<_LonLat> _routeCoords = [];
  double? _routeKm;
  int? _routeDurationSec;

  bool get _mapSupported => !kIsWindows && !kIsWeb;
  bool get kIsWindows => !kIsWeb && Platform.isWindows;
  // ===============================
  // JSON helpers (local)
  // ===============================
  dynamic _getNested(dynamic root, List<String> path) {
    dynamic cur = root;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  int? _toIntOrNullLocal(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  // Best-effort: hydrate missing booking fields via Tracking API Worker /track/booking (GET).
  // This endpoint exists on fluxidi-tracking-api (V2):
  //   GET /track/booking?booking_id=TEST-001
  // and returns pickup/dropoff + session status + last ping.
  Future<void> _hydrateActiveBookingDetails(String bookingId) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kGetBookingPath?booking_id=${Uri.encodeComponent(bookingId)}');
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['ok'] != true) return;

      // Tracking API returns flat fields
      final pickup = decoded['pickup']?.toString();
      final dropoff = decoded['dropoff']?.toString();
      final sessionId = decoded['session_id']?.toString();
      final status = decoded['status']?.toString();

      if (!mounted) return;

      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            from: pickup ?? _activeBooking!.from,
            to: dropoff ?? _activeBooking!.to,
            sessionId: sessionId ?? _activeBooking!.sessionId,
            status: status ?? _activeBooking!.status,
          );
        }

        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(
            from: pickup ?? _bookings[idx].from,
            to: dropoff ?? _bookings[idx].to,
            sessionId: sessionId ?? _bookings[idx].sessionId,
            status: status ?? _bookings[idx].status,
          );
        }
      });
    } catch (_) {
      // silent best-effort
    }
  }


  @override
  void initState() {
    super.initState();

    _splashAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _splashPulse = CurvedAnimation(parent: _splashAnimCtrl, curve: Curves.easeInOut);

    _activePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _activePulse = CurvedAnimation(parent: _activePulseCtrl, curve: Curves.easeInOut);

    _bootStartedAt = DateTime.now();
    // Minimum splash duration so it feels intentional (not a flicker)
    // Christophe wants it to linger a bit longer for a more premium feel.
    Timer(const Duration(milliseconds: 8000), () {
      if (!mounted) return;
      _bootMinElapsed = true;
      _maybeHideBootSplash();
    });
    _refreshBookings();

    // Auto-refresh bookings so website bookings appear in the app.
    _bookingPollTimer?.cancel();
    _bookingPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      if (_loadingBookings) return;
      _refreshBookings();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload the splash logo so we don't hit the errorBuilder fallback on first frame.
    // If the asset path is wrong, Flutter will throw during precache and we'll still fall back.
    unawaited(
      precacheImage(const AssetImage(kFluxidiLogoAsset), context)
          .catchError((_) {}),
    );
  }

  @override
  void dispose() {
    _splashAnimCtrl.dispose();
    _activePulseCtrl.dispose();
    _stopTrackingInternal();
    _manualFromCtrl.dispose();
    _manualToCtrl.dispose();
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }
Map<String, String> _headers({bool admin = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (admin && kAdminToken.trim().isNotEmpty) {
      h['x-admin-token'] = kAdminToken.trim();
    }
    return h;
  }

  Future<void> _refreshBookings() async {
    setState(() {
      _loadingBookings = true;
      _bookingsError = null;
    });

    try {
      // Tracking API expects admin header.
      final uri = Uri.parse('$kWorkerBaseUrl$kListBookingsPath?limit=50');
      final res = await http.get(uri, headers: _headers(admin: true));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response');
      }

      // Tracking API shape: { ok: true, count: n, bookings: [ ... ] }
      final raw = (decoded['bookings'] as List<dynamic>? ?? []);
      final items = raw
          .whereType<Map<String, dynamic>>()
          .map((j) => BookingItem.fromJson(j))
          .toList();

      setState(() {
        _bookings = items;
        _loadingBookings = false;
      });
    } catch (e) {
      setState(() {
        _bookingsError = e.toString();
        _loadingBookings = false;
      });
    } finally {
      _markBootFirstLoadDone();
    }
  }
  /// Open a booking in "ride preview" mode:
  /// - show route in OVERVIEW
  /// - do NOT create a trip_id yet
  /// - driver presses START on the map to begin tracking + streetview/follow cam
  Future<void> _goToRide(BookingItem b) async {
    try {
      // We are typically called from the Bookings Hub page.
      // UX: return to the main map/cockpit immediately.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }

      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }

      setState(() {
        _showManualLivePanel = false;
        _activeBooking = b;
        _activeTripId = null;
        _isStartingTrip = false;

        _kmDriven = 0.0;
        _pingCount = 0;
        _lastPing = '—';

        _routeCoords = [];
        _routeKm = null;
        _routeDurationSec = null;

        _cameraMode = _CameraMode.overview;
        _hasSwitchedToFollow = false;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;

        _trackingStartedAt = null;
      });

      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);
      await _ensureLocationPermission();

      // Start location stream for map + marker (pings are guarded by _activeTripId).
      _startTrackingInternal();

      final bb = _activeBooking ?? b;
      await _buildOverviewRoute(bb);

      // Stay in overview mode after opening a booking.
      // Driver explicitly presses START to begin an active tracking session & follow-cam.

      if (mounted) setState(() => _isStartingTrip = false);

    } catch (e) {
      _toast('Open ride failed: $e');
    }
  }


  Future<void> _startTrip(BookingItem b) async {
    try {
      if (mounted) setState(() => _isStartingTrip = true);

      // UX rule: Start in Drawer → Drawer closes → Map becomes primary focus
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      final uri = Uri.parse('$kWorkerBaseUrl$kStartTripPath');
      final payload = {
        'booking_id': b.bookingId,
        // Optional context (helps debugging / future UI)
        'pickup': (b.from ?? '').toString(),
        'dropoff': (b.to ?? '').toString(),
      };

      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final sessionId = (j['session_id'] ?? j['sessionId'] ?? '').toString();
      if (sessionId.isEmpty) throw Exception('No session_id returned by Worker.');

      setState(() {
        _activeTripId = sessionId;
        _activeBooking = b;
        _kmDriven = 0.0;
        _pingCount = 0;
        _lastPing = '—';

        _routeCoords = [];
        _routeKm = null;
        _routeDurationSec = null;

        _cameraMode = _CameraMode.overview;
        _hasSwitchedToFollow = false;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      });

      // Fetch canonical booking details (incl. fixed price) for display
      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);

      await _ensureLocationPermission();

      _startTrackingInternal();
      final bb = _activeBooking ?? b;
      await _buildOverviewRoute(bb);
    } catch (e) {
      if (mounted) setState(() => _isStartingTrip = false);
      _toast('Start failed: $e');
    }
  }


  Future<void> _hydrateActiveBookingPrice(String bookingId) async {
    // Pricing is owned by the BOOKING Worker (not the tracking Worker).
    // If the booking isn't known there yet (e.g. TEST-xxx created only in tracking),
    // we just skip without breaking tracking.
    try {
      final uri = Uri.parse('$kBookingBaseUrl$kGetBookingPath');
      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode({'booking_id': bookingId}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return;

      final quote = (j['quote'] is Map) ? (j['quote'] as Map).cast<String, dynamic>() : null;
      final pricing = (quote != null && quote['pricing'] is Map)
          ? (quote['pricing'] as Map).cast<String, dynamic>()
          : null;

      final priceIncl = pricing != null ? pricing['price_incl_vat'] : null;
      final num? price = (priceIncl is num) ? priceIncl : (priceIncl is String ? num.tryParse(priceIncl) : null);
      if (price == null) return;

      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(price: price, currency: 'EUR');
        }
      });
    } catch (_) {
      // silent
    }
  }

  
  Future<void> _setBookingStatus(BookingItem b, String status) async {
    // Tracking API V2 does not expose a booking status endpoint.
    // We keep UI flow intact by updating local state only.
    if (!mounted) return;
    setState(() {
      final idx = _bookings.indexWhere((x) => x.bookingId == b.bookingId);
      if (idx >= 0) _bookings[idx] = _bookings[idx].copyWith(status: status);
      if (_activeBooking?.bookingId == b.bookingId) {
        _activeBooking = _activeBooking!.copyWith(status: status);
      }
    });
    _toast('✅ $status: ${b.shortId}');
  }

  Future<void> _deleteBooking(BookingItem b) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kDeleteBookingPath');
      final payload = {'booking_id': b.bookingId};

      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      final j = jsonDecode(res.body);
      if (res.statusCode != 200 || (j is Map && j['ok'] != true)) {
        throw Exception('Worker error: ${res.statusCode} ${res.body}');
      }

      _toast('🗑️ Deleted: ${b.shortId}');
      await _refreshBookings();
    } catch (e) {
      _toast('❌ Delete failed: $e');
    }
  }

  Future<void> _confirmDelete(BookingItem b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete booking?'),
        content: Text(
          'This will remove the booking from the list (KV).\n\nID: ${b.bookingId}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, delete')),
        ],
      ),
    );
    if (ok == true) await _deleteBooking(b);
  }


  void _enterWaitMode() {
    if (_activeTripId == null) return;
    if (_isWaiting) return;
    setState(() {
      _isWaiting = true;
      _waitStartedAt = DateTime.now();
    });
    // TODO(worker): send WAIT_START event so backend is canonical
  }

  void _exitWaitMode() {
    if (_activeTripId == null) return;
    if (!_isWaiting) return;
    final started = _waitStartedAt;
    setState(() {
      _isWaiting = false;
      _waitStartedAt = null;
      if (started != null) {
        _waitElapsed += DateTime.now().difference(started);
      }
    });
    // TODO(worker): send WAIT_END event so backend is canonical
  }

  Duration get _effectiveWaitElapsed {
    if (_isWaiting && _waitStartedAt != null) {
      return _waitElapsed + DateTime.now().difference(_waitStartedAt!);
    }
    return _waitElapsed;
  }

  double get _displayTotalEur {
    final b = _activeBooking;
    final fixed = (b != null) ? b.price : null;
    if (fixed is num && fixed > 0) return fixed.toDouble();

    final km = _kmDriven;
    final waitMin = _effectiveWaitElapsed.inSeconds / 60.0;
    return _fallbackStartFee + (km * _fallbackPerKm) + (waitMin * _fallbackWaitPerMin);
  }

  String get _displayTotalText => '€ ${_displayTotalEur.toStringAsFixed(2)}';

Future<void> _stopTrip() async {
    final trip = _activeTripId;
    if (trip == null) return;

    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kStopTripPath');
      final payload = {'session_id': trip, 'driver_id': kDriverId};
      await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    _stopTrackingInternal();

    try {
      if (_routeLineManager != null && _routeLine != null) {
        await _routeLineManager!.delete(_routeLine!);
      }
      _routeLine = null;

      if (_pinsPointManager != null) {
        if (_pickupPin != null) await _pinsPointManager!.delete(_pickupPin!);
        if (_dropoffPin != null) await _pinsPointManager!.delete(_dropoffPin!);
      }
      _pickupPin = null;
      _dropoffPin = null;
    } catch (_) {}

    setState(() {
      _activeTripId = null;
      _activeBooking = null;
      _lastPing = '—';
      _pingCount = 0;
      _kmDriven = 0.0;

      _routeCoords = [];
      _routeKm = null;
      _routeDurationSec = null;

      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;

      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
    });
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _toast('Location is disabled on the phone.');
      return;
    }

    geo.LocationPermission perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      _toast('Location permission denied.');
      return;
    }
  }

  void _startTrackingInternal() {
    _bookingPollTimer?.cancel();
    _posSub?.cancel();

    const settings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.best,
      distanceFilter: 10,
    );

    _posSub = geo.Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
      final prev = _lastPos;
      _lastPos = pos;
      _startPos ??= pos;

      if (prev != null) {
        final meters = geo.Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (meters.isFinite && meters > 0) {
          // Only count driven distance once the trip is actually started.
          if (_activeTripId != null) {
            if (mounted) setState(() => _kmDriven += meters / 1000.0);
          }
        }

        if (_activeTripId != null && !_hasSwitchedToFollow && _startPos != null) {
          final movedFromStart = geo.Geolocator.distanceBetween(
            _startPos!.latitude,
            _startPos!.longitude,
            pos.latitude,
            pos.longitude,
          );
          final speedKmh = (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0);
          if (speedKmh >= 3.0 || movedFromStart >= 25.0) {
            _hasSwitchedToFollow = true;
            _cameraMode = _CameraMode.follow;
          }
        }
      }

      if (_mapSupported && _map != null && _driverPointManager != null) {
        await _updateDriverMarker(pos);
        if (_followCar && _cameraMode == _CameraMode.follow) {
          await _followCameraTesla(pos);
        }
      }

      await _sendPing(pos);
    });
  }

  void _stopTrackingInternal() {
    _posSub?.cancel();
    _posSub = null;
    _startPos = null;
  }

  /// ===============================
  /// HUD COMPUTED TEXTS (single source of truth)
  /// ===============================

  bool get _isTracking => _activeTripId != null && _posSub != null;

  String get _etaText {
    // Countdown style ETA (remaining), used both in preview and in active trip.
    final total = _routeDurationSec;
    if (total == null || total <= 0) return '';

    // When tracking, subtract progress (based on km fraction). When previewing, show total.
    int remainingSec;
    if (_isTracking) {
      remainingSec = _timeRemainingSeconds ?? total;
    } else {
      // Not tracking yet (preview)
      remainingSec = total;
    }

    remainingSec = math.max(0, remainingSec);
    if (remainingSec < 60) return '<1 min';

    final minutes = (remainingSec / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String get _kmRemainingText {
    // Show in preview as soon as we have a route.

    final remaining = _kmRemaining;
    if (remaining == null) return '';
    if (remaining < 0.05) return '0.0';
    return remaining.toStringAsFixed(1);
  }

  String get _timeRemainingText {
    if (!_isTracking) return '';
    final sec = _timeRemainingSeconds;
    if (sec == null) return '';
    final minutes = (sec / 60.0).round();
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  double? get _kmRemaining {
    final rk = _routeKm;
    if (rk == null) return null;
    final v = rk - _kmDriven;
    return v < 0 ? 0 : v;
  }

  int? get _timeRemainingSeconds {
    final total = _routeDurationSec;
    final rk = _routeKm;
    if (total == null || rk == null) return null;
    if (rk <= 0.01) return total;
    final fracDriven = (_kmDriven / rk).clamp(0.0, 1.0);
    final remaining = (total * (1.0 - fracDriven)).round();
    return remaining < 0 ? 0 : remaining;
  }

  /// Map HUD actions
  Future<void> _stopTracking() async {
    // Stop UI + pings immediately (best UX)
    _stopTrackingInternal();

    // Try to notify Worker (best-effort)
    try {
      await _stopTrip();
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openNavigation() async {
    // Premium default: toggle camera mode between overview and follow-car.
    if (_map == null) return;

    setState(() {
      if (_cameraMode == _CameraMode.follow) {
        _cameraMode = _CameraMode.overview;
      } else {
        _cameraMode = _CameraMode.follow;
        _hasSwitchedToFollow = true;
      }
    });

    final pos = _lastPos;
    if (pos != null && _cameraMode == _CameraMode.follow) {
      await _followCameraTesla(pos);
    } else {
      await _fitBoundsToRoute(_routeCoords);
    }
  }

  Future<void> _sendPing(geo.Position pos) async {
    final trip = _activeTripId;
    if (trip == null) return;

    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kPingPath');
      final payload = {
        'session_id': trip,
        'driver_id': kDriverId,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'speed': (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0),
        'heading': (pos.heading.isFinite ? pos.heading : 0.0),
        'accuracy_m': pos.accuracy,
        'ts': DateTime.now().toIso8601String(),
      };

      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _pingCount += 1;
        _lastPing = (res.statusCode == 200) ? 'OK' : 'HTTP ${res.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastPing = 'ERR');
    }
  }

  Future<void> _onMapCreated(mb.MapboxMap mapboxMap) async {
    _map = mapboxMap;

    // ✅ less “pitch black” but still premium
    try {
      await mapboxMap.style
          .setStyleURI('mapbox://styles/mapbox/navigation-night-v1');
    } catch (_) {}

    _driverPointManager =
        await mapboxMap.annotations.createPointAnnotationManager();
    _pinsPointManager =
        await mapboxMap.annotations.createPointAnnotationManager();
    _routeLineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();

    final pos = _lastPos;
    if (pos != null) {
      await _updateDriverMarker(pos, moveCamera: true);
    }
  }

  mb.Point _mbPoint(double lon, double lat) =>
      mb.Point(coordinates: mb.Position(lon, lat));

  Future<void> _updateDriverMarker(geo.Position pos,
      {bool moveCamera = false}) async {
    final mgr = _driverPointManager;
    if (mgr == null) return;

    final p = _mbPoint(pos.longitude, pos.latitude);

    if (_driverMarker == null) {
      _driverMarker = await mgr.create(
        mb.PointAnnotationOptions(
          geometry: p,
          iconSize: 1.2,
        ),
      );
    } else {
      _driverMarker!.geometry = p;
      await mgr.update(_driverMarker!);
    }

    if (moveCamera) {
      await _map?.flyTo(
        mb.CameraOptions(center: p, zoom: 13.5),
        mb.MapAnimationOptions(duration: 700),
      );
    }
  }

  Future<void> _followCameraTesla(geo.Position pos) async {
    final p = _mbPoint(pos.longitude, pos.latitude);
    final heading =
        (pos.heading.isFinite && pos.heading >= 0) ? pos.heading : 0.0;

    await _map?.flyTo(
      mb.CameraOptions(
        center: p,
        zoom: 16.0,
        bearing: heading,
        pitch: 50.0,
      ),
      mb.MapAnimationOptions(duration: 650),
    );
  }


  Future<void> _centerOnMe() async {
    final pos = _lastPos;
    if (pos == null) {
      _toast('Nog geen GPS-positie');
      return;
    }

    // If follow-cam is enabled and a trip is active, use the Tesla-style follow.
    if (_followCar && _activeTripId != null) {
      await _followCameraTesla(pos);
      return;
    }

    final p = _mbPoint(pos.longitude, pos.latitude);
    await _map?.flyTo(
      mb.CameraOptions(center: p, zoom: 13.5),
      mb.MapAnimationOptions(duration: 650),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // -------------------------------
  // ROUTE (Overview -> Follow)
  // -------------------------------

  Future<void> _buildOverviewRoute(BookingItem b) async {
    if (!_mapSupported || _map == null) return;
    if ((b.from ?? '').isEmpty || (b.to ?? '').isEmpty) return;

    try {
      // Prefer server-side routing (Worker) so the app never needs to call Mapbox Directions directly.
      await _tryWorkerRouteFallback(b);
      if (_routeCoords.length >= 2) return;

      // Fallback: direct Mapbox REST (dev only). If MAPBOX_TOKEN isn't provided, we stop here.
      if (kMapboxToken.trim().isEmpty) {
        return;
      }

      final fromLL = await _geocodeOne(b.from!);
      final toLL = await _geocodeOne(b.to!);

      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      final distanceMeters = route.$2;
      final durationSec = route.$3;

      if (coords.length < 2) return;

      setState(() {
        _routeCoords = coords;
        _routeKm = distanceMeters / 1000.0;
        _routeDurationSec = durationSec;
        _cameraMode = _CameraMode.overview;
      });

      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
      await _fitBoundsToRoute(coords);
    } on _UnauthorizedMapbox catch (_) {
      _toast(
        'Mapbox REST token refused (401) — using Worker route instead.',
      );
      await _tryWorkerRouteFallback(b);
    } catch (e) {
      _toast('Route overview failed: $e');
      await _tryWorkerRouteFallback(b);
    }
  }

  Future<void> _tryWorkerRouteFallback(BookingItem b) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kWorkerRoutePath');
      final payload = {'from': b.from, 'to': b.to};

      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 404) {
        _toast(
          'Route via Worker not available yet (404). Implement $kWorkerRoutePath to avoid exposing Mapbox token.',
        );
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('Worker route HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;

      final coordsAny =
          (j['coords'] ?? j['coordinates'] ?? j['route_coords'] ?? j['points']);
      List<dynamic> raw;
      if (coordsAny is List) {
        raw = coordsAny;
      } else if (j['geometry'] is Map<String, dynamic>) {
        raw = (j['geometry']['coordinates'] as List<dynamic>? ?? []);
      } else {
        raw = const [];
      }

      final out = <_LonLat>[];
      for (final c in raw) {
        if (c is List && c.length >= 2) {
          out.add(_LonLat((c[0] as num).toDouble(), (c[1] as num).toDouble()));
        }
      }

      if (out.length < 2) return;

      final dist = (j['distance_m'] ??
              j['distanceMeters'] ??
              j['distance'] ??
              0) as num;
      final dur =
          (j['duration_s'] ?? j['durationSec'] ?? j['duration'] ?? 0) as num;

      final fromLL = out.first;
      final toLL = out.last;

      setState(() {
        _routeCoords = out;
        _routeKm = dist.toDouble() / 1000.0;
        _routeDurationSec = dur.toInt();
        _cameraMode = _CameraMode.overview;
      });

      await _drawPins(fromLL, toLL);
      await _drawRouteLine(out);
      await _fitBoundsToRoute(out);
    } catch (e) {
      _toast('Worker route failed: $e');
    }
  }

  Future<_LonLat> _geocodeOne(String query) async {
    final q = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$q.json'
      '?access_token=$kMapboxToken&limit=1&country=BE&language=nl',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('geocoding');
    if (res.statusCode != 200) {
      throw Exception('Geocode HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final feats = (j['features'] as List<dynamic>? ?? []);
    if (feats.isEmpty) throw Exception('No geocode result for "$query"');
    final center =
        (feats.first as Map<String, dynamic>)['center'] as List<dynamic>;
    final lon = (center[0] as num).toDouble();
    final lat = (center[1] as num).toDouble();
    return _LonLat(lon, lat);
  }

  Future<(List<_LonLat>, double, int)> _directionsRoute(
      _LonLat from, _LonLat to) async {
    final coords = '${from.lon},${from.lat};${to.lon},${to.lat}';
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?alternatives=false&geometries=geojson&overview=full&steps=false'
      '&access_token=$kMapboxToken',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('directions');
    if (res.statusCode != 200) {
      throw Exception('Directions HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = (j['routes'] as List<dynamic>? ?? []);
    if (routes.isEmpty) throw Exception('No route returned.');
    final r0 = routes.first as Map<String, dynamic>;
    final distance = (r0['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (r0['duration'] as num?)?.toInt() ?? 0;
    final geom = (r0['geometry'] as Map<String, dynamic>?) ?? {};
    final line = (geom['coordinates'] as List<dynamic>? ?? []);
    final out = <_LonLat>[];
    for (final c in line) {
      final pair = c as List<dynamic>;
      out.add(_LonLat((pair[0] as num).toDouble(), (pair[1] as num).toDouble()));
    }
    return (out, distance, duration);
  }

  Future<void> _drawPins(_LonLat pickup, _LonLat dropoff) async {
    final mgr = _pinsPointManager;
    if (mgr == null) return;

    try {
      if (_pickupPin != null) await mgr.delete(_pickupPin!);
      if (_dropoffPin != null) await mgr.delete(_dropoffPin!);
    } catch (_) {}

    _pickupPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(pickup.lon, pickup.lat),
        iconSize: 1.1,
      ),
    );

    _dropoffPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(dropoff.lon, dropoff.lat),
        iconSize: 1.1,
      ),
    );
  }

  Future<void> _drawRouteLine(List<_LonLat> coords) async {
    final mgr = _routeLineManager;
    if (mgr == null) return;

    try {
      if (_routeLine != null) await mgr.delete(_routeLine!);
    } catch (_) {}

    final geometry = mb.LineString(
      coordinates: coords.map((c) => mb.Position(c.lon, c.lat)).toList(),
    );

    _routeLine = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: 6.0,
        lineOpacity: 0.90,
      ),
    );
  }

  Future<void> _fitBoundsToRoute(List<_LonLat> coords) async {
    if (_map == null || coords.isEmpty) return;

    double minLon = coords.first.lon, maxLon = coords.first.lon;
    double minLat = coords.first.lat, maxLat = coords.first.lat;
    for (final c in coords) {
      if (c.lon < minLon) minLon = c.lon;
      if (c.lon > maxLon) maxLon = c.lon;
      if (c.lat < minLat) minLat = c.lat;
      if (c.lat > maxLat) maxLat = c.lat;
    }

    final topPad = MediaQuery.of(context).padding.top + 86;
    final bottomPad = MediaQuery.of(context).padding.bottom + 210;

    try {
      final cam = await _map!.cameraForCoordinateBounds(
        mb.CoordinateBounds(
          southwest: _mbPoint(minLon, minLat),
          northeast: _mbPoint(maxLon, maxLat),
          infiniteBounds: false,
        ),
        mb.MbxEdgeInsets(top: topPad, left: 40, bottom: bottomPad, right: 40),
        null,
        null,
        null,
        null,
      );
      await _map!.flyTo(cam, mb.MapAnimationOptions(duration: 900));
    } catch (_) {
      final center = _mbPoint((minLon + maxLon) / 2, (minLat + maxLat) / 2);
      await _map!.flyTo(
        mb.CameraOptions(center: center, zoom: 12.5),
        mb.MapAnimationOptions(duration: 900),
      );
    }
  }

  
  void _markBootFirstLoadDone() {
    if (_bootFirstLoadDone) return;
    _bootFirstLoadDone = true;
    _maybeHideBootSplash();
  }

  void _maybeHideBootSplash() {
    if (!_bootSplashVisible) return;
    if (!_bootMinElapsed) return;
    if (!_bootFirstLoadDone) return;
    if (!mounted) return;
    setState(() {
      _bootSplashVisible = false;
      _showBootSplash = false;
    });
  }



  Widget _buildIdlePanel() {
    final canStart = _manualFromCtrl.text.trim().isNotEmpty && _manualToCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kGlow, width: 1.4),
          boxShadow: const [
            BoxShadow(blurRadius: 18, spreadRadius: 1.2, offset: Offset(0, 10)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live rit (handmatig)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualFromCtrl,
              focusNode: _fromFocus,
              onChanged: _onFromChanged,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Van (bv. Gent, straat, POI)').copyWith(
                suffixIcon: IconButton(
                  tooltip: 'Gebruik huidige locatie',
                  icon: const Icon(Icons.my_location, color: Color(0xFFFFD54A)),
                  onPressed: _useCurrentLocationAsFrom,
                ),
              ),
            ),
            if (_fromFocus.hasFocus) _suggestionList(
              items: _fromSuggestions,
              onPick: (s) {
                _manualFromCtrl.text = s.label;
                _manualFromPoint = (s.lon != null && s.lat != null)
                    ? mb.Point(coordinates: mb.Position(s.lon!, s.lat!))
                    : null;
                setState(() => _fromSuggestions = <_PlaceSuggestion>[]);
                FocusScope.of(context).requestFocus(_toFocus);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualToCtrl,
              focusNode: _toFocus,
              onChanged: _onToChanged,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Naar (bestemming)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isStartingTrip ? null : _startManualTrip,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_isStartingTrip ? 'Starten…' : 'Start rit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canStart ? const Color(0xFF1B7F3A) : Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: kGlow, width: 1.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            if (_toFocus.hasFocus) _suggestionList(
              items: _toSuggestions,
              onPick: (s) {
                _manualToCtrl.text = s.label;
                _manualToPoint = (s.lon != null && s.lat != null)
                    ? mb.Point(coordinates: mb.Position(s.lon!, s.lat!))
                    : null;
                setState(() => _toSuggestions = <_PlaceSuggestion>[]);
                FocusScope.of(context).unfocus();
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Tip: je kan dit gebruiken als GPS-cockpit. Zodra je start, begint tracking & telt alles mee.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.35),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kGlow, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<List<_PlaceSuggestion>> _fetchPlaceSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty || kMapboxToken.trim().isEmpty) return <_PlaceSuggestion>[];
    final encoded = Uri.encodeComponent(q);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
      '?autocomplete=true&limit=6&country=be&language=nl&access_token=$kMapboxToken',
    );
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return <_PlaceSuggestion>[];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (data['features'] as List<dynamic>? ?? const <dynamic>[]);
      final out = <_PlaceSuggestion>[];
      for (final f in feats) {
        final m = f as Map<String, dynamic>;
        final label = (m['place_name'] as String?) ?? '';
        final center = (m['center'] as List<dynamic>?);
        if (label.trim().isEmpty) continue;
        double? lon;
        double? lat;
        if (center != null && center.length >= 2) {
          lon = (center[0] as num?)?.toDouble();
          lat = (center[1] as num?)?.toDouble();
        }
        out.add(_PlaceSuggestion(label: label, lon: lon, lat: lat));
      }
      return out;
    } catch (_) {
      return <_PlaceSuggestion>[];
    }
  }

  void _onFromChanged(String v) {
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _fromSuggestions = list);
    });
  }

  void _onToChanged(String v) {
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _toSuggestions = list);
    });
  }

  Future<void> _useCurrentLocationAsFrom() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        final req = await geo.Geolocator.requestPermission();
        if (req == geo.LocationPermission.denied ||
            req == geo.LocationPermission.deniedForever) return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );
      _manualFromPoint = mb.Point(
        coordinates: mb.Position(pos.longitude, pos.latitude),
      );
      _manualFromCtrl.text = 'Mijn locatie';
      setState(() {
        _fromSuggestions = <_PlaceSuggestion>[];
      });
    } catch (_) {}
  }

  Widget _suggestionList({required List<_PlaceSuggestion> items, required void Function(_PlaceSuggestion) onPick}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FFD54A)),
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0x22000000)),
        itemBuilder: (_, i) {
          final s = items[i];
          return ListTile(
            dense: true,
            title: Text(
              s.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => onPick(s),
          );
        },
      ),
    );
  }


  Future<void> _startManualTrip() async {
    final from = _manualFromCtrl.text.trim();
    final to = _manualToCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      _toast('Vul zowel "Van" als "Naar" in.');
      return;
    }

    final id = 'MANUAL-${DateTime.now().millisecondsSinceEpoch}';
    final b = BookingItem(
      bookingId: id,
      from: from,
      to: to,
      pickupIso: DateTime.now().toUtc().toIso8601String(),
      status: 'manual',
      currency: 'EUR',
    );

    await _startTrip(b);
  }


  Widget _buildBrandBar(bool tripActive) {
    // Robust top bar: larger logo + stronger presence.
    // Pulse only when a trip is active (cockpit mode).
    final pulse = tripActive ? (0.70 + 0.30 * _activePulse.value) : 0.0;

    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: kFluxidiPanel.withOpacity(0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: kFluxidiYellowSoft.withOpacity(tripActive ? 0.55 * pulse : 0.20),
                    blurRadius: tripActive ? (28 * pulse) : 18,
                    spreadRadius: tripActive ? (2 * pulse) : 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  _GlowIconButton(
                    icon: Icons.menu,
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 10),
                  // Pulsing logo capsule (only on active trip)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.black.withOpacity(0.18),
                      border: Border.all(
                        color: const Color(0xFFFFD36A).withOpacity(tripActive ? (0.30 + 0.25 * pulse) : 0.18),
                      ),
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(0x66F5C400).withOpacity(0.55 * pulse),
                                blurRadius: 26 * pulse,
                                spreadRadius: 2 * pulse,
                              ),
                            ]
                          : const [],
                    ),
                    child: Transform.scale(
                      scale: tripActive ? (1.00 + 0.05 * pulse) : 1.0,
                      child: Image.asset(
                        kFluxidiLogoAsset,
                        height: 40,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => const Text(
                          'Fluxidi',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tripActive ? 'Rit actief' : 'Driver console',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tripActive ? const Color(0xFF4CD964) : Colors.white38,
                      shape: BoxShape.circle,
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(0x554CD964).withOpacity(0.7),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ===============================
  /// Fluxidi Cockpit UI (Design v1)
  /// ===============================

  /// Top status strip: branding + single dot (no extra text)
  Widget _buildStatusStrip(int state) {
    final bool active = state != 0;
    final dotColor = (state == 2)
        ? Colors.greenAccent
        : (state == 1)
            ? Colors.amberAccent
            : Colors.redAccent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 140,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              // Hamburger (everyone understands this)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: Icon(
                  Icons.menu_rounded,
                  color: Colors.white.withOpacity(0.88),
                  size: 32,
                ),
              ),

              // Center logo (bigger, cockpit-style)
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _activePulseCtrl,
                    builder: (_, __) {
                      final pulse =
                          active ? (0.98 + 0.04 * _activePulse.value) : 1.0;
                      return Transform.scale(
                        scale: (pulse * 1.6),
                        child: Image.asset(
                          kFluxidiLogoAsset,
                          height: 92, // dashboard badge (reduced)
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.local_taxi,
                            size: 72,
                            color: Colors.white70,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Single status dot (pulses only when active)
              AnimatedBuilder(
                animation: _activePulseCtrl,
                builder: (_, __) {
                  final pulse =
                      active ? (0.75 + 0.25 * _activePulse.value) : 1.0;
                  return Transform.scale(
                    scale: (pulse * 1.6),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withOpacity(active ? 1.0 : 0.9),
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withOpacity(active ? 0.55 : 0.35),
                            blurRadius: active ? 18 : 10,
                            spreadRadius: active ? 2 : 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom glass HUD (map remains primary)
  Widget _buildCockpitHud({required bool liveActive}) {
    final b = _activeBooking;
    final from = (b?.from ?? '').trim();
    final to = (b?.to ?? '').trim();

    final routeText = [
      if (from.isNotEmpty) 'A: $from',
      if (to.isNotEmpty) 'B: $to',
    ].join('  ->  ');

    // Fallback if destination is missing
    final hasB = to.isNotEmpty;
    final routeTextSafe = hasB ? routeText : (routeText.isNotEmpty ? (routeText + '  ->  B: —') : 'B: —');

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Route ticker (only route, no labels/icons beyond A/B)
                if (routeText.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: Colors.white.withOpacity(0.06),
                      child: Center(
                        child: RouteMarquee(
                          key: const ValueKey('route_marquee'),
                          text: routeTextSafe,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            letterSpacing: 0.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Price orb + mode (fixed/live) — minimal, cockpit-style
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.18),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 18,
                              spreadRadius: 1,
                              color: (liveActive ? Colors.greenAccent : Colors.amberAccent).withOpacity(0.12),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            liveActive ? '●' : '◐',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: liveActive ? Colors.greenAccent : Colors.amberAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // Primary action
                Center(
                child: SizedBox(
                  width: 220,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: liveActive
                          ? Colors.redAccent.withOpacity(0.95)
                          : const Color(0xFF1B7F3A),
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ).copyWith(
                      side: MaterialStateProperty.all(
                        BorderSide(
                          color: liveActive
                              ? Colors.redAccent.withOpacity(0.95)
                              : kFluxidiYellow.withOpacity(0.95),
                          width: 1.2,
                        ),
                      ),
                      overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft),
                    ),
                    onPressed: () async {
                      if (liveActive) {
                        await _stopTripSafely();
                      } else {
                        final b = _activeBooking;
                        if (b == null) return;
                        await _startTrip(b);
                      }
                    },
                    child: Text(
                      liveActive ? 'STOP' : 'START',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    ),
                  ),
                ),
                ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dial({required String label, required String value, required bool big}) {
    final size = big ? 92.0 : 78.0;
    final valueStyle = TextStyle(
      color: Colors.white,
      fontSize: big ? 26 : 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    );

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.06),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                textAlign: TextAlign.center,
                style: valueStyle,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Active trip elapsed time
  Duration get _activeElapsed {
    final started = _trackingStartedAt;
    if (started == null) return Duration.zero;
    final now = DateTime.now();
    final d = now.difference(started);
    if (d.isNegative) return Duration.zero;
    return d;
  }

  String get _etaString {
    // ETA as countdown (remaining time), not clock-time.
    final totalSec = _routeDurationSec;
    if (totalSec == null || totalSec <= 0) return '—';

    final elapsed = _activeElapsed.inSeconds;
    final remaining = math.max(0, totalSec - elapsed);

    if (remaining < 60) return '<1 min';

    final minutes = (remaining / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<void> _stopTripSafely() async {
    // Keep existing stop logic if present
    await _stopTrip();
  }

  String _formatHms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }



  Widget _buildBootSplashOverlay() {

final pulse = _splashPulse.value;

// Premium boot overlay: subtle golden aura + animated ring + logo shimmer.
return IgnorePointer(
  ignoring: true,
  child: AnimatedOpacity(
    duration: const Duration(milliseconds: 280),
    opacity: _showBootSplash ? 1 : 0,
    child: Container(
      color: const Color(0xFF070709),
      child: Stack(
        children: [
          // Background aura
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 0.95,
                  colors: [
                    const Color(0x33FFD36A).withOpacity(0.35 + 0.15 * pulse),
                    const Color(0x00070709),
                  ],
                ),
              ),
            ),
          ),

          // Center brand
          Center(
            child: AnimatedBuilder(
              animation: _splashAnimCtrl,
              builder: (context, _) {
                final p = _splashPulse.value;
                final ringAlpha = (0.22 + 0.18 * p).clamp(0.0, 1.0);
                final glowAlpha = (0.45 + 0.30 * p).clamp(0.0, 1.0);
                final scale = 0.985 + 0.025 * p;

                return Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 280,
                        height: 280,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer animated ring
                            Container(
                              width: 268,
                              height: 268,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Color.fromRGBO(255, 211, 106, ringAlpha),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color.fromRGBO(255, 211, 106, glowAlpha),
                                    blurRadius: 28 + 18 * p,
                                    spreadRadius: 2 + 2 * p,
                                  ),
                                ],
                              ),
                            ),

                            // Inner soft ring
                            Container(
                              width: 214,
                              height: 214,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Color.fromRGBO(255, 211, 106, (ringAlpha * 0.55).clamp(0.0, 1.0)),
                                  width: 1,
                                ),
                              ),
                            ),

                            // Logo + shimmer mask
                            ShaderMask(
                              shaderCallback: (rect) {
                                // Shimmer sweeps horizontally across the logo
                                final t = _splashAnimCtrl.value; // 0..1
                                final start = -0.6 + 1.6 * t;
                                return LinearGradient(
                                  begin: Alignment(start, 0),
                                  end: Alignment(start + 0.8, 0),
                                  colors: const [
                                    Color(0x66FFFFFF),
                                    Color(0xFFFFFFFF),
                                    Color(0x66FFFFFF),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ).createShader(rect);
                              },
                              blendMode: BlendMode.srcATop,
                              child: Image.asset(
                                kFluxidiLogoAsset,
                                width: 210,
                                height: 210,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stack) {
                                  return const Text(
                                    'FLUXIDI',
                                    style: TextStyle(
                                      color: Color(0xFFFFD36A),
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 4,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Fluxidi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Driver • Live Tracking',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Minimal loading hint
                      SizedBox(
                        width: 120,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: const Color(0x22FFFFFF),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color.fromRGBO(255, 211, 106, (0.75 + 0.20 * p).clamp(0.0, 1.0)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  ),
);
  }

  ButtonStyle _ghostButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: kFluxidiYellow.withOpacity(0.85), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ).copyWith(
      overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft),
    );
  }

  ButtonStyle _startButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: Colors.black.withOpacity(0.55),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ).copyWith(
      side: MaterialStateProperty.all(
        BorderSide(color: kFluxidiYellow.withOpacity(0.95), width: 1.2),
      ),
      shadowColor: MaterialStateProperty.all(kFluxidiYellowSoft),
      elevation: MaterialStateProperty.all(0),
      overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft),
    );
  }


  // -------------------------------
  // UI helpers for stats
  // -------------------------------

  int? _remainingSec() {
    final remainingKm =
        (_routeKm != null) ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0) : null;
    if (_routeDurationSec == null ||
        _routeKm == null ||
        _routeKm! <= 0 ||
        remainingKm == null) return null;
    final ratio = (remainingKm / _routeKm!).clamp(0.0, 1.0);
    return (_routeDurationSec! * ratio).round();
  }

  String _fmtDur(int? sec) {
    if (sec == null) return '—';
    final m = (sec / 60).round();
    if (m < 60) return '$m min';
    final h = (m / 60).floor();
    final mm = m % 60;
    return '${h}u ${mm}m';
  }

  String _fmtRemainingKm() {
    final remainingKm =
        (_routeKm != null) ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0) : null;
    if (remainingKm == null) return '—';
    return remainingKm.toStringAsFixed(1);
  }

  String _fmtPrice() {
    final b = _activeBooking;
    if (b?.price == null) return '—';
    return b!.price!.toStringAsFixed(2);
  }


  String _fmtMoney(num amount, String currency) {
    // Keep it simple & predictable (no locale surprises)
    final value = amount.toDouble().toStringAsFixed(2);
    final cur = currency.toUpperCase();
    if (cur == 'EUR' || cur == 'EURO' || cur == '€') return '€ $value';
    if (cur.length <= 3) return '$cur $value';
    return '$value';
  }


  // -------------------------------
  // UI
  // -------------------------------

  Widget _buildHintPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF081126).withOpacity(0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22),
              width: 1.1,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFFFD36A)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Open menu → Boekingen om een rit te kiezen, of menu → Live rit voor handmatig.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final bool liveActive = _activeTripId != null;
    final bool hasSelection = _activeBooking != null;
    final int state = liveActive ? 2 : (hasSelection ? 1 : 0);
    final bool showCockpit = liveActive || hasSelection;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          Positioned.fill(child: _buildMapLayer()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12,
            right: 12,
            child: _buildStatusStrip(state),
          ),
          if (showCockpit)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 10,
              child: _buildCockpitWidget(),
            ),
          if (!showCockpit && _showManualLivePanel)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      10,
                ),
                child: _buildIdlePanel(),
              ),
            ),
          if (!showCockpit && !_showManualLivePanel)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 10,
              child: _buildHintPanel(),
            ),
          ],
        ),
    );
  }

  Widget _buildMapLayer() {
    if (kIsWindows) {
      return _mapPlaceholder(
        title: 'Map unavailable on Windows',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    if (kIsWeb) {
      return _mapPlaceholder(
        title: 'Map unavailable on Web',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    return mb.MapWidget(
      key: const ValueKey('mapbox_map'),
      onMapCreated: _onMapCreated,
      styleUri: 'mapbox://styles/mapbox/streets-v12',
      cameraOptions: mb.CameraOptions(
        center: _mbPoint(3.62, 50.78),
        zoom: 12.0,
      ),
    );
  }

  Widget _mapPlaceholder({required String title, required String subtitle}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.2,
          colors: [
            Color(0xFF141B2F),
            Color(0xFF070A10),
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141B2F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatus(bool active) {
    if (!active) return const SizedBox.shrink();

    final eta = _fmtDur(_remainingSec());
    final km = _fmtRemainingKm();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10, color: Color(0xFF4CD964)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tracking actief • Ping: $_lastPing • ETA: $eta • KM: $km',
              style: const TextStyle(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFED6A5A).withOpacity(0.28),
              foregroundColor: const Color(0xFFFFB4AA),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _stopTrip,
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsSheet(double screenH) {
    final padding = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.all(12),
      padding:
          EdgeInsets.only(left: 14, right: 14, top: 14, bottom: 14 + padding),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
          BoxShadow(blurRadius: 26, spreadRadius: 1, color: kFluxidiYellowSoft),
        ],
      ),
      child: _buildBookingsList(screenH),
    );
  }

  Widget _buildBookingsList(double screenH) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Beschikbare ritten',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            OutlinedButton.icon(
              style: _ghostButtonStyle(),
              onPressed: _refreshBookings,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Vernieuw'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingBookings)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_bookingsError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Error: $_bookingsError',
                style: const TextStyle(color: Colors.redAccent)),
          )
        else if (_bookings.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Geen ritten gevonden.'),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _bookingCard(_bookings[i]),
            ),
          ),
      ],
    );
  }

  Widget _bookingCard(BookingItem b) {
    final dt = _formatPickup(b.pickupIso);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2240),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(icon: Icons.schedule, text: dt),
                  _pill(
                    icon: Icons.timelapse,
                    text: (b.status ?? 'PENDING').toUpperCase(),
                    borderColor: const Color(0xFFB07A2A),
                    textColor: const Color(0xFFE7B46A),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    style: _startButtonStyle(),
                    onPressed: () => _goToRide(b),
                    child: const Text('Ga naar rit'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _line(
              icon: Icons.radio_button_checked,
              title: 'Pickup',
              value: b.from ?? '—',
              maxLines: 2),
          const SizedBox(height: 6),
          _line(
              icon: Icons.place,
              title: 'Dropoff',
              value: b.to ?? '—',
              maxLines: 2),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(text: (b.tier ?? 'premium').toUpperCase()),
              _pill(text: '${b.pax ?? 0} pax'),
              _pill(text: '${b.bags ?? 0} bags'),
              _pill(text: 'ID: ${b.shortId}', textColor: Colors.white70),
              if (b.price != null) _pill(text: _fmtMoney(b.price!, b.currency ?? 'EUR')),
              if ((b.status ?? '').isNotEmpty) _pill(text: (b.status ?? '').toUpperCase(), textColor: Colors.white70),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: _ghostButtonStyle(),
                  onPressed: () => _setBookingStatus(b, 'COMPLETED'),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Completed'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: _ghostButtonStyle(),
                  onPressed: () => _setBookingStatus(b, 'CANCELLED'),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancelled'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => _confirmDelete(b),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildCockpitWidget() {
    // Bottom “cockpit” HUD — staggered round dials + one primary action.
    final eta = _etaText.isNotEmpty ? _etaText : '—';
    final km = _kmRemainingText.isNotEmpty ? _kmRemainingText : '—';
    final timeStr = _fmtDur(_activeElapsed.inSeconds);
    final modeStr = (_activeBooking?.price == null) ? 'LIVE' : 'FIXED';

    return CockpitWidget(
      activePulse: _activePulse,
      tripActive: _isTracking,
      isWaiting: _isWaiting,
      isStartingTrip: _isStartingTrip,
      hasActiveBooking: _activeBooking != null,
      from: _activeBooking?.from,
      to: _activeBooking?.to,
      etaText: eta,
      kmRemainingText: km,
      timeText: timeStr,
      priceText: _displayTotalText,
      modeText: modeStr,
      onEnterWaitMode: _enterWaitMode,
      onExitWaitMode: _exitWaitMode,
      onCenterOnMe: _centerOnMe,
      onStopTrip: _stopTrip,
      onNavigate: _openNavigation,
      onStartTrip: () {
        final b = _activeBooking;
        if (b == null) return;
        _startTrip(b);
      },
    );
  }

  Widget _dialGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;

        return Container(
          height: 86,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0xFF0B1733).withOpacity(0.55),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.20 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0x66F5C400).withOpacity(0.10 * t),
                  blurRadius: 22 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Round dial
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.18),
                    border: Border.all(
                      color: const Color(0xFFFFD36A).withOpacity(0.22 + 0.22 * t),
                      width: 1.0,
                    ),
                    boxShadow: [
                      if (highlight)
                        BoxShadow(
                          color: const Color(0x66F5C400).withOpacity(0.18 * t),
                          blurRadius: 18 * t,
                          spreadRadius: 1 * t,
                        ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: const Color(0xFFFFD36A).withOpacity(0.92)),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Label (right side)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: _activePulse,
        builder: (context, _) {
          final t = (0.65 + 0.35 * _activePulse.value);
          return Container(
            height: 86,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: filled ? const Color(0xFF3B2230) : const Color(0xFF0B1733).withOpacity(0.45),
              border: Border.all(
                color: filled
                    ? const Color(0xFFFFA7C0).withOpacity(0.50 + 0.25 * t)
                    : const Color(0xFFFFD36A).withOpacity(0.26 + 0.14 * t),
                width: 1.2,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: const Color(0x66FFA7C0).withOpacity(0.16 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0x66F5C400).withOpacity(0.10 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: filled ? const Color(0xFFFFA7C0) : const Color(0xFFFFD36A)),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cockpitGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, child) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF0B1733).withOpacity(0.65),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0xFFFFD36A).withOpacity(0.10 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFFFD36A).withOpacity(0.9)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cockpitAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: filled ? const Color(0xFF3B2230) : const Color(0xFF0B1733).withOpacity(0.55),
          border: Border.all(
            color: filled
                ? const Color(0xFFFFA7C0).withOpacity(0.55)
                : const Color(0xFFFFD36A).withOpacity(0.28),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: filled ? const Color(0xFFFFA7C0) : const Color(0xFFFFD36A)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyStat(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.70), fontSize: 12)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildActiveDetailsSheet() {
    final b = _activeBooking;

    return DraggableScrollableSheet(
      // ✅ smaller collapsed size so it doesn't hide the values
      initialChildSize: 0.10,
      minChildSize: 0.10,
      // ✅ lower max so it doesn't dominate
      maxChildSize: 0.56,
      builder: (context, controller) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141B2F).withOpacity(0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
            ],
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 10,
              bottom: 18 + MediaQuery.of(context).padding.bottom + 50,
            ),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Actieve rit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (b != null) ...[
                _line(
                    icon: Icons.confirmation_number,
                    title: 'Trip ID',
                    value: _activeTripId ?? '—',
                    maxLines: 1),
                const SizedBox(height: 8),
                _line(
                    icon: Icons.radio_button_checked,
                    title: 'Pickup',
                    value: b.from ?? '—',
                    maxLines: 3),
                const SizedBox(height: 8),
                _line(
                    icon: Icons.place,
                    title: 'Dropoff',
                    value: b.to ?? '—',
                    maxLines: 3),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(text: (b.tier ?? 'premium').toUpperCase()),
                    _pill(text: '${b.pax ?? 0} pax'),
                    _pill(text: '${b.bags ?? 0} bags'),
                    _pill(text: 'Pings: $_pingCount', textColor: Colors.white70),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFED6A5A).withOpacity(0.30),
                    foregroundColor: const Color(0xFFFFB4AA),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: _stopTrip,
                  child: const Text('Stop rit',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill({
    IconData? icon,
    required String text,
    Color? borderColor,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: (textColor ?? Colors.white70)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: textColor ?? Colors.white)),
        ],
      ),
    );
  }

  Widget _line({
    required IconData icon,
    required String title,
    required String value,
    int maxLines = 2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.72), fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                // ✅ FIX: w650 doesn't exist -> w600
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPickup(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }


  void _openBookingsHub() {
    // Close drawer first for a clean transition.
    Navigator.pop(context);
    setState(() { _showManualLivePanel = false; });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _BookingsHubPage(
          title: 'Boekingen',
          buildList: (h) => _buildBookingsList(h),
          onRefresh: _refreshBookings,
        ),
      ),
    );
  }

  void _openLiveRide() async {
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    setState(() {
      // Manual live-ride panel is ONLY shown when user explicitly chooses "Live rit"
      // and there is no active booking selection and no active tracking session yet.
      _showManualLivePanel = (_activeBooking == null && _activeTripId == null);
    });
if (_activeTripId == null) {
      _toast('Geen actieve rit. Kies een booking óf start handmatig hieronder.');
      // No return: Live cockpit can be used as GPS even without an active booking.
    }

    // Bring driver focus back to the live cockpit/map.
    try {
      if (_followCar) {
        final pos = _lastPos;
        if (pos != null) {
          await _followCameraTesla(pos);
        } else {
          await _centerOnMe();
        }
      } else {
        if (_routeCoords.isNotEmpty) {
          await _fitBoundsToRoute(_routeCoords);
        } else {
          await _centerOnMe();
        }
      }
    } catch (_) {
      // Never crash the UI from a camera move.
    }
  }


  Drawer _buildDrawer() {
    String tokenBadge() {
      final t = kMapboxToken.trim();
      if (t.isEmpty) return 'NOT SET';
      if (t.length <= 10) return 'SET ($t)';
      return 'SET (${t.substring(0, 6)}…${t.substring(t.length - 4)})';
    }

    return Drawer(
      backgroundColor: const Color(0xFF141B2F),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text('Fluxidi Driver',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Driver ID: $kDriverId',
                style: TextStyle(color: Colors.white.withOpacity(0.75))),
            const SizedBox(height: 8),
            Text('Worker: $kWorkerBaseUrl',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.60), fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              'Mapbox REST token: ${tokenBadge()}',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.60), fontSize: 12),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _followCar,
              onChanged: (v) => setState(() => _followCar = v),
              title: const Text('Follow car'),
              subtitle: const Text('Tesla-style camera in driving mode'),
            ),
            
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            // === Menu: Bookings hub ===
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Boekingen'),
              subtitle: Text(
                'Bekijk & beheer ritten',
                style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openBookingsHub,
            ),

            // === Menu: Live ride (only meaningful when a trip is active) ===
            ListTile(
              leading: const Icon(Icons.navigation_rounded),
              title: const Text('Live rit'),
              subtitle: Text(
                _activeTripId == null ? 'Live cockpit (handmatig)' : 'Cockpit & kaart (actief)',
                style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openLiveRide,
            ),

            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Vernieuw ritten'),
              onTap: () {
                Navigator.pop(context);
                _refreshBookings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Center op mij'),
              onTap: () async {
                Navigator.pop(context);
                final pos = _lastPos ?? await geo.Geolocator.getCurrentPosition();
                _lastPos = pos;

                if (_map != null) {
                  final p = _mbPoint(pos.longitude, pos.latitude);
                  await _map!.flyTo(
                    mb.CameraOptions(center: p, zoom: 14.0),
                    mb.MapAnimationOptions(duration: 900),
                  );
                } else {
                  _toast('Map not available here.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}


/// Small icon button with Fluxidi yellow glow.
///
/// Used in the brand bar (menu icon, etc.). Keeps hit-area large for in-car use.

/// Full-screen Bookings Hub opened from the drawer.
/// Keeps the map screen clean: operations live here.
class _BookingsHubPage extends StatelessWidget {
  final String title;
  final Widget Function(double screenH) buildList;
  final VoidCallback onRefresh;

  const _BookingsHubPage({
    required this.title,
    required this.buildList,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Vernieuw',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141B2F).withOpacity(0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(14),
              child: buildList(h),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const _GlowIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: disabled ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: disabled
                ? const []
                : const [
                    BoxShadow(
                      color: kFluxidiYellowSoft,
                      blurRadius: 18,
                      spreadRadius: 0.5,
                    ),
                  ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: disabled ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.90),
          ),
        ),
      ),
    );

    if ((tooltip ?? '').isEmpty) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
