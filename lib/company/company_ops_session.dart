// COMPANY-CUSTOMER-OPS-P0 — company session for ops HTTP, no demo fallback.

import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

/// Resolves the company used by company-ops HTTP.
///
/// Synthetic dart-define sessions are used only when the local-test bind is
/// allowed. The normal app uses the active paired company. Empty means "no
/// company" — callers must not invent demo drivers.
CompanyOpsLocalSession resolveCompanyOpsSession({
  CompanyOpsLocalSession? localOps,
  String? activeCompanyId,
  String? activeSessionToken,
  String? activeLinkMethod,
  required bool allowSynthetic,
  String syntheticCompanyId = '',
  String syntheticToken = '',
}) {
  CompanyOpsLocalSession? takeIfAllowed(
    String companyId,
    String sessionToken, {
    String? linkMethod,
  }) {
    final id = companyId.trim();
    final token = sessionToken.trim();
    if (id.isEmpty || token.isEmpty) return null;
    final synthetic = isLocalSyntheticCompanySessionRecord(
      companyId: id,
      sessionToken: token,
      linkMethod: linkMethod,
    );
    if (synthetic && !allowSynthetic) return null;
    return CompanyOpsLocalSession(companyId: id, sessionToken: token);
  }

  final fromLocal = localOps == null
      ? null
      : takeIfAllowed(localOps.companyId, localOps.sessionToken);
  if (fromLocal != null) return fromLocal;

  final fromActive = takeIfAllowed(
    activeCompanyId ?? '',
    activeSessionToken ?? '',
    linkMethod: activeLinkMethod,
  );
  if (fromActive != null) return fromActive;

  if (allowSynthetic) {
    final synthetic = takeIfAllowed(syntheticCompanyId, syntheticToken);
    if (synthetic != null) return synthetic;
  }

  return const CompanyOpsLocalSession(companyId: '', sessionToken: '');
}

CompanyOpsLocalSession resolveCompanyOpsLocalSession() {
  final active = activeCompanySessionNotifier.value;
  return resolveCompanyOpsSession(
    localOps: companyOpsLocalSessionNotifier.value,
    activeCompanyId: active?.companyId,
    activeSessionToken: active?.companySessionToken,
    activeLinkMethod: active?.linkMethod,
    allowSynthetic: shouldBindLocalSyntheticCompanySession(),
    syntheticCompanyId: kLocalSyntheticCompanyId,
    syntheticToken: kLocalSyntheticCompanySessionToken,
  );
}

bool companyOpsSessionIsReady(CompanyOpsLocalSession session) {
  return session.companyId.trim().isNotEmpty &&
      session.sessionToken.trim().isNotEmpty;
}
