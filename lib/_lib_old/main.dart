import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FluxidiTrackingApp());
}

/// ===============================
/// CONFIG
/// ===============================
/// Zet dit op je Worker base URL.
/// Voorbeeld: https://fluxidi-booking-api.<jouwsubdomain>.workers.dev
const String kWorkerBaseUrl = 'https://YOUR-WORKER-URL.workers.dev';

/// Endpoints (voorstel)
/// POST /track/session/start  { booking_id, driver_id }
/// POST /track/ping           { trip_id, driver_id, lat, lon, speed_kmh, accuracy_m, ts }
///
/// Je kan deze endpoints exact zo in je Worker toevoegen.

const String kDriverId = 'fluxidi_driver_01';

class FluxidiTrackingApp extends StatelessWidget {
  const FluxidiTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFc9a45a), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF0B0B0D),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fluxidi • Driver Tracking',
      theme: theme,
      home: const DriverTrackingHome(),
    );
  }
}

class DriverTrackingHome extends StatefulWidget {
  const DriverTrackingHome({super.key});

  @override
  State<DriverTrackingHome> createState() => _DriverTrackingHomeState();
}

class _DriverTrackingHomeState extends State<DriverTrackingHome> {
  // UI state
  bool _tracking = false;
  String _status = 'Idle';
  String _hint = 'Run this on your Android driver phone for real GPS.';
  Position? _lastPos;
  DateTime? _lastUpdated;

  // Booking / trip state
  final _bookingIdCtrl = TextEditingController();
  bool _sessionStarting = false;
  String? _tripId;
  Map<String, dynamic>? _bookingSnapshot; // contains price + details from Worker

  // Streaming GPS
  StreamSubscription<Position>? _posSub;
  Timer? _pingTimer;

