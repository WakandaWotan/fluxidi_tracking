import 'navigation_route_warnings.dart';

/// Additive UI state only. Has no network, GPS, map, router or ETA dependencies.
/// The authenticated route response owns the grant; a local preference cannot
/// authorize a company. The build capability is deliberately off by default.
class NavigationTrafficTestSession {
  NavigationTrafficTestSession({this.testBuildEnabled = false});
  final bool testBuildEnabled;
  int _epoch = 0;
  _DisplayedRoute? _route;
  Map<String, dynamic>? _grant;
  RouteWarnings _warnings = _empty;
  static const _empty =
      RouteWarnings(RouteWarningState.unavailable, [], null, null);

  /// Call on EVERY accepted route application and identity/scope change, even
  /// if the same geometry appears again. Capture the returned epoch before an
  /// asynchronous warning response, and present only the actual rendered route.
  int applyDisplayedRoute({
    required String tenantId,
    required String companyId,
    required String graphVersion,
    required String manifestSha256,
    required String evidenceRevision,
    required String routeEvidenceId,
    required DateTime routeValidUntil,
    required List<List<num>> geometry,
  }) {
    clear();
    try {
      if ([
            tenantId,
            companyId,
            graphVersion,
            manifestSha256,
            evidenceRevision,
            routeEvidenceId
          ].any((s) => s.isEmpty) ||
          geometry.length < 2 ||
          geometry.length > 100001 ||
          geometry.any((p) => p.length != 2 || p.any((n) => !n.isFinite)))
        return _epoch;
      final frozen = List<List<num>>.unmodifiable(
          geometry.map((p) => List<num>.unmodifiable(p)));
      _route = _DisplayedRoute(
          tenantId,
          companyId,
          graphVersion,
          manifestSha256,
          evidenceRevision,
          routeEvidenceId,
          routeValidUntil,
          frozen);
    } catch (_) {
      _route = null;
    }
    return _epoch;
  }

  /// Ignore late responses from any older route or signed-in company.
  /// For the current route an absent, malformed or stale update clears warnings.
  void receive(
      {required int epoch,
      required dynamic attachment,
      required DateTime now}) {
    if (epoch != _epoch) return;
    _warnings = _empty;
    _grant = null;
    final r = _route;
    if (!testBuildEnabled || r == null || !r.until.isAfter(now)) return;
    try {
      if (attachment is! Map ||
          attachment['grant'] is! Map ||
          attachment['warnings'] is! Map) return;
      final grant = Map<String, dynamic>.from(attachment['grant']);
      if (!_grantValid(grant, r, now)) return;
      final warnings = decodeRouteWarnings(
          dto: Map<String, dynamic>.from(attachment['warnings']),
          geometry: r.geometry,
          tenantId: r.tenant,
          companyId: r.company,
          graphVersion: r.graph,
          manifestSha256: r.manifest,
          evidenceRevision: r.revision,
          routeEvidenceId: r.evidence,
          now: now);
      _grant = Map.unmodifiable(grant);
      _warnings = warnings;
    } catch (_) {
      _warnings = _empty;
      _grant = null;
    }
  }

  bool _grantValid(Map<String, dynamic> g, _DisplayedRoute r, DateTime now) =>
      g['schema'] == 'fluxidi-navigation-traffic-test-grant-v1' &&
      g['enabled'] == true &&
      g['tenant_id'] == r.tenant &&
      g['company_id'] == r.company &&
      g['validUntil'] is int &&
      g['validUntil'] > now.millisecondsSinceEpoch;

  /// Call from the EXISTING navigation render/GPS/expiry lifecycle and on
  /// foreground resume. No additional polling or timer is introduced here.
  RouteWarnings current(DateTime now) {
    final r = _route;
    if (!testBuildEnabled ||
        r == null ||
        !r.until.isAfter(now) ||
        _grant == null ||
        !_grantValid(_grant!, r, now) ||
        _warnings.validUntil == null ||
        !_warnings.validUntil!.isAfter(now)) return _empty;
    return _warnings;
  }

  /// Navigation stop, logout/company switch, route invalidation or explicit
  /// test disable. Incrementing the epoch invalidates all in-flight responses.
  void clear() {
    _epoch++;
    _route = null;
    _grant = null;
    _warnings = _empty;
  }
}

class _DisplayedRoute {
  const _DisplayedRoute(this.tenant, this.company, this.graph, this.manifest,
      this.revision, this.evidence, this.until, this.geometry);
  final String tenant, company, graph, manifest, revision, evidence;
  final DateTime until;
  final List<List<num>> geometry;
}
