import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

/// Values persisted in [CompanyProfile.verificationStatus] (JSON string).
///
/// TODO(backend): Backend issues authoritative tenantId/companyId and owns verification state.
/// Local [CompanyProfile.companyId] is provisional until the backend confirms or replaces it.
/// Company admin access must later require an authenticated account plus verified role.
abstract final class CompanyVerificationStatus {
  CompanyVerificationStatus._();

  static const String draft = 'draft';
  static const String pendingVerification = 'pending_verification';
  static const String verified = 'verified';
  static const String suspended = 'suspended';
}

String _normalizeImportedVerificationStatus(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case CompanyVerificationStatus.draft:
      return CompanyVerificationStatus.draft;
    case CompanyVerificationStatus.pendingVerification:
      return CompanyVerificationStatus.pendingVerification;
    case CompanyVerificationStatus.verified:
      return CompanyVerificationStatus.verified;
    case CompanyVerificationStatus.suspended:
      return CompanyVerificationStatus.suspended;
    default:
      return CompanyVerificationStatus.pendingVerification;
  }
}

String _normalizePublicCompanyCode(String raw) {
  return raw
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

bool _isValidPublicCompanyCode(String code) {
  if (code.isEmpty) return false;
  return RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(code);
}

/// Fallback tenant id when no local company profile exists (aligned with Worker `tenant_id`).
const String kFallbackCompanyId = kTenantId;

String _maskCompanyIdForLog(String value) {
  final text = value.trim();
  if (text.isEmpty) return '—';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

String _shortErrForCompanyLog(Object error) {
  final raw = error.toString();
  final oneLine = raw.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
  if (oneLine.length <= 160) return oneLine;
  return '${oneLine.substring(0, 157)}...';
}

void _logSessionWriteSummary(String op, ActiveCompanySession session) {
  final hasToken = (session.companySessionToken ?? '').trim().isNotEmpty;
  final expiresAt = (session.companySessionExpiresAtUtc ?? '').trim();
  debugPrint(
    '[COMPANY_SESSION][SESSION_WRITE_SUMMARY] op=$op hasToken=$hasToken expiresAt=${expiresAt.isEmpty ? '—' : expiresAt}',
  );
}

/// Dev/QA-only shortcut to simulate overnight session expiry.
///
/// Activated by `--dart-define=COMPANY_SESSION_FORCE_EXPIRY_SECONDS=<n>` in
/// debug or profile builds (e.g. `flutter run --profile`). Default 0 = no-op.
/// Release builds ignore the value entirely because
/// [_maybeClampSessionExpiryForDev] returns the server expiry as-is when
/// [kReleaseMode] is true.
const int _kCompanySessionForceExpirySeconds = int.fromEnvironment(
  'COMPANY_SESSION_FORCE_EXPIRY_SECONDS',
  defaultValue: 0,
);

/// Returns [serverExpiry] unchanged unless the dev/QA force-expiry shortcut is
/// active. The shortcut may only **shorten** the expiry, never extend it.
/// No-op in [kReleaseMode] and when the env var is unset / non-positive.
DateTime? _maybeClampSessionExpiryForDev(DateTime? serverExpiry) {
  if (_kCompanySessionForceExpirySeconds <= 0) return serverExpiry;
  if (kReleaseMode) return serverExpiry;
  final shortcut = DateTime.now().toUtc().add(
    Duration(seconds: _kCompanySessionForceExpirySeconds),
  );
  final clamped = serverExpiry == null
      ? shortcut
      : (serverExpiry.isBefore(shortcut) ? serverExpiry : shortcut);
  final didClamp = serverExpiry == null || !serverExpiry.isBefore(shortcut);
  debugPrint(
    '[COMPANY_SESSION][DEV_FORCE_EXPIRY] active=true seconds=$_kCompanySessionForceExpirySeconds clamped=$didClamp',
  );
  return clamped;
}

final ValueNotifier<ActiveCompanySession?> activeCompanySessionNotifier =
    ValueNotifier<ActiveCompanySession?>(null);

final ValueNotifier<CompanyProfile?> companyProfileNotifier =
    ValueNotifier<CompanyProfile?>(null);

/// Stable company / tenant identifier for linking local MVP data — prefer [CompanyProfile.companyId].
String get resolvedCompanyId {
  final id = companyProfileNotifier.value?.companyId.trim();
  if (id != null && id.isNotEmpty) return id;
  return kFallbackCompanyId;
}

/// Local company profile (sync-ready with future backend tenant endpoints).
///
/// TODO(backend): Backend issues authoritative tenantId/companyId and owns [verificationStatus].
/// Local company data (VAT, address, etc.) is **not** proof of ownership until verified.
class CompanyProfile {
  const CompanyProfile({
    required this.companyId,
    required this.companyName,
    required this.ownerName,
    required this.email,
    required this.phone,
    required this.vatNumber,
    required this.addressLine,
    required this.postalCode,
    required this.city,
    required this.countryCode,
    required this.companyEmail,
    required this.supportEmail,
    required this.billingEmail,
    required this.bookingEmail,
    required this.notificationEmail,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    this.verificationStatus = CompanyVerificationStatus.pendingVerification,
  });

  final String companyId;
  String get tenantId => companyId;

  /// See [CompanyVerificationStatus]. Missing key in older JSON defaults to [pendingVerification].
  final String verificationStatus;

  final String companyName;
  final String ownerName;
  final String email;
  final String phone;
  final String vatNumber;
  final String addressLine;
  final String postalCode;
  final String city;
  final String countryCode;
  final String companyEmail;
  final String supportEmail;
  final String billingEmail;
  final String bookingEmail;
  final String notificationEmail;
  final String createdAt;
  final String updatedAt;
  final bool isActive;

  bool get isVerified =>
      verificationStatus == CompanyVerificationStatus.verified;

  bool get isSuspended =>
      verificationStatus == CompanyVerificationStatus.suspended;

  bool get isDraft => verificationStatus == CompanyVerificationStatus.draft;

  bool get isPendingVerification =>
      verificationStatus == CompanyVerificationStatus.pendingVerification;

  /// Short label for dashboard/settings badges.
  ///
  /// [serverPaired] is a server-confirmed company session (token + matching
  /// company scope). It is not Mollie, Chiron, or subscription state.
  /// `Geverifieerd` is only shown for an explicit [verified] backend fact.
  String verificationBadgeLabel(AppLanguage lang, {bool serverPaired = false}) {
    if (isSuspended) {
      switch (lang) {
        case AppLanguage.nl:
          return 'Geblokkeerd';
        case AppLanguage.en:
          return 'Suspended';
        case AppLanguage.fr:
          return 'Suspendu';
        case AppLanguage.es:
          return 'Suspendido';
        case AppLanguage.de:
          return 'Suspended';
      }
    }
    if (isVerified) {
      switch (lang) {
        case AppLanguage.nl:
          return 'Geverifieerd';
        case AppLanguage.en:
          return 'Verified';
        case AppLanguage.fr:
          return 'Vérifié';
        case AppLanguage.es:
          return 'Verificado';
        case AppLanguage.de:
          return 'Suspended';
      }
    }
    if (serverPaired) {
      switch (lang) {
        case AppLanguage.nl:
          return 'Gekoppeld';
        case AppLanguage.en:
          return 'Linked';
        case AppLanguage.fr:
          return 'Associé';
        case AppLanguage.es:
          return 'Vinculado';
        case AppLanguage.de:
          return 'Gekoppelt';
      }
    }
    switch (lang) {
      case AppLanguage.nl:
        return 'Niet geverifieerd';
      case AppLanguage.en:
        return 'Not verified';
      case AppLanguage.fr:
        return 'Non vérifié';
      case AppLanguage.es:
        return 'No verificado';
      case AppLanguage.de:
        return 'Suspended';
    }
  }

  /// Shown only for a truly local, unpaired company. Old
  /// `pending_verification` JSON stays readable but does not show this
  /// blocking copy after a proven server pairing.
  bool showsPendingVerificationNotice({bool serverPaired = false}) =>
      !isVerified && !isSuspended && !serverPaired;

  String verificationPendingNotice(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.nl:
        return 'Dit bedrijf is lokaal aangemaakt. Volledige live-functies worden later geactiveerd na verificatie.';
      case AppLanguage.en:
        return 'This company was created locally. Full live features will be activated later after verification.';
      case AppLanguage.fr:
        return 'Cette entreprise a été créée localement. Les fonctions en ligne complètes seront activées après vérification.';
      case AppLanguage.es:
        return 'Esta empresa se creó localmente. Las funciones en vivo completas se activarán después de la verificación.';
      case AppLanguage.de:
        return 'Verified';
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'companyId': companyId,
    'tenantId': companyId,
    'companyName': companyName,
    'ownerName': ownerName,
    'email': email,
    'phone': phone,
    'vatNumber': vatNumber,
    'addressLine': addressLine,
    'postalCode': postalCode,
    'city': city,
    'countryCode': countryCode,
    'companyEmail': companyEmail,
    'supportEmail': supportEmail,
    'billingEmail': billingEmail,
    'bookingEmail': bookingEmail,
    'notificationEmail': notificationEmail,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'isActive': isActive,
    'verificationStatus': verificationStatus,
  };

  factory CompanyProfile.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    final id = (read('companyId').isNotEmpty
        ? read('companyId')
        : read('tenantId'));
    final vs = json.containsKey('verificationStatus')
        ? _normalizeImportedVerificationStatus(
            json['verificationStatus']?.toString(),
          )
        : CompanyVerificationStatus.pendingVerification;
    return CompanyProfile(
      companyId: id,
      companyName: read('companyName'),
      ownerName: read('ownerName'),
      email: read('email'),
      phone: read('phone'),
      vatNumber: read('vatNumber'),
      addressLine: read('addressLine'),
      postalCode: read('postalCode'),
      city: read('city'),
      countryCode: read('countryCode'),
      companyEmail: read('companyEmail'),
      supportEmail: read('supportEmail'),
      billingEmail: read('billingEmail'),
      bookingEmail: read('bookingEmail'),
      notificationEmail: read('notificationEmail'),
      createdAt: read('createdAt'),
      updatedAt: read('updatedAt'),
      isActive: json['isActive'] is bool
          ? json['isActive'] as bool
          : read('isActive') != 'false',
      verificationStatus: vs,
    );
  }

  CompanyProfile copyWith({
    String? companyId,
    String? companyName,
    String? ownerName,
    String? email,
    String? phone,
    String? vatNumber,
    String? addressLine,
    String? postalCode,
    String? city,
    String? countryCode,
    String? companyEmail,
    String? supportEmail,
    String? billingEmail,
    String? bookingEmail,
    String? notificationEmail,
    String? createdAt,
    String? updatedAt,
    bool? isActive,
    String? verificationStatus,
  }) {
    return CompanyProfile(
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      ownerName: ownerName ?? this.ownerName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      vatNumber: vatNumber ?? this.vatNumber,
      addressLine: addressLine ?? this.addressLine,
      postalCode: postalCode ?? this.postalCode,
      city: city ?? this.city,
      countryCode: countryCode ?? this.countryCode,
      companyEmail: companyEmail ?? this.companyEmail,
      supportEmail: supportEmail ?? this.supportEmail,
      billingEmail: billingEmail ?? this.billingEmail,
      bookingEmail: bookingEmail ?? this.bookingEmail,
      notificationEmail: notificationEmail ?? this.notificationEmail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      verificationStatus: verificationStatus ?? this.verificationStatus,
    );
  }
}

class ActiveCompanySession {
  const ActiveCompanySession({
    required this.companyId,
    required this.role,
    required this.createdAt,
    required this.lastUsedAt,
    this.companySessionToken,
    this.companySessionExpiresAtUtc,
    this.companyCode,
    this.linkMethod,
  });

  final String companyId;

  /// Future sync: `'companyAdmin'` mirrors [AppRole.companyAdmin].
  final String role;
  final String createdAt;
  final String lastUsedAt;
  final String? companySessionToken;
  final String? companySessionExpiresAtUtc;
  final String? companyCode;
  final String? linkMethod;

  DateTime? get sessionExpiresAtUtc {
    final raw = (companySessionExpiresAtUtc ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed?.toUtc();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'companyId': companyId,
    'role': role,
    'createdAt': createdAt,
    'lastUsedAt': lastUsedAt,
    if ((companySessionToken ?? '').trim().isNotEmpty)
      'companySessionToken': companySessionToken,
    if ((companySessionExpiresAtUtc ?? '').trim().isNotEmpty)
      'companySessionExpiresAtUtc': companySessionExpiresAtUtc,
    if ((companyCode ?? '').trim().isNotEmpty) 'companyCode': companyCode,
    if ((linkMethod ?? '').trim().isNotEmpty) 'linkMethod': linkMethod,
  };

  factory ActiveCompanySession.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    String? readOptional(String key) {
      final value = (json[key] ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    return ActiveCompanySession(
      companyId: read('companyId'),
      role: read('role').isNotEmpty ? read('role') : 'companyAdmin',
      createdAt: read('createdAt'),
      lastUsedAt: read('lastUsedAt'),
      companySessionToken:
          readOptional('companySessionToken') ??
          readOptional('company_session_token') ??
          readOptional('token') ??
          readOptional('authToken') ??
          readOptional('auth_token') ??
          readOptional('companyToken') ??
          readOptional('company_token') ??
          readOptional('sessionToken') ??
          readOptional('session_token') ??
          readOptional('pairingToken') ??
          readOptional('pairing_token') ??
          readOptional('bootstrapToken') ??
          readOptional('bootstrap_token') ??
          readOptional('accessToken') ??
          readOptional('access_token'),
      companySessionExpiresAtUtc:
          readOptional('companySessionExpiresAtUtc') ??
          readOptional('company_session_expires_at_utc') ??
          readOptional('companySessionExpiresAt') ??
          readOptional('company_session_expires_at') ??
          readOptional('expires_at'),
      companyCode: readOptional('companyCode') ?? readOptional('company_code'),
      linkMethod: readOptional('linkMethod') ?? readOptional('link_method'),
    );
  }

  ActiveCompanySession copyWith({
    String? companyId,
    String? role,
    String? createdAt,
    String? lastUsedAt,
    String? companySessionToken,
    String? companySessionExpiresAtUtc,
    String? companyCode,
    String? linkMethod,
  }) {
    return ActiveCompanySession(
      companyId: companyId ?? this.companyId,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      companySessionToken: companySessionToken ?? this.companySessionToken,
      companySessionExpiresAtUtc:
          companySessionExpiresAtUtc ?? this.companySessionExpiresAtUtc,
      companyCode: companyCode ?? this.companyCode,
      linkMethod: linkMethod ?? this.linkMethod,
    );
  }
}

/// Persists `[CompanyProfile]` + `[ActiveCompanySession]` as JSON under app documents.
class CompanySessionStore {
  CompanySessionStore._();
  static final CompanySessionStore instance = CompanySessionStore._();

  static const String _profileFileName = 'company_profile_v1.json';
  static const String _sessionFileName = 'active_company_session_v1.json';

  CompanyProfile? _profileMemory;
  ActiveCompanySession? _sessionMemory;

  /// Local validity for restoring company UX state on-device.
  ///
  /// This is intentionally permissive: sessions without token metadata are
  /// still considered locally valid so the app can restore local company
  /// context and show recovery UX for backend-only flows.
  bool _isSessionStillValid(ActiveCompanySession session) {
    final token = (session.companySessionToken ?? '').trim();
    if (token.isEmpty) return true;
    final expires = session.sessionExpiresAtUtc;
    if (expires == null) return true;
    return DateTime.now().toUtc().isBefore(expires);
  }

  bool _isExpiredTokenBackedSession(ActiveCompanySession session) {
    final token = (session.companySessionToken ?? '').trim();
    if (token.isEmpty) return false;
    final expires = session.sessionExpiresAtUtc;
    if (expires == null) return false;
    return !DateTime.now().toUtc().isBefore(expires);
  }

  ActiveCompanySession _restoreExpiredTokenSessionToLocalContext(
    ActiveCompanySession session,
  ) {
    return ActiveCompanySession(
      companyId: session.companyId,
      role: session.role,
      createdAt: session.createdAt,
      lastUsedAt: session.lastUsedAt,
      companySessionToken: null,
      companySessionExpiresAtUtc: null,
      companyCode: session.companyCode,
      linkMethod: session.linkMethod,
    );
  }

  String _safeScopeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'default';
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isEmpty) return 'default';
    return sanitized;
  }

  ({String tenantId, String companyId})? _resolveScopeFromKnownState({
    CompanyProfile? profileHint,
    ActiveCompanySession? sessionHint,
  }) {
    final fromHintProfile = profileHint?.companyId.trim() ?? '';
    if (fromHintProfile.isNotEmpty) {
      return (tenantId: fromHintProfile, companyId: fromHintProfile);
    }
    final fromHintSession = sessionHint?.companyId.trim() ?? '';
    if (fromHintSession.isNotEmpty) {
      return (tenantId: fromHintSession, companyId: fromHintSession);
    }
    final fromMemoryProfile = _profileMemory?.companyId.trim() ?? '';
    if (fromMemoryProfile.isNotEmpty) {
      return (tenantId: fromMemoryProfile, companyId: fromMemoryProfile);
    }
    final fromMemorySession = _sessionMemory?.companyId.trim() ?? '';
    if (fromMemorySession.isNotEmpty) {
      return (tenantId: fromMemorySession, companyId: fromMemorySession);
    }
    final fromNotifierProfile =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromNotifierProfile.isNotEmpty) {
      return (tenantId: fromNotifierProfile, companyId: fromNotifierProfile);
    }
    final fromNotifierSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromNotifierSession.isNotEmpty) {
      return (tenantId: fromNotifierSession, companyId: fromNotifierSession);
    }
    return null;
  }

  Future<Directory> _stateRootDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}company_session');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _legacyProfileFile() async {
    final d = await _stateRootDir();
    return File('${d.path}${Platform.pathSeparator}$_profileFileName');
  }

  Future<File> _legacySessionFile() async {
    final d = await _stateRootDir();
    return File('${d.path}${Platform.pathSeparator}$_sessionFileName');
  }

  Future<Directory> _scopedDir({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _stateRootDir();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}tenant_${_safeScopeSegment(tenantId)}${Platform.pathSeparator}company_${_safeScopeSegment(companyId)}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _profileFileForScope({
    required String tenantId,
    required String companyId,
  }) async {
    final dir = await _scopedDir(tenantId: tenantId, companyId: companyId);
    final file = File('${dir.path}${Platform.pathSeparator}$_profileFileName');
    debugPrint(
      '[COMPANY_SESSION][PATH] target=profile tenant=$tenantId company=$companyId path=${file.path}',
    );
    return file;
  }

  Future<File> _sessionFileForScope({
    required String tenantId,
    required String companyId,
  }) async {
    final dir = await _scopedDir(tenantId: tenantId, companyId: companyId);
    final file = File('${dir.path}${Platform.pathSeparator}$_sessionFileName');
    debugPrint(
      '[COMPANY_SESSION][PATH] target=session tenant=$tenantId company=$companyId path=${file.path}',
    );
    return file;
  }

  Future<File?> _profileFileForKnownScope({
    CompanyProfile? profileHint,
    ActiveCompanySession? sessionHint,
  }) async {
    final scope = _resolveScopeFromKnownState(
      profileHint: profileHint,
      sessionHint: sessionHint,
    );
    if (scope == null) return null;
    return _profileFileForScope(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
  }

  Future<File?> _sessionFileForKnownScope({
    CompanyProfile? profileHint,
    ActiveCompanySession? sessionHint,
  }) async {
    final scope = _resolveScopeFromKnownState(
      profileHint: profileHint,
      sessionHint: sessionHint,
    );
    if (scope == null) return null;
    return _sessionFileForScope(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
  }

  Future<CompanyProfile?> _readProfileFromFile(File file) async {
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final p = CompanyProfile.fromJson(Map<String, dynamic>.from(decoded));
    if (p.companyId.isEmpty) return null;
    return p;
  }

  Future<ActiveCompanySession?> _readSessionFromFile(File file) async {
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final s = ActiveCompanySession.fromJson(Map<String, dynamic>.from(decoded));
    if (s.companyId.isEmpty) return null;
    return s;
  }

  String? _readTokenAliasFromRawSessionMap(Map<String, dynamic> json) {
    const keys = <String>[
      'companySessionToken',
      'company_session_token',
      'token',
      'authToken',
      'auth_token',
      'companyToken',
      'company_token',
      'sessionToken',
      'session_token',
      'pairingToken',
      'pairing_token',
      'bootstrapToken',
      'bootstrap_token',
      'accessToken',
      'access_token',
    ];
    for (final key in keys) {
      final raw = (json[key] ?? '').toString().trim();
      if (raw.isNotEmpty) return raw;
    }
    return null;
  }

  Future<({String? token, String source})> resolveCompanyBootstrapToken({
    ActiveCompanySession? preferredSession,
  }) async {
    final preferredToken = (preferredSession?.companySessionToken ?? '').trim();
    if (preferredToken.isNotEmpty) {
      debugPrint(
        '[COMPANY_PAIRING][TOKEN_RESOLVE] source=notifier hasToken=true aliasMerged=false',
      );
      return (token: preferredToken, source: 'notifier');
    }

    final loaded = await loadSession();
    final loadedToken = (loaded?.companySessionToken ?? '').trim();
    if (loadedToken.isNotEmpty) {
      debugPrint(
        '[COMPANY_PAIRING][TOKEN_RESOLVE] source=session hasToken=true aliasMerged=false',
      );
      return (token: loadedToken, source: 'session');
    }

    var aliasMerged = false;
    try {
      final scopedFile = await _sessionFileForKnownScope();
      if (scopedFile != null && await scopedFile.exists()) {
        final raw = await scopedFile.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = Map<String, dynamic>.from(decoded);
            final aliasToken = (_readTokenAliasFromRawSessionMap(map) ?? '')
                .trim();
            if (aliasToken.isNotEmpty) {
              final base = loaded ?? preferredSession;
              if (base != null &&
                  (base.companySessionToken ?? '').trim().isEmpty) {
                final merged = base.copyWith(companySessionToken: aliasToken);
                _sessionMemory = merged;
                activeCompanySessionNotifier.value = merged;
                try {
                  await scopedFile.writeAsString(jsonEncode(merged.toJson()));
                  aliasMerged = true;
                  _logSessionWriteSummary('alias_token_promote', merged);
                } catch (e) {
                  debugPrint(
                    '[COMPANY_SESSION][PERSIST_FAIL] op=alias_token_promote err=${_shortErrForCompanyLog(e)}',
                  );
                }
              }
              debugPrint(
                '[COMPANY_PAIRING][TOKEN_RESOLVE] source=session_alias hasToken=true aliasMerged=$aliasMerged',
              );
              return (token: aliasToken, source: 'session_alias');
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][LOAD_SESSION_FAIL] reason=alias_resolve_exception err=${_shortErrForCompanyLog(e)}',
      );
    }
    debugPrint(
      '[COMPANY_PAIRING][TOKEN_RESOLVE] source=none hasToken=false aliasMerged=false',
    );
    return (token: null, source: 'none');
  }

  /// Backend-usable company context for admin/sync entry points.
  ///
  /// Requires:
  /// - non-empty company scope from active profile/session
  /// - no profile/session company mismatch when both are present
  /// - non-empty bootstrap token from accepted sources
  ///
  /// Reason codes:
  /// - ok
  /// - missing_company_scope
  /// - profile_session_mismatch
  /// - missing_token
  Future<({bool ok, String reason, String tokenSource, String companyId})>
  resolveBackendUsableCompanyContext({
    CompanyProfile? profileHint,
    ActiveCompanySession? sessionHint,
  }) async {
    var profile = profileHint ?? companyProfileNotifier.value;
    profile ??= await loadProfile();
    var session = sessionHint ?? activeCompanySessionNotifier.value;
    session ??= await loadSession();

    final profileCompanyId = (profile?.companyId ?? '').trim();
    final sessionCompanyId = (session?.companyId ?? '').trim();

    if (profileCompanyId.isEmpty && sessionCompanyId.isEmpty) {
      debugPrint(
        '[COMPANY_SESSION][BACKEND_USABLE_CONTEXT] ok=false reason=missing_company_scope tokenSource=none companyId=—',
      );
      return (
        ok: false,
        reason: 'missing_company_scope',
        tokenSource: 'none',
        companyId: '',
      );
    }
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      debugPrint(
        '[COMPANY_SESSION][BACKEND_USABLE_CONTEXT] ok=false reason=profile_session_mismatch tokenSource=none profile=${_maskCompanyIdForLog(profileCompanyId)} session=${_maskCompanyIdForLog(sessionCompanyId)}',
      );
      return (
        ok: false,
        reason: 'profile_session_mismatch',
        tokenSource: 'none',
        companyId: '',
      );
    }

    final scopeCompanyId = sessionCompanyId.isNotEmpty
        ? sessionCompanyId
        : profileCompanyId;
    if (scopeCompanyId.isEmpty) {
      debugPrint(
        '[COMPANY_SESSION][BACKEND_USABLE_CONTEXT] ok=false reason=missing_company_scope tokenSource=none companyId=—',
      );
      return (
        ok: false,
        reason: 'missing_company_scope',
        tokenSource: 'none',
        companyId: '',
      );
    }

    final resolved = await resolveCompanyBootstrapToken(
      preferredSession: session,
    );
    final token = (resolved.token ?? '').trim();
    const acceptedSources = <String>{'notifier', 'session', 'session_alias'};
    if (token.isEmpty || !acceptedSources.contains(resolved.source)) {
      debugPrint(
        '[COMPANY_SESSION][BACKEND_USABLE_CONTEXT] ok=false reason=missing_token tokenSource=${resolved.source} companyId=${_maskCompanyIdForLog(scopeCompanyId)}',
      );
      return (
        ok: false,
        reason: 'missing_token',
        tokenSource: resolved.source,
        companyId: scopeCompanyId,
      );
    }

    debugPrint(
      '[COMPANY_SESSION][BACKEND_USABLE_CONTEXT] ok=true reason=ok tokenSource=${resolved.source} companyId=${_maskCompanyIdForLog(scopeCompanyId)}',
    );
    return (
      ok: true,
      reason: 'ok',
      tokenSource: resolved.source,
      companyId: scopeCompanyId,
    );
  }

  Future<CompanyProfile?> loadProfile() async {
    try {
      if (_profileMemory != null) return _profileMemory;
      var scopedHit = false;
      final scopedFile = await _profileFileForKnownScope();
      if (scopedFile != null) {
        final scoped = await _readProfileFromFile(scopedFile);
        if (scoped != null) {
          _profileMemory = scoped;
          return scoped;
        }
        scopedHit = await scopedFile.exists();
      }

      final legacyFile = await _legacyProfileFile();
      final legacyExists = await legacyFile.exists();
      final legacy = await _readProfileFromFile(legacyFile);
      if (legacy == null) {
        final discovered = await _discoverLatestScopedProfile();
        if (discovered != null) {
          _profileMemory = discovered;
          debugPrint(
            '[COMPANY_SESSION][DISCOVER] target=profile tenant=${discovered.tenantId} company=${discovered.companyId}',
          );
          return discovered;
        }
        debugPrint(
          '[COMPANY_SESSION][LOAD_PROFILE_MISS] scoped=$scopedHit legacy=$legacyExists discovered=false',
        );
        return null;
      }

      final scopedTarget = await _profileFileForScope(
        tenantId: legacy.tenantId,
        companyId: legacy.companyId,
      );
      if (scopedTarget.path != legacyFile.path &&
          !await scopedTarget.exists()) {
        await scopedTarget.writeAsString(jsonEncode(legacy.toJson()));
        debugPrint(
          '[COMPANY_SESSION][MIGRATE_LEGACY] target=profile tenant=${legacy.tenantId} company=${legacy.companyId} from=${legacyFile.path} to=${scopedTarget.path}',
        );
      }
      _profileMemory = legacy;
      return legacy;
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][LOAD_PROFILE_FAIL] reason=storage_read_exception err=${_shortErrForCompanyLog(e)}',
      );
      return null;
    }
  }

  Future<CompanyProfile?> _discoverLatestScopedProfile() async {
    try {
      final root = await _stateRootDir();
      if (!await root.exists()) return null;
      CompanyProfile? latestProfile;
      DateTime? latestModifiedAt;
      await for (final tenantNode in root.list(followLinks: false)) {
        if (tenantNode is! Directory) continue;
        await for (final companyNode in tenantNode.list(followLinks: false)) {
          if (companyNode is! Directory) continue;
          final profileFile = File(
            '${companyNode.path}${Platform.pathSeparator}$_profileFileName',
          );
          final profile = await _readProfileFromFile(profileFile);
          if (profile == null) continue;
          DateTime modifiedAt;
          try {
            modifiedAt = await profileFile.lastModified();
          } catch (e) {
            debugPrint(
              '[COMPANY_SESSION][DISCOVER_FAIL] op=last_modified err=${_shortErrForCompanyLog(e)}',
            );
            modifiedAt = DateTime.fromMillisecondsSinceEpoch(0);
          }
          if (latestModifiedAt == null ||
              modifiedAt.isAfter(latestModifiedAt)) {
            latestModifiedAt = modifiedAt;
            latestProfile = profile;
          }
        }
      }
      return latestProfile;
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][DISCOVER_FAIL] op=scan err=${_shortErrForCompanyLog(e)}',
      );
      return null;
    }
  }

  Future<ActiveCompanySession?> loadSession() async {
    try {
      if (_sessionMemory != null) return _sessionMemory;
      final scopedFile = await _sessionFileForKnownScope();
      if (scopedFile != null) {
        final scoped = await _readSessionFromFile(scopedFile);
        if (scoped != null) {
          if (_isExpiredTokenBackedSession(scoped)) {
            final expiresIso = (scoped.companySessionExpiresAtUtc ?? '').trim();
            final parsedExpiresAt = DateTime.tryParse(expiresIso)?.toUtc();
            final nowUtc = DateTime.now().toUtc();
            final ageOrDelta = parsedExpiresAt == null
                ? '—'
                : '${nowUtc.difference(parsedExpiresAt).inSeconds}s';
            debugPrint(
              '[COMPANY_SESSION][TOKEN_EXPIRY_DECISION] expired=true source=scoped company=${_maskCompanyIdForLog(scoped.companyId)} expiresAt=${expiresIso.isEmpty ? '—' : expiresIso} now=${nowUtc.toIso8601String()} ageOrDelta=$ageOrDelta',
            );
            final restored = _restoreExpiredTokenSessionToLocalContext(scoped);
            // Option A: non-destructive on disk. We deliberately do NOT
            // writeAsString the tokenless restored session back to
            // active_company_session_v1.json. The on-disk token+expiry are
            // left intact so subsequent backend calls can attempt the token
            // (server is the source of truth for invalidation), and so a
            // recovery flow can still resolve it via
            // resolveCompanyBootstrapToken. _touchSessionLastUsed below
            // preserves the stored token when memory is tokenless.
            _sessionMemory = restored;
            activeCompanySessionNotifier.value = restored;
            final nowIso = nowUtc.toIso8601String();
            debugPrint(
              '[COMPANY_PAIRING][TOKEN_EXPIRED_LOCAL_CONTEXT_RESTORED] company=${restored.companyId} expires_at=${expiresIso.isEmpty ? '—' : expiresIso} now=$nowIso',
            );
            return restored;
          }
          if (!_isSessionStillValid(scoped)) {
            debugPrint(
              '[COMPANY_SESSION][SESSION_INVALID_LOCAL] reason=stale_token_metadata source=scoped company=${_maskCompanyIdForLog(scoped.companyId)}',
            );
            return null;
          }
          _sessionMemory = scoped;
          return scoped;
        }
      }

      final legacyFile = await _legacySessionFile();
      final legacy = await _readSessionFromFile(legacyFile);
      if (legacy == null) return null;
      if (_isExpiredTokenBackedSession(legacy)) {
        final expiresIso = (legacy.companySessionExpiresAtUtc ?? '').trim();
        final parsedExpiresAt = DateTime.tryParse(expiresIso)?.toUtc();
        final nowUtc = DateTime.now().toUtc();
        final ageOrDelta = parsedExpiresAt == null
            ? '—'
            : '${nowUtc.difference(parsedExpiresAt).inSeconds}s';
        debugPrint(
          '[COMPANY_SESSION][TOKEN_EXPIRY_DECISION] expired=true source=legacy company=${_maskCompanyIdForLog(legacy.companyId)} expiresAt=${expiresIso.isEmpty ? '—' : expiresIso} now=${nowUtc.toIso8601String()} ageOrDelta=$ageOrDelta',
        );
        final restored = _restoreExpiredTokenSessionToLocalContext(legacy);
        // Option A: non-destructive on disk. Deliberately do NOT write the
        // tokenless restored session to the scoped target. The legacy file
        // (and its token+expiry) are preserved as-is. The valid-session
        // legacy->scoped migration below only runs for non-expired sessions.
        _sessionMemory = restored;
        activeCompanySessionNotifier.value = restored;
        final nowIso = nowUtc.toIso8601String();
        debugPrint(
          '[COMPANY_PAIRING][TOKEN_EXPIRED_LOCAL_CONTEXT_RESTORED] company=${restored.companyId} expires_at=${expiresIso.isEmpty ? '—' : expiresIso} now=$nowIso',
        );
        return restored;
      }
      if (!_isSessionStillValid(legacy)) {
        debugPrint(
          '[COMPANY_SESSION][SESSION_INVALID_LOCAL] reason=stale_token_metadata source=legacy company=${_maskCompanyIdForLog(legacy.companyId)}',
        );
        return null;
      }

      final scopedTarget = await _sessionFileForScope(
        tenantId: legacy.companyId,
        companyId: legacy.companyId,
      );
      if (scopedTarget.path != legacyFile.path &&
          !await scopedTarget.exists()) {
        await scopedTarget.writeAsString(jsonEncode(legacy.toJson()));
        debugPrint(
          '[COMPANY_SESSION][MIGRATE_LEGACY] target=session tenant=${legacy.companyId} company=${legacy.companyId} from=${legacyFile.path} to=${scopedTarget.path}',
        );
        _logSessionWriteSummary('migrate_legacy_session', legacy);
      }
      _sessionMemory = legacy;
      return legacy;
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][LOAD_SESSION_FAIL] reason=storage_read_exception err=${_shortErrForCompanyLog(e)}',
      );
      return null;
    }
  }

  /// Local company context validity for restoring company screens.
  ///
  /// This does not guarantee backend-usable token state. For backend-admin
  /// entry checks use [resolveBackendUsableCompanyContext].
  bool get hasValidCompanyContext =>
      companyProfileNotifier.value != null &&
      activeCompanySessionNotifier.value != null &&
      companyProfileNotifier.value!.isActive &&
      _isSessionStillValid(activeCompanySessionNotifier.value!) &&
      companyProfileNotifier.value!.companyId ==
          activeCompanySessionNotifier.value!.companyId;

  /// Prepared for future gated flows; do not use to block MVP navigation yet.
  bool get hasVerifiedCompanyContext =>
      hasValidCompanyContext && companyProfileNotifier.value!.isVerified;

  /// Call after tenant state load — reconciles disk + sets notifiers; does not overwrite pricing fields.
  Future<void> bootstrap() async {
    debugPrint('[COMPANY_PAIRING][BOOTSTRAP] started=true');
    _profileMemory = null;
    _sessionMemory = null;
    CompanyProfile? p = await loadProfile();
    ActiveCompanySession? s = await loadSession();

    if (p == null) {
      debugPrint('[COMPANY_PAIRING][SESSION_MISSING] reason=profile_missing');
      await clearLocalCompanyState();
      return;
    }
    if (p.companyId.isEmpty) {
      debugPrint(
        '[COMPANY_PAIRING][SESSION_MISSING] reason=profile_company_empty',
      );
      await clearLocalCompanyState();
      return;
    }
    if (!p.isActive) {
      debugPrint(
        '[COMPANY_PAIRING][SESSION_MISSING] reason=profile_inactive company=${_maskCompanyIdForLog(p.companyId)}',
      );
      await clearLocalCompanyState();
      return;
    }
    companyProfileNotifier.value = p;
    if (s == null) {
      await _writeSessionForProfile(p);
      final restored = activeCompanySessionNotifier.value;
      final hasToken = (restored?.companySessionToken ?? '').trim().isNotEmpty;
      final tokenExpiresAt = (restored?.companySessionExpiresAtUtc ?? '')
          .trim();
      debugPrint(
        '[COMPANY_PAIRING][SESSION_RESTORED] company=${p.companyId} source=profile_only hasToken=$hasToken tokenExpiresAt=${tokenExpiresAt.isEmpty ? '—' : tokenExpiresAt}',
      );
      return;
    }
    if (s.companyId != p.companyId) {
      debugPrint(
        '[COMPANY_PAIRING][SESSION_MISSING] reason=session_company_mismatch profile=${_maskCompanyIdForLog(p.companyId)} session=${_maskCompanyIdForLog(s.companyId)}',
      );
      await _writeSessionForProfile(p);
      final restored = activeCompanySessionNotifier.value;
      final hasToken = (restored?.companySessionToken ?? '').trim().isNotEmpty;
      final tokenExpiresAt = (restored?.companySessionExpiresAtUtc ?? '')
          .trim();
      debugPrint(
        '[COMPANY_PAIRING][SESSION_RESTORED] company=${p.companyId} source=profile_only hasToken=$hasToken tokenExpiresAt=${tokenExpiresAt.isEmpty ? '—' : tokenExpiresAt}',
      );
      return;
    }
    activeCompanySessionNotifier.value = s;
    await _touchSessionLastUsed();
    final restored = activeCompanySessionNotifier.value;
    final hasToken = (restored?.companySessionToken ?? '').trim().isNotEmpty;
    final tokenExpiresAt = (restored?.companySessionExpiresAtUtc ?? '').trim();
    debugPrint(
      '[COMPANY_PAIRING][SESSION_RESTORED] company=${p.companyId} source=profile_session hasToken=$hasToken tokenExpiresAt=${tokenExpiresAt.isEmpty ? '—' : tokenExpiresAt}',
    );
  }

  Future<void> _writeSessionForProfile(CompanyProfile p) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final prev = await loadSession();
    final file = await _sessionFileForScope(
      tenantId: p.tenantId,
      companyId: p.companyId,
    );
    final stored = await _readSessionFromFile(file);
    final storedToken = (stored?.companySessionToken ?? '').trim();
    final prevToken = (prev?.companySessionToken ?? '').trim();
    final preservedToken = prevToken.isNotEmpty
        ? prevToken
        : (storedToken.isNotEmpty ? storedToken : null);
    final preservedExpires =
        prev?.companySessionExpiresAtUtc ?? stored?.companySessionExpiresAtUtc;
    final preservedCompanyCode = prev?.companyCode ?? stored?.companyCode;
    final preservedLinkMethod = prev?.linkMethod ?? stored?.linkMethod;
    final session = ActiveCompanySession(
      companyId: p.companyId,
      role: 'companyAdmin',
      createdAt: prev != null && prev.companyId == p.companyId
          ? prev.createdAt
          : now,
      lastUsedAt: now,
      companySessionToken: preservedToken,
      companySessionExpiresAtUtc: preservedExpires,
      companyCode: preservedCompanyCode,
      linkMethod: preservedLinkMethod,
    );
    try {
      await file.writeAsString(jsonEncode(session.toJson()));
      _sessionMemory = session;
      activeCompanySessionNotifier.value = session;
      debugPrint(
        '[COMPANY_SESSION][SAVE] target=session tenant=${p.tenantId} company=${p.companyId} path=${file.path}',
      );
      _logSessionWriteSummary('write_session_for_profile', session);
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=write_session_for_profile company=${_maskCompanyIdForLog(p.companyId)} err=${_shortErrForCompanyLog(e)}',
      );
    }
  }

  Future<void> _touchSessionLastUsed() async {
    final cur = activeCompanySessionNotifier.value;
    if (cur == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      final file = await _sessionFileForScope(
        tenantId: cur.companyId,
        companyId: cur.companyId,
      );
      final stored = await _readSessionFromFile(file);
      final storedToken = (stored?.companySessionToken ?? '').trim();
      final currentToken = (cur.companySessionToken ?? '').trim();
      final preservedToken = currentToken.isNotEmpty
          ? currentToken
          : (storedToken.isNotEmpty ? storedToken : null);
      final next = cur.copyWith(
        lastUsedAt: now,
        companySessionToken: preservedToken,
      );
      await file.writeAsString(jsonEncode(next.toJson()));
      _sessionMemory = next;
      activeCompanySessionNotifier.value = next;
      debugPrint(
        '[COMPANY_SESSION][SAVE] target=session tenant=${cur.companyId} company=${cur.companyId} path=${file.path}',
      );
      _logSessionWriteSummary('touch_last_used', next);
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=touch_last_used company=${_maskCompanyIdForLog(cur.companyId)} err=${_shortErrForCompanyLog(e)}',
      );
    }
  }

  Future<void> updateActiveSessionCompanyCode(
    String companyCode, {
    String source = 'session',
  }) async {
    final current = activeCompanySessionNotifier.value;
    if (current == null) {
      debugPrint('[COMPANY_CODE][HYDRATE] found=false source=$source');
      return;
    }
    final normalized = _normalizePublicCompanyCode(companyCode);
    if (!_isValidPublicCompanyCode(normalized)) {
      debugPrint('[COMPANY_CODE][HYDRATE] found=false source=$source');
      return;
    }
    if ((current.companyCode ?? '').trim() == normalized) {
      debugPrint('[COMPANY_CODE][HYDRATE] found=true source=$source');
      return;
    }
    final next = current.copyWith(companyCode: normalized);
    try {
      final file = await _sessionFileForScope(
        tenantId: current.companyId,
        companyId: current.companyId,
      );
      await file.writeAsString(jsonEncode(next.toJson()));
      _sessionMemory = next;
      activeCompanySessionNotifier.value = next;
      debugPrint('[COMPANY_CODE][HYDRATE] found=true source=$source');
      _logSessionWriteSummary('update_company_code', next);
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=update_company_code source=$source err=${_shortErrForCompanyLog(e)}',
      );
    }
  }

  static String slugifyCompanyName(String raw) {
    var s = raw.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
    s = s.replaceAll(RegExp(r'_+'), '_');
    if (s.startsWith('_')) s = s.substring(1);
    if (s.endsWith('_')) s = s.substring(0, s.length - 1);
    if (s.length > 40) s = s.substring(0, 40);
    if (s.isEmpty) s = 'company';
    return s;
  }

  static String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = math.Random();
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(chars[r.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  /// Readable unique id, stable once stored in [CompanyProfile].
  static String generateCompanyId(String companyName) {
    final slug = slugifyCompanyName(companyName);
    return 'fluxidi_${slug}_${_randomSuffix()}';
  }

  static String _normalizeHumanCompanyId(String raw) {
    var text = raw.trim().toUpperCase();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'\s+'), '-');
    text = text.replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    text = text.replaceAll(RegExp(r'-+'), '-');
    text = text.replaceAll(RegExp(r'^-+|-+$'), '');
    if (text.length < 4 || text.length > 24) return '';
    if (!RegExp(r'[A-Z0-9]').hasMatch(text)) return '';
    return text;
  }

  /// Persists profile + session; mirrors key fields into [businessSettingsNotifier] for existing UI.
  Future<void> saveNewProfileFromOnboarding({
    required String companyName,
    required String ownerName,
    required String email,
    required String phone,
    String vatNumber = '',
    String city = '',
    String countryCode = 'BE',
    String? companyIdOverride,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedOverride = _normalizeHumanCompanyId(
      companyIdOverride ?? '',
    );
    final id = normalizedOverride.isNotEmpty
        ? normalizedOverride
        : generateCompanyId(companyName);
    final em = email.trim();
    final profile = CompanyProfile(
      companyId: id,
      companyName: companyName.trim(),
      ownerName: ownerName.trim(),
      email: em,
      phone: phone.trim(),
      vatNumber: vatNumber.trim(),
      addressLine: '',
      postalCode: '',
      city: city.trim(),
      countryCode: countryCode.trim().toUpperCase().isEmpty
          ? 'BE'
          : countryCode.trim().toUpperCase(),
      companyEmail: em,
      supportEmail: em,
      billingEmail: em,
      bookingEmail: em,
      notificationEmail: em,
      createdAt: now,
      updatedAt: now,
      isActive: true,
      verificationStatus: CompanyVerificationStatus.pendingVerification,
    );
    await persistProfile(profile);
    await _writeSessionForProfile(profile);
    companyProfileNotifier.value = profile;
    applyProfileToBusinessNotifier(profile);
  }

  /// Persists a backend-backed company registration session for first device setup.
  Future<void> savePublicCompanyRegistrationSession({
    required String tenantId,
    required String companyId,
    required String companyCode,
    required String companyName,
    required String countryCode,
    required String companySessionToken,
    String ownerName = '',
    String email = '',
    String phone = '',
    String vatNumber = '',
    String addressLine = '',
    String postalCode = '',
    String city = '',
    DateTime? issuedAt,
    DateTime? expiresAt,
    int? expiresInSeconds,
  }) async {
    final resolvedCompanyId = companyId.trim();
    final resolvedTenantId = tenantId.trim();
    final token = companySessionToken.trim();
    if (resolvedCompanyId.isEmpty ||
        resolvedTenantId.isEmpty ||
        token.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();
    final issued = (issuedAt ?? now).toUtc();
    final nowIso = now.toIso8601String();
    final issuedIso = issued.toIso8601String();
    final normalizedCountry = countryCode.trim().toUpperCase();
    final safeCountry = normalizedCountry.isEmpty ? 'BE' : normalizedCountry;
    final normalizedCode = _normalizePublicCompanyCode(companyCode);
    final String? safeCode = _isValidPublicCompanyCode(normalizedCode)
        ? normalizedCode
        : null;
    final safeName = companyName.trim().isEmpty
        ? (safeCode ?? resolvedCompanyId)
        : companyName.trim();
    final safeEmail = email.trim();
    final profile = CompanyProfile(
      companyId: resolvedCompanyId,
      companyName: safeName,
      ownerName: ownerName.trim(),
      email: safeEmail,
      phone: phone.trim(),
      vatNumber: vatNumber.trim(),
      addressLine: addressLine.trim(),
      postalCode: postalCode.trim(),
      city: city.trim(),
      countryCode: safeCountry,
      companyEmail: safeEmail,
      supportEmail: safeEmail,
      billingEmail: safeEmail,
      bookingEmail: safeEmail,
      notificationEmail: safeEmail,
      createdAt: issuedIso,
      updatedAt: nowIso,
      isActive: true,
      verificationStatus: CompanyVerificationStatus.pendingVerification,
    );
    await persistProfile(profile);
    final prev = await loadSession();
    final serverResolvedExpiresAtUtc = () {
      if (expiresAt != null) return expiresAt.toUtc();
      if (expiresInSeconds != null && expiresInSeconds > 0) {
        return now.add(Duration(seconds: expiresInSeconds)).toUtc();
      }
      return null;
    }();
    final resolvedExpiresAtUtc = _maybeClampSessionExpiryForDev(
      serverResolvedExpiresAtUtc,
    );
    final session = ActiveCompanySession(
      companyId: profile.companyId,
      role: 'companyAdmin',
      createdAt: prev != null && prev.companyId == profile.companyId
          ? prev.createdAt
          : nowIso,
      lastUsedAt: nowIso,
      companySessionToken: token,
      companySessionExpiresAtUtc: resolvedExpiresAtUtc?.toIso8601String(),
      companyCode: safeCode,
      linkMethod: 'public_company_register',
    );
    try {
      final file = await _sessionFileForScope(
        tenantId: profile.tenantId,
        companyId: profile.companyId,
      );
      await file.writeAsString(jsonEncode(session.toJson()));
      _sessionMemory = session;
      activeCompanySessionNotifier.value = session;
      debugPrint(
        '[COMPANY_SESSION][SAVE] target=session tenant=${profile.tenantId} company=${profile.companyId} path=${file.path}',
      );
      _logSessionWriteSummary('save_public_registration', session);
      final hasTokenPersist = (session.companySessionToken ?? '')
          .trim()
          .isNotEmpty;
      final expiresAtPersist = (session.companySessionExpiresAtUtc ?? '')
          .trim();
      debugPrint(
        '[COMPANY_SESSION][TOKEN_PERSIST_CHECK] hasToken=$hasTokenPersist expiresAt=${expiresAtPersist.isEmpty ? '—' : expiresAtPersist} source=public_registration',
      );
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=save_public_registration company=${_maskCompanyIdForLog(profile.companyId)} err=${_shortErrForCompanyLog(e)}',
      );
    }
    companyProfileNotifier.value = profile;
    applyProfileToBusinessNotifier(profile);
  }

  /// Persists a verified backend pairing into local company profile + session.
  /// This does not use admin endpoints and stores only safe public pairing fields.
  Future<void> saveVerifiedCompanyPairingSession({
    required String tenantId,
    required String companyId,
    String? companyCode,
    required String companyName,
    required String countryCode,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? companySessionToken,
    int? expiresInSeconds,
    DateTime? expiresAtUtc,
    String? linkMethod,
  }) async {
    final resolvedCompanyId = companyId.trim();
    if (resolvedCompanyId.isEmpty) return;
    final resolvedTenantId = tenantId.trim();
    if (resolvedTenantId.isEmpty) return;
    final now = DateTime.now().toUtc();
    final issued = (issuedAt ?? now).toUtc();
    final nowIso = now.toIso8601String();
    final issuedIso = issued.toIso8601String();
    final normalizedCountry = countryCode.trim().toUpperCase();
    final safeCountry = normalizedCountry.isEmpty ? 'BE' : normalizedCountry;
    final normalizedCode = _normalizePublicCompanyCode(companyCode ?? '');
    final String? safeCode = _isValidPublicCompanyCode(normalizedCode)
        ? normalizedCode
        : null;
    final safeName = companyName.trim().isEmpty
        ? (safeCode ?? resolvedCompanyId)
        : companyName.trim();
    final existingLocal = await loadProfile();
    final drafted = CompanyProfile(
      companyId: resolvedCompanyId,
      companyName: safeName,
      ownerName: '',
      email: '',
      phone: '',
      vatNumber: '',
      addressLine: '',
      postalCode: '',
      city: '',
      countryCode: safeCountry,
      companyEmail: '',
      supportEmail: '',
      billingEmail: '',
      bookingEmail: '',
      notificationEmail: '',
      createdAt: issuedIso,
      updatedAt: nowIso,
      isActive: true,
      verificationStatus: CompanyVerificationStatus.pendingVerification,
    );
    final profile = mergeCompanyProfileForVerifiedPairing(
      incoming: drafted,
      existingLocal: existingLocal,
      existingBackend: localBackendBusinessProfileNotifier.value,
    );
    await persistProfile(profile);
    final prev = await loadSession();
    final serverResolvedExpiresAtUtc = () {
      if (expiresAtUtc != null) return expiresAtUtc.toUtc();
      if (expiresAt != null) return expiresAt.toUtc();
      if (expiresInSeconds != null && expiresInSeconds > 0) {
        return now.add(Duration(seconds: expiresInSeconds)).toUtc();
      }
      return null;
    }();
    final resolvedExpiresAtUtc = _maybeClampSessionExpiryForDev(
      serverResolvedExpiresAtUtc,
    );
    final normalizedToken = (companySessionToken ?? '').trim();
    final normalizedLinkMethod = (linkMethod ?? '').trim();
    final session = ActiveCompanySession(
      companyId: profile.companyId,
      role: 'companyAdmin',
      createdAt: prev != null && prev.companyId == profile.companyId
          ? prev.createdAt
          : nowIso,
      lastUsedAt: nowIso,
      companySessionToken: normalizedToken.isEmpty ? null : normalizedToken,
      companySessionExpiresAtUtc: resolvedExpiresAtUtc?.toIso8601String(),
      companyCode: safeCode,
      linkMethod: normalizedLinkMethod.isEmpty
          ? (normalizedToken.isEmpty
                ? 'company_pairing_code'
                : 'public_company_pairing')
          : normalizedLinkMethod,
    );
    try {
      final file = await _sessionFileForScope(
        tenantId: profile.tenantId,
        companyId: profile.companyId,
      );
      await file.writeAsString(jsonEncode(session.toJson()));
      _sessionMemory = session;
      activeCompanySessionNotifier.value = session;
      debugPrint(
        '[COMPANY_SESSION][SAVE] target=session tenant=${profile.tenantId} company=${profile.companyId} path=${file.path}',
      );
      _logSessionWriteSummary('save_verified_pairing', session);
      final hasTokenPersist = (session.companySessionToken ?? '')
          .trim()
          .isNotEmpty;
      final expiresAtPersist = (session.companySessionExpiresAtUtc ?? '')
          .trim();
      final persistSourceLabel = (session.linkMethod ?? '').trim().isEmpty
          ? 'verified_pairing'
          : 'verified_pairing:${session.linkMethod}';
      debugPrint(
        '[COMPANY_SESSION][TOKEN_PERSIST_CHECK] hasToken=$hasTokenPersist expiresAt=${expiresAtPersist.isEmpty ? '—' : expiresAtPersist} source=$persistSourceLabel',
      );
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=save_verified_pairing company=${_maskCompanyIdForLog(profile.companyId)} err=${_shortErrForCompanyLog(e)}',
      );
    }
    companyProfileNotifier.value = profile;
    applyProfileToBusinessNotifier(profile);
    debugPrint(
      '[COMPANY_PAIRING][SAVE] tenant=$resolvedTenantId company=$resolvedCompanyId',
    );
    // Reserved for future session-expiry checks at bootstrap level.
    final _ = expiresAt;
  }

  Future<void> persistProfile(CompanyProfile profile) async {
    try {
      final file = await _profileFileForScope(
        tenantId: profile.tenantId,
        companyId: profile.companyId,
      );
      await file.writeAsString(jsonEncode(profile.toJson()));
      _profileMemory = profile;
      companyProfileNotifier.value = profile;
      debugPrint(
        '[COMPANY_SESSION][SAVE] target=profile tenant=${profile.tenantId} company=${profile.companyId} path=${file.path}',
      );
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=persist_profile company=${_maskCompanyIdForLog(profile.companyId)} err=${_shortErrForCompanyLog(e)}',
      );
    }
  }

  /// Merge into [businessSettingsNotifier] (pricing fields preserved).
  ///
  /// Empty incoming contact fields keep the current branding values. The
  /// primary contact mail is never used as a silent fallback for support,
  /// booking, or reply-to.
  void applyProfileToBusinessNotifier(CompanyProfile p) {
    final cur = businessSettingsNotifier.value;
    final addr = <String>[
      if (p.addressLine.trim().isNotEmpty) p.addressLine.trim(),
      if (p.postalCode.trim().isNotEmpty || p.city.trim().isNotEmpty)
        '${p.postalCode.trim()} ${p.city.trim()}'.trim(),
      if (p.countryCode.trim().isNotEmpty) p.countryCode.trim(),
    ].join('\n');
    updateBusinessSettings(
      cur.copyWith(
        companyName: p.companyName.trim().isNotEmpty
            ? p.companyName
            : cur.companyName,
        supportEmail: p.supportEmail.trim().isNotEmpty
            ? p.supportEmail
            : cur.supportEmail,
        supportPhone: p.phone.trim().isNotEmpty ? p.phone : cur.supportPhone,
        vatCompanyNumber: p.vatNumber.trim().isNotEmpty
            ? p.vatNumber
            : cur.vatCompanyNumber,
        address: addr.trim().isNotEmpty ? addr : cur.address,
        bookingSender: p.bookingEmail.trim().isNotEmpty
            ? p.bookingEmail
            : cur.bookingSender,
        bookingReplyTo: p.notificationEmail.trim().isNotEmpty
            ? p.notificationEmail
            : cur.bookingReplyTo,
        whatsappNumber: p.phone.trim().isNotEmpty
            ? p.phone
            : cur.whatsappNumber,
      ),
    );
  }

  /// Updates only the local primary contact mail after a successful backend save.
  Future<void> updatePrimaryContactEmailFromBackend(String email) async {
    final current = await loadProfile();
    if (current == null) return;
    final next = current.copyWith(
      email: email.trim(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await persistProfile(next);
  }

  /// Update profile preserving [companyId] and [createdAt].
  Future<void> updateSavedProfile(
    CompanyProfile next, {
    required String preservedCompanyId,
    required String preservedCreatedAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final merged = next.copyWith(
      companyId: preservedCompanyId,
      createdAt: preservedCreatedAt,
      updatedAt: now,
      isActive: true,
    );
    await persistProfile(merged);
    await _writeSessionForProfile(merged);
    applyProfileToBusinessNotifier(merged);
  }

  Future<void> clearLocalCompanyState() async {
    try {
      final scope = _resolveScopeFromKnownState();
      if (scope != null) {
        final pf = await _profileFileForScope(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        if (await pf.exists()) await pf.delete();
        final sf = await _sessionFileForScope(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        if (await sf.exists()) await sf.delete();
        debugPrint(
          '[COMPANY_SESSION][CLEAR] tenant=${scope.tenantId} company=${scope.companyId} profilePath=${pf.path} sessionPath=${sf.path}',
        );
      } else {
        debugPrint(
          '[COMPANY_SESSION][CLEAR] tenant=unknown company=unknown scoped_files_skipped=true',
        );
      }
    } catch (e) {
      debugPrint(
        '[COMPANY_SESSION][PERSIST_FAIL] op=clear_local_state err=${_shortErrForCompanyLog(e)}',
      );
    }
    _profileMemory = null;
    _sessionMemory = null;
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
  }
}

/// Local fleet rows without [VehicleProfile.companyId] / [DriverProfile.companyId] are legacy MVP data.
/// TODO(backend): enforce tenant ownership server-side; production must not trust client-side ids without auth.

bool isLegacyCompanylessFleetRecord(String? companyId) =>
    companyId == null || companyId.trim().isEmpty;

bool fleetRecordBelongsToActiveCompanyOrLegacy(String? companyId) {
  if (isLegacyCompanylessFleetRecord(companyId)) return true;
  return companyId!.trim() == resolvedCompanyId.trim();
}

bool fleetExplicitCompanyMismatch(String? a, String? b) {
  final ta = a?.trim() ?? '';
  final tb = b?.trim() ?? '';
  if (ta.isEmpty || tb.isEmpty) return false;
  return ta != tb;
}

bool canAssignDriverToVehicleFleet(
  DriverProfile driver,
  VehicleProfile vehicle,
) {
  if (!fleetRecordBelongsToActiveCompanyOrLegacy(driver.companyId))
    return false;
  if (!fleetRecordBelongsToActiveCompanyOrLegacy(vehicle.companyId))
    return false;
  if (fleetExplicitCompanyMismatch(driver.companyId, vehicle.companyId)) {
    return false;
  }
  return true;
}

bool canAssignDriverToVehicleCompany(
  DriverProfile driver,
  String? vehicleCompanyId,
) {
  if (!fleetRecordBelongsToActiveCompanyOrLegacy(driver.companyId))
    return false;
  if (!fleetRecordBelongsToActiveCompanyOrLegacy(vehicleCompanyId))
    return false;
  if (fleetExplicitCompanyMismatch(driver.companyId, vehicleCompanyId)) {
    return false;
  }
  return true;
}

/// Prefer company email, then owner/contact email, then support email.
String primaryContactEmailFromCompany(CompanyProfile local) {
  if (local.companyEmail.trim().isNotEmpty) return local.companyEmail.trim();
  if (local.email.trim().isNotEmpty) return local.email.trim();
  return local.supportEmail.trim();
}

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

/// Server-confirmed pairing: matching active company scope plus a session token.
/// Mollie/Chiron/subscription flags are intentionally not consulted.
bool hasServerConfirmedCompanyPairing({
  CompanyProfile? profile,
  ActiveCompanySession? session,
}) {
  final resolvedProfile = profile ?? companyProfileNotifier.value;
  final resolvedSession = session ?? activeCompanySessionNotifier.value;
  if (resolvedProfile == null || resolvedSession == null) return false;
  if (!resolvedProfile.isActive) return false;
  final profileId = resolvedProfile.companyId.trim();
  final sessionId = resolvedSession.companyId.trim();
  if (profileId.isEmpty || sessionId.isEmpty || profileId != sessionId) {
    return false;
  }
  return (resolvedSession.companySessionToken ?? '').trim().isNotEmpty;
}

enum CompanyLinkDisplayKind { suspended, verified, paired, localUnverified }

/// Display kind for the local-company status badge.
///
/// [mollieLive] and [chironProductionEnabled] are accepted only so tests can
/// prove they never change the result.
CompanyLinkDisplayKind resolveCompanyLinkDisplayKind({
  required CompanyProfile profile,
  ActiveCompanySession? session,
  bool? mollieLive,
  bool? chironProductionEnabled,
}) {
  final _ = (mollieLive, chironProductionEnabled);
  if (profile.isSuspended) return CompanyLinkDisplayKind.suspended;
  if (profile.isVerified) return CompanyLinkDisplayKind.verified;
  if (hasServerConfirmedCompanyPairing(profile: profile, session: session)) {
    return CompanyLinkDisplayKind.paired;
  }
  return CompanyLinkDisplayKind.localUnverified;
}

/// Canonical primary company contact mail: Booking `business_profile.email`,
/// with `companyEmail` only as a backend compatibility fallback.
String resolvePrimaryCompanyContactEmail({
  BackendBusinessProfile? backend,
  CompanyProfile? local,
}) {
  final fromBackend = _firstNonEmpty(<String>[
    backend?.email ?? '',
    backend?.companyEmail ?? '',
  ]);
  if (fromBackend.isNotEmpty) return fromBackend;
  return (local?.email ?? '').trim();
}

({String mijnEmail, String officialEmail}) hydratePrimaryContactEmails({
  BackendBusinessProfile? backend,
  CompanyProfile? local,
}) {
  final email = resolvePrimaryCompanyContactEmail(
    backend: backend,
    local: local,
  );
  return (mijnEmail: email, officialEmail: email);
}

/// Writes only the primary contact mail. Support, billing, booking,
/// notification, and a distinct `companyEmail` stay untouched.
BackendBusinessProfile applyPrimaryCompanyContactEmail(
  BackendBusinessProfile current,
  String email,
) {
  return current.copyWith(email: email.trim());
}

CompanyProfile applyPrimaryCompanyContactEmailToLocal(
  CompanyProfile local,
  String email,
) {
  return local.copyWith(email: email.trim());
}

class PrimaryCompanyContactSaveResult {
  const PrimaryCompanyContactSaveResult._({
    required this.ok,
    required this.saved,
    required this.draftEmail,
    this.error,
  });

  factory PrimaryCompanyContactSaveResult.success({
    required BackendBusinessProfile saved,
    required String draftEmail,
  }) {
    return PrimaryCompanyContactSaveResult._(
      ok: true,
      saved: saved,
      draftEmail: draftEmail,
    );
  }

  factory PrimaryCompanyContactSaveResult.failure({
    required String draftEmail,
    required Object error,
  }) {
    return PrimaryCompanyContactSaveResult._(
      ok: false,
      saved: null,
      draftEmail: draftEmail,
      error: error,
    );
  }

  final bool ok;
  final BackendBusinessProfile? saved;
  final String draftEmail;
  final Object? error;

  String get persistPath => kAdminBusinessProfilePath;
}

Future<PrimaryCompanyContactSaveResult> savePrimaryCompanyContactEmail({
  required String email,
  required Future<BackendBusinessProfile> Function() fetchCurrent,
  required Future<BackendBusinessProfile> Function(
    BackendBusinessProfile profile,
  )
  persist,
}) async {
  final draft = email.trim();
  try {
    final current = await fetchCurrent();
    final next = applyPrimaryCompanyContactEmail(current, draft);
    if (next.supportEmail != current.supportEmail ||
        next.invoiceEmail != current.invoiceEmail ||
        next.bookingEmail != current.bookingEmail ||
        next.notificationEmail != current.notificationEmail ||
        next.companyEmail != current.companyEmail) {
      throw StateError('primary_contact_email_must_not_overwrite_other_routes');
    }
    final saved = await persist(next);
    return PrimaryCompanyContactSaveResult.success(
      saved: saved,
      draftEmail: draft,
    );
  } catch (error) {
    return PrimaryCompanyContactSaveResult.failure(
      draftEmail: draft,
      error: error,
    );
  }
}

/// Re-pair keeps existing local/backend contact fields when incoming is empty.
CompanyProfile mergeCompanyProfileForVerifiedPairing({
  required CompanyProfile incoming,
  CompanyProfile? existingLocal,
  BackendBusinessProfile? existingBackend,
}) {
  final sameCompany =
      existingLocal != null &&
      existingLocal.companyId.trim().isNotEmpty &&
      existingLocal.companyId.trim() == incoming.companyId.trim();
  final useBackend =
      existingBackend != null && (sameCompany || existingLocal == null);

  String pick(String incomingValue, String localValue, String backendValue) {
    final fromIncoming = incomingValue.trim();
    if (fromIncoming.isNotEmpty) return fromIncoming;
    if (sameCompany && localValue.trim().isNotEmpty) return localValue.trim();
    if (useBackend && backendValue.trim().isNotEmpty)
      return backendValue.trim();
    return incomingValue;
  }

  return incoming.copyWith(
    ownerName: pick(incoming.ownerName, existingLocal?.ownerName ?? '', ''),
    email: pick(
      incoming.email,
      existingLocal?.email ?? '',
      existingBackend?.email ?? '',
    ),
    phone: pick(
      incoming.phone,
      existingLocal?.phone ?? '',
      existingBackend?.phone ?? '',
    ),
    vatNumber: pick(
      incoming.vatNumber,
      existingLocal?.vatNumber ?? '',
      existingBackend?.vatNumber ?? '',
    ),
    addressLine: pick(
      incoming.addressLine,
      existingLocal?.addressLine ?? '',
      existingBackend?.address ?? '',
    ),
    postalCode: pick(
      incoming.postalCode,
      existingLocal?.postalCode ?? '',
      existingBackend?.postcode ?? '',
    ),
    city: pick(
      incoming.city,
      existingLocal?.city ?? '',
      existingBackend?.city ?? '',
    ),
    companyEmail: pick(
      incoming.companyEmail,
      existingLocal?.companyEmail ?? '',
      existingBackend?.companyEmail ?? '',
    ),
    supportEmail: pick(
      incoming.supportEmail,
      existingLocal?.supportEmail ?? '',
      existingBackend?.supportEmail ?? '',
    ),
    billingEmail: pick(
      incoming.billingEmail,
      existingLocal?.billingEmail ?? '',
      existingBackend?.invoiceEmail ?? '',
    ),
    bookingEmail: pick(
      incoming.bookingEmail,
      existingLocal?.bookingEmail ?? '',
      existingBackend?.bookingEmail ?? '',
    ),
    notificationEmail: pick(
      incoming.notificationEmail,
      existingLocal?.notificationEmail ?? '',
      existingBackend?.notificationEmail ?? '',
    ),
    createdAt: sameCompany && existingLocal.createdAt.trim().isNotEmpty
        ? existingLocal.createdAt
        : incoming.createdAt,
    verificationStatus: sameCompany
        ? existingLocal.verificationStatus
        : incoming.verificationStatus,
  );
}

/// When [base] still looks like empty/template Worker fields, overlay local onboarding data.
/// Does not replace values that clearly diverge from app defaults (user or API edits).
BackendBusinessProfile mergeLocalIntoBackendPreview(
  BackendBusinessProfile base,
  CompanyProfile? local,
) {
  if (local == null) return base;
  final d = BackendBusinessProfile.defaults();
  String take(String current, String incoming, String def) {
    final c = current.trim();
    final inc = incoming.trim();
    final dt = def.trim();
    if (inc.isEmpty) return current;
    if (c.isEmpty || c == dt) return inc;
    return current;
  }

  final primaryEmail = primaryContactEmailFromCompany(local);

  return BackendBusinessProfile(
    companyName: take(base.companyName, local.companyName, d.companyName),
    legalName: take(base.legalName, local.companyName, d.legalName),
    vatNumber: take(base.vatNumber, local.vatNumber, d.vatNumber),
    companyRegistrationNumber: base.companyRegistrationNumber,
    address: take(base.address, local.addressLine, d.address),
    postcode: take(base.postcode, local.postalCode, d.postcode),
    city: take(base.city, local.city, d.city),
    country: take(base.country, local.countryCode, d.country),
    phone: take(base.phone, local.phone, d.phone),
    email: take(base.email, primaryEmail, d.email),
    companyEmail: base.companyEmail,
    supportEmail: base.supportEmail,
    notificationEmail: base.notificationEmail,
    website: base.website,
    bookingEmail: take(base.bookingEmail, local.bookingEmail, d.bookingEmail),
    invoiceEmail: take(base.invoiceEmail, local.billingEmail, d.invoiceEmail),
    iban: base.iban,
    paymentReferencePrefix: base.paymentReferencePrefix,
    invoiceReceiptFooterText: base.invoiceReceiptFooterText,
  );
}

// TODO(backlink): Sync fleet companyId with backend tenant APIs when auth lands.
