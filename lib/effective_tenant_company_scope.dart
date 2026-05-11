import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

class EffectiveTenantCompanyScope {
  const EffectiveTenantCompanyScope({
    required this.tenantId,
    required this.companyId,
    required this.source,
    required this.isFallback,
  });

  final String tenantId;
  final String companyId;
  final String source;
  final bool isFallback;
}

String _maskScopeValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 3)}...${trimmed.substring(trimmed.length - 3)}';
}

String _normalizeScopeId(String value, {required String fallback}) {
  final trimmed = value.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return fallback;
}

EffectiveTenantCompanyScope resolveEffectiveTenantCompanyScope({
  bool allowDriverFallback = false,
}) {
  final fallback = kTenantId.trim();

  final activeCompanySession = activeCompanySessionNotifier.value;
  final activeCompanyId = (activeCompanySession?.companyId ?? '').trim();
  if (activeCompanyId.isNotEmpty) {
    final scope = EffectiveTenantCompanyScope(
      tenantId: activeCompanyId,
      companyId: activeCompanyId,
      source: 'active_company_session',
      isFallback: false,
    );
    debugPrint(
      '[SCOPE][EFFECTIVE] source=${scope.source} tenant=${_maskScopeValue(scope.tenantId)} company=${_maskScopeValue(scope.companyId)} allowDriverFallback=$allowDriverFallback',
    );
    return scope;
  }

  final companyProfile = companyProfileNotifier.value;
  final profileCompanyId = (companyProfile?.companyId ?? '').trim();
  if (profileCompanyId.isNotEmpty) {
    final scope = EffectiveTenantCompanyScope(
      tenantId: profileCompanyId,
      companyId: profileCompanyId,
      source: 'company_profile',
      isFallback: false,
    );
    debugPrint(
      '[SCOPE][EFFECTIVE] source=${scope.source} tenant=${_maskScopeValue(scope.tenantId)} company=${_maskScopeValue(scope.companyId)} allowDriverFallback=$allowDriverFallback',
    );
    return scope;
  }

  if (allowDriverFallback) {
    final activeDriverSession = activeDriverSessionNotifier.value;
    final driverTenantId = (activeDriverSession?.tenantId ?? '').trim();
    final driverCompanyId = (activeDriverSession?.companyId ?? '').trim();
    final canUseDriverScope =
        (activeDriverSession?.isVerifiedPairingSession ?? false) &&
        driverTenantId.isNotEmpty &&
        driverCompanyId.isNotEmpty;
    if (canUseDriverScope) {
      final scope = EffectiveTenantCompanyScope(
        tenantId: driverTenantId,
        companyId: driverCompanyId,
        source: 'verified_driver_session',
        isFallback: false,
      );
      debugPrint(
        '[SCOPE][EFFECTIVE] source=${scope.source} tenant=${_maskScopeValue(scope.tenantId)} company=${_maskScopeValue(scope.companyId)} allowDriverFallback=$allowDriverFallback',
      );
      return scope;
    }
  }

  final normalizedFallback = _normalizeScopeId(fallback, fallback: 'fluxidi');
  final scope = EffectiveTenantCompanyScope(
    tenantId: normalizedFallback,
    companyId: normalizedFallback,
    source: 'default_fallback',
    isFallback: true,
  );
  debugPrint(
    '[SCOPE][EFFECTIVE] source=${scope.source} tenant=${_maskScopeValue(scope.tenantId)} company=${_maskScopeValue(scope.companyId)} allowDriverFallback=$allowDriverFallback',
  );
  return scope;
}
