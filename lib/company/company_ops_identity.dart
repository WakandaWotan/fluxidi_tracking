// COMPANY-CUSTOMER-OPS-P0 — company identity from the existing profile source.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';

class CompanyOpsLocalSession {
  const CompanyOpsLocalSession({
    required this.companyId,
    required this.sessionToken,
  });

  final String companyId;
  final String sessionToken;
}

class CompanyOpsIdentity {
  const CompanyOpsIdentity({
    required this.generation,
    required this.companyId,
    required this.companyName,
    required this.logo,
    this.profileError = '',
  });

  static const CompanyOpsIdentity empty = CompanyOpsIdentity(
    generation: 0,
    companyId: '',
    companyName: '',
    logo: CompanyLogoRef.unset,
  );

  final int generation;
  final String companyId;
  final String companyName;
  final CompanyLogoRef logo;
  final String profileError;

  bool get hasCompany => companyId.trim().isNotEmpty;
  bool get hasCompanyLogo => logo.isCompanyOwned && logo.isRenderable;
  bool get hasReadableName => companyName.trim().isNotEmpty;
}

class CompanyOpsDirectoryEntry {
  const CompanyOpsDirectoryEntry({
    required this.companyId,
    required this.sessionToken,
    required this.companyName,
    required this.publicLogoUrl,
  });

  final String companyId;
  final String sessionToken;
  final String companyName;
  final String publicLogoUrl;
}

final ValueNotifier<CompanyOpsLocalSession?> companyOpsLocalSessionNotifier =
    ValueNotifier<CompanyOpsLocalSession?>(null);

final ValueNotifier<CompanyOpsIdentity> companyOpsIdentityNotifier =
    ValueNotifier<CompanyOpsIdentity>(CompanyOpsIdentity.empty);

int companyOpsContextGeneration = 0;

/// Keeps the Windows route on the shared theme store. Does not invent a palette.
void applyCompanyOpsHuisstijl(String companyId) {
  bindBusinessThemeCompanyScope(companyId);
}

int beginCompanyOpsContextClear() {
  companyOpsContextGeneration += 1;
  companyOpsLocalSessionNotifier.value = null;
  companyOpsIdentityNotifier.value = CompanyOpsIdentity(
    generation: companyOpsContextGeneration,
    companyId: '',
    companyName: '',
    logo: CompanyLogoRef.unset,
  );
  bindBusinessThemeCompanyScope(null);
  try {
    final binding = PaintingBinding.instance;
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
  } catch (_) {}
  return companyOpsContextGeneration;
}

bool isCurrentCompanyOpsGeneration(int generation) =>
    generation == companyOpsContextGeneration;

CompanyOpsIdentity identityFromBusinessProfile({
  required int generation,
  required String companyId,
  required Map<String, dynamic> profile,
  String Function(String raw)? resolvePublicUrl,
}) {
  final name = _profileCompanyName(profile);
  final publicUrl = _profileLogoUrl(profile);
  final logo = resolveCompanyLogoRef(
    publicUrl: publicUrl,
    resolvePublicUrl: resolvePublicUrl,
    isWeb: true,
  );
  return CompanyOpsIdentity(
    generation: generation,
    companyId: companyId,
    companyName: name,
    logo: logo.isCompanyOwned ? logo : CompanyLogoRef.unset,
  );
}

bool shouldApplyCompanyOpsIdentity({
  required int generation,
  required String companyId,
  required CompanyOpsLocalSession? session,
}) {
  if (!isCurrentCompanyOpsGeneration(generation)) return false;
  final active = session?.companyId.trim() ?? '';
  return active.isNotEmpty && active == companyId.trim();
}

String _profileCompanyName(Map<String, dynamic> profile) {
  for (final key in <String>[
    'companyName',
    'company_name',
    'trading_name',
    'tradingName',
    'legalName',
    'legal_name',
  ]) {
    final value = profile[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _profileLogoUrl(Map<String, dynamic> profile) {
  for (final key in <String>['publicLogoUrl', 'public_logo_url']) {
    final value = profile[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}
