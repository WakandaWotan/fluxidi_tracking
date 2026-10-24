// FLUXIDI-CANONICAL-COMPANY-LOGO-AND-INVOICE-PRESENTATION-P0-1
//
// One canonical resolver for the company logo reference.
//
// Field failure: after a restart the branding page said "Geen bedrijfslogo
// ingesteld" while the dashboard still showed the uploaded logo. Both read the
// same stored value; they disagreed because each surface classified the
// reference with its own rules. The settings preview only understood
// `assets/...` and local file paths, so once startup bootstrap replaced the
// stored path with the company's public https URL it tried to open that URL as a
// file, failed, and fell through to the "not set" placeholder.
//
// Every surface now classifies and resolves through this file, and a reference
// that exists but cannot be rendered is reported as an error — never as "not
// set", which is a different and misleading claim.

/// How a company logo reference must be loaded.
enum CompanyLogoRefKind {
  /// No usable reference (never rendered as an image).
  none,

  /// Packaged asset, e.g. `assets/...`.
  asset,

  /// On-device file path written by the branding picker.
  file,

  /// Remote https/http reference (public company media).
  network,
}

/// Which owner supplied the resolved reference.
enum CompanyLogoSource {
  none,
  /// Tenant-scoped branding field (`BusinessSettingsState.logoAssetPath`).
  localBranding,
  /// Public partner profile field (`BackendBusinessProfile.publicLogoUrl`).
  publicProfile,
  /// Packaged Fluxidi mark; means the company has not set a logo.
  fluxidiFallback,
}

class CompanyLogoRef {
  const CompanyLogoRef({
    required this.ref,
    required this.kind,
    required this.source,
  });

  static const CompanyLogoRef unset = CompanyLogoRef(
    ref: '',
    kind: CompanyLogoRefKind.none,
    source: CompanyLogoSource.none,
  );

  final String ref;
  final CompanyLogoRefKind kind;
  final CompanyLogoSource source;

  /// True when a company-owned logo was resolved (not the Fluxidi fallback).
  bool get isCompanyOwned =>
      kind != CompanyLogoRefKind.none &&
      source != CompanyLogoSource.fluxidiFallback &&
      source != CompanyLogoSource.none;

  bool get isRenderable => kind != CompanyLogoRefKind.none && ref.isNotEmpty;

  @override
  String toString() => 'CompanyLogoRef($ref, $kind, $source)';
}

/// Packaged Fluxidi mark. Its presence means "no company logo set".
const String kPackagedFluxidiLogoAsset = 'assets/fluxidi/fluxidi_logo.png';

String normalizeCompanyLogoRefForCompare(String raw) =>
    raw.trim().replaceAll('\\', '/').toLowerCase();

/// True for empty references and every known packaged Fluxidi default.
bool isDefaultFluxidiLogoRef(String raw, {String? configuredAsset}) {
  final norm = normalizeCompanyLogoRefForCompare(raw);
  if (norm.isEmpty) return true;
  final configured = normalizeCompanyLogoRefForCompare(configuredAsset ?? '');
  if (configured.isNotEmpty && norm == configured) return true;
  if (norm == kPackagedFluxidiLogoAsset) return true;
  if (norm == 'fluxidi_logo.png') return true;
  if (norm.endsWith('/fluxidi_logo.png')) return true;
  if (norm.contains('assets/fluxidi/fluxidi_logo.png')) return true;
  return false;
}

/// Classifies how [raw] must be loaded, without touching the filesystem.
///
/// The settings preview previously had no network branch, so a stored https
/// reference was opened as a file and reported as "no logo set".
CompanyLogoRefKind classifyCompanyLogoRef(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return CompanyLogoRefKind.none;
  final lower = text.toLowerCase();
  if (lower.startsWith('assets/')) return CompanyLogoRefKind.asset;
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return CompanyLogoRefKind.network;
  }
  // Worker-relative media refs are only usable once resolved to an absolute URL.
  if (lower.startsWith('/public/media/') || lower.startsWith('public-media/')) {
    return CompanyLogoRefKind.none;
  }
  if (lower.startsWith('data:')) return CompanyLogoRefKind.none;
  return CompanyLogoRefKind.file;
}

/// Resolves the canonical company logo, preferring the tenant branding field.
///
/// [fileExists] and [resolvePublicUrl] are injected so the rules stay pure and
/// testable; production passes the real filesystem check and media resolver.
CompanyLogoRef resolveCompanyLogoRef({
  String localPath = '',
  String publicUrl = '',
  String? configuredFluxidiAsset,
  String fluxidiFallbackAsset = kPackagedFluxidiLogoAsset,
  bool Function(String path)? fileExists,
  String Function(String raw)? resolvePublicUrl,
  bool isWeb = false,
}) {
  CompanyLogoRef? attempt(String raw, CompanyLogoSource source) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (isDefaultFluxidiLogoRef(text, configuredAsset: configuredFluxidiAsset)) {
      return null;
    }

    // A worker-relative ref becomes usable once resolved to an absolute URL.
    final resolvedPublic = (resolvePublicUrl?.call(text) ?? '').trim();
    if (resolvedPublic.isNotEmpty &&
        classifyCompanyLogoRef(resolvedPublic) == CompanyLogoRefKind.network) {
      return CompanyLogoRef(
        ref: resolvedPublic,
        kind: CompanyLogoRefKind.network,
        source: source,
      );
    }

    switch (classifyCompanyLogoRef(text)) {
      case CompanyLogoRefKind.asset:
        return CompanyLogoRef(
          ref: text,
          kind: CompanyLogoRefKind.asset,
          source: source,
        );
      case CompanyLogoRefKind.network:
        return CompanyLogoRef(
          ref: text,
          kind: CompanyLogoRefKind.network,
          source: source,
        );
      case CompanyLogoRefKind.file:
        if (isWeb) return null;
        if (fileExists != null && !fileExists(text)) return null;
        return CompanyLogoRef(
          ref: text,
          kind: CompanyLogoRefKind.file,
          source: source,
        );
      case CompanyLogoRefKind.none:
        return null;
    }
  }

  final local = attempt(localPath, CompanyLogoSource.localBranding);
  if (local != null) return local;
  final public = attempt(publicUrl, CompanyLogoSource.publicProfile);
  if (public != null) return public;
  return CompanyLogoRef(
    ref: fluxidiFallbackAsset,
    kind: CompanyLogoRefKind.asset,
    source: CompanyLogoSource.fluxidiFallback,
  );
}

/// What the branding preview should display.
///
/// Distinguishing [failed] from [empty] is the point: a reference that exists
/// but cannot be decoded must never claim the company has no logo.
enum CompanyLogoPreviewState { empty, ready, failed }

CompanyLogoPreviewState resolveCompanyLogoPreviewState({
  required CompanyLogoRef resolved,
  required bool loadFailed,
}) {
  if (!resolved.isCompanyOwned) return CompanyLogoPreviewState.empty;
  return loadFailed
      ? CompanyLogoPreviewState.failed
      : CompanyLogoPreviewState.ready;
}
