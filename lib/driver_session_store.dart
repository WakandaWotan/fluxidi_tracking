import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_config.dart';

const String kCompanyAdminDriverViewLinkMethod = 'company_admin_driver_view';
const String kStandaloneDriverLinkMethod = 'standalone_driver';

/// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3)
///
/// `link_method` value for a driver session that was minted for a company
/// owner via `POST /driver/session/mint-for-operator` on the booking worker.
/// Mirrors the server-side record shape (see [Commit 1] worker route). Kept
/// as a top-level constant so both the API helper and the session store can
/// classify sessions consistently without duplicating the string literal.
const String kOperatorMintDriverLinkMethod = 'operator_mint';

/// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3)
///
/// Machine-readable session provenance derived from
/// [ActiveDriverSession.linkMethod]. Callers should prefer this getter over
/// raw string comparisons on `linkMethod`.
///
///   - [standaloneLogin]         driver authenticated with their own
///                                credentials (public login or pairing).
///   - [companyAdminDriverView]  legacy business-preview session without
///                                a real bearer (kept for backwards
///                                compatibility only).
///   - [operatorMint]            short-lived, company-owner-minted driver
///                                session; scope is server-derived from the
///                                minting company session (never trusted
///                                from client input).
///   - [unknown]                  session has no linkMethod or an
///                                unrecognised value; downstream code should
///                                treat this as untrusted.
enum SessionOrigin {
  standaloneLogin,
  companyAdminDriverView,
  operatorMint,
  unknown,
}

/// Business-scoped driver cockpit preview (never used for standalone restore).
class BusinessDriverPreviewRecord {
  const BusinessDriverPreviewRecord({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    this.vehicleId,
    this.driverName,
    this.driverPhotoUrl,
    this.mode = kCompanyAdminDriverViewLinkMethod,
    this.updatedAt = '',
  });

  final String tenantId;
  final String companyId;
  final String driverId;
  final String? vehicleId;
  final String? driverName;
  final String? driverPhotoUrl;
  final String mode;
  final String updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 2,
    'tenantId': tenantId,
    'companyId': companyId,
    'previewDriverId': driverId,
    'driverId': driverId,
    if ((vehicleId ?? '').trim().isNotEmpty) 'vehicleId': vehicleId,
    if ((driverName ?? '').trim().isNotEmpty) 'driverName': driverName,
    if ((driverPhotoUrl ?? '').trim().isNotEmpty)
      'driverPhotoUrl': driverPhotoUrl,
    'mode': mode,
    'updatedAt': updatedAt.isEmpty
        ? DateTime.now().toUtc().toIso8601String()
        : updatedAt,
  };

  factory BusinessDriverPreviewRecord.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    String? readOptional(String key) {
      final value = read(key);
      return value.isEmpty ? null : value;
    }

    return BusinessDriverPreviewRecord(
      tenantId: read('tenantId'),
      companyId: read('companyId'),
      driverId: read('previewDriverId').isNotEmpty
          ? read('previewDriverId')
          : read('driverId'),
      vehicleId: readOptional('vehicleId'),
      driverName: readOptional('driverName'),
      driverPhotoUrl:
          readOptional('driverPhotoUrl') ?? readOptional('publicPortraitUrl'),
      mode: read('mode').isEmpty
          ? kCompanyAdminDriverViewLinkMethod
          : read('mode'),
      updatedAt: read('updatedAt'),
    );
  }
}

/// Global pointer to the last real standalone driver session scope (no token).
class StandaloneDriverScopePointer {
  const StandaloneDriverScopePointer({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.linkMethod,
    required this.updatedAt,
  });

  final String tenantId;
  final String companyId;
  final String driverId;
  final String linkMethod;
  final String updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'tenantId': tenantId,
    'companyId': companyId,
    'driverId': driverId,
    'linkMethod': linkMethod,
    'updatedAt': updatedAt,
  };

  factory StandaloneDriverScopePointer.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    return StandaloneDriverScopePointer(
      tenantId: read('tenantId'),
      companyId: read('companyId'),
      driverId: read('driverId'),
      linkMethod: read('linkMethod'),
      updatedAt: read('updatedAt'),
    );
  }
}

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

  bool get isStandaloneLoginSession =>
      isVerifiedPairingSession ||
      isPublicDriverLoginSession ||
      (linkMethod ?? '').trim().toLowerCase() == 'standalone_driver';

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3):
  /// true when this session was minted for a company owner via
  /// `/driver/session/mint-for-operator`.
  bool get isOperatorMintedSession =>
      (linkMethod ?? '').trim().toLowerCase() ==
      kOperatorMintDriverLinkMethod;

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3):
  /// canonical provenance for logs, diagnostics and access-control gating.
  /// Prefer this over ad-hoc linkMethod string checks.
  SessionOrigin get sessionOrigin {
    if (isOperatorMintedSession) return SessionOrigin.operatorMint;
    if (isCompanyAdminDriverViewSession) {
      return SessionOrigin.companyAdminDriverView;
    }
    if (isStandaloneLoginSession) return SessionOrigin.standaloneLogin;
    return SessionOrigin.unknown;
  }

  String get sessionMode {
    switch (sessionOrigin) {
      case SessionOrigin.operatorMint:
        return 'business_driver_view_minted';
      case SessionOrigin.companyAdminDriverView:
        return 'business_driver_view';
      case SessionOrigin.standaloneLogin:
      case SessionOrigin.unknown:
        return 'standalone_driver';
    }
  }

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
      tenantId: readOptional('tenantId') ?? readOptional('tenant_id'),
      companyId: readOptional('companyId') ?? readOptional('company_id'),
      companyCode: readOptional('companyCode') ?? readOptional('company_code'),
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

String _shortErrForDriverLog(Object error) {
  final raw = error.toString();
  final oneLine = raw.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
  if (oneLine.length <= 160) return oneLine;
  return '${oneLine.substring(0, 157)}...';
}

bool _isHttpPhotoUrl(String value) {
  final lower = value.trim().toLowerCase();
  return lower.startsWith('https://') || lower.startsWith('http://');
}

String? _resolvePersistableDriverPhotoUrl(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final resolved = resolvePublicHttpsMediaUrl(text);
  if (resolved.isNotEmpty) return resolved;
  if (_isHttpPhotoUrl(text)) return text;
  final lower = text.toLowerCase();
  if (lower.startsWith('/public/media/') || lower.startsWith('public-media/')) {
    return text;
  }
  return null;
}

const List<String> _driverPhotoPayloadKeys = <String>[
  'public_portrait_url',
  'publicPortraitUrl',
  'driver_photo_url',
  'driverPhotoUrl',
  'photo_url',
  'photoUrl',
  'avatar_url',
  'avatarUrl',
  'profile_photo_url',
  'profilePhotoUrl',
  'portrait_url',
  'portraitUrl',
  'image_url',
  'imageUrl',
];

