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

  /// Short label for dashboard/settings badges (not proof of legal verification).
  String verificationBadgeLabel(AppLanguage lang) {
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
    }
  }

  /// Shown under the badge for provisional tenants ([draft] / [pendingVerification] / unknown non-terminal).
  bool get showsPendingVerificationNotice => !isVerified && !isSuspended;

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
  bool _sessionInvalidForSecurity = false;

  bool _isSessionStillValid(ActiveCompanySession session) {
    final linkMethod = (session.linkMethod ?? '').trim().toLowerCase();
    final token = (session.companySessionToken ?? '').trim();
    final usesTokenSession =
        linkMethod == 'public_company_pairing' || token.isNotEmpty;
    if (!usesTokenSession) return true;
    if (token.isEmpty) return false;
    final expires = session.sessionExpiresAtUtc;
    if (expires == null) return true;
    return DateTime.now().toUtc().isBefore(expires);
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
      return (token: preferredToken, source: 'notifier');
    }

    final loaded = await loadSession();
    final loadedToken = (loaded?.companySessionToken ?? '').trim();
    if (loadedToken.isNotEmpty) {
      return (token: loadedToken, source: 'session');
    }

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
                } catch (_) {}
              }
              return (token: aliasToken, source: 'session_alias');
            }
          }
        }
      }
    } catch (_) {}
    return (token: null, source: 'none');
  }

  Future<CompanyProfile?> loadProfile() async {
    try {
      if (_profileMemory != null) return _profileMemory;
      final scopedFile = await _profileFileForKnownScope();
      if (scopedFile != null) {
        final scoped = await _readProfileFromFile(scopedFile);
        if (scoped != null) {
          _profileMemory = scoped;
          return scoped;
        }
      }

      final legacyFile = await _legacyProfileFile();
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
    } catch (_) {
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
          } catch (_) {
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
    } catch (_) {
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
          if (!_isSessionStillValid(scoped)) {
            _sessionInvalidForSecurity = true;
            try {
              if (await scopedFile.exists()) await scopedFile.delete();
            } catch (_) {}
            return null;
          }
          _sessionMemory = scoped;
          return scoped;
        }
      }

      final legacyFile = await _legacySessionFile();
      final legacy = await _readSessionFromFile(legacyFile);
      if (legacy == null) return null;
      if (!_isSessionStillValid(legacy)) {
        _sessionInvalidForSecurity = true;
        try {
          if (await legacyFile.exists()) await legacyFile.delete();
        } catch (_) {}
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
      }
      _sessionMemory = legacy;
      return legacy;
    } catch (_) {
      return null;
    }
  }

  /// Valid when profile exists, active, session matches ids.
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
    _sessionInvalidForSecurity = false;
    CompanyProfile? p = await loadProfile();
    ActiveCompanySession? s = await loadSession();

    if (p == null || !p.isActive || p.companyId.isEmpty) {
      debugPrint('[COMPANY_PAIRING][SESSION_MISSING] reason=profile_missing');
      await clearLocalCompanyState();
      return;
    }
    companyProfileNotifier.value = p;
    if (s == null || s.companyId != p.companyId) {
      if (_sessionInvalidForSecurity) {
        activeCompanySessionNotifier.value = null;
        debugPrint(
          '[COMPANY_PAIRING][SESSION_EXPIRED] company=${p.companyId} source=token_session',
        );
        return;
      }
      await _writeSessionForProfile(p);
      debugPrint(
        '[COMPANY_PAIRING][SESSION_RESTORED] company=${p.companyId} source=profile_only',
      );
      return;
    }
    activeCompanySessionNotifier.value = s;
    await _touchSessionLastUsed();
    debugPrint(
      '[COMPANY_PAIRING][SESSION_RESTORED] company=${p.companyId} source=profile_session',
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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
    final resolvedExpiresAtUtc = () {
      if (expiresAt != null) return expiresAt.toUtc();
      if (expiresInSeconds != null && expiresInSeconds > 0) {
        return now.add(Duration(seconds: expiresInSeconds)).toUtc();
      }
      return null;
    }();
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
    } catch (_) {}
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
    final profile = CompanyProfile(
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
    await persistProfile(profile);
    final prev = await loadSession();
    final resolvedExpiresAtUtc = () {
      if (expiresAtUtc != null) return expiresAtUtc.toUtc();
      if (expiresAt != null) return expiresAt.toUtc();
      if (expiresInSeconds != null && expiresInSeconds > 0) {
        return now.add(Duration(seconds: expiresInSeconds)).toUtc();
      }
      return null;
    }();
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
    } catch (_) {}
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
    } catch (_) {}
  }

  /// Merge into [businessSettingsNotifier] (pricing fields preserved).
  void applyProfileToBusinessNotifier(CompanyProfile p) {
    final cur = businessSettingsNotifier.value;
    final addr = <String>[
      if (p.addressLine.trim().isNotEmpty) p.addressLine.trim(),
      if (p.postalCode.trim().isNotEmpty || p.city.trim().isNotEmpty)
        '${p.postalCode.trim()} ${p.city.trim()}'.trim(),
      if (p.countryCode.trim().isNotEmpty) p.countryCode.trim(),
    ].join('\n');
    final support = p.supportEmail.trim().isNotEmpty ? p.supportEmail : p.email;
    final book = p.bookingEmail.trim().isNotEmpty ? p.bookingEmail : p.email;
    final reply = p.notificationEmail.trim().isNotEmpty
        ? p.notificationEmail
        : support;
    updateBusinessSettings(
      cur.copyWith(
        companyName: p.companyName,
        supportEmail: support,
        supportPhone: p.phone,
        vatCompanyNumber: p.vatNumber,
        address: addr,
        bookingSender: book,
        bookingReplyTo: reply,
        whatsappNumber: p.phone,
      ),
    );
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
    } catch (_) {}
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
    website: base.website,
    bookingEmail: take(base.bookingEmail, local.bookingEmail, d.bookingEmail),
    invoiceEmail: take(base.invoiceEmail, local.billingEmail, d.invoiceEmail),
    iban: base.iban,
    paymentReferencePrefix: base.paymentReferencePrefix,
    invoiceReceiptFooterText: base.invoiceReceiptFooterText,
  );
}

// TODO(backlink): Sync fleet companyId with backend tenant APIs when auth lands.
