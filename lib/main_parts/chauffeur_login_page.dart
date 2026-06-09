part of '../main.dart';

class ChauffeurLoginPage extends StatefulWidget {
  const ChauffeurLoginPage({super.key, this.openedFromBusinessHome = false});

  final bool openedFromBusinessHome;

  @override
  State<ChauffeurLoginPage> createState() => _ChauffeurLoginPageState();
}

class _BackendDriverLoginResult {
  const _BackendDriverLoginResult({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.driverName,
    required this.companyDisplayName,
    required this.assignedVehicleId,
    required this.driverPhotoUrl,
    required this.companyLogoUrl,
    required this.vehiclePhotoUrl,
    required this.driverSessionToken,
    required this.expiresInSeconds,
  });

  final String tenantId;
  final String companyId;
  final String driverId;
  final String driverName;
  final String companyDisplayName;
  final String assignedVehicleId;
  final String driverPhotoUrl;
  final String companyLogoUrl;
  final String vehiclePhotoUrl;
  final String driverSessionToken;
  final int? expiresInSeconds;
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

void _logStandalonePhotoKeys({
  required String driverId,
  required Map<String, dynamic> payload,
  required Map<String, dynamic> driverMap,
}) {
  final hits = <String>[];
  void scanMap(Map<String, dynamic> map, String prefix) {
    for (final key in _driverPhotoPayloadKeys) {
      final value = (map[key] ?? '').toString().trim();
      if (value.isNotEmpty) hits.add('$prefix.$key');
    }
  }

  scanMap(driverMap, 'driver');
  final profileRaw = payload['profile'];
  if (profileRaw is Map) {
    scanMap(Map<String, dynamic>.from(profileRaw), 'profile');
  }
  scanMap(payload, 'payload');
  final trimmedDriverId = driverId.trim();
  final maskedDriverId = trimmedDriverId.length <= 4
      ? trimmedDriverId
      : '${trimmedDriverId.substring(0, 2)}…${trimmedDriverId.substring(trimmedDriverId.length - 2)}';
  debugPrint(
    '[DRIVER_SESSION][STANDALONE_PHOTO_KEYS] driver=$maskedDriverId keys=${hits.isEmpty ? 'none' : hits.join(',')}',
  );
}

String? _readDriverPhotoUrlFromMap(Map<String, dynamic> map) {
  for (final key in _driverPhotoPayloadKeys) {
    final value = (map[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

({String? url, String source}) _extractStandaloneDriverPhotoFromPairingPayload({
  required Map<String, dynamic> payload,
  required Map<String, dynamic> driverMap,
}) {
  final fromDriver = _readDriverPhotoUrlFromMap(driverMap);
  if (fromDriver != null) {
    return (url: fromDriver, source: 'payload');
  }
  final profileRaw = payload['profile'];
  if (profileRaw is Map) {
    final fromProfile = _readDriverPhotoUrlFromMap(
      Map<String, dynamic>.from(profileRaw),
    );
    if (fromProfile != null) {
      return (url: fromProfile, source: 'profile');
    }
  }
  final fromPayload = _readDriverPhotoUrlFromMap(payload);
  if (fromPayload != null) {
    return (url: fromPayload, source: 'payload');
  }
  return (url: null, source: 'none');
}

String? _resolveStandaloneDriverPhotoForSave(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final resolved = resolvePublicHttpsMediaUrl(text);
  if (resolved.isNotEmpty) return resolved;
  final lower = text.toLowerCase();
  if (lower.startsWith('https://') || lower.startsWith('http://')) return text;
  if (lower.startsWith('/public/media/') || lower.startsWith('public-media/')) {
    return text;
  }
  return null;
}

class _ChauffeurLoginPageState extends State<ChauffeurLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  bool _busy = false;
  String? _lookupError;
  bool _manualCodeCameFromTemporaryQr = false;
  bool _suppressManualCodeSourceReset = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    _companyCtrl.addListener(() {
      if (_lookupError != null) setState(() => _lookupError = null);
    });
    _idCtrl.addListener(() {
      final shouldResetTemporaryQrGuard =
          !_suppressManualCodeSourceReset && _manualCodeCameFromTemporaryQr;
      if (_lookupError != null || shouldResetTemporaryQrGuard) {
        setState(() {
          if (_lookupError != null) _lookupError = null;
          if (shouldResetTemporaryQrGuard) {
            _manualCodeCameFromTemporaryQr = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDriverHomeAfterLogin({required bool fromBusiness}) async {
    if (!mounted) return;
    setState(() => _busy = false);
    setAppRole(AppRole.driver);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DriverHomePage(openedFromBusinessHome: fromBusiness),
      ),
    );
  }

  Future<void> _completeBusinessDriverViewLogin({
    required String tenantId,
    required String companyId,
    required String driverId,
    required String employeeNumber,
    required String fullName,
    String? companyCode,
    String? assignedVehicleId,
    String? driverPhotoUrl,
    String? companyLogoUrl,
    String? vehiclePhotoUrl,
    String? driverSessionToken,
    String? driverSessionExpiresAtUtc,
  }) async {
    await DriverSessionStore.instance.saveBusinessDriverPreview(
      BusinessDriverPreviewRecord(
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        vehicleId: assignedVehicleId,
        driverName: fullName,
        driverPhotoUrl: driverPhotoUrl,
      ),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    DriverSessionStore.instance.setBusinessDriverViewSessionInMemory(
      ActiveDriverSession(
        driverId: driverId.trim(),
        employeeNumber: employeeNumber.trim(),
        fullName: fullName.trim(),
        phone: '',
        loggedInAt: now,
        updatedAt: now,
        tenantId: tenantId.trim(),
        companyId: companyId.trim(),
        companyCode: (companyCode ?? '').trim().isEmpty
            ? null
            : companyCode!.trim(),
        assignedVehicleId: (assignedVehicleId ?? '').trim().isEmpty
            ? null
            : assignedVehicleId!.trim(),
        driverPhotoUrl: (driverPhotoUrl ?? '').trim().isEmpty
            ? null
            : driverPhotoUrl!.trim(),
        companyLogoUrl: (companyLogoUrl ?? '').trim().isEmpty
            ? null
            : companyLogoUrl!.trim(),
        vehiclePhotoUrl: (vehiclePhotoUrl ?? '').trim().isEmpty
            ? null
            : vehiclePhotoUrl!.trim(),
        driverSessionToken: (driverSessionToken ?? '').trim().isEmpty
            ? null
            : driverSessionToken!.trim(),
        driverSessionExpiresAtUtc:
            (driverSessionExpiresAtUtc ?? '').trim().isEmpty
            ? null
            : driverSessionExpiresAtUtc!.trim(),
        linkMethod: kCompanyAdminDriverViewLinkMethod,
      ),
    );
    debugPrint(
      '[DRIVER_LOGIN][OK] source=business_preview driver=${_maskLoginCode(driverId)}',
    );
    await _openDriverHomeAfterLogin(fromBusiness: true);
  }

  Future<void> _submit() async {
    setState(() => _lookupError = null);
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_manualCodeCameFromTemporaryQr) {
      setState(() {
        _lookupError = _t(
          nl: 'Dit veld bevat een tijdelijke koppelcode uit QR-scan. Voor handmatig inloggen gebruik je een vaste chauffeurcode of scan je een nieuwe tijdelijke koppel-QR.',
          en: 'This field contains a temporary pairing code from QR scan. For manual login, use a fixed driver code or scan a new temporary pairing QR.',
          fr: 'Ce champ contient un code de liaison temporaire issu du scan QR. Pour la connexion manuelle, utilisez un code chauffeur fixe ou scannez un nouveau QR temporaire.',
          es: 'Este campo contiene un código temporal de vinculación del escaneo QR. Para inicio manual, usa un código fijo de conductor o escanea un nuevo QR temporal.',
        );
      });
      return;
    }
    setState(() => _busy = true);
    final enteredCompanyCode = _normalizeCompanyCode(_companyCtrl.text);
    final enteredDriverCode = _idCtrl.text.trim();
    final backendLogin = await _loginDriverWithBackend(
      companyCode: enteredCompanyCode,
      driverCode: enteredDriverCode,
    );
    if (backendLogin != null) {
      if (widget.openedFromBusinessHome) {
        String? tokenExpiry;
        if ((backendLogin.expiresInSeconds ?? 0) > 0) {
          tokenExpiry = DateTime.now()
              .toUtc()
              .add(Duration(seconds: backendLogin.expiresInSeconds!))
              .toIso8601String();
        }
        await _completeBusinessDriverViewLogin(
          tenantId: backendLogin.tenantId,
          companyId: backendLogin.companyId,
          driverId: backendLogin.driverId,
          employeeNumber: backendLogin.driverId,
          fullName: backendLogin.driverName,
          assignedVehicleId: backendLogin.assignedVehicleId,
          driverPhotoUrl: backendLogin.driverPhotoUrl,
          companyLogoUrl: backendLogin.companyLogoUrl,
          vehiclePhotoUrl: backendLogin.vehiclePhotoUrl,
          driverSessionToken: backendLogin.driverSessionToken,
          driverSessionExpiresAtUtc: tokenExpiry,
        );
        return;
      }
      final resolvedBackendPhoto = _resolveStandaloneDriverPhotoForSave(
        backendLogin.driverPhotoUrl,
      );
      debugPrint(
        '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskLoginCode(backendLogin.driverId)} photo=${resolvedBackendPhoto == null ? 'missing' : 'present'} source=payload',
      );
      await DriverSessionStore.instance.saveBackendDriverLoginSession(
        tenantId: backendLogin.tenantId,
        companyId: backendLogin.companyId,
        driverId: backendLogin.driverId,
        driverName: backendLogin.driverName,
        companyDisplayName: backendLogin.companyDisplayName,
        employeeNumber: enteredDriverCode,
        assignedVehicleId: backendLogin.assignedVehicleId,
        driverPhotoUrl: resolvedBackendPhoto,
        companyLogoUrl: backendLogin.companyLogoUrl,
        vehiclePhotoUrl: backendLogin.vehiclePhotoUrl,
        driverSessionToken: backendLogin.driverSessionToken,
        expiresInSeconds: backendLogin.expiresInSeconds,
      );
      debugPrint(
        '[DRIVER_LOGIN][BACKEND_SESSION_SAVE] tenant=${_maskLoginCode(backendLogin.tenantId)} company=${_maskLoginCode(backendLogin.companyId)} driver=${_maskLoginCode(backendLogin.driverId)}',
      );
      debugPrint(
        '[DRIVER_LOGIN][OK] source=backend driver=${_maskLoginCode(backendLogin.driverId)}',
      );
      await _openDriverHomeAfterLogin(fromBusiness: false);
      return;
    }
    debugPrint('[DRIVER_LOGIN][FALLBACK_LOCAL] reason=backend_failed');
    final companyScope = _findCompanyScopeForDriverLogin(
      enteredCompanyCode: _companyCtrl.text,
      drivers: driversNotifier.value,
    );
    debugPrint(
      '[DRIVER_LOGIN][COMPANY_LOOKUP] entered=${_maskLoginCode(_companyCtrl.text)} active_company=${companyScope.activeCompanyMasked} match=${companyScope.reason}',
    );
    if (companyScope.companyId == null) {
      debugPrint('[DRIVER_LOGIN][FAIL] reason=company_not_found');
      if (mounted) {
        setState(() {
          _busy = false;
          _lookupError = _t(
            nl: 'Bedrijf niet gevonden. Controleer de bedrijfscode.',
            en: 'Company not found. Check the company ID.',
            fr: 'Entreprise introuvable. Vérifiez le code entreprise.',
            es: 'Empresa no encontrada. Comprueba el código de empresa.',
          );
        });
      }
      return;
    }
    final activeCompanyId = companyScope.companyId!;
    final lookup = _findLocalDriverForLogin(
      entered: _idCtrl.text,
      activeCompanyId: activeCompanyId,
      drivers: driversNotifier.value,
    );
    debugPrint(
      '[DRIVER_LOGIN][LOOKUP] entered=${_maskLoginCode(_idCtrl.text)} drivers_total=${driversNotifier.value.length} active_company=${activeCompanyId.isEmpty ? "none" : _maskLoginCode(activeCompanyId)} candidates=${lookup.visibleCandidates} match=${lookup.match == null ? "none" : lookup.reason}',
    );
    if (lookup.match == null) {
      debugPrint('[DRIVER_LOGIN][FAIL] reason=driver_not_found');
      if (mounted) {
        setState(() {
          _busy = false;
          _lookupError = _t(
            nl: 'Geen actieve chauffeur gevonden met deze chauffeurcode.',
            en: 'No active driver found with this driver code.',
            fr: 'Aucun chauffeur actif trouvé avec ce code.',
            es: 'No se encontró ningún conductor activo con este código.',
          );
        });
      }
      return;
    }
    final selectedDriver = lookup.match!;
    var normalizedMatch = _driverWithNormalizedLoginCode(
      selectedDriver,
      enteredCode: _idCtrl.text,
    );
    final shouldMigrateLegacyToScope =
        lookup.reason == 'legacy_employee_code' ||
        lookup.reason == 'legacy_internal_id';
    if (shouldMigrateLegacyToScope && activeCompanyId.isNotEmpty) {
      normalizedMatch = normalizedMatch.copyWith(companyId: activeCompanyId);
    }
    if (_driverChangedForLoginMigration(selectedDriver, normalizedMatch)) {
      updateDriver(selectedDriver.id, normalizedMatch);
      debugPrint(
        '[DRIVER_LOGIN][MIGRATE] driver=${_maskLoginCode(selectedDriver.id)} company=${_maskLoginCode(activeCompanyId)} code=${_maskLoginCode(normalizedMatch.employeeNumber)} reason=${lookup.reason}',
      );
    }
    if (widget.openedFromBusinessHome) {
      await _completeBusinessDriverViewLogin(
        tenantId: activeCompanyId,
        companyId: activeCompanyId,
        driverId: normalizedMatch.id,
        employeeNumber: normalizedMatch.employeeNumber,
        fullName: normalizedMatch.fullName,
        assignedVehicleId: _resolveFleetVehicleIdForDriverGlobal(
          normalizedMatch.id,
        ),
        driverPhotoUrl: normalizedMatch.publicPortraitUrl,
      );
      return;
    }
    final prev = await DriverSessionStore.instance.load();
    await DriverSessionStore.instance.saveFromDriverProfile(
      normalizedMatch,
      previous: prev,
    );
    DriverSessionStore.instance.logOk(normalizedMatch.id);
    debugPrint(
      '[DRIVER_LOGIN][OK] driverId=${_maskLoginCode(normalizedMatch.id)}',
    );
    await _openDriverHomeAfterLogin(fromBusiness: false);
  }

  Future<_BackendDriverLoginResult?> _loginDriverWithBackend({
    required String companyCode,
    required String driverCode,
  }) async {
    final normalizedCompanyCode = _normalizeCompanyCode(companyCode);
    final normalizedDriverCode = driverCode.trim();
    if (normalizedCompanyCode.isEmpty || normalizedDriverCode.isEmpty) {
      return null;
    }
    debugPrint(
      '[DRIVER_LOGIN][BACKEND_REQ] company=${_maskLoginCode(normalizedCompanyCode)}',
    );
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
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final ok = body['ok'] == true;
      final role = (body['role'] ?? '').toString().trim().toLowerCase();
      final tenantId = (body['tenant_id'] ?? '').toString().trim();
      final companyId = (body['company_id'] ?? '').toString().trim();
      final driverId = (body['driver_id'] ?? '').toString().trim();
      final driverName = (body['driver_name'] ?? '').toString().trim();
      final companyDisplayName = (body['company_display_name'] ?? '')
          .toString()
          .trim();
      final assignedVehicleId =
          (body['assigned_vehicle_id'] ??
                  body['assignedVehicleId'] ??
                  body['vehicle_id'] ??
                  body['vehicleId'] ??
                  '')
              .toString()
              .trim();
      final driverBody = body['driver'] is Map
          ? Map<String, dynamic>.from(body['driver'] as Map)
          : <String, dynamic>{};
      var driverPhotoUrl = _readDriverPhotoUrlFromMap(body) ?? '';
      if (driverPhotoUrl.isEmpty && driverBody.isNotEmpty) {
        driverPhotoUrl = _readDriverPhotoUrlFromMap(driverBody) ?? '';
      }
      final profileBody = body['profile'] is Map
          ? Map<String, dynamic>.from(body['profile'] as Map)
          : <String, dynamic>{};
      if (driverPhotoUrl.isEmpty && profileBody.isNotEmpty) {
        driverPhotoUrl = _readDriverPhotoUrlFromMap(profileBody) ?? '';
      }
      driverPhotoUrl =
          (_resolveStandaloneDriverPhotoForSave(driverPhotoUrl) ?? '').trim();
      final companyLogoUrl =
          (body['company_logo_url'] ??
                  body['companyLogoUrl'] ??
                  body['logo_url'] ??
                  body['logoUrl'] ??
                  '')
              .toString()
              .trim();
      final vehiclePhotoUrl =
          (body['vehicle_photo_url'] ??
                  body['vehiclePhotoUrl'] ??
                  body['public_photo_url'] ??
                  body['publicPhotoUrl'] ??
                  body['photo_url'] ??
                  body['photoUrl'] ??
                  '')
              .toString()
              .trim();
      final driverSessionToken =
          (body['driver_session_token'] ?? body['driverSessionToken'] ?? '')
              .toString()
              .trim();
      final expiresInRaw = (body['expires_in'] ?? body['expiresIn'] ?? '')
          .toString()
          .trim();
      final expiresInSeconds = int.tryParse(expiresInRaw);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          ok &&
          role == 'driver' &&
          tenantId.isNotEmpty &&
          companyId.isNotEmpty &&
          driverId.isNotEmpty) {
        debugPrint(
          '[DRIVER_LOGIN][BACKEND_OK] driver=${_maskLoginCode(driverId)}',
        );
        return _BackendDriverLoginResult(
          tenantId: tenantId,
          companyId: companyId,
          driverId: driverId,
          driverName: driverName,
          companyDisplayName: companyDisplayName,
          assignedVehicleId: assignedVehicleId,
          driverPhotoUrl: driverPhotoUrl,
          companyLogoUrl: companyLogoUrl,
          vehiclePhotoUrl: vehiclePhotoUrl,
          driverSessionToken: driverSessionToken,
          expiresInSeconds: expiresInSeconds,
        );
      }
      debugPrint('[DRIVER_LOGIN][BACKEND_FAIL] status=${response.statusCode}');
      return null;
    } catch (_) {
      debugPrint('[DRIVER_LOGIN][BACKEND_FAIL] status=exception');
      return null;
    }
  }

  ({String? companyId, String reason, String activeCompanyMasked})
  _findCompanyScopeForDriverLogin({
    required String enteredCompanyCode,
    required List<DriverProfile> drivers,
  }) {
    final normalized = _normalizeCompanyCode(enteredCompanyCode);
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    final activeCompany = fromProfile.isNotEmpty
        ? fromProfile
        : (fromSession.isNotEmpty ? fromSession : '');

    if (normalized.isEmpty) {
      return (
        companyId: null,
        reason: 'empty_input',
        activeCompanyMasked: _maskLoginCode(activeCompany),
      );
    }

    bool matches(String candidate) =>
        candidate.trim().isNotEmpty &&
        _sameCode(_normalizeCompanyCode(candidate), normalized);

    if (matches(fromProfile)) {
      return (
        companyId: fromProfile,
        reason: 'active_profile_match',
        activeCompanyMasked: _maskLoginCode(activeCompany),
      );
    }
    if (matches(fromSession)) {
      return (
        companyId: fromSession,
        reason: 'active_session_match',
        activeCompanyMasked: _maskLoginCode(activeCompany),
      );
    }

    final knownDriverCompanies = drivers
        .map((d) => d.companyId?.trim() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet();
    for (final company in knownDriverCompanies) {
      if (!matches(company)) continue;
      return (
        companyId: company,
        reason: 'driver_scope_match',
        activeCompanyMasked: _maskLoginCode(activeCompany),
      );
    }

    return (
      companyId: null,
      reason: 'company_not_found',
      activeCompanyMasked: _maskLoginCode(activeCompany),
    );
  }

  String _normalizeCompanyCode(String raw) {
    var value = raw.trim().toUpperCase();
    value = value.replaceAll(RegExp(r'\s+'), '-');
    value = value.replaceAll(RegExp(r'-+'), '-');
    return value;
  }

  ({String kind, String companyCode, String code, String challengeId})?
  _parseDriverQrPayload(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'fluxidi') return null;
    final host = uri.host.toLowerCase();
    final companyCode = (uri.queryParameters['company_code'] ?? '')
        .trim()
        .toUpperCase();
    if (companyCode.isEmpty) return null;
    if (!RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(companyCode)) return null;
    if (host == 'driver-link') {
      final pairingCode = (uri.queryParameters['pairing_code'] ?? '').trim();
      final challengeId = (uri.queryParameters['challenge_id'] ?? '').trim();
      if (pairingCode.isEmpty) return null;
      return (
        kind: 'driver_link',
        companyCode: companyCode,
        code: pairingCode,
        challengeId: challengeId,
      );
    }
    if (host == 'driver-login') {
      final driverCode = (uri.queryParameters['driver_code'] ?? '').trim();
      if (driverCode.isEmpty) return null;
      return (
        kind: 'driver_login_legacy',
        companyCode: companyCode,
        code: driverCode,
        challengeId: '',
      );
    }
    return null;
  }

  Future<bool> _confirmDriverLinkQrUse({required String companyCode}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141B2F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _t(
            nl: 'Tijdelijke koppel-QR gebruiken?',
            en: 'Use temporary pairing QR?',
            fr: 'Utiliser le QR de liaison temporaire ?',
            es: '¿Usar QR temporal de vinculación?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Je gaat koppelen met bedrijfscode $companyCode. Deze QR is éénmalig bruikbaar.',
            en: 'You are about to pair with company code $companyCode. This QR is one-time use.',
            fr: 'Vous allez vous lier avec le code entreprise $companyCode. Ce QR est à usage unique.',
            es: 'Vas a vincularte con el código de empresa $companyCode. Este QR es de un solo uso.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _t(
                nl: 'Doorgaan',
                en: 'Continue',
                fr: 'Continuer',
                es: 'Continuar',
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _verifyDriverLinkFromQr({
    required String companyCode,
    required String pairingCode,
    String challengeId = '',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lookupError = null;
    });
    final response = await _verifyDriverPairingCode(
      companyCode: companyCode,
      pairingCode: pairingCode,
      challengeId: challengeId,
    );
    final responseOk = response['ok'] == true;
    final safeErrorCode =
        (response['error'] ?? response['reason'] ?? response['code'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    debugPrint(
      '[DRIVER_LINK_QR][VERIFY_HTTP_RES] response_ok=$responseOk error=$safeErrorCode',
    );
    if (!mounted) return;
    final payloadRaw = response['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : Map<String, dynamic>.from(response);
    final role = (payload['role'] ?? '').toString().trim().toLowerCase();
    final tenantId = (payload['tenant_id'] ?? '').toString().trim();
    final companyId = (payload['company_id'] ?? '').toString().trim();
    final resolvedCompanyCode =
        (payload['company_code'] ?? payload['companyCode'] ?? companyCode)
            .toString()
            .trim();
    final driverRaw = payload['driver'] is Map
        ? payload['driver']
        : (payload['driver_profile'] is Map
              ? payload['driver_profile']
              : (payload['driverSession'] is Map
                    ? payload['driverSession']
                    : null));
    final driverMap = driverRaw is Map
        ? Map<String, dynamic>.from(driverRaw)
        : <String, dynamic>{};
    final driverId =
        (driverMap['driver_id'] ??
                driverMap['driverId'] ??
                driverMap['id'] ??
                '')
            .toString()
            .trim();
    final driverName =
        (driverMap['driver_name'] ??
                driverMap['driverName'] ??
                driverMap['full_name'] ??
                driverMap['fullName'] ??
                driverMap['name'] ??
                '')
            .toString()
            .trim();
    final employeeNumberFromDriver =
        (driverMap['employee_number'] ??
                driverMap['employeeNumber'] ??
                driverMap['driver_code'] ??
                driverMap['driverCode'] ??
                driverMap['login_code'] ??
                driverMap['loginCode'] ??
                '')
            .toString()
            .trim();
    final employeeNumberFromPayload =
        (payload['employee_number'] ??
                payload['employeeNumber'] ??
                payload['driver_code'] ??
                payload['driverCode'] ??
                payload['login_code'] ??
                payload['loginCode'] ??
                '')
            .toString()
            .trim();
    var employeeNumber = employeeNumberFromDriver.isNotEmpty
        ? employeeNumberFromDriver
        : employeeNumberFromPayload;
    var employeeNumberSource = employeeNumberFromDriver.isNotEmpty
        ? 'driver'
        : (employeeNumberFromPayload.isNotEmpty ? 'payload' : 'missing');
    final hasCompanyCode = resolvedCompanyCode.isNotEmpty;
    final hasDriverId = driverId.isNotEmpty;
    if (response['ok'] != true) {
      debugPrint(
        '[DRIVER_LINK_QR][VERIFY_REJECT] reason=backend_ok_false error=$safeErrorCode',
      );
      debugPrint('[DRIVER_LINK_QR][VERIFY_REJECT] reason=response_not_ok');
      setState(() {
        _busy = false;
        _lookupError = _driverPairingInvalidText();
      });
      return;
    }
    final ok = response['ok'] == true || payload['ok'] == true;
    final hasStrictIdentity =
        ok &&
        role == 'driver' &&
        tenantId.isNotEmpty &&
        companyId.isNotEmpty &&
        resolvedCompanyCode.isNotEmpty &&
        driverId.isNotEmpty;
    if (employeeNumber.isEmpty &&
        hasStrictIdentity &&
        pairingCode.trim().isNotEmpty) {
      employeeNumber = pairingCode.trim();
      employeeNumberSource = 'temporary_qr_fallback';
    }
    final hasEmployeeNumber = employeeNumber.isNotEmpty;
    debugPrint(
      '[DRIVER_LINK_QR][VERIFY_RES] response_ok=${response['ok'] == true} has_payload=${payloadRaw is Map} role=$role has_driver=${driverMap.isNotEmpty} has_tenant=${tenantId.isNotEmpty} has_company=${companyId.isNotEmpty} has_company_code=$hasCompanyCode has_driver_id=$hasDriverId has_employee_number=$hasEmployeeNumber employee_number_source=$employeeNumberSource',
    );
    final assignedVehicleId =
        (driverMap['assigned_vehicle_id'] ??
                driverMap['assignedVehicleId'] ??
                '')
            .toString()
            .trim();
    final pairingDriverSessionToken =
        (payload['driver_session_token'] ?? payload['driverSessionToken'] ?? '')
            .toString()
            .trim();
    final pairingTokenExpiresAtRaw =
        (payload['driver_session_expires_at'] ??
                payload['driverSessionExpiresAtUtc'] ??
                payload['driver_session_expires_at_utc'] ??
                '')
            .toString()
            .trim();
    DateTime? pairingTokenExpiresAt = pairingTokenExpiresAtRaw.isEmpty
        ? null
        : DateTime.tryParse(pairingTokenExpiresAtRaw)?.toUtc();
    if (pairingTokenExpiresAt == null) {
      final expiresInRaw = (payload['expires_in'] ?? payload['expiresIn'] ?? '')
          .toString()
          .trim();
      final expiresInSeconds = int.tryParse(expiresInRaw);
      if (expiresInSeconds != null && expiresInSeconds > 0) {
        pairingTokenExpiresAt = DateTime.now().toUtc().add(
          Duration(seconds: expiresInSeconds),
        );
      }
    }
    if (!ok ||
        role != 'driver' ||
        tenantId.isEmpty ||
        companyId.isEmpty ||
        resolvedCompanyCode.isEmpty ||
        driverId.isEmpty ||
        employeeNumber.isEmpty) {
      debugPrint(
        '[DRIVER_LINK_QR][VERIFY_REJECT] reason=invalid_payload has_company_code=$hasCompanyCode has_driver_id=$hasDriverId has_employee_number=$hasEmployeeNumber employee_number_source=$employeeNumberSource',
      );
      setState(() {
        _busy = false;
        _lookupError = _driverPairingInvalidText();
      });
      return;
    }
    final issuedAt = DateTime.tryParse(
      (payload['issued_at'] ?? '').toString().trim(),
    );
    final expiresAt = DateTime.tryParse(
      (payload['expires_at'] ?? '').toString().trim(),
    );
    if (widget.openedFromBusinessHome) {
      await _completeBusinessDriverViewLogin(
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        employeeNumber: employeeNumber,
        fullName: driverName,
        companyCode: resolvedCompanyCode,
        assignedVehicleId: assignedVehicleId,
        driverSessionToken: pairingDriverSessionToken,
        driverSessionExpiresAtUtc: pairingTokenExpiresAt?.toIso8601String(),
      );
      return;
    }
    _logStandalonePhotoKeys(
      driverId: driverId,
      payload: payload,
      driverMap: driverMap,
    );
    final pairingPhoto = _extractStandaloneDriverPhotoFromPairingPayload(
      payload: payload,
      driverMap: driverMap,
    );
    final resolvedPairingPhoto = _resolveStandaloneDriverPhotoForSave(
      pairingPhoto.url,
    );
    debugPrint(
      '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskLoginCode(driverId)} photo=${resolvedPairingPhoto == null ? 'missing' : 'present'} source=${pairingPhoto.source}',
    );
    await DriverSessionStore.instance.saveVerifiedDriverPairingSession(
      tenantId: tenantId,
      companyId: companyId,
      companyCode: resolvedCompanyCode,
      driverId: driverId,
      driverName: driverName,
      employeeNumber: employeeNumber,
      assignedVehicleId: assignedVehicleId,
      driverPhotoUrl: resolvedPairingPhoto,
      driverSessionToken: pairingDriverSessionToken,
      driverSessionExpiresAtUtc: pairingTokenExpiresAt,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
    await _openDriverHomeAfterLogin(fromBusiness: false);
  }

  Future<void> _scanDriverLoginQr() async {
    if (_busy) return;
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DriverLoginQrScannerPage()),
    );
    if (!mounted || raw == null) return;
    final parsed = _parseDriverQrPayload(raw);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Ongeldige Fluxidi QR-code.',
              en: 'Invalid Fluxidi QR code.',
              fr: 'Code QR Fluxidi invalide.',
              es: 'Código QR de Fluxidi no válido.',
            ),
          ),
        ),
      );
      return;
    }
    if (parsed.kind == 'driver_login_legacy') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Deze QR is verouderd. Maak een tijdelijke koppel-QR.',
              en: 'This QR is outdated. Create a temporary pairing QR.',
              fr: 'Ce QR est obsolète. Créez un QR de liaison temporaire.',
              es: 'Este QR está obsoleto. Crea un QR temporal de vinculación.',
            ),
          ),
        ),
      );
      return;
    }
    final confirmed = await _confirmDriverLinkQrUse(
      companyCode: parsed.companyCode,
    );
    if (!mounted || !confirmed) return;
    _companyCtrl.text = parsed.companyCode;
    _suppressManualCodeSourceReset = true;
    _idCtrl.text = parsed.code;
    _suppressManualCodeSourceReset = false;
    setState(() {
      _manualCodeCameFromTemporaryQr = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Tijdelijke koppel-QR gelezen. Controle wordt uitgevoerd...',
            en: 'Temporary pairing QR read. Verifying...',
            fr: 'QR de liaison temporaire lu. Vérification...',
            es: 'QR temporal de vinculación leído. Verificando...',
          ),
        ),
      ),
    );
    await _verifyDriverLinkFromQr(
      companyCode: parsed.companyCode,
      pairingCode: parsed.code,
      challengeId: parsed.challengeId,
    );
  }

  String _normalizeLoginCode(String raw) => raw.trim().toLowerCase();

  String _maskLoginCode(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'empty';
    if (t.length <= 2) return '*' * t.length;
    return '${t[0]}***${t[t.length - 1]}(len=${t.length})';
  }

  bool _sameCode(String a, String b) {
    final na = _normalizeLoginCode(a);
    final nb = _normalizeLoginCode(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb;
  }

  bool _driverBelongsToActiveCompany(
    DriverProfile driver,
    String activeCompanyId,
  ) {
    final company = driver.companyId?.trim() ?? '';
    if (activeCompanyId.isEmpty) return company.isEmpty;
    return company.isNotEmpty && company == activeCompanyId;
  }

  bool _driverIsLegacyCompanyless(DriverProfile driver) =>
      (driver.companyId?.trim() ?? '').isEmpty;

  ({DriverProfile? match, String reason, int visibleCandidates})
  _findLocalDriverForLogin({
    required String entered,
    required String activeCompanyId,
    required List<DriverProfile> drivers,
  }) {
    final normalized = _normalizeLoginCode(entered);
    if (normalized.isEmpty) {
      return (match: null, reason: 'empty_input', visibleCandidates: 0);
    }
    if (drivers.isEmpty) {
      return (match: null, reason: 'no_drivers_loaded', visibleCandidates: 0);
    }

    final eligible = drivers
        .where((driver) {
          if (!driver.isActive) return false;
          final company = driver.companyId?.trim() ?? '';
          if (company.isEmpty) return true;
          if (activeCompanyId.isEmpty) return false;
          return company == activeCompanyId;
        })
        .toList(growable: false);
    if (eligible.isEmpty) {
      return (match: null, reason: 'scope_mismatch', visibleCandidates: 0);
    }

    for (final driver in eligible) {
      if (_driverBelongsToActiveCompany(driver, activeCompanyId) &&
          _sameCode(driver.employeeNumber, normalized)) {
        return (
          match: driver,
          reason: 'scoped_employee_code',
          visibleCandidates: eligible.length,
        );
      }
    }
    for (final driver in eligible) {
      if (_driverIsLegacyCompanyless(driver) &&
          _sameCode(driver.employeeNumber, normalized)) {
        return (
          match: driver,
          reason: 'legacy_employee_code',
          visibleCandidates: eligible.length,
        );
      }
    }
    for (final driver in eligible) {
      if (_driverBelongsToActiveCompany(driver, activeCompanyId) &&
          _sameCode(driver.id, normalized)) {
        return (
          match: driver,
          reason: 'scoped_internal_id',
          visibleCandidates: eligible.length,
        );
      }
    }
    for (final driver in eligible) {
      if (_driverIsLegacyCompanyless(driver) &&
          _sameCode(driver.id, normalized)) {
        return (
          match: driver,
          reason: 'legacy_internal_id',
          visibleCandidates: eligible.length,
        );
      }
    }
    return (
      match: null,
      reason: 'no_code_match',
      visibleCandidates: eligible.length,
    );
  }

  bool _driverChangedForLoginMigration(
    DriverProfile before,
    DriverProfile after,
  ) {
    return before.employeeNumber.trim() != after.employeeNumber.trim() ||
        (before.companyId?.trim() ?? '') != (after.companyId?.trim() ?? '');
  }

  DriverProfile _driverWithNormalizedLoginCode(
    DriverProfile driver, {
    String enteredCode = '',
  }) {
    final code = driver.employeeNumber.trim();
    if (code.isNotEmpty) return driver;
    final fallbackId = driver.id.trim();
    final fallbackInput = enteredCode.trim();
    final resolved = fallbackId.isNotEmpty ? fallbackId : fallbackInput;
    if (resolved.isEmpty) return driver;
    return driver.copyWith(employeeNumber: resolved);
  }

  String _driverPairingInvalidText() {
    return _t(
      nl: 'Chauffeurcode ongeldig of verlopen',
      en: 'Driver code is invalid or expired',
      fr: 'Le code chauffeur est invalide ou expiré',
      es: 'El código de conductor no es válido o ha caducado',
    );
  }

  Future<Map<String, dynamic>> _verifyDriverPairingCode({
    required String companyCode,
    required String pairingCode,
    String challengeId = '',
  }) async {
    final uri = Uri.parse('$kBookingBaseUrl/public/company/driver-link/verify');
    try {
      final response = await http
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'company_code': companyCode,
              'pairing_code': pairingCode,
              if (challengeId.trim().isNotEmpty) ...{
                'challenge_id': challengeId.trim(),
                'challengeId': challengeId.trim(),
              },
              'device_label': 'Tablet chauffeur',
              'device_type': 'tablet',
            }),
          )
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final ok = body['ok'] == true;
      final role = (body['role'] ?? '').toString().trim().toLowerCase();
      if (response.statusCode == 200 && ok && role == 'driver') {
        return <String, dynamic>{'ok': true, 'payload': body};
      }
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, String>?> _showDriverPairingSheet(BuildContext context) {
    final companyCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0B0B),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFE5B641),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE5B641).withOpacity(0.16),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t(
                        nl: 'Chauffeurcode',
                        en: 'Driver code',
                        fr: 'Code chauffeur',
                        es: 'Código de conductor',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: companyCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Bedrijfs-ID',
                          en: 'Company ID',
                          fr: 'ID d’entreprise',
                          es: 'ID de empresa',
                        ),
                        labelStyle: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF151515),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setSheetState(() => errorText = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Chauffeurcode',
                          en: 'Driver code',
                          fr: 'Code chauffeur',
                          es: 'Código de conductor',
                        ),
                        labelStyle: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF151515),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setSheetState(() => errorText = null);
                        }
                      },
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFFF8A8A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(
                            _t(
                              nl: 'Annuleren',
                              en: 'Cancel',
                              fr: 'Annuler',
                              es: 'Cancelar',
                            ),
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            final companyCode = _normalizeCompanyCode(
                              companyCtrl.text,
                            );
                            final pairingCode = codeCtrl.text.trim();
                            if (companyCode.isEmpty || pairingCode.isEmpty) {
                              setSheetState(
                                () => errorText = _driverPairingInvalidText(),
                              );
                              return;
                            }
                            Navigator.of(sheetContext).pop(<String, String>{
                              'company_code': companyCode,
                              'pairing_code': pairingCode,
                            });
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                          ),
                          child: Text(
                            _t(
                              nl: 'Code koppelen',
                              en: 'Link code',
                              fr: 'Lier le code',
                              es: 'Vincular código',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      companyCtrl.dispose();
      codeCtrl.dispose();
    });
  }

  Future<void> _submitPairingCodeFlow() async {
    if (_busy) return;
    final formData = await _showDriverPairingSheet(context);
    if (!mounted || formData == null) return;
    setState(() {
      _busy = true;
      _lookupError = null;
    });
    final response = await _verifyDriverPairingCode(
      companyCode: formData['company_code'] ?? '',
      pairingCode: formData['pairing_code'] ?? '',
    );
    if (!mounted) return;
    if (response['ok'] != true) {
      setState(() {
        _busy = false;
        _lookupError = _driverPairingInvalidText();
      });
      return;
    }
    final payload = response['payload'] is Map
        ? Map<String, dynamic>.from(response['payload'] as Map)
        : <String, dynamic>{};
    final tenantId = (payload['tenant_id'] ?? '').toString().trim();
    final companyId = (payload['company_id'] ?? '').toString().trim();
    final companyCode = (payload['company_code'] ?? '').toString().trim();
    final role = (payload['role'] ?? '').toString().trim().toLowerCase();
    final ok = payload['ok'] == true;
    final driverMap = payload['driver'] is Map
        ? Map<String, dynamic>.from(payload['driver'] as Map)
        : <String, dynamic>{};
    final driverId = (driverMap['driver_id'] ?? '').toString().trim();
    final driverName = (driverMap['driver_name'] ?? '').toString().trim();
    final employeeNumber = (driverMap['employee_number'] ?? '')
        .toString()
        .trim();
    final assignedVehicleId =
        (driverMap['assigned_vehicle_id'] ??
                driverMap['assignedVehicleId'] ??
                '')
            .toString()
            .trim();
    final pairingDriverSessionToken =
        (payload['driver_session_token'] ?? payload['driverSessionToken'] ?? '')
            .toString()
            .trim();
    final pairingTokenExpiresAtRaw =
        (payload['driver_session_expires_at'] ??
                payload['driverSessionExpiresAtUtc'] ??
                payload['driver_session_expires_at_utc'] ??
                '')
            .toString()
            .trim();
    DateTime? pairingTokenExpiresAt = pairingTokenExpiresAtRaw.isEmpty
        ? null
        : DateTime.tryParse(pairingTokenExpiresAtRaw)?.toUtc();
    if (pairingTokenExpiresAt == null) {
      final expiresInRaw = (payload['expires_in'] ?? payload['expiresIn'] ?? '')
          .toString()
          .trim();
      final expiresInSeconds = int.tryParse(expiresInRaw);
      if (expiresInSeconds != null && expiresInSeconds > 0) {
        pairingTokenExpiresAt = DateTime.now().toUtc().add(
          Duration(seconds: expiresInSeconds),
        );
      }
    }
    if (!ok ||
        role != 'driver' ||
        tenantId.isEmpty ||
        companyId.isEmpty ||
        companyCode.isEmpty ||
        driverId.isEmpty ||
        employeeNumber.isEmpty) {
      setState(() {
        _busy = false;
        _lookupError = _driverPairingInvalidText();
      });
      return;
    }
    final issuedAt = DateTime.tryParse(
      (payload['issued_at'] ?? '').toString().trim(),
    );
    final expiresAt = DateTime.tryParse(
      (payload['expires_at'] ?? '').toString().trim(),
    );
    if (widget.openedFromBusinessHome) {
      await _completeBusinessDriverViewLogin(
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        employeeNumber: employeeNumber,
        fullName: driverName,
        companyCode: companyCode,
        assignedVehicleId: assignedVehicleId,
        driverSessionToken: pairingDriverSessionToken,
        driverSessionExpiresAtUtc: pairingTokenExpiresAt?.toIso8601String(),
      );
      return;
    }
    _logStandalonePhotoKeys(
      driverId: driverId,
      payload: payload,
      driverMap: driverMap,
    );
    final pairingPhoto = _extractStandaloneDriverPhotoFromPairingPayload(
      payload: payload,
      driverMap: driverMap,
    );
    final resolvedPairingPhoto = _resolveStandaloneDriverPhotoForSave(
      pairingPhoto.url,
    );
    debugPrint(
      '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskLoginCode(driverId)} photo=${resolvedPairingPhoto == null ? 'missing' : 'present'} source=${pairingPhoto.source}',
    );
    await DriverSessionStore.instance.saveVerifiedDriverPairingSession(
      tenantId: tenantId,
      companyId: companyId,
      companyCode: companyCode,
      driverId: driverId,
      driverName: driverName,
      employeeNumber: employeeNumber,
      assignedVehicleId: assignedVehicleId,
      driverPhotoUrl: resolvedPairingPhoto,
      driverSessionToken: pairingDriverSessionToken,
      driverSessionExpiresAtUtc: pairingTokenExpiresAt,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
    await _openDriverHomeAfterLogin(fromBusiness: false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RoleEntryPage()),
                    );
                  },
          ),
          title: Text(
            _t(
              nl: 'Chauffeur login',
              en: 'Driver login',
              fr: 'Connexion chauffeur',
              es: 'Acceso conductor',
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Vul de bedrijfscode en je chauffeurcode in. Werkt ook op een nieuw toestel zodra de chauffeur door het bedrijf is aangemaakt.',
                            en: 'Enter the company ID and your driver code. This also works on a new device once the driver has been created by the company.',
                            fr: 'Entrez le code entreprise et votre code chauffeur. Cela fonctionne aussi sur un nouvel appareil dès que le chauffeur est créé par l’entreprise.',
                            es: 'Introduce el código de empresa y tu código de conductor. Esto también funciona en un dispositivo nuevo cuando la empresa ya creó al conductor.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _companyCtrl,
                          enabled: !_busy,
                          style: const TextStyle(color: Colors.white),
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: _t(
                              nl: 'Bedrijfscode',
                              en: 'Company ID',
                              fr: 'Code entreprise',
                              es: 'Código de empresa',
                            ),
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF141B2F),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return _t(
                                nl: 'Vul je bedrijfscode in.',
                                en: 'Enter your company ID.',
                                fr: 'Saisissez votre code entreprise.',
                                es: 'Introduce tu código de empresa.',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _idCtrl,
                          enabled: !_busy,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_busy) unawaited(_submit());
                          },
                          decoration: InputDecoration(
                            labelText: _t(
                              nl: 'Vaste chauffeurcode',
                              en: 'Fixed driver code',
                              fr: 'Code chauffeur fixe',
                              es: 'Código fijo de conductor',
                            ),
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF141B2F),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return _t(
                                nl: 'Vul je vaste chauffeurcode in.',
                                en: 'Enter your fixed driver code.',
                                fr: 'Saisissez votre code chauffeur fixe.',
                                es: 'Introduce tu código fijo de conductor.',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            nl: 'Handmatig inloggen is alleen voor een vaste chauffeurcode. Tijdelijke QR/koppelcodes worden automatisch verwerkt via QR-scan. Werkt de scan niet, scan opnieuw of vraag een nieuwe tijdelijke koppelcode.',
                            en: 'Manual login is only for a fixed driver code. Temporary QR/pairing codes are processed automatically via QR scan. If verification fails, rescan or request a new temporary pairing code.',
                            fr: 'La connexion manuelle est uniquement pour un code chauffeur fixe. Les codes QR/de liaison temporaires sont traités automatiquement via scan QR. En cas d’échec, rescannez ou demandez un nouveau code temporaire.',
                            es: 'El inicio manual es solo para un código fijo de conductor. Los códigos temporales QR/de vinculación se procesan automáticamente por escaneo QR. Si falla la verificación, vuelve a escanear o solicita un nuevo código temporal.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => unawaited(_scanDriverLoginQr()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE5B641),
                            side: const BorderSide(
                              color: Color(0xFFE5B641),
                              width: 1.2,
                            ),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _t(
                              nl: 'Scan bedrijfs QR',
                              en: 'Scan company QR',
                              fr: 'Scanner QR entreprise',
                              es: 'Escanear QR de empresa',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_lookupError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _lookupError!,
                            style: const TextStyle(
                              color: Color(0xFFFF8A8A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  unawaited(_submit());
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black54,
                                  ),
                                )
                              : Text(
                                  _t(
                                    nl: 'Inloggen als chauffeur',
                                    en: 'Log in as driver',
                                    fr: 'Se connecter comme chauffeur',
                                    es: 'Iniciar sesión como conductor',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  unawaited(_submitPairingCodeFlow());
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE5B641),
                            side: const BorderSide(
                              color: Color(0xFFE5B641),
                              width: 1.2,
                            ),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _t(
                              nl: 'Ik heb een chauffeurcode',
                              en: 'I have a driver code',
                              fr: 'J’ai un code chauffeur',
                              es: 'Tengo un código de conductor',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