  @override
  void dispose() {
    _posSub?.cancel();
    _pingTimer?.cancel();
    _bookingIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location services are OFF. Enable GPS.');
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied. Enable it in Settings.');
    }
  }

  Future<Map<String, dynamic>> _startTripSession({
    required String bookingId,
  }) async {
    final uri = Uri.parse('$kWorkerBaseUrl/track/session/start');
    final body = {
      'booking_id': bookingId.trim(),
      'driver_id': kDriverId,
    };

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Session start failed (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) throw Exception('Invalid session response.');

    // Expected:
    // { trip_id, booking: { ... includes price, breakdown ... } }
    if (data['trip_id'] == null) throw Exception('Missing trip_id in response.');
    return data;
  }

  Future<void> _sendPing(Position p) async {
    if (_tripId == null) return;

    final uri = Uri.parse('$kWorkerBaseUrl/track/ping');
    final now = DateTime.now().toUtc();

    final body = {
      'trip_id': _tripId,
      'driver_id': kDriverId,
      'lat': p.latitude,
      'lon': p.longitude,
      'accuracy_m': p.accuracy,
      'speed_kmh': (p.speed * 3.6),
      'ts': now.toIso8601String(),
    };

    // Fire-and-forget, maar met error logging:
    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Niet killen — alleen tonen
        debugPrint('Ping failed ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('Ping exception: $e');
    }
  }

  Future<void> _startTracking() async {
    if (_tracking) return;

    final bookingId = _bookingIdCtrl.text.trim();
    if (bookingId.isEmpty) {
      _toast('Fill in Booking ID first.');
      return;
    }

    setState(() {
      _sessionStarting = true;
      _status = 'Starting session…';
      _hint = 'Linking booking → trip and loading price…';
    });

    try {
      await _ensureLocationPermission();

      // 1) Start trip session (get trip_id + price snapshot)
      final session = await _startTripSession(bookingId: bookingId);

      setState(() {
        _tripId = session['trip_id']?.toString();
        _bookingSnapshot = (session['booking'] is Map) ? Map<String, dynamic>.from(session['booking']) : null;
      });

      // 2) Start GPS stream
      final settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // meters
      );

      _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
        setState(() {
          _lastPos = pos;
          _lastUpdated = DateTime.now();
          _status = 'Tracking… (GPS OK)';
          _hint = 'If you want background tracking: allow Location = Always.';
          _tracking = true;
        });
      });

      // 3) Ping backend every 5s with last known position
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        final p = _lastPos;
        if (p != null) _sendPing(p);
      });
    } catch (e) {
      setState(() {
        _status = 'Idle';
        _hint = 'Error: $e';
        _tracking = false;
      });
      _toast('Error: $e');
    } finally {
      setState(() => _sessionStarting = false);
    }
  }

  Future<void> _stopTracking() async {
    if (!_tracking) return;

    await _posSub?.cancel();
    _posSub = null;
    _pingTimer?.cancel();
    _pingTimer = null;

    setState(() {
      _tracking = false;
      _status = 'Idle';
      _hint = 'Stopped. You can start again with a booking id.';
      _lastPos = null;
      _lastUpdated = null;
      // We keep trip/booking snapshot visible, but you can clear if you want:
      // _tripId = null;
      // _bookingSnapshot = null;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _fmtUpdated() => _lastUpdated?.toString() ?? '-';

  String _fmtPos() {
    final p = _lastPos;
    if (p == null) return '-';
    return '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
    // You can add heading later.
  }

  String _fmtSpeed() {
    final p = _lastPos;
    if (p == null) return '-';
    return '${(p.speed * 3.6).toStringAsFixed(1)} km/h';
  }

  String _fmtAcc() {
    final p = _lastPos;
    if (p == null) return '-';
    return '${p.accuracy.toStringAsFixed(1)} m';
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final cardBg = const Color(0xFF121216);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxidi • Driver Tracking'),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            _Card(
              title: 'Trip session',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _bookingIdCtrl,
                    enabled: !_tracking && !_sessionStarting,
                    decoration: InputDecoration(
                      labelText: 'Booking ID',
                      hintText: 'e.g. BKG_12345',
                      filled: true,
                      fillColor: cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Trip ID: ${_tripId ?? '-'}',
                          style: TextStyle(color: Colors.white.withOpacity(0.9)),
                        ),
                      ),
                      if (_sessionStarting)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _Card(
              title: 'Status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: gold),
                  ),
                  const SizedBox(height: 8),
                  Text(_hint, style: TextStyle(color: Colors.white.withOpacity(0.75))),
                  const SizedBox(height: 12),
                  _kv('Last position', _fmtPos()),
                  _kv('Speed', _fmtSpeed()),
                  _kv('Accuracy', _fmtAcc()),
                  _kv('Updated', _fmtUpdated()),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _Card(
              title: 'Booking & price',
              child: _bookingSnapshot == null
                  ? Text(
                      'No booking loaded yet. Start tracking with a booking id.',
                      style: TextStyle(color: Colors.white.withOpacity(0.75)),
                    )
                  : _BookingSummary(booking: _bookingSnapshot!),
            ),
            const SizedBox(height: 12),

            _Card(
              title: 'Controls',
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_tracking || _sessionStarting) ? null : _startTracking,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Start tracking'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _tracking ? _stopTracking : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Stop'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Text(
              'Tip: price stays server-side. App displays Worker snapshot + live GPS.',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: Colors.white.withOpacity(0.65)))),
          Expanded(child: Text(v, style: TextStyle(color: Colors.white.withOpacity(0.9)))),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BookingSummary extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _BookingSummary({required this.booking});

  @override
  Widget build(BuildContext context) {
    String money(dynamic v) {
      if (v == null) return '-';
      if (v is num) return '€ ${v.toStringAsFixed(2)}';
      return v.toString();
    }

    // Suggested fields your Worker can return:
    // booking_id, pickup, dropoff, tier, pax, bags, fixed_price, currency, breakdown{}
    final bookingId = booking['booking_id'] ?? '-';
    final pickup = booking['pickup'] ?? booking['from'] ?? '-';
    final dropoff = booking['dropoff'] ?? booking['to'] ?? '-';
    final tier = booking['tier'] ?? '-';
    final pax = booking['pax']?.toString() ?? '-';
    final bags = booking['bags']?.toString() ?? '-';
    final fixedPrice = booking['fixed_price'] ?? booking['price'] ?? null;

    final breakdown = (booking['breakdown'] is Map)
        ? Map<String, dynamic>.from(booking['breakdown'])
        : <String, dynamic>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('Booking', bookingId.toString()),
        _line('Route', '$pickup  →  $dropoff'),
        _line('Tier', tier.toString()),
        _line('Passengers', pax),
        _line('Bags', bags),
        const Divider(height: 18),
        Text(
          'Fixed price',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          money(fixedPrice),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        if (breakdown.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Breakdown', style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...breakdown.entries.map((e) => _line(e.key, e.value.toString())),
        ],
      ],
    );
  }

  Widget _line(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: TextStyle(color: Colors.white.withOpacity(0.65)))),
          Expanded(child: Text(v, style: TextStyle(color: Colors.white.withOpacity(0.9)))),
        ],
      ),
    );
  }
}
