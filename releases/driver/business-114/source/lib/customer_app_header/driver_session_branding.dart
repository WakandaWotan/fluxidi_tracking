import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../driver_session_store.dart';
import 'customer_app_header_branding.dart';

/// Public presentation only, scoped to the company code in the driver session.
/// Does not hydrate or change the device's company-owner settings.
class DriverSessionBranding extends ChangeNotifier with WidgetsBindingObserver {
  DriverSessionBranding({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_foreground) unawaited(refresh());
    });
  }

  final String baseUrl;
  final http.Client _client;
  Timer? _timer;
  String _identity = '';
  String _code = '';
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _freshPresentation = false;
  CustomerAppHeaderBranding? branding;

  static String identity(ActiveDriverSession? session) => session == null
      ? ''
      : '${session.tenantId}|${session.companyId}|${session.driverId}|${session.companyCode}';

  CustomerAppHeaderBranding? forSession(ActiveDriverSession? session) =>
      identity(session) == _identity ? branding : null;

  void updateSession(ActiveDriverSession? session) {
    final next = identity(session);
    if (next == _identity) return;
    _identity = next;
    _code = (session?.companyId ?? '').trim().isEmpty
        ? ''
        : (session?.companyCode ?? '').trim().toUpperCase();
    _generation++;
    branding = null;
    _freshPresentation = false;
    notifyListeners();
    unawaited(_restoreCached(_identity));
    unawaited(refresh());
  }

  Future<void> _restoreCached(String identity) async {
    final scope = '$baseUrl|$identity';
    final cached = await loadCachedHeaderBranding(scope);
    if (_disposed || identity != _identity || _freshPresentation) return;
    if (cached != null) {
      branding = cached;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_disposed || _code.isEmpty) return;
    final generation = ++_generation;
    final code = _code;
    try {
      final response = await _client
          .get(
            Uri.parse(baseUrl).resolve(
              '/public/company/resolve?code=${Uri.encodeQueryComponent(code)}',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (_disposed || generation != _generation) return;
      if (response.statusCode == 404) {
        _freshPresentation = true;
        unawaited(
          cacheHeaderBranding(
            '$baseUrl|$_identity',
            const CustomerAppHeaderBranding(),
          ),
        );
        branding = null;
        notifyListeners();
        return;
      }
      if (response.statusCode != 200) return;
      final raw = jsonDecode(utf8.decode(response.bodyBytes));
      if (raw is! Map ||
          raw['ok'] != true ||
          (raw['company_code'] ?? '').toString().trim().toUpperCase() != code)
        return;
      _freshPresentation = true;
      branding = CustomerAppHeaderBranding.fromJson(
        Map<String, dynamic>.from(raw),
      );
      notifyListeners();
      await cacheHeaderBranding('$baseUrl|$_identity', branding!);
    } catch (_) {
      // A temporary network failure keeps this session's last known branding.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _client.close();
    super.dispose();
  }
}
