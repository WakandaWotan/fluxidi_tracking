import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';

bool _companyOpsThemeRemoteSyncRegistered = false;

/// Writes the shared theme document onto GET/POST /admin/business/profile.
void registerCompanyOpsThemeRemoteSync() {
  if (_companyOpsThemeRemoteSyncRegistered) return;
  _companyOpsThemeRemoteSyncRegistered = true;
  businessThemeCompanyRemoteSync = (companyId, themeDocument) async {
    final session = companyOpsLocalSessionNotifier.value;
    if (session == null || session.companyId.trim() != companyId.trim()) {
      return;
    }
    final profile = await fetchCompanyOpsBusinessProfile();
    await saveCompanyOpsBusinessProfile(<String, dynamic>{
      ...profile,
      ...themeDocument,
    });
  };
}

@visibleForTesting
void resetCompanyOpsThemeRemoteSyncForTest() {
  _companyOpsThemeRemoteSyncRegistered = false;
  businessThemeCompanyRemoteSync = null;
}
