import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'navigation_route_warnings.dart';
import 'navigation_traffic_test_session.dart';

/// Presentation evidence captured with an authenticated route response.
/// No wire-field inference: an endpoint adapter may supply this only after its
/// exact contract and authentication have been approved. Ordinary routes use null.
class NavigationRouteWarningBinding {
  const NavigationRouteWarningBinding({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.graphVersion,
    required this.manifestSha256,
    required this.evidenceRevision,
    required this.routeEvidenceId,
    required this.routeValidUntil,
    required this.attachment,
  });
  final String tenantId, companyId, driverId;
  final String graphVersion, manifestSha256, evidenceRevision, routeEvidenceId;
  final DateTime routeValidUntil;
  final dynamic attachment;
}

/// Connects the existing warning decoder to existing navigation lifecycle events.
/// It owns no network, timer, GPS, route, ETA or financial state.
class NavigationRouteWarningController extends ChangeNotifier {
  NavigationRouteWarningController({bool testBuildEnabled = false})
    : _session = NavigationTrafficTestSession(
        testBuildEnabled: testBuildEnabled,
      );

  final NavigationTrafficTestSession _session;
  DateTime? _grantExpiry;
  DateTime? _routeExpiry;
  double progressMeters = 0;
  bool progressTrusted = false;

  RouteWarnings current(DateTime now) => _session.current(now);

  void install({
    required NavigationRouteWarningBinding? binding,
    required String tenantId,
    required String companyId,
    required String driverId,
    required List<List<num>> displayedGeometry,
    required DateTime now,
  }) {
    clear();
    if (binding == null ||
        tenantId.isEmpty ||
        companyId.isEmpty ||
        driverId.isEmpty ||
        binding.tenantId != tenantId ||
        binding.companyId != companyId ||
        binding.driverId != driverId)
      return;
    final epoch = _session.applyDisplayedRoute(
      tenantId: tenantId,
      companyId: companyId,
      graphVersion: binding.graphVersion,
      manifestSha256: binding.manifestSha256,
      evidenceRevision: binding.evidenceRevision,
      routeEvidenceId: binding.routeEvidenceId,
      routeValidUntil: binding.routeValidUntil,
      geometry: displayedGeometry,
    );
    _session.receive(epoch: epoch, attachment: binding.attachment, now: now);
    _routeExpiry = binding.routeValidUntil;
    final attachment = binding.attachment;
    if (attachment is Map && attachment['grant'] is Map) {
      final expiry = attachment['grant']['validUntil'];
      if (expiry is int && expiry >= 0 && expiry <= 8640000000000000) {
        _grantExpiry = DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true);
      }
    }
    refresh(now);
  }

  void updateProgress(
    double? meters, {
    required bool trusted,
    required DateTime now,
  }) {
    progressTrusted =
        trusted && meters != null && meters.isFinite && meters >= 0;
    if (progressTrusted) progressMeters = math.max(progressMeters, meters!);
    refresh(now);
  }

  /// The existing single navigation expiry timer also handles a stationary car.
  DateTime? nextExpiry(DateTime now) {
    final snapshot = current(now);
    if (snapshot.state != RouteWarningState.available) return null;
    final candidates = <DateTime?>[
      snapshot.validUntil,
      _grantExpiry,
      _routeExpiry,
      for (final item in snapshot.items) ...[
        item.validUntil,
        item.confirmedAt.add(const Duration(seconds: 180)),
      ],
    ].whereType<DateTime>().where((t) => t.isAfter(now)).toList()..sort();
    return candidates.isEmpty ? null : candidates.first;
  }

  void refresh(DateTime now) => notifyListeners();

  void clear() {
    _session.clear();
    _grantExpiry = null;
    _routeExpiry = null;
    progressMeters = 0;
    progressTrusted = false;
    notifyListeners();
  }
}