String? _readDriverPhotoUrlFromMap(Map<String, dynamic> map) {
  for (final key in _driverPhotoPayloadKeys) {
    final value = (map[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? _extractDriverPhotoFromPayloadMaps({
  required Map<String, dynamic> body,
  Map<String, dynamic>? driverMap,
  Map<String, dynamic>? profileMap,
}) {
  if (driverMap != null) {
    final fromDriver = _readDriverPhotoUrlFromMap(driverMap);
    if (fromDriver != null) return fromDriver;
  }
  if (profileMap != null) {
    final fromProfile = _readDriverPhotoUrlFromMap(profileMap);
    if (fromProfile != null) return fromProfile;
  }
  return _readDriverPhotoUrlFromMap(body);
}

DriverProfile? _findScopedLocalDriver(
  List<DriverProfile> drivers,
  ActiveDriverSession session,
) {
  final sessionCompany = (session.companyId ?? '').trim();
  final sessionDriverId = session.driverId.trim();
  if (sessionDriverId.isEmpty) return null;
  for (final driver in drivers) {
    if (driver.id.trim() != sessionDriverId) continue;
    final driverCompany = (driver.companyId ?? '').trim();
    if (sessionCompany.isNotEmpty &&
        driverCompany.isNotEmpty &&
        driverCompany != sessionCompany) {
      continue;
    }
    return driver;
  }
  for (final driver in driversNotifier.value) {
    if (driver.id.trim() != sessionDriverId) continue;
    final driverCompany = (driver.companyId ?? '').trim();
    if (sessionCompany.isNotEmpty &&
        driverCompany.isNotEmpty &&
        driverCompany != sessionCompany) {
      continue;
    }
    return driver;
  }
  return null;
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
  static const String _businessPreviewFileName =
      'business_driver_preview_v1.json';
  static const String _standalonePointerFileName =
      'last_standalone_driver_scope_v1.json';

  ActiveDriverSession? _cache;
  String _cacheScopeKey = '';
  String? _standaloneOperationalBlockReason;

  String? get standaloneOperationalBlockReason =>
      _standaloneOperationalBlockReason;

  void clearStandaloneOperationalBlockReason() {
    _standaloneOperationalBlockReason = null;
  }

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

  Future<File> _businessPreviewFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _stateRootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}tenant_${_safeScopeSegment(tenantId)}${Platform.pathSeparator}company_${_safeScopeSegment(companyId)}',
    );
    if (!await scopedDir.exists()) await scopedDir.create(recursive: true);
    return File(
      '${scopedDir.path}${Platform.pathSeparator}$_businessPreviewFileName',
    );
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

  Future<File> _standalonePointerFile() async {
    final dir = await _stateRootDir();
    return File(
      '${dir.path}${Platform.pathSeparator}$_standalonePointerFileName',
    );
  }

  Future<void> saveStandaloneScopePointer(ActiveDriverSession session) async {
    if (!_isRestorableStandaloneSession(session)) return;
    final tenant = (session.tenantId ?? '').trim();
    final company = (session.companyId ?? '').trim();
    final driver = session.driverId.trim();
    final link = (session.linkMethod ?? kStandaloneDriverLinkMethod).trim();
    if (tenant.isEmpty || company.isEmpty || driver.isEmpty) return;
    final pointer = StandaloneDriverScopePointer(
      tenantId: tenant,
      companyId: company,
      driverId: driver,
      linkMethod: link,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    try {
      final file = await _standalonePointerFile();
      await file.writeAsString(jsonEncode(pointer.toJson()));
      debugPrint(
        '[DRIVER_SESSION][STANDALONE_POINTER_SAVE] tenant=${_maskIdForLog(tenant)} company=${_maskIdForLog(company)} driver=${_maskIdForLog(driver)} method=$link',
      );
    } catch (e) {
      debugPrint(
        '[DRIVER_LOGIN][WARN] standalone_pointer_save_failed reason=$e',
      );
    }
  }

  Future<StandaloneDriverScopePointer?> loadStandaloneScopePointer() async {
    try {
      final file = await _standalonePointerFile();
      if (!await file.exists()) {
        debugPrint(
          '[DRIVER_SESSION][POINTER_MISSING] reason=file_not_found path=${file.path}',
        );
        return null;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        debugPrint('[DRIVER_SESSION][POINTER_MISSING] reason=empty');
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        debugPrint('[DRIVER_SESSION][POINTER_MISSING] reason=invalid_json');
        return null;
      }
      final pointer = StandaloneDriverScopePointer.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (pointer.tenantId.isEmpty ||
          pointer.companyId.isEmpty ||
          pointer.driverId.isEmpty) {
        debugPrint(
          '[DRIVER_SESSION][POINTER_MISSING] reason=incomplete tenant=${_maskIdForLog(pointer.tenantId)} company=${_maskIdForLog(pointer.companyId)} driver=${_maskIdForLog(pointer.driverId)}',
        );
        return null;
      }
      return pointer;
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][POINTER_LOAD_FAIL] reason=storage_read_exception err=${_shortErrForDriverLog(e)}',
      );
      return null;
    }
  }

  Future<void> clearStandaloneScopePointer() async {
    try {
      final file = await _standalonePointerFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][POINTER_CLEAR_FAIL] err=${_shortErrForDriverLog(e)}',
      );
    }
  }

  Future<ActiveDriverSession?> _loadSessionAtScope({
    required String tenantId,
    required String companyId,
  }) async {
    final file = await _scopedFile(tenantId: tenantId, companyId: companyId);
    return _readSession(file);
  }

  Future<void> _writeSessionAtScope(ActiveDriverSession session) async {
    final tenant = (session.tenantId ?? '').trim();
    final company = (session.companyId ?? '').trim();
    if (tenant.isEmpty || company.isEmpty) return;
    final file = await _scopedFile(tenantId: tenant, companyId: company);
    await file.writeAsString(jsonEncode(session.toJson()));
    _cache = session;
    _cacheScopeKey = '$tenant::$company';
  }

  void _logScopeValidate({
    required String expectedTenant,
    required String expectedCompany,
    required String sessionTenant,
    required String sessionCompany,
    required String pointerTenant,
    required String pointerCompany,
    required String fileScopeTenant,
    required String fileScopeCompany,
    required String source,
    required String result,
  }) {
    debugPrint(
      '[DRIVER_SESSION][SCOPE_VALIDATE] expected_tenant=${_maskIdForLog(expectedTenant)} expected_company=${_maskIdForLog(expectedCompany)} session_tenant=${_maskIdForLog(sessionTenant)} session_company=${_maskIdForLog(sessionCompany)} pointer_tenant=${_maskIdForLog(pointerTenant)} pointer_company=${_maskIdForLog(pointerCompany)} file_tenant=${_maskIdForLog(fileScopeTenant)} file_company=${_maskIdForLog(fileScopeCompany)} source=$source result=$result',
    );
  }

  bool _fileScopeMatchesRestoreScope({
    required String fileScopeTenant,
    required String fileScopeCompany,
    required String expectedTenant,
    required String expectedCompany,
  }) {
    return fileScopeTenant.trim() == expectedTenant.trim() &&
        fileScopeCompany.trim() == expectedCompany.trim();
  }

  bool _isTrueStandaloneScopeSecurityMismatch({
    required String fileScopeTenant,
    required String fileScopeCompany,
    required String expectedTenant,
    required String expectedCompany,
    StandaloneDriverScopePointer? pointer,
  }) {
    if (!_fileScopeMatchesRestoreScope(
      fileScopeTenant: fileScopeTenant,
      fileScopeCompany: fileScopeCompany,
      expectedTenant: expectedTenant,
      expectedCompany: expectedCompany,
    )) {
      return true;
    }
    if (pointer == null) return false;
    return pointer.tenantId.trim() != fileScopeTenant.trim() ||
        pointer.companyId.trim() != fileScopeCompany.trim();
  }

  ActiveDriverSession _copySessionWithScope(
    ActiveDriverSession session, {
    required String tenantId,
    required String companyId,
  }) {
    return ActiveDriverSession(
      driverId: session.driverId,
      employeeNumber: session.employeeNumber,
      fullName: session.fullName,
      phone: session.phone,
      loggedInAt: session.loggedInAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      tenantId: tenantId,
      companyId: companyId,
      companyCode: session.companyCode,
      assignedVehicleId: session.assignedVehicleId,
      driverPhotoUrl: session.driverPhotoUrl,
      companyLogoUrl: session.companyLogoUrl,
      vehiclePhotoUrl: session.vehiclePhotoUrl,
      driverSessionToken: session.driverSessionToken,
      driverSessionExpiresAtUtc: session.driverSessionExpiresAtUtc,
      linkMethod: session.linkMethod,
      expiresAt: session.expiresAt,
    );
  }

  Future<ActiveDriverSession?> _resolveStandaloneSessionForRestore({
    required ActiveDriverSession session,
    required String fileScopeTenant,
    required String fileScopeCompany,
    required String expectedTenant,
    required String expectedCompany,
    required String source,
    StandaloneDriverScopePointer? pointer,
  }) async {
    if (!_isRestorableStandaloneSession(session)) return null;

    final sessionTenant = (session.tenantId ?? '').trim();
    final sessionCompany = (session.companyId ?? '').trim();
    final pointerTenant = (pointer?.tenantId ?? '').trim();
    final pointerCompany = (pointer?.companyId ?? '').trim();

    if (_isTrueStandaloneScopeSecurityMismatch(
      fileScopeTenant: fileScopeTenant,
      fileScopeCompany: fileScopeCompany,
      expectedTenant: expectedTenant,
      expectedCompany: expectedCompany,
      pointer: pointer,
    )) {
      _logScopeValidate(
        expectedTenant: expectedTenant,
        expectedCompany: expectedCompany,
        sessionTenant: sessionTenant,
        sessionCompany: sessionCompany,
        pointerTenant: pointerTenant,
        pointerCompany: pointerCompany,
        fileScopeTenant: fileScopeTenant,
        fileScopeCompany: fileScopeCompany,
        source: source,
        result: 'security_mismatch',
      );
      return null;
    }

    if (sessionTenant == expectedTenant.trim() &&
        sessionCompany == expectedCompany.trim()) {
      _logScopeValidate(
        expectedTenant: expectedTenant,
        expectedCompany: expectedCompany,
        sessionTenant: sessionTenant,
        sessionCompany: sessionCompany,
        pointerTenant: pointerTenant,
        pointerCompany: pointerCompany,
        fileScopeTenant: fileScopeTenant,
        fileScopeCompany: fileScopeCompany,
        source: source,
        result: 'ok',
      );
      return session;
    }

    final repaired = _copySessionWithScope(
      session,
      tenantId: expectedTenant.trim(),
      companyId: expectedCompany.trim(),
    );
    await _writeSessionAtScope(repaired);
    if (pointer != null &&
        (pointerTenant != expectedTenant.trim() ||
            pointerCompany != expectedCompany.trim())) {
      await saveStandaloneScopePointer(repaired);
    }
    _logScopeValidate(
      expectedTenant: expectedTenant,
      expectedCompany: expectedCompany,
      sessionTenant: sessionTenant,
      sessionCompany: sessionCompany,
      pointerTenant: pointerTenant,
      pointerCompany: pointerCompany,
      fileScopeTenant: fileScopeTenant,
      fileScopeCompany: fileScopeCompany,
      source: source,
      result: 'repair',
    );
    debugPrint(
      '[DRIVER_SESSION][SCOPE_REPAIR] driver=${_maskIdForLog(repaired.driverId)} ok=true source=$source',
    );
    return repaired;
  }

  bool _validateStandalonePointerRestore(
    StandaloneDriverScopePointer pointer,
    ActiveDriverSession session,
  ) {
    if (!_isRestorableStandaloneSession(session)) return false;
    if (pointer.driverId.trim() != session.driverId.trim()) return false;
    final pointerLink = pointer.linkMethod.trim().toLowerCase();
    final sessionLink = (session.linkMethod ?? '').trim().toLowerCase();
    if (pointerLink.isNotEmpty &&
        sessionLink.isNotEmpty &&
        pointerLink != sessionLink) {
      return false;
    }
    if (session.isPublicDriverLoginSession) {
      if ((session.driverSessionToken ?? '').trim().isEmpty) return false;
    }
    return true;
  }

  String _firstNonEmptyScopeField(
    Map<String, dynamic>? payload,
    List<String> keys,
  ) {
    if (payload == null) return '';
    for (final key in keys) {
      final value = (payload[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Preserve previous [ActiveDriverSession.driverPhotoUrl] when [incomingPhoto]
  /// is empty for the same [driverId]. Never preserves across different drivers.
  String? _preservePhotoForSameDriver({
    required String? incomingPhoto,
    required ActiveDriverSession? existing,
    required String newDriverId,
    required String saveSource,
  }) {
    final incoming = (incomingPhoto ?? '').trim();
    if (incoming.isNotEmpty) return incoming;
    if (existing == null) return null;
    if (existing.driverId.trim() != newDriverId.trim()) return null;
    final existingPhoto = (existing.driverPhotoUrl ?? '').trim();
    if (existingPhoto.isEmpty) return null;
    debugPrint(
      '[DRIVER_SESSION][PHOTO_PRESERVE] driver=${_maskIdForLog(newDriverId)} source=existing_session save=$saveSource',
    );
    return existingPhoto;
  }

  Future<void> _clearSessionAtScope({
    required String tenantId,
    required String companyId,
  }) async {
    try {
      final file = await _scopedFile(tenantId: tenantId, companyId: companyId);
      if (await file.exists()) await file.delete();
      if (_cacheScopeKey == '$tenantId::$companyId') {
        _cache = null;
        _cacheScopeKey = '';
      }
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][PERSIST_FAIL] op=clear_session_at_scope tenant=${_maskIdForLog(tenantId)} company=${_maskIdForLog(companyId)} err=${_shortErrForDriverLog(e)}',
      );
    }
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

      if (scope == null) {
        debugPrint(
          '[DRIVER_SESSION][LOAD][SKIP_LATEST_SCOPED_NO_ACTIVE_SCOPE]',
        );
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('[DRIVER_LOGIN][WARN] corrupt_session reason=parse_failed');
      return null;
    }
  }

  bool _sessionScopeMatchesActive(ActiveDriverSession session) {
    final sessionTenant = (session.tenantId ?? '').trim();
    final sessionCompany = (session.companyId ?? '').trim();
    final active = _activeScope();
    if (active == null) {
      return sessionTenant.isEmpty && sessionCompany.isEmpty;
    }
    if (sessionTenant.isEmpty || sessionCompany.isEmpty) {
      return false;
    }
    return sessionTenant == active.tenantId.trim() &&
        sessionCompany == active.companyId.trim();
  }

  bool _isRestorableStandaloneSession(ActiveDriverSession session) {
    if (session.isCompanyAdminDriverViewSession) return false;
    if (session.isStandaloneLoginSession) return true;
    final link = (session.linkMethod ?? '').trim().toLowerCase();
    if (link.isNotEmpty && link != 'standalone_driver') return false;
    return (session.tenantId ?? '').trim().isNotEmpty &&
        (session.companyId ?? '').trim().isNotEmpty &&
        session.driverId.trim().isNotEmpty;
  }

  void prepareBusinessDriverCockpitEntry() {
    debugPrint(
      '[DRIVER_SESSION][BUSINESS_VIEW_NO_STANDALONE_PERSIST] action=prepare_entry',
    );
    final current = activeDriverSessionNotifier.value;
    if (current == null) return;
    if (current.isCompanyAdminDriverViewSession) return;
    debugPrint(
      '[DRIVER_SESSION][BUSINESS_VIEW_NO_STANDALONE_PERSIST] action=detach_standalone_notifier driver=${_maskIdForLog(current.driverId)}',
    );
    activeDriverSessionNotifier.value = null;
  }

  void prepareStandaloneDriverEntry() {
    final current = activeDriverSessionNotifier.value;
    if (current == null) return;
    if (!current.isCompanyAdminDriverViewSession) return;
    debugPrint(
      '[DRIVER_SESSION][BUSINESS_VIEW_NO_STANDALONE_PERSIST] action=detach_business_notifier driver=${_maskIdForLog(current.driverId)}',
    );
    activeDriverSessionNotifier.value = null;
  }

  void setBusinessDriverViewSessionInMemory(ActiveDriverSession session) {
    debugPrint(
      '[DRIVER_SESSION][BUSINESS_VIEW_NO_STANDALONE_PERSIST] action=memory_only driver=${_maskIdForLog(session.driverId)} tenant=${_maskIdForLog(session.tenantId ?? '')} company=${_maskIdForLog(session.companyId ?? '')}',
    );
    _cache = null;
    _cacheScopeKey = '';
    activeDriverSessionNotifier.value = session;
  }

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3)
  ///
  /// Hydrate the in-memory driver session with an operator-minted bearer.
  /// This method deliberately never writes to disk: the minted token has a
  /// short TTL (1h by default) and MUST NOT survive an app restart. If the
  /// business preview is re-entered later, a fresh mint request is issued.
  ///
  /// The bearer value itself is never logged; only the driver id, tenant,
  /// company, and the (stable) `origin=operator_mint` tag appear in the
  /// diagnostic line.
  void setOperatorMintedDriverSessionInMemory(ActiveDriverSession session) {
    assert(
      session.isOperatorMintedSession,
      'setOperatorMintedDriverSessionInMemory requires linkMethod=$kOperatorMintDriverLinkMethod',
    );
    debugPrint(
      '[DRIVER_SESSION][OPERATOR_MINT_HYDRATE] action=memory_only origin=operator_mint driver=${_maskIdForLog(session.driverId)} tenant=${_maskIdForLog(session.tenantId ?? '')} company=${_maskIdForLog(session.companyId ?? '')}',
    );
    _cache = null;
    _cacheScopeKey = '';
    activeDriverSessionNotifier.value = session;
  }

  Future<void> clearStandaloneSessionIfScopeMismatch({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenant = tenantId.trim();
    final normalizedCompany = companyId.trim();
    if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) return;
    final scopedFile = await _scopedFile(
      tenantId: normalizedTenant,
      companyId: normalizedCompany,
    );
    final scopedSession = await _readSession(scopedFile);
    if (scopedSession != null &&
        scopedSession.isCompanyAdminDriverViewSession) {
      try {
        if (await scopedFile.exists()) await scopedFile.delete();
      } catch (e) {
        debugPrint(
          '[DRIVER_SESSION][PERSIST_FAIL] op=clear_business_view tenant=${_maskIdForLog(normalizedTenant)} company=${_maskIdForLog(normalizedCompany)} err=${_shortErrForDriverLog(e)}',
        );
      }
      debugPrint(
        '[DRIVER_SESSION][CLEAR_STALE] reason=business_view_on_company_entry tenant=${_maskIdForLog(normalizedTenant)} company=${_maskIdForLog(normalizedCompany)}',
      );
      if (_cacheScopeKey == '$normalizedTenant::$normalizedCompany') {
        _cache = null;
        _cacheScopeKey = '';
      }
    }
    final current = activeDriverSessionNotifier.value;
    if (current == null) return;
    final currentTenant = (current.tenantId ?? '').trim();
    final currentCompany = (current.companyId ?? '').trim();
    if (current.isCompanyAdminDriverViewSession ||
        (currentTenant.isNotEmpty &&
            currentCompany.isNotEmpty &&
            (currentTenant != normalizedTenant ||
                currentCompany != normalizedCompany))) {
      activeDriverSessionNotifier.value = null;
      _cache = null;
      _cacheScopeKey = '';
    }
  }

  Future<({String? photo, String source})> _backfillStandaloneDriverPhoto({
    required ActiveDriverSession session,
    required List<DriverProfile> drivers,
  }) async {
    final scopedLocal = _findScopedLocalDriver(drivers, session);
    final localPhoto = _resolvePersistableDriverPhotoUrl(
      scopedLocal?.publicPortraitUrl,
    );
    if (localPhoto != null) {
      return (photo: localPhoto, source: 'local');
    }

    final companyCode = (session.companyCode ?? '').trim();
    final driverCode = session.employeeNumber.trim();
    if (companyCode.isNotEmpty && driverCode.isNotEmpty) {
      final backendPhoto = await _fetchStandaloneDriverPhotoViaPublicLogin(
        companyCode: companyCode,
        driverCode: driverCode,
        expectedDriverId: session.driverId.trim(),
      );
      if (backendPhoto != null) {
        return (photo: backendPhoto, source: 'backend');
      }
    }

    final companyId = (session.companyId ?? '').trim();
    final driverId = session.driverId.trim();
    if (companyId.isNotEmpty && driverId.isNotEmpty) {
      final profilePhoto = await _fetchStandaloneDriverPhotoViaPartnerProfile(
        companyId: companyId,
        driverId: driverId,
      );
      if (profilePhoto != null) {
        return (photo: profilePhoto, source: 'driver_profile');
      }
    }

    return (photo: null, source: 'none');
  }

  Future<String?> _fetchStandaloneDriverPhotoViaPublicLogin({
    required String companyCode,
    required String driverCode,
    required String expectedDriverId,
  }) async {
    final normalizedCompanyCode = companyCode.trim().toUpperCase();
    final normalizedDriverCode = driverCode.trim();
    if (normalizedCompanyCode.isEmpty || normalizedDriverCode.isEmpty) {
      return null;
    }
    final uri = Uri.parse('${appConfig.bookingBaseUrl}/public/driver/login');
    try {
      final response = await http
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'company_code': normalizedCompanyCode,
              'driver_code': normalizedDriverCode,
              'companyCode': normalizedCompanyCode,
              'driverCode': normalizedDriverCode,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final body = Map<String, dynamic>.from(decoded);
      if (body['ok'] != true) return null;
      final responseDriverId = (body['driver_id'] ?? body['driverId'] ?? '')
          .toString()
          .trim();
      if (expectedDriverId.isNotEmpty &&
          responseDriverId.isNotEmpty &&
          responseDriverId != expectedDriverId) {
        return null;
      }
      final driverMap = body['driver'] is Map
          ? Map<String, dynamic>.from(body['driver'] as Map)
          : null;
      final profileMap = body['profile'] is Map
          ? Map<String, dynamic>.from(body['profile'] as Map)
          : null;
      final rawPhoto = _extractDriverPhotoFromPayloadMaps(
        body: body,
        driverMap: driverMap,
        profileMap: profileMap,
      );
      return _resolvePersistableDriverPhotoUrl(rawPhoto);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchStandaloneDriverPhotoViaPartnerProfile({
    required String companyId,
    required String driverId,
  }) async {
    final normalizedCompanyId = companyId.trim();
    final normalizedDriverId = driverId.trim();
    if (normalizedCompanyId.isEmpty || normalizedDriverId.isEmpty) {
      return null;
    }
    final uri = Uri.parse('${appConfig.bookingBaseUrl}/partners/profile')
        .replace(
          queryParameters: <String, String>{'partner_id': normalizedCompanyId},
        );
    try {
      final response = await http
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final root = Map<String, dynamic>.from(decoded);
      if (root['ok'] != true) return null;
      final profileRaw = root['profile'];
      if (profileRaw is! Map) return null;
      final profile = Map<String, dynamic>.from(profileRaw);
      final driversRaw = profile['drivers'];
      if (driversRaw is! List) return null;
      for (final row in driversRaw) {
        if (row is! Map) continue;
        final driverMap = Map<String, dynamic>.from(row);
        final rowDriverId =
            (driverMap['driver_id'] ??
                    driverMap['driverId'] ??
                    driverMap['id'] ??
                    '')
                .toString()
                .trim();
        if (rowDriverId != normalizedDriverId) continue;
        final rawPhoto = _extractDriverPhotoFromPayloadMaps(
          body: driverMap,
          driverMap: driverMap,
        );
        final resolved = _resolvePersistableDriverPhotoUrl(rawPhoto);
        if (resolved != null) return resolved;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<({bool ok, String? destructiveReason, String? recoverableReason})>
  _restoreValidatedSession(
    List<DriverProfile> drivers,
    ActiveDriverSession s, {
    required String restoreSource,
    required String fileScopeTenant,
    required String fileScopeCompany,
    StandaloneDriverScopePointer? pointer,
  }) async {
    _standaloneOperationalBlockReason = null;

    var sessionForRestore = s;
    if (s.isStandaloneLoginSession && !s.isCompanyAdminDriverViewSession) {
      final expectedTenant = fileScopeTenant.trim();
      final expectedCompany = fileScopeCompany.trim();
      if (expectedTenant.isNotEmpty && expectedCompany.isNotEmpty) {
        final repaired = await _resolveStandaloneSessionForRestore(
          session: s,
          fileScopeTenant: fileScopeTenant,
          fileScopeCompany: fileScopeCompany,
          expectedTenant: expectedTenant,
          expectedCompany: expectedCompany,
          source: restoreSource == 'standalone_pointer'
              ? 'pointer'
              : 'scoped_file',
          pointer: pointer,
        );
        if (repaired == null &&
            _isTrueStandaloneScopeSecurityMismatch(
              fileScopeTenant: fileScopeTenant,
              fileScopeCompany: fileScopeCompany,
              expectedTenant: expectedTenant,
              expectedCompany: expectedCompany,
              pointer: pointer,
            )) {
          debugPrint(
            '[DRIVER_SESSION][INVALIDATE] reason=scope_mismatch driver=${_maskIdForLog(s.driverId)}',
          );
          return (
            ok: false,
            destructiveReason: 'security_mismatch',
            recoverableReason: null,
          );
        }
        if (repaired != null) {
          sessionForRestore = repaired;
        }
      }

      if (sessionForRestore.isVerifiedPairingSession) {
        final expiresAt = sessionForRestore.expiresAtUtc;
        final nowUtc = DateTime.now().toUtc();
        if (expiresAt != null && expiresAt.isBefore(nowUtc)) {
          debugPrint(
            '[DRIVER_SESSION][INVALIDATE] reason=expired method=driver_pairing_code driver=${_maskIdForLog(sessionForRestore.driverId)} expires_at=${expiresAt.toIso8601String()} now=${nowUtc.toIso8601String()}',
          );
          return (
            ok: false,
            destructiveReason: 'expired',
            recoverableReason: null,
          );
        }
      } else if (sessionForRestore.isPublicDriverLoginSession) {
        // Token expiry is destructive (re-login overwrites file).
        final expiresRaw = (sessionForRestore.driverSessionExpiresAtUtc ?? '')
            .trim();
        if (expiresRaw.isNotEmpty) {
          final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
          final nowUtc = DateTime.now().toUtc();
          if (expiresAt != null && expiresAt.isBefore(nowUtc)) {
            debugPrint(
              '[DRIVER_SESSION][INVALIDATE] reason=expired method=public_driver_login driver=${_maskIdForLog(sessionForRestore.driverId)} expires_at=${expiresAt.toIso8601String()} now=${nowUtc.toIso8601String()}',
            );
            return (
              ok: false,
              destructiveReason: 'expired',
              recoverableReason: null,
            );
          }
        }
        // Required identity must be present for backend session to be usable.
        final hasDriverId = sessionForRestore.driverId.trim().isNotEmpty;
        final hasToken = (sessionForRestore.driverSessionToken ?? '')
            .trim()
            .isNotEmpty;
        final hasTenant = (sessionForRestore.tenantId ?? '').trim().isNotEmpty;
        final hasCompany = (sessionForRestore.companyId ?? '')
            .trim()
            .isNotEmpty;
        final hasIdentity = hasDriverId && hasToken && hasTenant && hasCompany;
        if (!hasIdentity) {
          debugPrint(
            '[DRIVER_SESSION][RESTORE_BLOCKED_NON_DESTRUCTIVE] reason=missing_identity driver=${_maskIdForLog(sessionForRestore.driverId)} has_driverId=$hasDriverId has_token=$hasToken has_tenant=$hasTenant has_company=$hasCompany',
          );
          return (
            ok: false,
            destructiveReason: null,
            recoverableReason: 'missing_identity',
          );
        }
        // Fleet validation runs in informational mode only — backend login
        // owns identity, employee_mismatch is tolerated.
        final fleetReason = standaloneDriverSessionFleetInvalidationReason(
          driverId: sessionForRestore.driverId,
          employeeNumber: sessionForRestore.employeeNumber,
          assignedVehicleId: sessionForRestore.assignedVehicleId,
          tenantId: sessionForRestore.tenantId,
          companyId: sessionForRestore.companyId,
          drivers: drivers,
          validateVehicleAssignment: true,
          activeCompanyId: fileScopeCompany.trim().isNotEmpty
              ? fileScopeCompany.trim()
              : null,
        );
        if (fleetReason != null) {
          debugPrint(
            '[DRIVER_SESSION][EMPLOYEE_MISMATCH_TOLERATED] method=public_driver_login reason=$fleetReason driver=${_maskIdForLog(sessionForRestore.driverId)}',
          );
        }
      } else {
        final invalidationReason =
            standaloneDriverSessionFleetInvalidationReason(
              driverId: sessionForRestore.driverId,
              employeeNumber: sessionForRestore.employeeNumber,
              assignedVehicleId: sessionForRestore.assignedVehicleId,
              tenantId: sessionForRestore.tenantId,
              companyId: sessionForRestore.companyId,
              drivers: drivers,
              validateVehicleAssignment: true,
              activeCompanyId: fileScopeCompany.trim().isNotEmpty
                  ? fileScopeCompany.trim()
                  : null,
            );
        if (invalidationReason != null) {
          // Recoverable: keep the file, just block UI entry. The session may
          // become valid again once company inventory hydrates.
          debugPrint(
            '[DRIVER_SESSION][RESTORE_BLOCKED_NON_DESTRUCTIVE] reason=$invalidationReason driver=${_maskIdForLog(sessionForRestore.driverId)}',
          );
          return (
            ok: false,
            destructiveReason: null,
            recoverableReason: invalidationReason,
          );
        }
      }
      final blockReason = standaloneDriverSessionOperationalBlockReason(
        driverId: sessionForRestore.driverId,
        assignedVehicleId: sessionForRestore.assignedVehicleId,
        tenantId: sessionForRestore.tenantId,
        companyId: sessionForRestore.companyId,
        drivers: drivers,
        activeCompanyId: fileScopeCompany.trim().isNotEmpty
            ? fileScopeCompany.trim()
            : null,
      );
      if (blockReason != null) {
        _standaloneOperationalBlockReason = blockReason;
        debugPrint(
          '[DRIVER_SESSION][BLOCK] reason=$blockReason driver=${_maskIdForLog(sessionForRestore.driverId)}',
        );
      }
    }
    final stillValid = _isStillValid(drivers, sessionForRestore);
    if (!stillValid &&
        sessionForRestore.isPublicDriverLoginSession &&
        sessionForRestore.driverId.trim().isNotEmpty &&
        (sessionForRestore.driverSessionToken ?? '').trim().isNotEmpty) {
      // public_driver_login already validated identity+expiry above; ignore
      // local inventory shape mismatch and proceed with restore.
      debugPrint(
        '[DRIVER_SESSION][EMPLOYEE_MISMATCH_TOLERATED] method=public_driver_login reason=is_still_valid_inventory driver=${_maskIdForLog(sessionForRestore.driverId)}',
      );
    } else if (!stillValid) {
      debugPrint(
        '[DRIVER_SESSION][RESTORE_BLOCKED_NON_DESTRUCTIVE] reason=invalid_session_state driver=${_maskIdForLog(sessionForRestore.driverId)}',
      );
      return (
        ok: false,
        destructiveReason: null,
        recoverableReason: 'invalid_session_state',
      );
    }
    {
      ActiveDriverSession resolved = sessionForRestore;
      final matched = _findScopedLocalDriver(drivers, sessionForRestore);
      final sessionPhotoRaw = (sessionForRestore.driverPhotoUrl ?? '').trim();
      final backendPhotoRaw = (matched?.publicPortraitUrl ?? '').trim();
      final legacyLooksPreferred =
          sessionPhotoRaw.isNotEmpty &&
          !_isPreferredCanonicalPhotoUrl(sessionPhotoRaw) &&
          backendPhotoRaw.isNotEmpty &&
          _isPreferredCanonicalPhotoUrl(backendPhotoRaw);
      if (legacyLooksPreferred) {
        debugPrint(
          '[DRIVER_PHOTO_CANONICAL][LEGACY_IGNORED] driver=${_maskIdForLog(sessionForRestore.driverId)} reason=session_prefers_legacy_remote',
        );
      }
      final resolvedSessionPhoto = _resolvePersistableDriverPhotoUrl(
        sessionPhotoRaw,
      );
      final resolvedBackendPhoto = _resolvePersistableDriverPhotoUrl(
        backendPhotoRaw,
      );
      String? canonicalCandidate;
      var restorePhotoSource = 'none';
      if (resolvedSessionPhoto != null) {
        canonicalCandidate = resolvedSessionPhoto;
        restorePhotoSource = 'session';
      } else if (resolvedBackendPhoto != null) {
        canonicalCandidate = resolvedBackendPhoto;
        restorePhotoSource = 'local';
      }
      if (canonicalCandidate == null &&
          sessionForRestore.isStandaloneLoginSession &&
          !sessionForRestore.isCompanyAdminDriverViewSession) {
        final backfill = await _backfillStandaloneDriverPhoto(
          session: sessionForRestore,
          drivers: drivers,
        );
        debugPrint(
          '[DRIVER_SESSION][RESTORE_PHOTO_BACKFILL] driver=${_maskIdForLog(sessionForRestore.driverId)} photo=${backfill.photo == null ? 'missing' : 'present'} source=${backfill.source}',
        );
        if (backfill.photo != null) {
          canonicalCandidate = backfill.photo;
          restorePhotoSource = backfill.source;
        }
      }
      debugPrint(
        '[DRIVER_SESSION][RESTORE_PHOTO] driver=${_maskIdForLog(sessionForRestore.driverId)} photo=${canonicalCandidate == null ? 'missing' : 'present'} source=$restorePhotoSource',
      );
      final source = () {
        switch (restorePhotoSource) {
          case 'session':
            return 'session';
          case 'local':
            return 'local';
          case 'backend':
          case 'driver_profile':
            return 'backend';
          default:
            return 'fallback';
        }
      }();
      if (canonicalCandidate != null && canonicalCandidate.isNotEmpty) {
        debugPrint(
          '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskIdForLog(sessionForRestore.driverId)} photo=present source=$restorePhotoSource',
        );
      }
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][SOURCE] driver=${_maskIdForLog(sessionForRestore.driverId)} source=$source',
      );
      final shouldPatch =
          canonicalCandidate != null &&
          canonicalCandidate.trim() != sessionPhotoRaw;
      if (shouldPatch) {
        resolved = ActiveDriverSession(
          driverId: sessionForRestore.driverId,
          employeeNumber: sessionForRestore.employeeNumber,
          fullName: sessionForRestore.fullName,
          phone: sessionForRestore.phone,
          loggedInAt: sessionForRestore.loggedInAt,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          tenantId: sessionForRestore.tenantId,
          companyId: sessionForRestore.companyId,
          companyCode: sessionForRestore.companyCode,
          assignedVehicleId: sessionForRestore.assignedVehicleId,
          driverPhotoUrl: canonicalCandidate,
          companyLogoUrl: sessionForRestore.companyLogoUrl,
          vehiclePhotoUrl: sessionForRestore.vehiclePhotoUrl,
          driverSessionToken: sessionForRestore.driverSessionToken,
          driverSessionExpiresAtUtc:
              sessionForRestore.driverSessionExpiresAtUtc,
          linkMethod: sessionForRestore.linkMethod,
          expiresAt: sessionForRestore.expiresAt,
        );
        await _writeSessionAtScope(resolved);
        debugPrint(
          '[DRIVER_SESSION][RESTORE_PHOTO_PATCH_SAVE] driver=${_maskIdForLog(sessionForRestore.driverId)} ok=true',
        );
      } else {
        _cache = resolved;
        final tenant = (resolved.tenantId ?? '').trim();
        final company = (resolved.companyId ?? '').trim();
        if (tenant.isNotEmpty && company.isNotEmpty) {
          _cacheScopeKey = '$tenant::$company';
        }
      }
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][SESSION_PATCH] driver=${_maskIdForLog(sessionForRestore.driverId)} updated=$shouldPatch',
      );
      debugPrint(
        '[DRIVER_PHOTO_CANONICAL][DONE] driver=${_maskIdForLog(sessionForRestore.driverId)} urlSource=$source',
      );
      activeDriverSessionNotifier.value = resolved;
      if (restoreSource == 'standalone_pointer') {
        debugPrint(
          '[DRIVER_SESSION][STANDALONE_POINTER_RESTORE_OK] driver=${_maskIdForLog(resolved.driverId)} tenant=${_maskIdForLog(resolved.tenantId ?? '')} company=${_maskIdForLog(resolved.companyId ?? '')}',
        );
      }
      debugPrint(
        '[DRIVER_SESSION][RESTORE_OK] driver=${_maskIdForLog(resolved.driverId)} mode=${resolved.sessionMode} tenant=${_maskIdForLog(resolved.tenantId ?? '')} company=${_maskIdForLog(resolved.companyId ?? '')} source=$restoreSource',
      );
      return (ok: true, destructiveReason: null, recoverableReason: null);
    }
  }

  /// Call after tenant drivers are loaded. Clears stale sessions.
  Future<void> bootstrap(
    List<DriverProfile> drivers, {
    bool standaloneRestoreOnly = true,
    bool useStandaloneScopePointer = true,
  }) async {
    final active = _activeScope();
    debugPrint(
      '[DRIVER_SESSION][RESTORE_ATTEMPT] mode=${standaloneRestoreOnly ? 'standalone' : 'any'} tenant=${_maskIdForLog(active?.tenantId ?? '')} company=${_maskIdForLog(active?.companyId ?? '')}',
    );

    ActiveDriverSession? candidate;
    var restoreSource = 'none';
    var fileScopeTenant = '';
    var fileScopeCompany = '';
    StandaloneDriverScopePointer? pointer;

    if (active != null) {
      final activeSession = await _loadSessionAtScope(
        tenantId: active.tenantId,
        companyId: active.companyId,
      );
      if (activeSession != null) {
        if (!standaloneRestoreOnly) {
          candidate = activeSession;
          restoreSource = 'active_scope';
          fileScopeTenant = active.tenantId;
          fileScopeCompany = active.companyId;
        } else if (activeSession.isCompanyAdminDriverViewSession) {
          debugPrint(
            '[DRIVER_SESSION][RESTORE_SKIP_BUSINESS_VIEW] driver=${_maskIdForLog(activeSession.driverId)}',
          );
          await _clearSessionAtScope(
            tenantId: active.tenantId,
            companyId: active.companyId,
          );
        } else if (_isRestorableStandaloneSession(activeSession)) {
          final resolvedSession = await _resolveStandaloneSessionForRestore(
            session: activeSession,
            fileScopeTenant: active.tenantId,
            fileScopeCompany: active.companyId,
            expectedTenant: active.tenantId,
            expectedCompany: active.companyId,
            source: 'scoped_file',
          );
          if (resolvedSession != null) {
            candidate = resolvedSession;
            restoreSource = 'active_scope';
            fileScopeTenant = active.tenantId;
            fileScopeCompany = active.companyId;
          }
        }
      }
    }

    if (candidate == null &&
        standaloneRestoreOnly &&
        useStandaloneScopePointer) {
      pointer = await loadStandaloneScopePointer();
      if (pointer != null) {
        debugPrint(
          '[DRIVER_SESSION][STANDALONE_POINTER_LOAD] tenant=${_maskIdForLog(pointer.tenantId)} company=${_maskIdForLog(pointer.companyId)} driver=${_maskIdForLog(pointer.driverId)} method=${pointer.linkMethod}',
        );
        final pointerSession = await _loadSessionAtScope(
          tenantId: pointer.tenantId,
          companyId: pointer.companyId,
        );
        if (pointerSession != null &&
            _isRestorableStandaloneSession(pointerSession)) {
          final expectedTenant = pointer.tenantId;
          final expectedCompany = pointer.companyId;
          final resolvedSession = await _resolveStandaloneSessionForRestore(
            session: pointerSession,
            fileScopeTenant: pointer.tenantId,
            fileScopeCompany: pointer.companyId,
            expectedTenant: expectedTenant,
            expectedCompany: expectedCompany,
            source: 'pointer',
            pointer: pointer,
          );
          if (resolvedSession != null &&
              _validateStandalonePointerRestore(pointer, resolvedSession)) {
            candidate = resolvedSession;
            restoreSource = 'standalone_pointer';
            fileScopeTenant = pointer.tenantId;
            fileScopeCompany = pointer.companyId;
          } else {
            final securityMismatch = _isTrueStandaloneScopeSecurityMismatch(
              fileScopeTenant: pointer.tenantId,
              fileScopeCompany: pointer.companyId,
              expectedTenant: expectedTenant,
              expectedCompany: expectedCompany,
              pointer: pointer,
            );
            debugPrint(
              '[DRIVER_SESSION][STANDALONE_POINTER_SKIP] tenant=${_maskIdForLog(pointer.tenantId)} company=${_maskIdForLog(pointer.companyId)} driver=${_maskIdForLog(pointer.driverId)} reason=${securityMismatch ? 'security_mismatch' : 'validation_failed'}',
            );
            if (securityMismatch) {
              await _clearSessionAtScope(
                tenantId: pointer.tenantId,
                companyId: pointer.companyId,
              );
              await clearStandaloneScopePointer();
            }
          }
        } else if (pointerSession == null) {
          debugPrint(
            '[DRIVER_SESSION][STANDALONE_POINTER_NEEDS_LOGIN] tenant=${_maskIdForLog(pointer.tenantId)} company=${_maskIdForLog(pointer.companyId)} driver=${_maskIdForLog(pointer.driverId)} reason=missing_session_no_token keep_pointer=true',
          );
        } else {
          debugPrint(
            '[DRIVER_SESSION][STANDALONE_POINTER_SKIP] tenant=${_maskIdForLog(pointer.tenantId)} company=${_maskIdForLog(pointer.companyId)} driver=${_maskIdForLog(pointer.driverId)} reason=non_restorable',
          );
        }
      }
    }

    if (candidate == null) {
      debugPrint(
        '[DRIVER_SESSION][RESTORE_NO_CANDIDATE] active_scope=${active != null} pointer=${pointer != null} standaloneOnly=$standaloneRestoreOnly useStandalonePointer=$useStandaloneScopePointer',
      );
      activeDriverSessionNotifier.value = null;
      return;
    }

    if (standaloneRestoreOnly && candidate.isCompanyAdminDriverViewSession) {
      debugPrint(
        '[DRIVER_SESSION][RESTORE_SKIP_BUSINESS_VIEW] driver=${_maskIdForLog(candidate.driverId)}',
      );
      activeDriverSessionNotifier.value = null;
      return;
    }
    if (standaloneRestoreOnly && !_isRestorableStandaloneSession(candidate)) {
      debugPrint(
        '[DRIVER_SESSION][RESTORE_SKIP_NON_STANDALONE] driver=${_maskIdForLog(candidate.driverId)} link=${(candidate.linkMethod ?? '').trim().isEmpty ? 'unknown' : candidate.linkMethod}',
      );
      if (restoreSource == 'standalone_pointer' && pointer != null) {
        await _clearSessionAtScope(
          tenantId: pointer.tenantId,
          companyId: pointer.companyId,
        );
        await clearStandaloneScopePointer();
      } else if (active != null) {
        await _clearSessionAtScope(
          tenantId: active.tenantId,
          companyId: active.companyId,
        );
      }
      activeDriverSessionNotifier.value = null;
      return;
    }

    if (fileScopeTenant.isEmpty || fileScopeCompany.isEmpty) {
      fileScopeTenant = (candidate.tenantId ?? '').trim();
      fileScopeCompany = (candidate.companyId ?? '').trim();
    }

    final restoreResult = await _restoreValidatedSession(
      drivers,
      candidate,
      restoreSource: restoreSource,
      fileScopeTenant: fileScopeTenant,
      fileScopeCompany: fileScopeCompany,
      pointer: pointer,
    );
    if (restoreResult.ok) return;

    final destructive = restoreResult.destructiveReason;
    final recoverable = restoreResult.recoverableReason;
    if (destructive != null) {
      debugPrint('[DRIVER_SESSION][CLEAR_STALE] reason=$destructive');
      final clearTenant = fileScopeTenant.isNotEmpty
          ? fileScopeTenant
          : (pointer?.tenantId ?? active?.tenantId ?? '');
      final clearCompany = fileScopeCompany.isNotEmpty
          ? fileScopeCompany
          : (pointer?.companyId ?? active?.companyId ?? '');
      if (clearTenant.isNotEmpty && clearCompany.isNotEmpty) {
        await _clearSessionAtScope(
          tenantId: clearTenant,
          companyId: clearCompany,
        );
      }
      if (destructive == 'security_mismatch' &&
          restoreSource == 'standalone_pointer' &&
          pointer != null) {
        await clearStandaloneScopePointer();
      }
    } else {
      debugPrint(
        '[DRIVER_SESSION][RESTORE_BLOCKED_NON_DESTRUCTIVE] reason=${recoverable ?? 'unknown'} driver=${_maskIdForLog(candidate.driverId)} keep_file=true keep_pointer=true',
      );
    }
    activeDriverSessionNotifier.value = null;
  }

  static bool _isStillValid(
    List<DriverProfile> drivers,
    ActiveDriverSession s,
  ) {
    if (s.isCompanyAdminDriverViewSession) {
      debugPrint(
        '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=company_admin_driver_view driver=${_maskIdForLog(s.driverId)}',
      );
      return false;
    }
    if (s.isVerifiedPairingSession) {
      final expiresAt = s.expiresAtUtc;
      if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
        debugPrint(
          '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=pairing_expired driver=${_maskIdForLog(s.driverId)}',
        );
        return false;
      }
      final hasDriverId = s.driverId.trim().isNotEmpty;
      final hasEmployee = s.employeeNumber.trim().isNotEmpty;
      if (!(hasDriverId && hasEmployee)) {
        debugPrint(
          '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=pairing_identity_incomplete driver=${_maskIdForLog(s.driverId)} has_driverId=$hasDriverId has_employee=$hasEmployee',
        );
      }
      return hasDriverId && hasEmployee;
    }
    if (s.isPublicDriverLoginSession) {
      final expiresRaw = (s.driverSessionExpiresAtUtc ?? '').trim();
      if (expiresRaw.isNotEmpty) {
        final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
        if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
          debugPrint(
            '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=public_login_expired driver=${_maskIdForLog(s.driverId)}',
          );
          return false;
        }
      }
      final hasDriverId = s.driverId.trim().isNotEmpty;
      final hasToken = (s.driverSessionToken ?? '').trim().isNotEmpty;
      if (!(hasDriverId && hasToken)) {
        debugPrint(
          '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=public_login_identity_incomplete driver=${_maskIdForLog(s.driverId)} has_driverId=$hasDriverId has_token=$hasToken',
        );
      }
      return hasDriverId && hasToken;
    }
    for (final d in drivers) {
      if (d.id != s.driverId) continue;
      if (!d.isActive) {
        debugPrint(
          '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=driver_inactive driver=${_maskIdForLog(s.driverId)}',
        );
        return false;
      }
      final de = d.employeeNumber.trim();
      final se = s.employeeNumber.trim();
      if (de.isEmpty || se.isEmpty) {
        debugPrint(
          '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=employee_empty driver=${_maskIdForLog(s.driverId)} fleet_empty=${de.isEmpty} session_empty=${se.isEmpty}',
        );
        return false;
      }
      if (de.toLowerCase() != se.toLowerCase()) {
        debugPrint(
          '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=employee_mismatch driver=${_maskIdForLog(s.driverId)}',
        );
        return false;
      }
      return true;
    }
    debugPrint(
      '[DRIVER_SESSION][LOCAL_VALIDATE_FAIL] reason=no_match_in_drivers driver=${_maskIdForLog(s.driverId)} drivers_total=${drivers.length}',
    );
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
    final normalizedLinkOverride = (linkMethodOverride ?? '').trim();
    if (normalizedLinkOverride.toLowerCase() ==
        kCompanyAdminDriverViewLinkMethod) {
      debugPrint(
        '[DRIVER_SESSION][BUSINESS_VIEW_NO_STANDALONE_PERSIST] blocked=saveFromDriverProfile driver=${_maskIdForLog(driver.id)}',
      );
      return;
    }
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
    final incomingPhoto = _resolvePersistableDriverPhotoUrl(
      driver.publicPortraitUrl,
    );
    final preservedPhoto = _preservePhotoForSameDriver(
      incomingPhoto: incomingPhoto,
      existing: effectivePrevious,
      newDriverId: driver.id.trim(),
      saveSource: 'saveFromDriverProfile',
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
      driverPhotoUrl: preservedPhoto,
      driverSessionToken: preservedToken.token,
      driverSessionExpiresAtUtc: preservedToken.tokenExpiryUtc,
      linkMethod: normalizedLinkOverride.isEmpty
          ? kStandaloneDriverLinkMethod
          : normalizedLinkOverride,
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
          '[DRIVER_SESSION][SAVE] mode=${session.sessionMode} tenant=${scope.tenantId} company=${scope.companyId} driver=${_maskIdForLog(session.driverId)} path=${file.path}',
        );
      }
      activeDriverSessionNotifier.value = session;
      await saveStandaloneScopePointer(session);
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
    String? driverPhotoUrl,
    String? driverSessionToken,
    DateTime? driverSessionExpiresAtUtc,
    DateTime? issuedAt,
    DateTime? expiresAt,
    Map<String, dynamic>? verifiedPayload,
  }) async {
    final payload = verifiedPayload ?? const <String, dynamic>{};
    var normalizedTenantId = tenantId.trim().isNotEmpty
        ? tenantId.trim()
        : _firstNonEmptyScopeField(payload, <String>['tenant_id', 'tenantId']);
    var normalizedCompanyId = companyId.trim().isNotEmpty
        ? companyId.trim()
        : _firstNonEmptyScopeField(payload, <String>[
            'company_id',
            'companyId',
          ]);
    var normalizedCompanyCode = companyCode.trim().isNotEmpty
        ? companyCode.trim().toUpperCase()
        : _firstNonEmptyScopeField(payload, <String>[
            'company_code',
            'companyCode',
          ]).toUpperCase();
    final activeScope = _activeScope();
    if (normalizedTenantId.isEmpty && activeScope != null) {
      normalizedTenantId = activeScope.tenantId.trim();
    }
    if (normalizedCompanyId.isEmpty && activeScope != null) {
      normalizedCompanyId = activeScope.companyId.trim();
    }
    if (normalizedTenantId.isNotEmpty &&
        normalizedCompanyId.isEmpty &&
        activeScope != null) {
      normalizedCompanyId = normalizedTenantId;
    }
    if (normalizedCompanyId.isNotEmpty &&
        normalizedTenantId.isEmpty &&
        activeScope != null) {
      normalizedTenantId = normalizedCompanyId;
    }
    final normalizedDriverId = driverId.trim();
    final normalizedDriverName = driverName.trim();
    final normalizedEmployeeNumber = employeeNumber.trim();
    final normalizedAssignedVehicleId = (assignedVehicleId ?? '').trim();
    final normalizedDriverPhotoUrl =
        _resolvePersistableDriverPhotoUrl(driverPhotoUrl) ?? '';
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
    final preservedPhoto = _preservePhotoForSameDriver(
      incomingPhoto: normalizedDriverPhotoUrl.isEmpty
          ? null
          : normalizedDriverPhotoUrl,
      existing: existingScopedSession,
      newDriverId: normalizedDriverId,
      saveSource: 'saveVerifiedDriverPairingSession',
    );
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
      driverPhotoUrl: (preservedPhoto ?? '').isEmpty ? null : preservedPhoto,
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
      final savedPhoto = (session.driverPhotoUrl ?? '').trim();
      debugPrint(
        '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskIdForLog(session.driverId)} photo=${savedPhoto.isEmpty ? 'missing' : 'present'} source=pairing',
      );
      debugPrint(
        '[DRIVER_SESSION][SAVE_VERIFIED] tenant=$normalizedTenantId company=$normalizedCompanyId driver=${_maskIdForLog(session.driverId)} method=driver_pairing_code path=${scopedFile.path}',
      );
      await saveStandaloneScopePointer(session);
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
    String? employeeNumber,
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
    final normalizedDriverPhotoUrl =
        _resolvePersistableDriverPhotoUrl(driverPhotoUrl) ?? '';
    final normalizedCompanyLogoUrl = (companyLogoUrl ?? '').trim();
    final normalizedVehiclePhotoUrl = (vehiclePhotoUrl ?? '').trim();
    final normalizedDriverSessionToken = (driverSessionToken ?? '').trim();
    final normalizedEmployeeNumber = (employeeNumber ?? '').trim();
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
    // Prefer the real driver code (chauffeur login code) for employeeNumber so
    // local fleet validation can match the local DriverProfile. Fall back to
    // driverId only when no code is provided (backward compatible).
    final resolvedEmployeeNumber = normalizedEmployeeNumber.isEmpty
        ? normalizedDriverId
        : normalizedEmployeeNumber;
    final existingScopedSession = await _readSession(
      await _scopedFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      ),
    );
    final preservedPhoto = _preservePhotoForSameDriver(
      incomingPhoto: normalizedDriverPhotoUrl.isEmpty
          ? null
          : normalizedDriverPhotoUrl,
      existing: existingScopedSession,
      newDriverId: normalizedDriverId,
      saveSource: 'saveBackendDriverLoginSession',
    );
    final session = ActiveDriverSession(
      driverId: normalizedDriverId,
      employeeNumber: resolvedEmployeeNumber,
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
      driverPhotoUrl: (preservedPhoto ?? '').isEmpty ? null : preservedPhoto,
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
      final savedPhoto = (session.driverPhotoUrl ?? '').trim();
      debugPrint(
        '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskIdForLog(session.driverId)} photo=${savedPhoto.isEmpty ? 'missing' : 'present'} source=backend',
      );
      debugPrint(
        '[DRIVER_SESSION][SAVE_BACKEND] tenant=$normalizedTenantId company=$normalizedCompanyId driver=${_maskIdForLog(session.driverId)} method=public_driver_login path=${file.path}',
      );
      await saveStandaloneScopePointer(session);
    } catch (e) {
      debugPrint('[DRIVER_LOGIN][WARN] persist_failed reason=$e');
    }
  }

  Future<void> clear() async {
    try {
      final pointer = await loadStandaloneScopePointer();
      if (pointer != null) {
        final file = await _scopedFile(
          tenantId: pointer.tenantId,
          companyId: pointer.companyId,
        );
        if (await file.exists()) await file.delete();
        debugPrint(
          '[DRIVER_SESSION][CLEAR] tenant=${pointer.tenantId} company=${pointer.companyId} path=${file.path} source=standalone_pointer',
        );
        await clearStandaloneScopePointer();
      } else {
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
      }
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][PERSIST_FAIL] op=clear err=${_shortErrForDriverLog(e)}',
      );
    }
    _cache = null;
    _cacheScopeKey = '';
    activeDriverSessionNotifier.value = null;
  }

  String _maskPhotoForLog(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 'missing';
    if (text.length <= 12) return 'present';
    return '${text.substring(0, 6)}…${text.substring(text.length - 4)}';
  }

  Future<void> saveBusinessDriverPreview(BusinessDriverPreviewRecord record) {
    final normalizedTenantId = record.tenantId.trim();
    final normalizedCompanyId = record.companyId.trim();
    final normalizedDriverId = record.driverId.trim();
    if (normalizedTenantId.isEmpty ||
        normalizedCompanyId.isEmpty ||
        normalizedDriverId.isEmpty) {
      return Future<void>.value();
    }
    final payload = BusinessDriverPreviewRecord(
      tenantId: normalizedTenantId,
      companyId: normalizedCompanyId,
      driverId: normalizedDriverId,
      vehicleId: record.vehicleId,
      driverName: record.driverName,
      driverPhotoUrl: record.driverPhotoUrl,
      mode: record.mode.trim().isEmpty
          ? kCompanyAdminDriverViewLinkMethod
          : record.mode.trim(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    debugPrint(
      '[DRIVER_SESSION][BUSINESS_PREVIEW_SAVE] driver=${_maskIdForLog(normalizedDriverId)} tenant=${_maskIdForLog(normalizedTenantId)} company=${_maskIdForLog(normalizedCompanyId)} photo=${_maskPhotoForLog(payload.driverPhotoUrl)}',
    );
    debugPrint(
      '[DRIVER_SESSION][BUSINESS_PREVIEW_PHOTO] driver=${_maskIdForLog(normalizedDriverId)} photo=${_maskPhotoForLog(payload.driverPhotoUrl)}',
    );
    return _writeBusinessDriverPreview(payload);
  }

  Future<void> _writeBusinessDriverPreview(
    BusinessDriverPreviewRecord record,
  ) async {
    try {
      final file = await _businessPreviewFile(
        tenantId: record.tenantId,
        companyId: record.companyId,
      );
      await file.writeAsString(jsonEncode(record.toJson()));
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][PERSIST_FAIL] op=write_business_preview tenant=${_maskIdForLog(record.tenantId)} company=${_maskIdForLog(record.companyId)} err=${_shortErrForDriverLog(e)}',
      );
    }
  }

  Future<void> saveBusinessPreviewDriverSelection({
    required String tenantId,
    required String companyId,
    required String driverId,
    String? vehicleId,
    String? driverName,
    String? driverPhotoUrl,
  }) {
    return saveBusinessDriverPreview(
      BusinessDriverPreviewRecord(
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        vehicleId: vehicleId,
        driverName: driverName,
        driverPhotoUrl: driverPhotoUrl,
      ),
    );
  }

  Future<BusinessDriverPreviewRecord?> loadBusinessDriverPreview({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) return null;
    try {
      final file = await _businessPreviewFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final record = BusinessDriverPreviewRecord.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (record.driverId.isEmpty) return null;
      if (record.tenantId.trim() != normalizedTenantId ||
          record.companyId.trim() != normalizedCompanyId) {
        debugPrint(
          '[DRIVER_SESSION][BUSINESS_PREVIEW_SKIP_SCOPE_MISMATCH] expected_tenant=${_maskIdForLog(normalizedTenantId)} expected_company=${_maskIdForLog(normalizedCompanyId)}',
        );
        await clearBusinessPreviewDriverSelection(
          tenantId: normalizedTenantId,
          companyId: normalizedCompanyId,
        );
        return null;
      }
      if (record.mode.trim().toLowerCase() !=
          kCompanyAdminDriverViewLinkMethod) {
        debugPrint(
          '[DRIVER_SESSION][BUSINESS_PREVIEW_SKIP_SCOPE_MISMATCH] reason=mode_mismatch mode=${record.mode}',
        );
        return null;
      }
      debugPrint(
        '[DRIVER_SESSION][BUSINESS_PREVIEW_RESTORE_OK] driver=${_maskIdForLog(record.driverId)} tenant=${_maskIdForLog(record.tenantId)} company=${_maskIdForLog(record.companyId)} photo=${_maskPhotoForLog(record.driverPhotoUrl)}',
      );
      debugPrint(
        '[DRIVER_SESSION][BUSINESS_PREVIEW_PHOTO] driver=${_maskIdForLog(record.driverId)} photo=${_maskPhotoForLog(record.driverPhotoUrl)}',
      );
      return record;
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][BUSINESS_PREVIEW_LOAD_FAIL] tenant=${_maskIdForLog(normalizedTenantId)} company=${_maskIdForLog(normalizedCompanyId)} err=${_shortErrForDriverLog(e)}',
      );
      return null;
    }
  }

  Future<String?> loadBusinessPreviewDriverSelection({
    required String tenantId,
    required String companyId,
  }) async {
    final preview = await loadBusinessDriverPreview(
      tenantId: tenantId,
      companyId: companyId,
    );
    final driverId = preview?.driverId.trim() ?? '';
    return driverId.isEmpty ? null : driverId;
  }

  Future<void> clearBusinessPreviewDriverSelection({
    required String tenantId,
    required String companyId,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedCompanyId = companyId.trim();
    if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) return;
    try {
      final file = await _businessPreviewFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint(
        '[DRIVER_SESSION][PERSIST_FAIL] op=clear_business_preview tenant=${_maskIdForLog(normalizedTenantId)} company=${_maskIdForLog(normalizedCompanyId)} err=${_shortErrForDriverLog(e)}',
      );
    }
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
