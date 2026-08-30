// FLUTTER-REQUEST-DEDUPE-P0
//
// Shared company subscription-profile cache + single-flight.
//
// TTL: 45 seconds. Inside the required 30–60 s band. Short enough that a
// billing mutation followed by a forced refresh is always a new GET; long
// enough that settings rebuilds, vehicle/driver gates and bootstrap share
// one successful profile. Failures are never cached as success.

import 'package:fluxidi_tracking/app_config.dart';

/// 45 s — documented short TTL (30–60 s band).
const Duration kCompanySubscriptionProfileTtl = Duration(seconds: 45);

/// Network loader for [CompanySubscriptionProfileRepository].
typedef CompanySubscriptionProfileLoader =
    Future<BackendSubscriptionProfile> Function({
      String? tenantId,
      String? companyId,
    });

class _CachedCompanySubscriptionProfile {
  const _CachedCompanySubscriptionProfile({
    required this.profile,
    required this.fetchedAt,
  });

  final BackendSubscriptionProfile profile;
  final DateTime fetchedAt;
}

/// Process-wide repository keyed by authenticated tenant_id + company_id.
///
/// Does not store tokens, secrets or complete auth objects — only the
/// already-decoded [BackendSubscriptionProfile].
class CompanySubscriptionProfileRepository {
  CompanySubscriptionProfileRepository({
    required CompanySubscriptionProfileLoader loader,
    this.ttl = kCompanySubscriptionProfileTtl,
    DateTime Function()? clock,
  }) : _loader = loader,
       _clock = clock ?? DateTime.now;

  final CompanySubscriptionProfileLoader _loader;
  final Duration ttl;
  final DateTime Function() _clock;

  final Map<String, _CachedCompanySubscriptionProfile> _cache =
      <String, _CachedCompanySubscriptionProfile>{};
  final Map<String, Future<BackendSubscriptionProfile>> _inFlight =
      <String, Future<BackendSubscriptionProfile>>{};

  static String scopeKey({
    required String tenantId,
    required String companyId,
  }) {
    return '${tenantId.trim()}|${companyId.trim()}';
  }

  DateTime now() => _clock();

  Future<BackendSubscriptionProfile> fetch({
    String? tenantId,
    String? companyId,
    bool forceRefresh = false,
  }) {
    final tenant = (tenantId ?? '').trim();
    final company = (companyId ?? '').trim();
    if (tenant.isEmpty || company.isEmpty) {
      return _loader(tenantId: tenantId, companyId: companyId);
    }
    final key = scopeKey(tenantId: tenant, companyId: company);
    if (!forceRefresh) {
      final cached = _cache[key];
      if (cached != null && now().difference(cached.fetchedAt) < ttl) {
        return Future<BackendSubscriptionProfile>.value(cached.profile);
      }
    }
    final existing = _inFlight[key];
    if (existing != null) {
      return existing;
    }
    late final Future<BackendSubscriptionProfile> future;
    future = Future<BackendSubscriptionProfile>(() async {
      try {
        final profile = await _loader(tenantId: tenant, companyId: company);
        // A mutation or sign-out may have dropped this in-flight entry.
        // Do not restore a stale successful profile after invalidation.
        if (identical(_inFlight[key], future)) {
          _cache[key] = _CachedCompanySubscriptionProfile(
            profile: profile,
            fetchedAt: now(),
          );
        }
        return profile;
      } finally {
        if (identical(_inFlight[key], future)) {
          _inFlight.remove(key);
        }
      }
    });
    _inFlight[key] = future;
    return future;
  }

  void invalidate({String? tenantId, String? companyId}) {
    final tenant = (tenantId ?? '').trim();
    final company = (companyId ?? '').trim();
    if (tenant.isEmpty && company.isEmpty) {
      invalidateAll();
      return;
    }
    if (tenant.isNotEmpty && company.isNotEmpty) {
      final key = scopeKey(tenantId: tenant, companyId: company);
      _cache.remove(key);
      _inFlight.remove(key);
      return;
    }
    final needle = tenant.isNotEmpty ? tenant : company;
    bool matches(String key) {
      final parts = key.split('|');
      return parts.isNotEmpty &&
          (parts.first == needle || parts.last == needle);
    }

    _cache.removeWhere((key, _) => matches(key));
    _inFlight.removeWhere((key, _) => matches(key));
  }

  void invalidateAll() {
    _cache.clear();
    _inFlight.clear();
  }

  void resetForTest() {
    _cache.clear();
    _inFlight.clear();
  }

  bool hasFreshCache({
    required String tenantId,
    required String companyId,
    DateTime? now,
  }) {
    final key = scopeKey(tenantId: tenantId, companyId: companyId);
    final cached = _cache[key];
    if (cached == null) return false;
    return (now ?? this.now()).difference(cached.fetchedAt) < ttl;
  }
}

CompanySubscriptionProfileRepository? _companySubscriptionProfileRepository;

/// Process-wide repository. Loader is bound lazily to the uncached HTTP
/// function in `app_config.dart` so library initialization cannot cycle.
CompanySubscriptionProfileRepository get companySubscriptionProfileRepository {
  return _companySubscriptionProfileRepository ??=
      CompanySubscriptionProfileRepository(
        loader: loadCompanySubscriptionProfileUncached,
      );
}

void resetCompanySubscriptionProfileRepositoryForTest() {
  _companySubscriptionProfileRepository?.resetForTest();
}
