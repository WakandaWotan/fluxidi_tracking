import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_config.dart';

/// Persisted chauffeur session (local-first). Not a security credential.
class ActiveDriverSession {
  const ActiveDriverSession({
    required this.driverId,
    required this.employeeNumber,
    required this.fullName,
    required this.phone,
    required this.loggedInAt,
    required this.updatedAt,
    this.tenantId,
    this.companyId,
    this.companyCode,
    this.assignedVehicleId,
    this.driverPhotoUrl,
    this.companyLogoUrl,
    this.vehiclePhotoUrl,
    this.driverSessionToken,
    this.driverSessionExpiresAtUtc,
    this.linkMethod,
    this.expiresAt,
  });

  final String driverId;
  final String employeeNumber;
  final String fullName;
  final String phone;
  final String loggedInAt;
  final String updatedAt;
  final String? tenantId;
  final String? companyId;
  final String? companyCode;
  final String? assignedVehicleId;
  final String? driverPhotoUrl;
  final String? companyLogoUrl;
  final String? vehiclePhotoUrl;
  final String? driverSessionToken;
  final String? driverSessionExpiresAtUtc;
  final String? linkMethod;
  final String? expiresAt;

  bool get isVerifiedPairingSession =>
      (linkMethod ?? '').trim().toLowerCase() == 'driver_pairing_code';

  bool get isPublicDriverLoginSession =>
      (linkMethod ?? '').trim().toLowerCase() == 'public_driver_login';

  bool get isCompanyAdminDriverViewSession =>
      (linkMethod ?? '').trim().toLowerCase() == 'company_admin_driver_view';

  DateTime? get expiresAtUtc {
    final raw = (expiresAt ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed?.toUtc();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'driverId': driverId,
    'employeeNumber': employeeNumber,
    'fullName': fullName,
    'phone': phone,
    'loggedInAt': loggedInAt,
    'updatedAt': updatedAt,
    if ((tenantId ?? '').trim().isNotEmpty) 'tenantId': tenantId,
    if ((companyId ?? '').trim().isNotEmpty) 'companyId': companyId,
    if ((companyCode ?? '').trim().isNotEmpty) 'companyCode': companyCode,
    if ((assignedVehicleId ?? '').trim().isNotEmpty)
      'assignedVehicleId': assignedVehicleId,
    if ((driverPhotoUrl ?? '').trim().isNotEmpty)
      'driverPhotoUrl': driverPhotoUrl,
    if ((companyLogoUrl ?? '').trim().isNotEmpty)
      'companyLogoUrl': companyLogoUrl,
    if ((vehiclePhotoUrl ?? '').trim().isNotEmpty)
      'vehiclePhotoUrl': vehiclePhotoUrl,
    if ((driverSessionToken ?? '').trim().isNotEmpty)
      'driverSessionToken': driverSessionToken,
    if ((driverSessionExpiresAtUtc ?? '').trim().isNotEmpty)
      'driverSessionExpiresAtUtc': driverSessionExpiresAtUtc,
    if ((linkMethod ?? '').trim().isNotEmpty) 'linkMethod': linkMethod,
    if ((expiresAt ?? '').trim().isNotEmpty) 'expiresAt': expiresAt,
  };

  factory ActiveDriverSession.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    String? readOptional(String key) {
      final value = (json[key] ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    return ActiveDriverSession(
      driverId: read('driverId'),
      employeeNumber: read('employeeNumber'),
      fullName: read('fullName'),
      phone: read('phone'),
      loggedInAt: read('loggedInAt'),
      updatedAt: read('updatedAt'),
      tenantId: readOptional('tenantId'),
      companyId: readOptional('companyId'),
      companyCode: readOptional('companyCode'),
      assignedVehicleId:
          readOptional('assignedVehicleId') ??
          readOptional('assigned_vehicle_id'),
      driverPhotoUrl:
          readOptional('driverPhotoUrl') ??
          readOptional('driver_photo_url') ??
          readOptional('publicPortraitUrl') ??
          readOptional('public_portrait_url') ??
          readOptional('profilePhotoUrl') ??
          readOptional('profile_photo_url'),
      companyLogoUrl:
          readOptional('companyLogoUrl') ??
          readOptional('company_logo_url') ??
          readOptional('logoUrl') ??
          readOptional('logo_url'),
      vehiclePhotoUrl:
          readOptional('vehiclePhotoUrl') ??
          readOptional('vehicle_photo_url') ??
          readOptional('publicPhotoUrl') ??
          readOptional('public_photo_url') ??
          readOptional('photoUrl') ??
          readOptional('photo_url'),
      driverSessionToken:
          readOptional('driverSessionToken') ??
          readOptional('driver_session_token'),
      driverSessionExpiresAtUtc:
          readOptional('driverSessionExpiresAtUtc') ??
          readOptional('driver_session_expires_at_utc') ??
          readOptional('driverSessionExpiresAt') ??
          readOptional('driver_session_expires_at') ??
          readOptional('expires_at'),
      linkMethod: readOptional('linkMethod'),
      expiresAt: readOptional('expiresAt'),
    );
  }
}

/// Mirrors on-disk chauffeur session for API driver_id resolution.
final ValueNotifier<ActiveDriverSession?> activeDriverSessionNotifier =
    ValueNotifier<ActiveDriverSession?>(null);

/// Default tracking id when no chauffeur session (e.g. company preview driver view).
const String kFallbackDriverTrackingId = 'fluxidi_driver_01';

/// Worker `driver_id` payloads: chauffeur session [DriverProfile.id] when present.
String get resolvedDriverTrackingId {
  final id = activeDriverSessionNotifier.value?.driverId.trim();
  if (id != null && id.isNotEmpty) return id;
  return kFallbackDriverTrackingId;
}

String _maskIdForLog(String id) {
  final t = id.trim();
  if (t.length <= 4) return t.isEmpty ? '—' : '…${t.substring(t.length - 1)}';
  return '${t.substring(0, 2)}…${t.substring(t.length - 2)}';
}

bool _isHttpPhotoUrl(String value) {
  final lower = value.trim().toLowerCase();
  return lower.startsWith('https://') || lower.startsWith('http://');
}

bool _isPreferredCanonicalPhotoUrl(String value) {
  final lower = value.trim().toLowerCase();
  return lower.contains('/public/media/') ||
      lower.contains('public-media/') ||
      lower.contains('/public-media/');
}

/// Local JSON: `<documents>/driver_session/active_driver_session_v1.json`
class DriverSessionStore {
  DriverSessionStore._();
  static final DriverSessionStore instance = DriverSessionStore._();

  static const String _fileName = 'active_driver_session_v1.json';

  ActiveDriverSession? _cache;
  String _cacheScopeKey = '';

  String _safeScopeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'default';
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isEmpty) return 'default';
    return sanitized;
  }

  ({String tenantId, String companyId})? _activeScope() {
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) {
      return (tenantId: fromProfile, companyId: fromProfile);
    }
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromSession.isNotEmpty) {
      return (tenantId: fromSession, companyId: fromSession);
    }
    final resolved = resolvedCompanyId.trim();
    if (resolved.isNotEmpty) {
      return (tenantId: resolved, companyId: resolved);
    }
    return null;
  }

  Future<Directory> _stateRootDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}driver_session',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _legacyFile() async {
    final dir = await _stateRootDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}tenant_${_safeScopeSegment(tenantId)}${Platform.pathSeparator}company_${_safeScopeSegment(companyId)}',
    );
    if (!await scopedDir.exists()) await scopedDir.create(recursive: true);
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[DRIVER_SESSION][PATH] tenant=$tenantId company=$companyId path=${file.path}',
    );
    return file;
  }

  Future<File?> _file() async {
    final scope = _activeScope();
    if (scope == null) return null;
    return _scopedFile(tenantId: scope.tenantId, companyId: scope.companyId);
  }

  Future<ActiveDriverSession?> _readSession(File file) async {
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);
    final s = ActiveDriverSession.fromJson(m);
    if (s.driverId.isEmpty) return null;
    return s;
  }

  Future<ActiveDriverSession?> _readLatestScopedSessionFallback() async {
    final root = await _stateRootDir();
    ActiveDriverSession? best;
    DateTime? bestStamp;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('$_fileName')) continue;
      final session = await _readSession(entity);
      if (session == null) continue;
      final stamp =
          DateTime.tryParse(session.updatedAt)?.toUtc() ??
          DateTime.tryParse(session.loggedInAt)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      if (best == null || stamp.isAfter(bestStamp!)) {
        best = session;
        bestStamp = stamp;
      }
    }
    return best;
  }

  /// Load parsed session without validation (may be stale).
  Future<ActiveDriverSession?> load() async {
    try {
      final scope = _activeScope();
      final scopeKey = scope == null
          ? '_unknown_scope_'
          : '${scope.tenantId.trim()}::${scope.companyId.trim()}';
      if (_cache != null && _cacheScopeKey == scopeKey) return _cache;
      _cache = null;
      _cacheScopeKey = scopeKey;

      final scopedFile = await _file();
      if (scopedFile != null) {
        final scoped = await _readSession(scopedFile);
        if (scoped != null) {
          _cache = scoped;
          return scoped;
        }
      }

      final legacyFile = await _legacyFile();
      final legacy = await _readSession(legacyFile);
      if (legacy != null) {
        if (scope != null && scopedFile != null) {
          await scopedFile.writeAsString(jsonEncode(legacy.toJson()));
          debugPrint(
            '[DRIVER_SESSION][MIGRATE_LEGACY] tenant=${scope.tenantId} company=${scope.companyId} driver=${_maskIdForLog(legacy.driverId)} from=${legacyFile.path} to=${scopedFile.path}',
          );
        }
        _cache = legacy;
        return legacy;
      }

      final latestScoped = await _readLatestScopedSessionFallback();
      if (latestScoped != null) {
        debugPrint(
          '[DRIVER_SESSION][LOAD_FALLBACK] driver=${_maskIdForLog(latestScoped.driverId)} reason=latest_scoped_without_active_company',
        );
        _cache = latestScoped;
        return latestScoped;
      }
      return null;
    } catch (e) {
      debugPrint('[DRIVER_LOGIN][WARN] corrupt_session reason=parse_failed');
      return null;
    }
  }

  /// Call after tenant drivers are loaded. Clears stale sessions.
  Future<void> bootstrap(List<DriverProfile> drivers) async {
    final s = await load();
    if (s == null) {
      activeDriverSessionNotifier.value = null;
      return;
    }
    if (_isStillValid(drivers, s)) {
      ActiveDriverSession resolved = s;
      DriverProfile? matched;
      for (final driver in drivers) {
        if (driver.id.trim() == s.driverId.trim()) {
          matched = driver;
          break;
        }
      }
      final canonicalPhoto = (matched?.publicPortraitUrl ?? '').trim();
      final sessionPhoto = (s.driverPhotoUrl ?? '').trim();
      final legacyLooksPreferred =
          sessionPhoto.isNotEmpty &&
          !_isPreferredCanonicalPhotoUrl(sessionPhoto) &&
          canonicalPhoto.isNotEmpty &&
          _isPreferredCanonicalPhotoUrl(canonicalPhoto);
      if (legacyLooksPreferred) {
        debugPrint(
          '[DRIVER_PHOTO_CANONICAL][LEGACY_IGNORED] driver=${_maskIdForLog(s.driverId)} reason=session_prefers_legacy_remote',
        );
      }
      final canonicalCandidate =
          canonicalPhoto.isNotEmpty && _isHttpPhotoUrl(canonicalPhoto)
          ? canonicalPhoto
          : (sessionPhoto.isNotEmpty && _isHttpPhotoUrl(sessionPhoto)
                ? sessionPhoto
                : null);
      final source = canonicalCandidate == null
          ? 'fallback'
          : (canonicalCandidate == canonicalPhoto ? 'backend' : 'session');
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][SOURCE] driver=${_maskIdForLog(s.driverId)} source=$source',
      );
      final shouldPatch =
          canonicalCandidate != null &&
          canonicalCandidate.trim() != sessionPhoto;
      if (shouldPatch) {
        resolved = ActiveDriverSession(
          driverId: s.driverId,
          employeeNumber: s.employeeNumber,
          fullName: s.fullName,
          phone: s.phone,
          loggedInAt: s.loggedInAt,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          tenantId: s.tenantId,
          companyId: s.companyId,
          companyCode: s.companyCode,
          assignedVehicleId: s.assignedVehicleId,
          driverPhotoUrl: canonicalCandidate,
          companyLogoUrl: s.companyLogoUrl,
          vehiclePhotoUrl: s.vehiclePhotoUrl,
          driverSessionToken: s.driverSessionToken,
          driverSessionExpiresAtUtc: s.driverSessionExpiresAtUtc,
          linkMethod: s.linkMethod,
          expiresAt: s.expiresAt,
        );
        final file = await _file() ?? await _legacyFile();
        await file.writeAsString(jsonEncode(resolved.toJson()));
      }
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][SESSION_PATCH] driver=${_maskIdForLog(s.driverId)} updated=$shouldPatch',
      );
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][DONE] driver=${_maskIdForLog(s.driverId)} urlSource=$source',
      );
      _cache = resolved;
      activeDriverSessionNotifier.value = resolved;
      return;
    }
    debugPrint('[DRIVER_LOGIN][SESSION_CLEAR] reason=inactive_or_missing');
    await clear();
  }

  static bool _isStillValid(
    List<DriverProfile> drivers,
    ActiveDriverSession s,
  ) {
    if (s.isVerifiedPairingSession) {
      final expiresAt = s.expiresAtUtc;
      if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
        return false;
      }
      return s.driverId.trim().isNotEmpty && s.employeeNumber.trim().isNotEmpty;
    }
    if (s.isPublicDriverLoginSession) {
      final expiresRaw = (s.driverSessionExpiresAtUtc ?? '').trim();
      if (expiresRaw.isNotEmpty) {
        final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
        if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
          return false;
        }
      }
      return s.driverId.trim().isNotEmpty &&
          (s.driverSessionToken ?? '').trim().isNotEmpty;
    }
    for (final d in drivers) {
      if (d.id != s.driverId) continue;
      if (!d.isActive) return false;
      final de = d.employeeNumber.trim();
      final se = s.employeeNumber.trim();
      if (de.isEmpty || se.isEmpty) return false;
      if (de.toLowerCase() != se.toLowerCase()) return false;
      return true;
    }
    return false;
  }

  ({String? token, String? tokenExpiryUtc, bool matched, bool preserved})
  _resolvePreservedDriverToken({
    required String source,
    required ActiveDriverSession? existing,
    required String newDriverId,
    required String newTenantId,
    required String newCompanyId,
  }) {
    final existingToken = (existing?.driverSessionToken ?? '').trim();
    final existingDriverId = (existing?.driverId ?? '').trim();
    final existingTenantId = (existing?.tenantId ?? '').trim();
    final existingCompanyId = (existing?.companyId ?? '').trim();
    final matched =
        existing != null &&
        existingDriverId.isNotEmpty &&
        existingTenantId.isNotEmpty &&
        existingCompanyId.isNotEmpty &&
        existingDriverId == newDriverId &&
        existingTenantId == newTenantId &&
        existingCompanyId == newCompanyId;
    if (!matched) {
      debugPrint(
        '[DRIVER_SESSION][TOKEN_PRESERVE] source=$source matched=false preserved=false',
      );
      debugPrint(
        '[DRIVER_SESSION][TOKEN_DROP] source=$source reason=identity_mismatch',
      );
      return (
        token: null,
        tokenExpiryUtc: null,
        matched: false,
        preserved: false,
      );
    }
    if (existingToken.isEmpty) {
      debugPrint(
        '[DRIVER_SESSION][TOKEN_PRESERVE] source=$source matched=true preserved=false',
      );
      debugPrint(
        '[DRIVER_SESSION][TOKEN_DROP] source=$source reason=no_existing_token',
      );
      return (
        token: null,
        tokenExpiryUtc: null,
        matched: true,
        preserved: false,
      );
    }
    debugPrint(
      '[DRIVER_SESSION][TOKEN_PRESERVE] source=$source matched=true preserved=true',
    );
    final existingTokenExpiry = (existing.driverSessionExpiresAtUtc ?? '')
        .trim();
    return (
      token: existingToken,
      tokenExpiryUtc: existingTokenExpiry.isEmpty ? null : existingTokenExpiry,
      matched: true,
      preserved: true,
    );
  }

  Future<void> saveFromDriverProfile(
    DriverProfile driver, {
    ActiveDriverSession? previous,
    String? linkMethodOverride,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final activeScope = _activeScope();
    final effectivePrevious = previous ?? await load();
    final preservedToken = _resolvePreservedDriverToken(
      source: 'saveFromDriverProfile',
      existing: effectivePrevious,
      newDriverId: driver.id.trim(),
      newTenantId: (activeScope?.tenantId ?? '').trim(),
      newCompanyId: (activeScope?.companyId ?? '').trim(),
    );
    final session = ActiveDriverSession(
      driverId: driver.id.trim(),
      employeeNumber: driver.employeeNumber.trim(),
      fullName: driver.fullName,
      phone: driver.phone,
      loggedInAt: previous?.loggedInAt ?? now,
      updatedAt: now,
      tenantId: activeScope?.tenantId,
      companyId: activeScope?.companyId,
      driverSessionToken: preservedToken.token,
      driverSessionExpiresAtUtc: preservedToken.tokenExpiryUtc,
      linkMethod: (linkMethodOverride ?? '').trim().isEmpty
          ? null
          : linkMethodOverride!.trim(),
    );
    try {
      final file = await _file();
      if (file == null) {
        debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=missing_scope');
        return;
      }
      await file.writeAsString(jsonEncode(session.toJson()));
      _cache = session;
      final scope = _activeScope();
      if (scope != null) {
        _cacheScopeKey = '${scope.tenantId.trim()}::${scope.companyId.trim()}';
        debugPrint(
          '[DRIVER_SESSION][SAVE] tenant=${scope.tenantId} company=${scope.companyId} driver=${_maskIdForLog(session.driverId)} path=${file.path}',
        );
      }
      activeDriverSessionNotifier.value = session;
    } catch (e) {
      debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=$e');
    }
  }

  Future<void> saveVerifiedDriverPairingSession({
    required String tenantId,
    required String companyId,
    required String companyCode,
    required String driverId,
    required String driverName,
    required String employeeNumber,
    String? assignedVehicleId,
    String? driverSessionToken,
    DateTime? driverSessionExpiresAtUtc,
    DateTime? issuedAt,
    DateTime? expiresAt,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    final normalizedCompanyCode = companyCode.trim().toUpperCase();
    final normalizedDriverId = driverId.trim();
    final normalizedDriverName = driverName.trim();
    final normalizedEmployeeNumber = employeeNumber.trim();
    final normalizedAssignedVehicleId = (assignedVehicleId ?? '').trim();
    final normalizedIncomingToken = (driverSessionToken ?? '').trim();
    final incomingTokenExpiryUtc = driverSessionExpiresAtUtc
        ?.toUtc()
        .toIso8601String();
    if (normalizedTenantId.isEmpty ||
        normalizedCompanyId.isEmpty ||
        normalizedCompanyCode.isEmpty ||
        normalizedDriverId.isEmpty ||
        normalizedEmployeeNumber.isEmpty) {
      debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=missing_required');
      return;
    }
    final now = DateTime.now().toUtc();
    final scopedFile = await _scopedFile(
      tenantId: normalizedTenantId,
      companyId: normalizedCompanyId,
    );
    final existingScopedSession = await _readSession(scopedFile);
    final preservedToken = _resolvePreservedDriverToken(
      source: 'saveVerifiedDriverPairingSession',
      existing: existingScopedSession,
      newDriverId: normalizedDriverId,
      newTenantId: normalizedTenantId,
      newCompanyId: normalizedCompanyId,
    );
    final tokenFromPairing = normalizedIncomingToken.isNotEmpty;
    debugPrint(
      '[DRIVER_SESSION][TOKEN_FROM_PAIRING] has_token=$tokenFromPairing',
    );
    final resolvedToken = tokenFromPairing
        ? normalizedIncomingToken
        : preservedToken.token;
    final resolvedTokenExpiryUtc = tokenFromPairing
        ? incomingTokenExpiryUtc
        : preservedToken.tokenExpiryUtc;
    final session = ActiveDriverSession(
      driverId: normalizedDriverId,
      employeeNumber: normalizedEmployeeNumber,
      fullName: normalizedDriverName.isEmpty
          ? normalizedEmployeeNumber
          : normalizedDriverName,
      phone: '',
      loggedInAt: (issuedAt ?? now).toUtc().toIso8601String(),
      updatedAt: now.toIso8601String(),
      tenantId: normalizedTenantId,
      companyId: normalizedCompanyId,
      companyCode: normalizedCompanyCode,
      assignedVehicleId: normalizedAssignedVehicleId.isEmpty
          ? null
          : normalizedAssignedVehicleId,
      driverSessionToken: resolvedToken,
      driverSessionExpiresAtUtc: resolvedTokenExpiryUtc,
      linkMethod: 'driver_pairing_code',
      expiresAt: expiresAt?.toUtc().toIso8601String(),
    );
    try {
      await scopedFile.writeAsString(jsonEncode(session.toJson()));
      _cache = session;
      _cacheScopeKey = '$normalizedTenantId::$normalizedCompanyId';
      activeDriverSessionNotifier.value = session;
      debugPrint(
        '[DRIVER_SESSION][SAVE_VERIFIED] tenant=$normalizedTenantId company=$normalizedCompanyId driver=${_maskIdForLog(session.driverId)} method=driver_pairing_code path=${scopedFile.path}',
      );
    } catch (e) {
      debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=$e');
    }
  }

  Future<void> saveBackendDriverLoginSession({
    required String tenantId,
    required String companyId,
    required String driverId,
    required String driverName,
    required String companyDisplayName,
    String? assignedVehicleId,
    String? driverPhotoUrl,
    String? companyLogoUrl,
    String? vehiclePhotoUrl,
    String? driverSessionToken,
    int? expiresInSeconds,
    DateTime? expiresAtUtc,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    final normalizedDriverId = driverId.trim();
    final normalizedDriverName = driverName.trim();
    final normalizedCompanyDisplayName = companyDisplayName.trim();
    final normalizedAssignedVehicleId = (assignedVehicleId ?? '').trim();
    final normalizedDriverPhotoUrl = (driverPhotoUrl ?? '').trim();
    final normalizedCompanyLogoUrl = (companyLogoUrl ?? '').trim();
    final normalizedVehiclePhotoUrl = (vehiclePhotoUrl ?? '').trim();
    final normalizedDriverSessionToken = (driverSessionToken ?? '').trim();
    if (normalizedTenantId.isEmpty ||
        normalizedCompanyId.isEmpty ||
        normalizedDriverId.isEmpty) {
      debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=missing_required');
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    String? resolvedTokenExpiryUtc;
    if (expiresAtUtc != null) {
      resolvedTokenExpiryUtc = expiresAtUtc.toUtc().toIso8601String();
    } else if ((expiresInSeconds ?? 0) > 0) {
      resolvedTokenExpiryUtc = DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresInSeconds!))
          .toIso8601String();
    }
    final fallbackName = normalizedCompanyDisplayName.isEmpty
        ? normalizedDriverId
        : '$normalizedCompanyDisplayName chauffeur';
    final session = ActiveDriverSession(
      driverId: normalizedDriverId,
      employeeNumber: normalizedDriverId,
      fullName: normalizedDriverName.isEmpty
          ? fallbackName
          : normalizedDriverName,
      phone: '',
      loggedInAt: now,
      updatedAt: now,
      tenantId: normalizedTenantId,
      companyId: normalizedCompanyId,
      assignedVehicleId: normalizedAssignedVehicleId.isEmpty
          ? null
          : normalizedAssignedVehicleId,
      driverPhotoUrl: normalizedDriverPhotoUrl.isEmpty
          ? null
          : normalizedDriverPhotoUrl,
      companyLogoUrl: normalizedCompanyLogoUrl.isEmpty
          ? null
          : normalizedCompanyLogoUrl,
      vehiclePhotoUrl: normalizedVehiclePhotoUrl.isEmpty
          ? null
          : normalizedVehiclePhotoUrl,
      driverSessionToken: normalizedDriverSessionToken.isEmpty
          ? null
          : normalizedDriverSessionToken,
      driverSessionExpiresAtUtc: resolvedTokenExpiryUtc,
      linkMethod: 'public_driver_login',
    );
    try {
      final file = await _scopedFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      await file.writeAsString(jsonEncode(session.toJson()));
      _cache = session;
      _cacheScopeKey = '$normalizedTenantId::$normalizedCompanyId';
      activeDriverSessionNotifier.value = session;
      debugPrint(
        '[DRIVER_SESSION][SAVE_BACKEND] tenant=$normalizedTenantId company=$normalizedCompanyId driver=${_maskIdForLog(session.driverId)} method=public_driver_login path=${file.path}',
      );
    } catch (e) {
      debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=$e');
    }
  }

  Future<void> clear() async {
    try {
      final scope = _activeScope();
      if (scope != null) {
        final file = await _scopedFile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        if (await file.exists()) await file.delete();
        debugPrint(
          '[DRIVER_SESSION][CLEAR] tenant=${scope.tenantId} company=${scope.companyId} path=${file.path}',
        );
      } else {
        debugPrint(
          '[DRIVER_SESSION][CLEAR] tenant=unknown company=unknown scoped_file_skipped=true',
        );
      }
    } catch (_) {}
    _cache = null;
    _cacheScopeKey = '';
    activeDriverSessionNotifier.value = null;
  }

  DriverProfile? findDriverByEnteredId(
    List<DriverProfile> drivers,
    String entered,
  ) {
    final n = entered.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final d in drivers) {
      final en = d.employeeNumber.trim();
      if (en.isEmpty) continue;
      if (en.toLowerCase() == n && d.isActive) return d;
    }
    return null;
  }

  void logOk(String driverId) {
    debugPrint('[DRIVER_LOGIN][OK] driverId=${_maskIdForLog(driverId)}');
  }
}
