part of '../main.dart';

class ChauffeurLoginPage extends StatefulWidget {
  const ChauffeurLoginPage({super.key, this.openedFromBusinessHome = false,
    this.deviceDutyTarget, this.deviceDutyDriverName, this.retainedCompanyScope,
    @visibleForTesting this.driverDashboardBuilder});

  final bool openedFromBusinessHome;
  final DriverDutyIdentity? deviceDutyTarget;
  final String? deviceDutyDriverName;
  /// Presentation/scope lock after personal logout; never an authentication credential.
  final ({String tenantId, String companyId, String companyCode})? retainedCompanyScope;
  final WidgetBuilder? driverDashboardBuilder;

  @override
  State<ChauffeurLoginPage> createState() => _ChauffeurLoginPageState();
}

class _BackendDriverLoginOutcome {
  const _BackendDriverLoginOutcome.ok(this.login) : error = '';
  const _BackendDriverLoginOutcome.fail(this.error) : login = null;

  final _BackendDriverLoginResult? login;
  final String error;
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
  final _loginPinCtrl = TextEditingController();
  bool _showPin = false;
  bool _showFixedCode = false;
  bool _directoryLoading = false;
  bool _directoryVerified = false;
  bool _deviceVerified = false;
  String? _pendingDeviceTransition;
  bool _personalHints = false;
  CustomerAppHeaderBranding? _loginBranding;
  bool _busy = false;
  String? _lookupError;
  Map<String, dynamic>? _vehicleDriverChoices;
  String? _selectedVehicleDriverId;
  bool _usingVehiclePin = false;
  int _driverChoicesEpoch = 0;
  bool _companyDriverContext = false;
  bool _vehiclePinScopeMatches = false;

  Map<String, dynamic>? _personalPinScope() {
    final choices = _vehicleDriverChoices;
    if (choices == null || ['tenant_id', 'company_id'].any((key) =>
        choices[key] is! String || (choices[key] as String).trim().isEmpty)) return null;
    return {'tenant_id': choices['tenant_id'], 'company_id': choices['company_id'],
      'pin_kind': 'personal'};
  }

  Future<Map<String, dynamic>?> _loginPinScope() async {
    final personal = _personalPinScope();
    final driver = _selectedVehicleDriverId;
    if (personal != null && driver != null &&
        await DriverPersonalPinStore().hasPin(personal, driver)) return personal;
    Map<String, dynamic>? paired;
    try { paired = await VehicleDeviceStore().pinScope(); } catch (_) {}
    if (paired != null && _pinScopeMatchesChoices(paired)) return paired;
    return personal;
  }

  VehicleDriverPinStore _pinStore(Map<String, dynamic> scope) =>
      scope['pin_kind'] == 'personal' ? DriverPersonalPinStore() : VehicleDriverPinStore();

  bool _samePinScope(Map<String, dynamic> a, Map<String, dynamic>? b) =>
      b != null && a['pin_kind'] == b['pin_kind'] &&
      (a['pin_kind'] == 'personal'
        ? a['tenant_id'] == b['tenant_id'] && a['company_id'] == b['company_id']
        : _sameDeviceScope(a, b));

  Future<String?> _askVehiclePin({required bool enroll}) async {
    final pin = TextEditingController();
    final confirmation = TextEditingController();
    final form = GlobalKey<FormState>();
    try {
      final route = DialogRoute<String>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(_t(nl: enroll ? 'Persoonlijke pincode instellen' : 'Aanmelden met pincode', en: enroll ? 'Set personal PIN' : 'Sign in with PIN', fr: enroll ? 'Créer votre code PIN' : 'Connexion par PIN', es: enroll ? 'Crear PIN personal' : 'Entrar con PIN')),
        content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_t(nl: enroll ? 'Kies zes cijfers voor jouw profiel op dit toestel. Deel deze pincode niet.' : 'Vul jouw persoonlijke pincode van zes cijfers in.', en: enroll ? 'Choose six digits for your profile on this device. Keep this PIN private.' : 'Enter your personal six-digit PIN.', fr: enroll ? 'Choisissez six chiffres pour votre profil sur cet appareil. Gardez ce PIN privé.' : 'Saisissez votre PIN personnel à six chiffres.', es: enroll ? 'Elige seis cifras para tu perfil en este dispositivo. No compartas este PIN.' : 'Introduce tu PIN personal de seis cifras.')),
          TextFormField(key: const ValueKey('vehicle_personal_pin'), controller: pin, obscureText: true, enableSuggestions: false, autocorrect: false, keyboardType: TextInputType.number, maxLength: 6,
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '') ? null : _t(nl: 'Gebruik zes cijfers.', en: 'Use six digits.', de: 'Verwende sechs Ziffern.', fr: 'Utilisez six chiffres.', es: 'Usa seis cifras.')),
          if (enroll) TextFormField(key: const ValueKey('vehicle_personal_pin_confirm'), controller: confirmation, obscureText: true, enableSuggestions: false, autocorrect: false, keyboardType: TextInputType.number, maxLength: 6,
            decoration: InputDecoration(labelText: _t(nl: 'Herhaal pincode', en: 'Repeat PIN', de: 'PIN wiederholen', fr: 'Répéter le PIN', es: 'Repite el PIN')),
            validator: (value) => value == pin.text ? null : _t(nl: 'Pincodes verschillen.', en: 'PINs differ.', de: 'Die PINs stimmen nicht überein.', fr: 'Les PIN diffèrent.', es: 'Los PIN son distintos.')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t(nl: 'Annuleren', en: 'Cancel', de: 'Abbrechen', fr: 'Annuler', es: 'Cancelar'))),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(dialogContext, pin.text); }, child: Text(_t(nl: 'Doorgaan', en: 'Continue', de: 'Weiter', fr: 'Continuer', es: 'Continuar'))),
        ],
      ));
      final result = await Navigator.of(context).push(route);
      await route.completed;
      return result;
    } finally { pin.dispose(); confirmation.dispose(); }
  }

  Future<void> _unlockVehicleDriver({String? enteredPin}) async {
    if (_busy || _selectedVehicleDriverId == null || !_vehiclePinScopeMatches) return;
    if (enteredPin != null && !RegExp(r'^\d{6}$').hasMatch(enteredPin)) return;
    final driverId = _selectedVehicleDriverId!;
    final epoch = _driverChoicesEpoch;
    setState(() { _busy = true; _lookupError = null; });
    try {
      final scope = await _loginPinScope();
      if (scope == null) throw StateError('vehicle_device_missing');
      final store = _pinStore(scope);
      if (!await store.hasPin(scope, driverId)) {
        if (mounted && epoch == _driverChoicesEpoch) setState(() => _lookupError = _t(nl: 'Meld je eerst één keer aan met je vaste chauffeurscode. Daarna kun je jouw pincode instellen.', en: 'First sign in once with your fixed driver code, then set your PIN.', de: 'Melde dich zuerst mit deinem festen Fahrercode an und lege dann deine PIN fest.', fr: 'Connectez-vous une fois avec votre code chauffeur, puis créez votre PIN.', es: 'Entra una vez con tu código de conductor y configura tu PIN.'));
        return;
      }
      if (!mounted) return;
      final pin = enteredPin ?? await _askVehiclePin(enroll: false);
      _loginPinCtrl.clear();
      if (pin == null || !mounted || epoch != _driverChoicesEpoch ||
          driverId != _selectedVehicleDriverId ||
          !_samePinScope(scope, await _loginPinScope())) return;
      final credential = await store.unlockForLogin(scope, driverId, pin);
      if (credential == null) throw StateError('vehicle_pin_incorrect');
      if (!_samePinScope(scope, await _loginPinScope())) return;
      if (!mounted || epoch != _driverChoicesEpoch || driverId != _selectedVehicleDriverId ||
          !_samePinScope(scope, await _loginPinScope())) return;
      if (!_acceptRetainedCompanyCode(credential.companyCode)) return;
      if (credential.serverSession != null) {
        final deviceScope = await _retainedAuthDeviceScope();
        final verified = await credential.serverSession!.verify();
        if (!_loginReplyIsCurrent(epoch, driverId) ||
            !await _retainedAuthDeviceIsCurrent(deviceScope) ||
            !_loginReplyIsCurrent(epoch, driverId) ||
            !_samePinScope(scope, await _loginPinScope()) ||
            !_loginReplyIsCurrent(epoch, driverId) ||
            !_acceptDeviceDutyActor(tenantId: verified.tenantId!,
              companyId: verified.companyId!, driverId: verified.driverId,
              vehicleId: verified.assignedVehicleId ?? '')) return;
        await DriverSessionStore.instance.saveVerifiedDriverPairingSession(
          tenantId: verified.tenantId!, companyId: verified.companyId!,
          companyCode: verified.companyCode!, driverId: verified.driverId,
          driverName: verified.fullName, employeeNumber: verified.driverId,
          assignedVehicleId: verified.assignedVehicleId,
          driverPhotoUrl: verified.driverPhotoUrl,
          driverSessionToken: verified.driverSessionToken,
          driverSessionExpiresAtUtc: DateTime.parse(verified.driverSessionExpiresAtUtc!),
        );
        if (_loginReplyIsCurrent(epoch, driverId)) {
          await _openDriverHomeAfterLogin(fromBusiness: false);
        }
        return;
      }
      _companyCtrl.text = credential.companyCode;
      _idCtrl.text = credential.driverCode;
      _usingVehiclePin = true;
      try { await _submit(); } finally {
        _usingVehiclePin = false;
        if (mounted) {
          final error = _lookupError;
          _idCtrl.clear();
          setState(() => _lookupError = error);
        }
      }
    } catch (error) {
      if (mounted && epoch == _driverChoicesEpoch) setState(() => _lookupError = error is StateError && error.message == 'vehicle_pin_locked'
        ? _t(nl: 'Te veel pogingen. Probeer over 15 minuten opnieuw of gebruik jouw vaste chauffeurscode.', en: 'Too many attempts. Try again in 15 minutes or use your fixed driver code.', de: 'Zu viele Versuche. Versuche es in 15 Minuten erneut oder verwende deinen festen Fahrercode.', fr: 'Trop de tentatives. Réessayez dans 15 minutes ou utilisez votre code chauffeur.', es: 'Demasiados intentos. Espera 15 minutos o usa tu código de conductor.')
        : _t(nl: 'Pincode onjuist of niet beschikbaar. Je kunt je vaste chauffeurscode gebruiken.', en: 'PIN incorrect or unavailable. You can use your fixed driver code.', de: 'PIN falsch oder nicht verfügbar. Du kannst deinen festen Fahrercode verwenden.', fr: 'PIN incorrect ou indisponible. Utilisez votre code chauffeur.', es: 'PIN incorrecto o no disponible. Usa tu código de conductor.'));
    } finally { if (mounted && epoch == _driverChoicesEpoch) setState(() => _busy = false); }
  }

  Future<void> _offerVehiclePin(_BackendDriverLoginResult login, String companyCode, String driverCode) async {
    if (_usingVehiclePin || widget.openedFromBusinessHome ||
        !const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI')) return;
    final epoch = _driverChoicesEpoch;
    final selected = _selectedVehicleDriverId;
    final verificationAge = Stopwatch()..start();
    bool verificationIsFresh() => verificationAge.elapsed < const Duration(minutes: 5);
    try {
      final deviceScope = await _retainedAuthDeviceScope();
      // Scope comes from the successful server response, including first-time
      // logins without a preloaded picker and drivers with another vehicle.
      final scope = <String, dynamic>{'tenant_id': login.tenantId,
        'company_id': login.companyId, 'pin_kind': 'personal'};
      if (!_loginReplyIsCurrent(epoch, selected) || !_acceptDeviceDutyActor(
          tenantId: login.tenantId, companyId: login.companyId,
          driverId: login.driverId, vehicleId: login.assignedVehicleId)) return;
      final store = DriverPersonalPinStore();
      await store.rememberVerifiedDriver(scope, login.driverId, login.driverName, companyCode);
      if (await store.hasPin(scope, login.driverId) || !_loginReplyIsCurrent(epoch, selected)) return;
      final pin = await _askVehiclePin(enroll: true);
      if (pin != null && verificationIsFresh() && _loginReplyIsCurrent(epoch, selected) &&
          await _retainedAuthDeviceIsCurrent(deviceScope) && verificationIsFresh() && _loginReplyIsCurrent(epoch, selected)) {
        await store.enroll(scope, login.driverId, companyCode, driverCode, pin,
          stillAuthorized: () async => _loginReplyIsCurrent(epoch, selected) &&
            await _retainedAuthDeviceIsCurrent(deviceScope) && verificationIsFresh() && _loginReplyIsCurrent(epoch, selected));
        if (_loginReplyIsCurrent(epoch, selected)) await store.rememberDriver(scope, login.driverId, login.driverName);
      }
    } catch (_) {
      if (mounted && epoch == _driverChoicesEpoch) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t(nl: 'Pincode niet opgeslagen. Aanmelden met je vaste code blijft mogelijk.', en: 'PIN not saved. You can still sign in with your fixed code.', de: 'PIN nicht gespeichert. Du kannst dich weiterhin mit deinem festen Code anmelden.', fr: 'PIN non enregistré. Votre code chauffeur reste utilisable.', es: 'PIN no guardado. Puedes usar tu código de conductor.'))));
    }
  }

  Future<void> _offerPinAfterPairing({required String verifiedToken, required DateTime? verifiedExpiry}) async {
    if (widget.openedFromBusinessHome ||
        !const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI')) return;
    final session = activeDriverSessionNotifier.value;
    if (session == null || !session.isStandaloneLoginSession ||
        verifiedToken.isEmpty || session.driverSessionToken != verifiedToken ||
        verifiedExpiry == null || !verifiedExpiry.isAfter(DateTime.now())) return;
    final epoch = _driverChoicesEpoch;
    final selected = _selectedVehicleDriverId;
    try {
      final verification = FreshDriverPinSetup(session);
      await DriverPersonalPinStore().rememberVerifiedDriver({
        'tenant_id': session.tenantId, 'company_id': session.companyId,
      }, session.driverId, session.fullName, session.companyCode ?? '');
      if (!_loginReplyIsCurrent(epoch, selected)) return;
      final proceed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(_t(nl: 'Persoonlijke pincode instellen', en: 'Set personal PIN', de: 'Persönliche PIN festlegen', fr: 'Créer votre code PIN', es: 'Crear PIN personal')),
        content: Text(_t(nl: 'Wil je voor dit chauffeurprofiel een PIN instellen of herstellen? Een tijdelijke QR-code wordt nooit als vaste inlogcode bewaard.',
          en: 'Set or recover a PIN for this driver profile? A temporary QR code is never saved as a fixed login code.', de: 'PIN für dieses Fahrerprofil festlegen oder wiederherstellen? Ein temporärer QR-Code wird niemals als fester Anmeldecode gespeichert.',
          fr: 'Créer ou récupérer le PIN de ce chauffeur ? Le QR temporaire ne sera pas conservé comme code permanent.',
          es: '¿Crear o recuperar el PIN de este conductor? El QR temporal nunca se guarda como código permanente.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t(nl: 'Later', en: 'Later', de: 'Später', fr: 'Plus tard', es: 'Más tarde'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t(nl: 'PIN instellen', en: 'Set PIN', de: 'PIN festlegen', fr: 'Créer le PIN', es: 'Crear PIN'))),
        ],
      ));
      if (proceed == true && mounted && _loginReplyIsCurrent(epoch, selected) &&
          activeDriverSessionNotifier.value?.driverSessionToken == session.driverSessionToken) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
          DriverPersonalPinPage(session: session, freshVerification: verification)));
      }
    } catch (_) {
      // Login remains valid if optional PIN setup or encrypted hints fail.
    }
  }

  bool _retainedScopeMatches(Map<String, dynamic>? scope) {
    final retained = widget.retainedCompanyScope;
    return retained == null || (scope != null &&
        scope['tenant_id'] == retained.tenantId &&
        scope['company_id'] == retained.companyId);
  }

  bool _sameDeviceScope(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
      a != null && b != null &&
      ['tenant_id', 'company_id', 'vehicle_id', 'device_id']
          .every((key) => a[key] == b[key]);

  bool _loginReplyIsCurrent(int epoch, String? selectedDriver) {
    if (!mounted) return false;
    if (epoch == _driverChoicesEpoch && selectedDriver == _selectedVehicleDriverId) return true;
    return false;
  }

  Future<Map<String, dynamic>?> _retainedAuthDeviceScope() async {
    if (widget.retainedCompanyScope == null) return null;
    try {
      final scope = await VehicleDeviceStore().pinScope();
      return _retainedScopeMatches(scope) ? scope : null;
    } catch (_) { return null; }
  }

  Future<bool> _retainedAuthDeviceIsCurrent(Map<String, dynamic>? captured) async {
    if (captured == null) return true;
    final current = await _retainedAuthDeviceScope();
    if (_sameDeviceScope(captured, current)) return true;
    if (mounted) setState(() {
      _busy = false;
      _vehicleDriverChoices = null;
      _selectedVehicleDriverId = null;
      _vehiclePinScopeMatches = false;
      _directoryVerified = false;
      _deviceVerified = false;
      _personalHints = false;
      _loginBranding = null;
      _lookupError = _t(nl: 'Voertuigkoppeling gewijzigd. Meld je opnieuw aan.',
          en: 'Vehicle pairing changed. Sign in again.', de: 'Die Fahrzeugbindung wurde geändert. Melde dich erneut an.', fr: 'La liaison du véhicule a changé. Reconnectez-vous.',
          es: 'La vinculación del vehículo cambió. Vuelve a iniciar sesión.');
    });
    return false;
  }

  bool _acceptRetainedCompanyCode(String code) {
    final retained = widget.retainedCompanyScope;
    if (retained == null) return true;
    final expected = _normalizeCompanyCode(_companyCtrl.text);
    if (expected.isNotEmpty && _normalizeCompanyCode(code) == expected) return true;
    if (mounted) setState(() => _lookupError = _t(
      nl: 'Deze chauffeurcode hoort niet bij dit bedrijf.',
      en: 'This driver code does not belong to this company.', de: 'Dieser Fahrercode gehört nicht zu diesem Unternehmen.',
      fr: 'Ce code chauffeur ne correspond pas à cette entreprise.',
      es: 'Este código de conductor no corresponde a esta empresa.'));
    return false;
  }

  Future<void> _loadVehicleDriverChoices() async {
    final epoch = ++_driverChoicesEpoch;
    final pendingTransition = await VehicleDeviceStore().pendingTransitionOperation();
    if (!mounted || epoch != _driverChoicesEpoch) return;
    setState(() => _pendingDeviceTransition = pendingTransition);
    final session = resolveCompanyOpsLocalSession();
    final companyId = session.companyId.trim();
    final token = session.sessionToken.trim();
    final activeCompanyId = activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    final target = widget.deviceDutyTarget;
    final retained = widget.retainedCompanyScope;
    final companyContext = _companyDriverContext || target != null || retained != null ||
        companyId.isNotEmpty || activeCompanyId.isNotEmpty ||
        (companyOpsLocalSessionNotifier.value?.companyId.trim().isNotEmpty ?? false);
    _companyDriverContext = companyContext;
    var companyDirectory = false;
    var personalHints = false;
    if (mounted) setState(() {
      _directoryLoading = true;
      _directoryVerified = false;
      _deviceVerified = false;
      _personalHints = false;
      _loginBranding = null;
      _loginPinCtrl.clear();
      _vehicleDriverChoices = null;
      _selectedVehicleDriverId = null;
      _vehiclePinScopeMatches = false;
      _lookupError = null;
      if (retained != null) _companyCtrl.text = retained.companyCode;
    });
    bool current() {
      final now = resolveCompanyOpsLocalSession();
      return mounted && epoch == _driverChoicesEpoch &&
          retained == widget.retainedCompanyScope &&
          ((retained == null || companyDirectory) && companyContext
              ? now.companyId.trim() == companyId &&
                  now.sessionToken.trim() == token &&
                  (activeCompanySessionNotifier.value?.companyId.trim() ?? '') == activeCompanyId
              : true);
    }
    try {
      Map<String, dynamic>? choices;
      Map<String, dynamic>? capturedDeviceScope;
      if (retained != null) {
        if (retained.tenantId.isEmpty || retained.companyId.isEmpty) {
          throw StateError('company_driver_picker_session_scope_mismatch');
        }
        companyDirectory = companyId == retained.companyId && token.isNotEmpty &&
            (activeCompanyId.isEmpty || activeCompanyId == retained.companyId);
        if (companyDirectory) {
          choices = await fetchCompanyDriverPicker(bookingBaseUrl: appConfig.bookingBaseUrl,
              tenantId: retained.tenantId, companyId: retained.companyId, sessionToken: token);
          choices['vehicle_id'] = '';
          choices['vehicle_label'] = _t(nl: 'Chauffeurs bij dit bedrijf', en: 'Drivers at this company', de: 'Fahrer dieses Unternehmens',
              fr: 'Chauffeurs de cette entreprise', es: 'Conductores de esta empresa');
        } else {
          capturedDeviceScope = await VehicleDeviceStore().pinScope();
          if (!_retainedScopeMatches(capturedDeviceScope) || capturedDeviceScope == null) {
            capturedDeviceScope = null;
            choices = await DriverPersonalPinStore().rememberedChoices({
              'tenant_id': retained.tenantId, 'company_id': retained.companyId});
            personalHints = choices != null;
            if (choices == null) throw StateError('company_driver_picker_session_scope_mismatch');
          } else {
            choices = await VehicleDeviceStore().driverChoices(appConfig.bookingBaseUrl);
          }
          if (!_retainedScopeMatches(choices)) {
            throw StateError('company_driver_picker_session_scope_mismatch');
          }
        }
      } else if (companyContext) {
        companyDirectory = true;
        if (companyId.isEmpty || token.isEmpty ||
            (activeCompanyId.isNotEmpty && activeCompanyId != companyId) ||
            (target != null && (target.companyId != companyId || target.tenantId != companyId))) {
          throw StateError('company_driver_picker_session_scope_mismatch');
        }
        choices = await fetchCompanyDriverPicker(bookingBaseUrl: appConfig.bookingBaseUrl,
          tenantId: companyId, companyId: companyId, sessionToken: token);
        choices['vehicle_id'] = target?.vehicleId ?? '';
        choices['vehicle_label'] = _t(nl: 'Chauffeurs bij dit bedrijf', en: 'Drivers at this company', de: 'Fahrer dieses Unternehmens',
          fr: 'Chauffeurs de cette entreprise', es: 'Conductores de esta empresa');
      } else {
        capturedDeviceScope = await VehicleDeviceStore().pinScope();
        personalHints = capturedDeviceScope == null;
        choices = capturedDeviceScope == null ? await DriverPersonalPinStore().preferredChoices()
            : await VehicleDeviceStore().driverChoices(appConfig.bookingBaseUrl);
      }
      if (!current()) return;
      Map<String, dynamic>? pinScope;
      try { pinScope = await VehicleDeviceStore().pinScope(); } catch (_) {}
      if (!current()) return;
      if (!companyDirectory && capturedDeviceScope != null &&
          !_sameDeviceScope(capturedDeviceScope, pinScope)) {
        throw StateError('company_driver_picker_session_scope_mismatch');
      }
      if (retained != null && choices != null && _retainedScopeMatches(pinScope)) {
        choices['vehicle_id'] = pinScope?['vehicle_id'] ?? '';
      }
      setState(() {
        _directoryLoading = false;
        _directoryVerified = choices != null && !personalHints;
        _personalHints = choices != null && personalHints;
        _deviceVerified = choices != null && capturedDeviceScope != null &&
            _sameDeviceScope(capturedDeviceScope, pinScope);
        _vehicleDriverChoices = choices; _selectedVehicleDriverId = null;
        _vehiclePinScopeMatches = (pinScope != null && _pinScopeMatchesChoices(pinScope)) ||
            _personalPinScope() != null;
        if (choices?['company_code'] is String) _companyCtrl.text = choices!['company_code'] as String;
        if (retained != null) {
          if (retained.companyCode.isNotEmpty) _companyCtrl.text = retained.companyCode;
          else if (companyDirectory && activeCompanySessionNotifier.value?.companyId == retained.companyId) {
            _companyCtrl.text = activeCompanySessionNotifier.value?.companyCode ?? '';
          }
        } else if (companyContext && activeCompanySessionNotifier.value?.companyId == companyId) {
          _companyCtrl.text = activeCompanySessionNotifier.value?.companyCode ?? '';
        }
      });
      if (choices != null && !personalHints && current()) {
        unawaited(_loadLoginBranding(epoch, choices));
      }
    } catch (_) {
      if (current()) setState(() {
        _directoryLoading = false;
        _lookupError = _t(nl: 'Chauffeurslijst niet beschikbaar. Controleer de bedrijfssessie of voertuigkoppeling.', en: 'Driver list unavailable. Check the company session or vehicle pairing.', de: 'Fahrerliste nicht verfügbar. Prüfe die Unternehmenssitzung oder Fahrzeugbindung.', fr: 'Liste des chauffeurs indisponible. Vérifiez la session entreprise ou la liaison.', es: 'Lista de conductores no disponible. Comprueba la sesión de empresa o la vinculación.');
      });
    }
  }

  Future<void> _loadLoginBranding(int epoch, Map<String, dynamic> choices) async {
    final presentation = choices['company_presentation'];
    if (presentation is Map && _deviceVerified) {
      final scope = await VehicleDeviceStore().pinScope();
      if (!mounted || epoch != _driverChoicesEpoch || !identical(choices,_vehicleDriverChoices) ||
          !_directoryVerified || scope == null || !_pinScopeMatchesChoices(scope)) return;
      final branding = CustomerAppHeaderBranding.fromJson(Map<String,dynamic>.from(presentation));
      if (branding.companyName.isNotEmpty) {
        setState(()=>_loginBranding=branding);
        return;
      }
    }
    // One bounded public presentation read per verified directory load. No auth
    // or stored theme changes; public branding cannot authorize a driver/device.
    final owner = activeCompanySessionNotifier.value;
    final retained = widget.retainedCompanyScope;
    final personal = activeDriverSessionNotifier.value;
    final trustedCode = choices['company_code'] ??
        (retained?.tenantId == choices['tenant_id'] && retained?.companyId == choices['company_id']
            ? retained?.companyCode : null) ??
        (personal?.tenantId == choices['tenant_id'] && personal?.companyId == choices['company_id']
            ? personal?.companyCode : null) ??
        (owner?.companyId == choices['tenant_id'] && owner?.companyId == choices['company_id']
            ? owner?.companyCode : null);
    final code = _normalizeCompanyCode((trustedCode ?? '').toString());
    if (code.isEmpty) return;
    try {
      final expectsDevice = _deviceVerified;
      final deviceScope = expectsDevice ? await VehicleDeviceStore().pinScope() : null;
      if (expectsDevice && (deviceScope == null || !_pinScopeMatchesChoices(deviceScope))) return;
      final response = await http.get(Uri.parse(appConfig.bookingBaseUrl).resolve(
        '/public/company/resolve?code=${Uri.encodeQueryComponent(code)}'))
        .timeout(const Duration(seconds: 10));
      final dynamic raw = jsonDecode(utf8.decode(response.bodyBytes));
      final currentDeviceScope = deviceScope == null ? null : await VehicleDeviceStore().pinScope();
      if (!mounted || epoch != _driverChoicesEpoch || !_directoryVerified ||
          !identical(choices, _vehicleDriverChoices) || response.statusCode != 200 ||
          raw is! Map || raw['ok'] != true ||
          (deviceScope != null && !_sameDeviceScope(deviceScope, currentDeviceScope)) ||
          (raw['tenant_id'] != null && raw['tenant_id'] != choices['tenant_id']) ||
          (raw['company_id'] != null && raw['company_id'] != choices['company_id']) ||
          _normalizeCompanyCode((raw['company_code'] ?? '').toString()) != code) return;
      setState(() => _loginBranding = CustomerAppHeaderBranding.fromJson(Map<String, dynamic>.from(raw)));
    } catch (_) { /* Logo/name unavailable: retain neutral scope label, never invent a brand. */ }
  }

  bool _pinScopeMatchesChoices(Map<String, dynamic> scope) {
    final choices = _vehicleDriverChoices;
    return choices != null && scope['tenant_id'] == choices['tenant_id'] &&
        scope['company_id'] == choices['company_id'] && scope['vehicle_id'] == choices['vehicle_id'];
  }

  Future<Map<String, dynamic>?> _scopedVehicleLoginIdentity() async {
    if (!const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI') ||
        widget.openedFromBusinessHome) return null;
    final store = VehicleDeviceStore();
    final retained = widget.retainedCompanyScope;
    if (retained != null) {
      final epoch = _driverChoicesEpoch;
      try {
        final scope = await store.pinScope();
        if (scope == null || !_retainedScopeMatches(scope)) return null;
        final identity = await store.loginIdentity();
        final currentScope = await store.pinScope();
        if (!mounted || epoch != _driverChoicesEpoch || retained != widget.retainedCompanyScope ||
            !_sameDeviceScope(scope, currentScope)) return null;
        return identity;
      } catch (_) { return null; }
    }
    if (!_companyDriverContext && widget.deviceDutyTarget == null) return store.loginIdentity();
    final epoch = _driverChoicesEpoch;
    final session = resolveCompanyOpsLocalSession();
    final target = widget.deviceDutyTarget;
    final activeId = activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (session.companyId.isEmpty || session.sessionToken.isEmpty ||
        (activeId.isNotEmpty && activeId != session.companyId) ||
        (target != null && (target.companyId != session.companyId || target.tenantId != session.companyId))) return null;
    try {
      final scope = await store.pinScope();
      if (scope == null || scope['tenant_id'] != session.companyId ||
          scope['company_id'] != session.companyId ||
          (target != null && scope['vehicle_id'] != target.vehicleId)) return null;
      final identity = await store.loginIdentity();
      final now = resolveCompanyOpsLocalSession();
      if (!mounted || epoch != _driverChoicesEpoch || now.companyId != session.companyId ||
          now.sessionToken != session.sessionToken) return null;
      return identity;
    } catch (_) { return null; }
  }

  void _onDriverPickerCompanyChanged() {
    if (!mounted || widget.openedFromBusinessHome ||
        !const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI')) return;
    setState(() => _busy = false);
    _companyCtrl.clear();
    _idCtrl.clear();
    unawaited(_loadVehicleDriverChoices());
  }
  bool _manualCodeCameFromTemporaryQr = false;
  bool _suppressManualCodeSourceReset = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
    String? de,
  }) => _tr(nl: nl, en: en, fr: fr, es: es, de: de);

  bool _acceptDeviceDutyActor({required String tenantId,
    required String companyId, required String driverId, required String vehicleId}) {
    final target = widget.deviceDutyTarget;
    final session = resolveCompanyOpsLocalSession();
    final activeId = activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    final retained = widget.retainedCompanyScope;
    final companyMatches = retained != null
        ? tenantId == retained.tenantId && companyId == retained.companyId &&
            _selectedVehicleDriverId != null && driverId == _selectedVehicleDriverId
        : !_companyDriverContext ||
            (session.sessionToken.isNotEmpty && tenantId == session.companyId &&
              companyId == session.companyId && (activeId.isEmpty || activeId == companyId));
    final choices = _vehicleDriverChoices;
    final choicesMatch = choices == null ||
        (tenantId == choices['tenant_id'] && companyId == choices['company_id']);
    if (companyMatches && choicesMatch && (_selectedVehicleDriverId == null || driverId == _selectedVehicleDriverId) &&
        (target == null || target.matches(tenantId: tenantId, companyId: companyId,
      driverId: driverId, vehicleId: vehicleId))) return true;
    if (mounted) setState(() {
      _busy = false;
      _lookupError = _t(
        nl: 'Deze login hoort niet bij de gekozen chauffeur en het gekoppelde voertuig. Gebruik zijn chauffeurcode of koppel-QR.',
        en: 'This login does not match the selected driver and assigned vehicle. Use their driver code or pairing QR.',
        fr: 'Cette connexion ne correspond pas au chauffeur choisi et à son véhicule. Utilisez son code chauffeur ou son QR de liaison.',
        es: 'Esta cuenta no corresponde al conductor seleccionado y su vehículo. Usa su código de conductor o QR de vinculación.',
        de: 'Diese Anmeldung gehört nicht zum gewählten Fahrer und zugewiesenen Fahrzeug. Verwenden Sie seinen Fahrercode oder Kopplungs-QR.',
      );
    });
    return false;
  }

  @override
  void initState() {
    super.initState();
    _companyCtrl.text = widget.retainedCompanyScope?.companyCode ?? '';
    activeCompanySessionNotifier.addListener(_onDriverPickerCompanyChanged);
    companyOpsLocalSessionNotifier.addListener(_onDriverPickerCompanyChanged);
    if (const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI')) {
      if (!widget.openedFromBusinessHome) unawaited(_loadVehicleDriverChoices());
    }
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
  void didUpdateWidget(covariant ChauffeurLoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceDutyTarget != widget.deviceDutyTarget ||
        oldWidget.openedFromBusinessHome != widget.openedFromBusinessHome ||
        oldWidget.retainedCompanyScope != widget.retainedCompanyScope) {
      _onDriverPickerCompanyChanged();
    }
  }

  @override
  void dispose() {
    ++_driverChoicesEpoch;
    activeCompanySessionNotifier.removeListener(_onDriverPickerCompanyChanged);
    companyOpsLocalSessionNotifier.removeListener(_onDriverPickerCompanyChanged);
    _companyCtrl.dispose();
    _idCtrl.dispose();
    _loginPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDriverHomeAfterLogin({required bool fromBusiness}) async {
    if (!mounted) return;
    if (!fromBusiness) {
      await DriverStartupPreference.instance.markDriver(
        activeDriverSessionNotifier.value,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    setAppRole(AppRole.driver);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => fromBusiness
            ? const DriverHomePage(openedFromBusinessHome: true)
            : DriverSessionGatePage(newlyIssued: true, activateAfterSignIn: true, dashboardBuilder: widget.driverDashboardBuilder),
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
    if (widget.retainedCompanyScope != null && _selectedVehicleDriverId == null) {
      setState(() => _lookupError = _t(nl: 'Kies jouw naam bij dit bedrijf.',
          en: 'Choose your name at this company.', de: 'Wähle deinen Namen bei diesem Unternehmen.', fr: 'Choisissez votre nom dans cette entreprise.',
          es: 'Elige tu nombre en esta empresa.'));
      return;
    }
    if (_manualCodeCameFromTemporaryQr) {
      setState(() {
        _lookupError = _t(
          nl: 'Dit veld bevat een tijdelijke koppelcode uit QR-scan. Voor handmatig inloggen gebruik je een vaste chauffeurcode of scan je een nieuwe tijdelijke koppel-QR.',
          en: 'This field contains a temporary pairing code from QR scan. For manual login, use a fixed driver code or scan a new temporary pairing QR.', de: 'Dieses Feld enthält einen temporären QR-Koppelcode. Verwende für die manuelle Anmeldung einen festen Fahrercode oder scanne einen neuen temporären QR.',
          fr: 'Ce champ contient un code de liaison temporaire issu du scan QR. Pour la connexion manuelle, utilisez un code chauffeur fixe ou scannez un nouveau QR temporaire.',
          es: 'Este campo contiene un código temporal de vinculación del escaneo QR. Para inicio manual, usa un código fijo de conductor o escanea un nuevo QR temporal.',
        );
      });
      return;
    }
    setState(() => _busy = true);
    final enteredCompanyCode = _normalizeCompanyCode(_companyCtrl.text);
    final enteredDriverCode = _idCtrl.text.trim();
    final epoch = _driverChoicesEpoch;
    final selectedDriver = _selectedVehicleDriverId;
    final capturedDeviceScope = await _retainedAuthDeviceScope();
    if (!_loginReplyIsCurrent(epoch, selectedDriver)) return;
    final backendLogin = await _loginDriverWithBackend(
      companyCode: enteredCompanyCode,
      driverCode: enteredDriverCode,
    );
    if (!_loginReplyIsCurrent(epoch, selectedDriver) ||
        !await _retainedAuthDeviceIsCurrent(capturedDeviceScope) ||
        !_loginReplyIsCurrent(epoch, selectedDriver)) return;
    if (backendLogin.login != null) {
      final login = backendLogin.login!;
      if (!mounted || !_acceptDeviceDutyActor(tenantId: login.tenantId,
        companyId: login.companyId, driverId: login.driverId,
        vehicleId: login.assignedVehicleId)) return;
      if (widget.openedFromBusinessHome) {
        String? tokenExpiry;
        if ((login.expiresInSeconds ?? 0) > 0) {
          tokenExpiry = DateTime.now()
              .toUtc()
              .add(Duration(seconds: login.expiresInSeconds!))
              .toIso8601String();
        }
        await _completeBusinessDriverViewLogin(
          tenantId: login.tenantId,
          companyId: login.companyId,
          driverId: login.driverId,
          employeeNumber: login.driverId,
          fullName: login.driverName,
          assignedVehicleId: login.assignedVehicleId,
          driverPhotoUrl: login.driverPhotoUrl,
          companyLogoUrl: login.companyLogoUrl,
          vehiclePhotoUrl: login.vehiclePhotoUrl,
          driverSessionToken: login.driverSessionToken,
          driverSessionExpiresAtUtc: tokenExpiry,
        );
        return;
      }
      final resolvedBackendPhoto = _resolveStandaloneDriverPhotoForSave(
        login.driverPhotoUrl,
      );
      await _offerVehiclePin(login, enteredCompanyCode, enteredDriverCode);
      if (!_loginReplyIsCurrent(epoch, selectedDriver) ||
          !await _retainedAuthDeviceIsCurrent(capturedDeviceScope) ||
          !_loginReplyIsCurrent(epoch, selectedDriver) ||
          !_acceptDeviceDutyActor(tenantId: login.tenantId, companyId: login.companyId,
              driverId: login.driverId, vehicleId: login.assignedVehicleId)) return;
      debugPrint(
        '[DRIVER_SESSION][STANDALONE_PHOTO] driver=${_maskLoginCode(login.driverId)} photo=${resolvedBackendPhoto == null ? 'missing' : 'present'} source=payload',
      );
      await DriverSessionStore.instance.saveBackendDriverLoginSession(
        companyCode: enteredCompanyCode,
        tenantId: login.tenantId,
        companyId: login.companyId,
        driverId: login.driverId,
        driverName: login.driverName,
        companyDisplayName: login.companyDisplayName,
        employeeNumber: enteredDriverCode,
        assignedVehicleId: login.assignedVehicleId,
        driverPhotoUrl: resolvedBackendPhoto,
        companyLogoUrl: login.companyLogoUrl,
        vehiclePhotoUrl: login.vehiclePhotoUrl,
        driverSessionToken: login.driverSessionToken,
        expiresInSeconds: login.expiresInSeconds,
      );
      debugPrint(
        '[DRIVER_LOGIN][BACKEND_SESSION_SAVE] tenant=${_maskLoginCode(login.tenantId)} company=${_maskLoginCode(login.companyId)} driver=${_maskLoginCode(login.driverId)}',
      );
      debugPrint(
        '[DRIVER_LOGIN][OK] source=backend driver=${_maskLoginCode(login.driverId)}',
      );
      await _openDriverHomeAfterLogin(fromBusiness: false);
      return;
    }
    // A fresh login requires a server-issued session. Cached fleet records
    // are presentation data and cannot override rejection or network failure.
      if (mounted) {
        setState(() {
          _busy = false;
          _lookupError = _driverAuthErrorText(backendLogin.error);
        });
      }
  }

  String _driverAuthErrorText(String code) {
    if (code == 'wrong_environment') {
      return _t(
        nl: 'Dit bedrijf staat niet op deze lokale debug-Worker (${describePublicAuthHost(kBookingBaseUrl)}). Gebruik een lokale chauffeurcode of een productie-build.',
        en: 'This company is not on this local debug Worker (${describePublicAuthHost(kBookingBaseUrl)}). Use a local driver code or a production build.', de: 'Dieses Unternehmen ist auf dem lokalen Debug-Worker (${describePublicAuthHost(kBookingBaseUrl)}) nicht verfügbar. Verwende einen lokalen Fahrercode oder eine Produktionsversion.',
        fr: 'Cette entreprise n’est pas sur ce Worker local (${describePublicAuthHost(kBookingBaseUrl)}).',
        es: 'Esta empresa no está en este Worker local (${describePublicAuthHost(kBookingBaseUrl)}).',
      );
    }
    if (code == 'local_worker_unreachable') {
      return _t(
        nl: 'De lokale Worker is niet bereikbaar. Start eerst de Worker op ${describePublicAuthHost(kBookingBaseUrl)}.',
        en: 'The local Worker is unreachable. Start the Worker on ${describePublicAuthHost(kBookingBaseUrl)} first.', de: 'Der lokale Worker ist nicht erreichbar. Starte zuerst den Worker auf ${describePublicAuthHost(kBookingBaseUrl)}.',
        fr: 'Le Worker local est injoignable.',
        es: 'El Worker local no responde.',
      );
    }
    if (code == 'network_error') {
      return _t(
        nl: 'Geen verbinding met de aanmeldserver. Controleer het netwerk.',
        en: 'No connection to the sign-in server. Check the network.', de: 'Keine Verbindung zum Anmeldeserver. Prüfe das Netzwerk.',
        fr: 'Pas de connexion au serveur. Vérifiez le réseau.',
        es: 'Sin conexión con el servidor. Comprueba la red.',
      );
    }
    if (code == 'company_not_found') {
      return _t(
        nl: 'Bedrijf niet gevonden. Controleer de bedrijfscode.',
        en: 'Company not found. Check the company ID.', de: 'Unternehmen nicht gefunden. Prüfe den Unternehmenscode.',
        fr: 'Entreprise introuvable. Vérifiez le code entreprise.',
        es: 'Empresa no encontrada. Comprueba el código de empresa.',
      );
    }
    if (code == 'verification_failed') {
      return _driverPairingInvalidText();
    }
    return _t(
      nl: 'Chauffeurlogin mislukt. Controleer bedrijfscode en chauffeurcode.',
      en: 'Driver login failed. Check the company ID and driver code.', de: 'Fahreranmeldung fehlgeschlagen. Prüfe Unternehmens- und Fahrercode.',
      fr: 'Connexion chauffeur échouée. Vérifiez les codes.',
      es: 'Inicio de conductor fallido. Comprueba los códigos.',
    );
  }

  Future<_BackendDriverLoginOutcome> _loginDriverWithBackend({
    required String companyCode,
    required String driverCode,
  }) async {
    final normalizedCompanyCode = _normalizeCompanyCode(companyCode);
    final normalizedDriverCode = driverCode.trim();
    final loopback = isLoopbackBookingBaseUrl(appConfig.bookingBaseUrl) ||
        isLoopbackBookingBaseUrl(kBookingBaseUrl);
    if (normalizedCompanyCode.isEmpty || normalizedDriverCode.isEmpty) {
      return const _BackendDriverLoginOutcome.fail('invalid_company_code');
    }
    debugPrint(
      '[DRIVER_LOGIN][BACKEND_REQ] company=${_maskLoginCode(normalizedCompanyCode)}',
    );
    final uri = Uri.parse('${appConfig.bookingBaseUrl}/public/driver/login');
    try {
      final vehicleDevice = await _scopedVehicleLoginIdentity();
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
              if (vehicleDevice != null) 'vehicle_device': vehicleDevice,
              if (vehicleDevice != null && _selectedVehicleDriverId != null) 'selected_driver_id': _selectedVehicleDriverId,
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
          driverId.isNotEmpty &&
          driverSessionToken.isNotEmpty) {
        debugPrint(
          '[DRIVER_LOGIN][BACKEND_OK] driver=${_maskLoginCode(driverId)}',
        );
        return _BackendDriverLoginOutcome.ok(
          _BackendDriverLoginResult(
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
          ),
        );
      }
      var companyResolvable = false;
      if (loopback) {
        try {
          final resolveUri = Uri.parse(
            '$kBookingBaseUrl/public/company/resolve?code=${Uri.encodeQueryComponent(normalizedCompanyCode)}',
          );
          final resolved = await http.get(resolveUri).timeout(
            const Duration(seconds: 8),
          );
          companyResolvable = resolved.statusCode == 200;
        } catch (_) {
          companyResolvable = false;
        }
      }
      final kind = classifyRemoteAuthFailure(
        statusCode: response.statusCode,
        error: (body['error'] ?? '').toString(),
        loopbackHost: loopback,
        companyResolvable: companyResolvable,
      );
      debugPrint(
        '[DRIVER_LOGIN][BACKEND_FAIL] status=${response.statusCode} kind=${authFailureCode(kind)}',
      );
      return _BackendDriverLoginOutcome.fail(authFailureCode(kind));
    } catch (err) {
      final kind = classifyThrownAuthFailure(err, loopbackHost: loopback);
      debugPrint(
        '[DRIVER_LOGIN][BACKEND_FAIL] status=exception kind=${authFailureCode(kind)}',
      );
      return _BackendDriverLoginOutcome.fail(authFailureCode(kind));
    }
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
            en: 'Use temporary pairing QR?', de: 'Temporären Koppel-QR verwenden?',
            fr: 'Utiliser le QR de liaison temporaire ?',
            es: '¿Usar QR temporal de vinculación?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Je gaat koppelen met bedrijfscode $companyCode. Deze QR is éénmalig bruikbaar.',
            en: 'You are about to pair with company code $companyCode. This QR is one-time use.', de: 'Du verknüpfst dich mit dem Unternehmenscode $companyCode. Dieser QR kann einmal verwendet werden.',
            fr: 'Vous allez vous lier avec le code entreprise $companyCode. Ce QR est à usage unique.',
            es: 'Vas a vincularte con el código de empresa $companyCode. Este QR es de un solo uso.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', de: 'Abbrechen', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _t(
                nl: 'Doorgaan',
                en: 'Continue', de: 'Weiter',
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
    final epoch = _driverChoicesEpoch;
    final selectedDriver = _selectedVehicleDriverId;
    final capturedDeviceScope = await _retainedAuthDeviceScope();
    if (!_loginReplyIsCurrent(epoch, selectedDriver)) return;
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
    if (!_loginReplyIsCurrent(epoch, selectedDriver) ||
        !await _retainedAuthDeviceIsCurrent(capturedDeviceScope) ||
        !_loginReplyIsCurrent(epoch, selectedDriver)) return;
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
    if (!_acceptDeviceDutyActor(tenantId: tenantId, companyId: companyId,
      driverId: driverId, vehicleId: assignedVehicleId)) return;
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
    await _offerPinAfterPairing(verifiedToken: pairingDriverSessionToken, verifiedExpiry: pairingTokenExpiresAt);
    await _openDriverHomeAfterLogin(fromBusiness: false);
  }

  Future<void> _scanDriverLoginQr() async {
    if (_busy) return;
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DriverLoginQrScannerPage()),
    );
    if (!mounted || raw == null) return;
    // The company QR entry also accepts the existing authorized first-device QR.
    // It cannot replace an existing binding: VehicleDeviceStore.pair fences it.
    try {
      final payload = jsonDecode(raw);
      if (payload is Map && payload['kind'] == 'fluxidi_vehicle_device') {
        await _scanVehicleDeviceQr(rawQr: raw);
        return;
      }
    } catch (_) { /* Existing parser handles malformed QR without logging it. */ }
    final parsed = _parseDriverQrPayload(raw);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Ongeldige Fluxidi QR-code.',
              en: 'Invalid Fluxidi QR code.', de: 'Ungültiger Fluxidi-QR-Code.',
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
              en: 'This QR is outdated. Create a temporary pairing QR.', de: 'Dieser QR ist veraltet. Erstelle einen temporären Koppel-QR.',
              fr: 'Ce QR est obsolète. Créez un QR de liaison temporaire.',
              es: 'Este QR está obsoleto. Crea un QR temporal de vinculación.',
            ),
          ),
        ),
      );
      return;
    }
    if (!_acceptRetainedCompanyCode(parsed.companyCode)) return;
    final epoch = _driverChoicesEpoch;
    final confirmed = await _confirmDriverLinkQrUse(
      companyCode: parsed.companyCode,
    );
    if (!mounted || !confirmed || epoch != _driverChoicesEpoch ||
        !_acceptRetainedCompanyCode(parsed.companyCode)) return;
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
            en: 'Temporary pairing QR read. Verifying...', de: 'Temporärer Koppel-QR gelesen. Prüfung läuft…',
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

  Future<void> _changeDevice(String operation) async {
    if (_busy) return;
    if (activeDriverSessionNotifier.value != null || nativeDriverDutySessionNotifier.value != null) {
      setState(()=>_lookupError=_t(nl:'Beëindig eerst je rit en dienst veilig en meld je af.',en:'End your trip and duty safely, then sign out.',fr:'Terminez la course et le service en sécurité, puis déconnectez-vous.',es:'Finaliza el viaje y el turno de forma segura y cierra sesión.',de:'Fahrt und Dienst sicher beenden und dann abmelden.'));
      return;
    }
    final store = VehicleDeviceStore();
    final pending = await store.pendingTransitionOperation();
    if (!mounted || pending != null && pending != operation) return;
    final title = operation == 'switch'
        ? _t(nl:'Voertuig wijzigen',en:'Switch vehicle',fr:'Changer de véhicule',es:'Cambiar vehículo',de:'Fahrzeug wechseln')
        : _t(nl:'Toestel ontkoppelen',en:'Unlink device',fr:'Dissocier l’appareil',es:'Desvincular dispositivo',de:'Gerät entkoppeln');
    final vehicle = (_vehicleDriverChoices?['vehicle_label'] ?? _vehicleDriverChoices?['vehicle_id'] ?? '').toString();
    final confirmed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:Text('${_loginCompanyLabel()}\n$vehicle\n\n${_t(
        nl:'Alleen met een bevoegde, eenmalige QR voor deze actie. Beëindig eerst je rit en dienst veilig.',
        en:'Requires an authorized, one-use QR for this action. First end your trip and duty safely.',
        fr:'Un QR autorisé à usage unique est requis. Terminez d’abord la course et le service en sécurité.',
        es:'Requiere un QR autorizado de un solo uso. Finaliza primero el viaje y el turno de forma segura.',
        de:'Ein autorisierter Einmal-QR für diese Aktion ist erforderlich. Fahrt und Dienst zuerst sicher beenden.')}'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(title))]));
    if (!mounted || confirmed != true) return;
    final raw = pending == null ? await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>const DriverLoginQrScannerPage())) : null;
    if (!mounted || pending == null && raw == null || activeDriverSessionNotifier.value != null || nativeDriverDutySessionNotifier.value != null) return;
    setState(() { _busy=true; ++_driverChoicesEpoch; _loginPinCtrl.clear(); });
    try {
      await store.transition(raw,appConfig.bookingBaseUrl,operation:operation,
        afterServerConfirmed:DriverSessionStore.instance.clearAfterDeviceTransition);
      if (!mounted) return;
      // Drop retained presentation scope too: a later first pairing may belong
      // to another authorized company without inheriting the previous scope.
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder:(_)=>const ChauffeurLoginPage()));
    } catch (_) {
      if (mounted) {
        setState(()=>_busy=false);
        await _loadVehicleDriverChoices();
        if (mounted) setState(()=>_lookupError=_t(
          nl:'Wijziging niet bevestigd. Beëindig eerst rit en dienst. Bij een verbindingsfout kun je dezelfde actie veilig opnieuw proberen.',
          en:'Change not confirmed. End the trip and duty first. After a connection failure, retry the same action safely.',
          fr:'Modification non confirmée. Terminez la course et le service. Après une erreur réseau, réessayez la même action.',
          es:'Cambio sin confirmar. Finaliza el viaje y el turno. Tras un error de conexión, vuelve a intentar la misma acción.',
          de:'Änderung nicht bestätigt. Fahrt und Dienst zuerst beenden. Bei Verbindungsfehler dieselbe Aktion erneut versuchen.'));
      }
    }
  }

  Future<void> _scanVehicleDeviceQr({String? rawQr}) async {
    if (_busy) return;
    final raw = rawQr ?? await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const DriverLoginQrScannerPage()));
    if (!mounted || raw == null) return;
    setState(() { _busy = true; });
    var success = false;
    try {
      final session = resolveCompanyOpsLocalSession();
      final target = widget.deviceDutyTarget;
      if (_companyDriverContext && (session.companyId.isEmpty || session.sessionToken.isEmpty ||
          (target != null && (target.companyId != session.companyId || target.tenantId != session.companyId)))) {
        throw StateError('company_driver_picker_session_scope_mismatch');
      }
      await VehicleDeviceStore().pair(raw, appConfig.bookingBaseUrl,
        expectedTenantId: _companyDriverContext ? session.companyId : null,
        expectedCompanyId: _companyDriverContext ? session.companyId : null,
        expectedVehicleId: target?.vehicleId);
      success = true;
    }
    catch (_) { /* No token or QR contents in logs or messages. */ }
    if (!mounted) return;
    setState(() { _busy = false; });
    if (success) await _loadVehicleDriverChoices();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success
      ? _t(nl:'Toestel aan voertuig gekoppeld. Meld je nu persoonlijk aan.',en:'Device linked to vehicle. Now sign in personally.', de: 'Gerät mit Fahrzeug verknüpft. Melde dich jetzt persönlich an.',fr:'Appareil lié au véhicule. Connectez-vous personnellement.',es:'Dispositivo vinculado al vehículo. Inicia sesión personalmente.')
      : _t(nl:'Voertuigkoppeling niet bevestigd. Vraag een nieuwe koppelcode.',en:'Vehicle pairing not confirmed. Request a new code.', de: 'Fahrzeugbindung nicht bestätigt. Fordere einen neuen Code an.',fr:'Liaison non confirmée. Demandez un nouveau code.',es:'Vinculación no confirmada. Solicita un código nuevo.'))));
  }

  String _maskLoginCode(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'empty';
    if (t.length <= 2) return '*' * t.length;
    return '${t[0]}***${t[t.length - 1]}(len=${t.length})';
  }

  String _driverPairingInvalidText() {
    return _t(
      nl: 'Chauffeurcode ongeldig of verlopen',
      en: 'Driver code is invalid or expired', de: 'Fahrercode ungültig oder abgelaufen',
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
      final vehicleDevice = await _scopedVehicleLoginIdentity();
      final response = await http
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'company_code': companyCode,
              'pairing_code': pairingCode,
              if (vehicleDevice != null) 'vehicle_device': vehicleDevice,
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
      final loopback = isLoopbackBookingBaseUrl(kBookingBaseUrl);
      var companyResolvable = false;
      if (loopback) {
        try {
          final resolveUri = Uri.parse(
            '$kBookingBaseUrl/public/company/resolve?code=${Uri.encodeQueryComponent(companyCode)}',
          );
          final resolved = await http.get(resolveUri).timeout(
            const Duration(seconds: 8),
          );
          companyResolvable = resolved.statusCode == 200;
        } catch (_) {
          companyResolvable = false;
        }
      }
      final kind = classifyRemoteAuthFailure(
        statusCode: response.statusCode,
        error: (body['error'] ?? '').toString(),
        loopbackHost: loopback,
        companyResolvable: companyResolvable,
      );
      return <String, dynamic>{'ok': false, 'error': authFailureCode(kind)};
    } catch (err) {
      final kind = classifyThrownAuthFailure(
        err,
        loopbackHost: isLoopbackBookingBaseUrl(kBookingBaseUrl),
      );
      return <String, dynamic>{'ok': false, 'error': authFailureCode(kind)};
    }
  }

  Future<Map<String, String>?> _showDriverPairingSheet(BuildContext context) async {
    final companyCtrl = TextEditingController(text: widget.retainedCompanyScope == null ? '' : _companyCtrl.text);
    final codeCtrl = TextEditingController();
    final route = ModalBottomSheetRoute<Map<String, String>>(
      capturedThemes: InheritedTheme.capture(from: context, to: Navigator.of(context).context),
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
                        en: 'Driver code', de: 'Fahrercode',
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
                    if (widget.retainedCompanyScope == null) TextField(
                      controller: companyCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Bedrijfs-ID',
                          en: 'Company ID', de: 'Unternehmenscode',
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
                          en: 'Driver code', de: 'Fahrercode',
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
                              en: 'Cancel', de: 'Abbrechen',
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
                              en: 'Link code', de: 'Code verknüpfen',
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
    );
    try {
      final result = await Navigator.of(context).push(route);
      await route.completed;
      return result;
    } finally {
      companyCtrl.dispose();
      codeCtrl.dispose();
    }
  }

  Future<void> _submitPairingCodeFlow() async {
    if (_busy) return;
    final formEpoch = _driverChoicesEpoch;
    final formData = await _showDriverPairingSheet(context);
    if (!mounted || formData == null || formEpoch != _driverChoicesEpoch ||
        !_acceptRetainedCompanyCode(formData['company_code'] ?? '')) return;
    setState(() {
      _busy = true;
      _lookupError = null;
    });
    final epoch = _driverChoicesEpoch;
    final selectedDriver = _selectedVehicleDriverId;
    final capturedDeviceScope = await _retainedAuthDeviceScope();
    if (!_loginReplyIsCurrent(epoch, selectedDriver)) return;
    final response = await _verifyDriverPairingCode(
      companyCode: formData['company_code'] ?? '',
      pairingCode: formData['pairing_code'] ?? '',
    );
    if (!_loginReplyIsCurrent(epoch, selectedDriver) ||
        !await _retainedAuthDeviceIsCurrent(capturedDeviceScope) ||
        !_loginReplyIsCurrent(epoch, selectedDriver)) return;
    if (response['ok'] != true) {
      setState(() {
        _busy = false;
        _lookupError = _driverAuthErrorText(
          (response['error'] ?? 'verification_failed').toString(),
        );
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
    if (!_acceptDeviceDutyActor(tenantId: tenantId, companyId: companyId,
      driverId: driverId, vehicleId: assignedVehicleId)) return;
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
    await _offerPinAfterPairing(verifiedToken: pairingDriverSessionToken, verifiedExpiry: pairingTokenExpiresAt);
    await _openDriverHomeAfterLogin(fromBusiness: false);
  }


  void _showLoginHelp() {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(_t(nl: 'Eerste aanmelding of pincode vergeten?', en: 'First sign-in or forgotten PIN?', fr: 'Première connexion ou PIN oublié ?', es: '¿Primera vez o PIN olvidado?', de: 'Erste Anmeldung oder PIN vergessen?')),
      content: Text(_t(
        nl: 'Gebruik je chauffeur-QR of vaste chauffeurscode om je identiteit te bevestigen. Daarna kun je jouw persoonlijke PIN instellen. De server controleert elke aanmelding. Een voertuigkoppeling wijzigen kan alleen met een bevoegde koppel-QR. Een actieve rit of dienst moet eerst veilig worden beëindigd.',
        en: 'Verify your identity with your driver QR or fixed driver code, then set your personal PIN. The server checks every sign-in. Changing a vehicle binding requires an authorized pairing QR. An active trip or duty must first be ended safely.', de: 'Bestätige deine Identität mit Fahrer-QR oder Fahrercode und lege deine PIN fest. Der Server prüft jede Anmeldung. Ein Fahrzeugwechsel erfordert einen autorisierten QR. Fahrt und Dienst zuerst sicher beenden.',
        fr: 'Vérifiez votre identité avec votre QR chauffeur ou code fixe, puis créez votre PIN. Le serveur contrôle chaque connexion. Changer de véhicule nécessite un QR autorisé. Une course ou un service actif doit d’abord être terminé en sécurité.',
        es: 'Verifica tu identidad con tu QR o código fijo y configura tu PIN. El servidor comprueba cada acceso. Cambiar el vehículo requiere un QR autorizado. Primero debe finalizarse de forma segura el viaje o turno activo.')),
      actions: [TextButton(onPressed: () { Navigator.pop(ctx); setState(()=>_showFixedCode=true); },
        child:Text(_t(nl:'Ik heb een chauffeurscode',en:'I have a driver code',fr:'J’ai un code chauffeur',es:'Tengo un código de conductor',de:'Ich habe einen Fahrercode'))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar',de:'Schließen')))],
    ));
  }

  String _loginCompanyLabel() {
    final choices = _vehicleDriverChoices;
    final profile = companyProfileNotifier.value;
    final company = _loginBranding?.companyName.trim();
    return company != null && company.isNotEmpty ? company
        : _directoryVerified && profile?.companyId == choices?['company_id'] && profile!.companyName.isNotEmpty
          ? profile.companyName : _directoryVerified && _companyCtrl.text.isNotEmpty ? _companyCtrl.text
          : _directoryVerified
            ? _t(nl: 'Gekoppeld bedrijf', en: 'Linked company', fr: 'Entreprise liée', es: 'Empresa vinculada', de: 'Verknüpftes Unternehmen')
            : _t(nl: 'Bedrijf nog niet bevestigd', en: 'Company not yet verified', fr: 'Entreprise non confirmée', es: 'Empresa sin verificar', de: 'Unternehmen noch nicht bestätigt');
  }

  Widget _loginContextCard(BuildContext context, BusinessThemePalette palette) {
    final choices = _vehicleDriverChoices;
    final name = _loginCompanyLabel();
    final onCard = companyOpsReadableOn(palette.surface, palette);
    final border = companyOpsEnsureContrast(color: palette.accent, background: palette.surface, minRatio: 3, toward: onCard);
    Widget fallback() => Icon(Icons.business_outlined, size: 42, color: onCard);
    final logo = _loginBranding?.displayLogoUrl ?? '';
    final mark = SizedBox(width: 80, height: 64, child: logo.isEmpty ? fallback()
        : Image.network(logo, key: const ValueKey('driver_company_logo'), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback()));
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_t(nl:'GEKOPPELD BEDRIJF',en:'LINKED COMPANY',fr:'ENTREPRISE LIÉE',es:'EMPRESA VINCULADA',de:'VERKNÜPFTES UNTERNEHMEN'),style:TextStyle(color:onCard,fontSize:10)),
      Text(name, style: TextStyle(color: onCard, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      if (_deviceVerified) ...[
        Text((choices?['vehicle_label'] ?? '').toString().isNotEmpty
            ? choices!['vehicle_label'] as String
            : _t(nl: 'Gekoppeld voertuig', en: 'Paired vehicle', de: 'Verknüpftes Fahrzeug', fr: 'Véhicule lié', es: 'Vehículo vinculado'),
          style: TextStyle(color: onCard, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_circle, color: companyOpsEnsureContrast(
            color: palette.success, background: palette.surface, minRatio: 3, toward: onCard)), const SizedBox(width: 10),
          Expanded(child: Text(_t(nl: 'Toestelbinding geverifieerd', en: 'Device binding verified', fr: 'Liaison de l’appareil vérifiée', es: 'Vinculación verificada', de: 'Gerätebindung bestätigt'), style: TextStyle(color: onCard))),
        ]),
      ] else Text(_directoryLoading
          ? _t(nl: 'Koppeling controleren…', en: 'Checking binding…', de: 'Verknüpfung wird geprüft…', fr: 'Vérification de la liaison…', es: 'Verificando vínculo…')
          : _t(nl: 'Voertuigkoppeling nog niet bevestigd', en: 'Vehicle binding not yet verified', de: 'Fahrzeugbindung noch nicht bestätigt', fr: 'Liaison véhicule non confirmée', es: 'Vínculo del vehículo sin verificar'), style: TextStyle(color: onCard)),
    ]);
    return Container(key: _deviceVerified ? const ValueKey('driver_verified_vehicle') : const ValueKey('driver_unverified_context'),
      padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: palette.surface,
        borderRadius: BorderRadius.circular(18), border: Border.all(color: border, width: 1.5)),
      child: LayoutBuilder(builder: (_, box) {
        if (box.maxWidth < 240 || MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [mark, const SizedBox(height: 10), details]);
        }
        return Row(children: [mark, Container(width: 1, height: 64, margin: const EdgeInsets.symmetric(horizontal: 14), color: border), Expanded(child: details)]);
      }));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: Listenable.merge([appLanguageNotifier, businessThemeNotifier, brandSignaturePaletteNotifier]), builder: (context, _) {
      final companyId = _directoryVerified ? (_vehicleDriverChoices?['company_id'] as String?) : null;
      final variant = companyId == null ? BusinessThemeVariant.executiveGold : resolveStoredBusinessThemeForCompany(companyId);
      final palette = variant == BusinessThemeVariant.brandSignatureGold
          ? brandSignatureBusinessPalette(resolveStoredBrandSignaturePalette(companyId)) : paletteForBusinessTheme(variant);
      return Theme(data: driverLoginTheme(palette), child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final pinReady = !_busy && !_directoryLoading && (_directoryVerified || _personalHints) && _selectedVehicleDriverId != null &&
            _vehiclePinScopeMatches && RegExp(r'^\d{6}$').hasMatch(_loginPinCtrl.text);
        final canPair = const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI') &&
            !_deviceVerified && !_directoryLoading && !widget.openedFromBusinessHome && widget.retainedCompanyScope == null;
        final titleStyle = theme.textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700);
        return Scaffold(
          appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _busy ? null : () {
              if (widget.deviceDutyTarget != null) { Navigator.of(context).pop(); return; }
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RoleEntryPage()));
            }), title: Text(_t(nl: 'Chauffeur login', en: 'Driver login', fr: 'Connexion chauffeur', es: 'Acceso conductor', de: 'Fahrer-Anmeldung'))),
          body: SafeArea(child: SingleChildScrollView(key: const ValueKey('driver_login_scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: Form(key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _loginContextCard(context, palette),
                if (_deviceVerified) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: palette.surfaceAlt, borderRadius: BorderRadius.circular(16)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.shield_outlined), const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_t(nl: 'Dit toestel is gekoppeld aan ${_loginCompanyLabel()}.',
                          en: 'This device is linked to ${_loginCompanyLabel()}.',
                          fr: 'Cet appareil est lié à ${_loginCompanyLabel()}.',
                          es: 'Este dispositivo está vinculado a ${_loginCompanyLabel()}.', de: 'Dieses Gerät ist mit ${_loginCompanyLabel()} verknüpft.'),
                          style: TextStyle(color: companyOpsReadableOn(palette.surfaceAlt, palette), fontWeight: FontWeight.w700)),
                        Text(_t(nl: 'De beheerder hoeft niet ingelogd te blijven.', en: 'The administrator does not need to stay signed in.', fr: 'L’administrateur ne doit pas rester connecté.', es: 'El administrador no necesita permanecer conectado.', de: 'Der Administrator muss nicht angemeldet bleiben.'),
                          style: TextStyle(color: companyOpsReadableOn(palette.surfaceAlt, palette))),
                      ])),
                    ]))),
                if (_directoryLoading) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Semantics(liveRegion: true,
                  label: _t(nl: 'Chauffeurs laden', en: 'Loading drivers', fr: 'Chargement des chauffeurs', es: 'Cargando conductores',de:'Fahrer werden geladen'), child: const LinearProgressIndicator())),
                if ((_directoryVerified || _personalHints) && _vehicleDriverChoices != null && !widget.openedFromBusinessHome) ...[
                  const SizedBox(height: 12),
                  if (_personalHints) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_t(
                    nl: 'Bewaarde persoonlijke profielen. Bedrijf en voertuig zijn nog niet bevestigd; de server controleert je aanmelding.',
                    en: 'Saved personal profiles. Company and vehicle are not yet verified; the server checks your sign-in.', de: 'Gespeicherte persönliche Profile. Unternehmen und Fahrzeug sind noch nicht bestätigt; der Server prüft deine Anmeldung.',
                    fr: 'Profils personnels enregistrés. Entreprise et véhicule non confirmés ; le serveur vérifie la connexion.',
                    es: 'Perfiles personales guardados. Empresa y vehículo sin verificar; el servidor comprueba el acceso.'))),
                  Text(_t(nl: 'Kies je naam', en: 'Choose your name', fr: 'Choisissez votre nom', es: 'Elige tu nombre', de: 'Wähle deinen Namen'), style: titleStyle),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(key: ValueKey(_personalHints ? 'personal_profile_choice' : 'vehicle_driver_choice'), value: _selectedVehicleDriverId, isExpanded: true,
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.person_outline), hintText: _t(nl: 'Selecteer chauffeur', en: 'Select driver', fr: 'Sélectionner le chauffeur', es: 'Selecciona conductor', de: 'Fahrer auswählen')),
                    selectedItemBuilder: (context) => (_vehicleDriverChoices!['drivers'] as List).map<Widget>((row) => Align(alignment: AlignmentDirectional.centerStart,
                      child: Text(row['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                    items: (_vehicleDriverChoices!['drivers'] as List).map((row) => DropdownMenuItem<String>(value: row['driver_id'] as String,
                      child: Text(row['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis))).toList(),
                    itemHeight: null,
                    onChanged: _busy ? null : (value) => setState(() { _selectedVehicleDriverId = value; _idCtrl.clear(); _loginPinCtrl.clear(); _lookupError = null; })),
                  const SizedBox(height: 12),
                  Row(children:[Expanded(child:Text(_t(nl: 'Persoonlijke pincode', en: 'Personal PIN', fr: 'Code PIN personnel', es: 'PIN personal', de: 'Persönliche PIN'), style: titleStyle)),Text(_t(nl:'6 cijfers',en:'6 digits',fr:'6 chiffres',es:'6 cifras',de:'6 Ziffern'),style:theme.textTheme.bodySmall)]),
                  const SizedBox(height: 6),
                  TextField(key: const ValueKey('driver_login_pin'), controller: _loginPinCtrl, enabled: !_busy,
                    obscureText: !_showPin, enableSuggestions: false, autocorrect: false,
                    keyboardType: TextInputType.number, maxLength: 6, textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) { if (pinReady) unawaited(_unlockVehicleDriver(enteredPin: _loginPinCtrl.text)); },
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.lock_outline),
                      counterText: '', hintText: _t(nl: '6 cijfers', en: '6 digits', fr: '6 chiffres', es: '6 cifras', de: '6 Ziffern'),
                      suffixIcon: IconButton(onPressed: _busy ? null : () => setState(() => _showPin = !_showPin),
                        tooltip: _showPin ? _t(nl: 'PIN verbergen', en: 'Hide PIN', fr: 'Masquer le PIN', es: 'Ocultar PIN', de: 'PIN verbergen')
                            : _t(nl: 'PIN tonen', en: 'Show PIN', fr: 'Afficher le PIN', es: 'Mostrar PIN', de: 'PIN anzeigen'),
                        icon: Icon(_showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined)))),
                  const SizedBox(height: 12),
                  FilledButton(key: const ValueKey('vehicle_pin_login'), onPressed: pinReady ? () => unawaited(_unlockVehicleDriver(enteredPin: _loginPinCtrl.text)) : null,
                    child: Text(_t(nl: 'Inloggen als chauffeur', en: 'Sign in as driver', fr: 'Connexion chauffeur', es: 'Entrar como conductor', de: 'Als Fahrer anmelden'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                ],
                if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                if (_lookupError != null) ...[
                  const SizedBox(height: 16),
                  Semantics(liveRegion: true, child: Container(padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(16)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer), const SizedBox(width: 10),
                      Expanded(child: Text(_lookupError!, style: TextStyle(color: theme.colorScheme.onErrorContainer)))]))),
                  if (!_directoryVerified) TextButton.icon(key: const ValueKey('driver_directory_retry'),
                    onPressed: _busy || _directoryLoading ? null : _loadVehicleDriverChoices, icon: const Icon(Icons.refresh),
                    label: Text(_t(nl: 'Opnieuw controleren', en: 'Check again', de: 'Erneut prüfen', fr: 'Vérifier à nouveau', es: 'Volver a comprobar'))),
                ],
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
                  const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_t(nl: 'OF', en: 'OR', fr: 'OU', es: 'O', de: 'ODER'))), const Expanded(child: Divider()),
                ])),
                OutlinedButton.icon(key: const ValueKey('driver_scan_qr'), onPressed: _busy || _directoryLoading ? null : () => unawaited(_scanDriverLoginQr()),
                  icon: const Icon(Icons.qr_code_scanner), label: Text(_t(nl: 'Scan bedrijfs-QR', en: 'Scan company QR', fr: 'Scanner le QR de l’entreprise', es: 'Escanear QR de empresa', de:'Firmen-QR scannen'), textAlign: TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:16))),
                if (_deviceVerified || _pendingDeviceTransition != null) ...[
                  const SizedBox(height:10),
                  OutlinedButton.icon(key:const ValueKey('driver_switch_vehicle'),
                    onPressed:_busy || _pendingDeviceTransition == 'unlink' ? null : ()=>unawaited(_changeDevice('switch')),
                    icon:const Icon(Icons.directions_car_outlined),label:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(_t(nl:'Voertuig wijzigen',en:'Switch vehicle',fr:'Changer de véhicule',es:'Cambiar vehículo',de:'Fahrzeug wechseln'),style:const TextStyle(fontWeight:FontWeight.w700)),
                      Text(_t(nl:'Koppel dit toestel aan een ander voertuig',en:'Link this device to another vehicle',fr:'Lier cet appareil à un autre véhicule',es:'Vincular este dispositivo a otro vehículo',de:'Dieses Gerät mit einem anderen Fahrzeug verbinden'),style:theme.textTheme.bodySmall)])),const Icon(Icons.chevron_right)])),
                  const SizedBox(height:10),
                  OutlinedButton.icon(key:const ValueKey('driver_unlink_device'),
                    style:OutlinedButton.styleFrom(foregroundColor:theme.colorScheme.error,side:BorderSide(color:theme.colorScheme.error)),
                    onPressed:_busy || _pendingDeviceTransition == 'switch' ? null : ()=>unawaited(_changeDevice('unlink')),
                    icon:const Icon(Icons.link_off),label:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(_t(nl:'Toestel ontkoppelen',en:'Unlink device',fr:'Dissocier l’appareil',es:'Desvincular dispositivo',de:'Gerät entkoppeln'),style:const TextStyle(fontWeight:FontWeight.w700)),
                      Text(_t(nl:'Verwijder de koppeling met dit bedrijf',en:'Remove the link to this company',fr:'Supprimer le lien avec cette entreprise',es:'Eliminar el vínculo con esta empresa',de:'Verknüpfung mit dieser Firma entfernen'),style:theme.textTheme.bodySmall)])),const Icon(Icons.chevron_right)])),
                ],
                if (!_deviceVerified) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(key: const ValueKey('driver_fixed_code_toggle'), onPressed: _busy ? null : () => setState(() => _showFixedCode = !_showFixedCode),
                  icon: const Icon(Icons.key_outlined), label: Text(_t(nl: 'Ik heb een chauffeurscode', en: 'I have a driver code', de: 'Ich habe einen Fahrercode', fr: 'J’ai un code chauffeur', es: 'Tengo un código de conductor'), textAlign: TextAlign.center)),
                ],
                if (_showFixedCode || widget.openedFromBusinessHome) ...[
                  const SizedBox(height: 16),
                  if (widget.retainedCompanyScope == null) TextFormField(key: const ValueKey('driver_company_code'), controller: _companyCtrl, enabled: !_busy, readOnly: _directoryVerified,
                    decoration: InputDecoration(labelText: _t(nl: 'Bedrijfscode', en: 'Company ID', de: 'Unternehmenscode', fr: 'Code entreprise', es: 'Código de empresa')),
                    validator: (v) => (v ?? '').trim().isEmpty ? _t(nl: 'Vul je bedrijfscode in.', en: 'Enter company ID.', de: 'Gib den Unternehmenscode ein.', fr: 'Saisissez le code entreprise.', es: 'Introduce la empresa.') : null),
                  const SizedBox(height: 12),
                  TextFormField(key: const ValueKey('driver_fixed_code_field'), controller: _idCtrl, enabled: !_busy, textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) { if (!_busy) unawaited(_submit()); },
                    decoration: InputDecoration(labelText: _t(nl: 'Vaste chauffeurcode', en: 'Fixed driver code', de: 'Fester Fahrercode', fr: 'Code chauffeur fixe', es: 'Código fijo de conductor')),
                    validator: (v) => (v ?? '').trim().isEmpty ? _t(nl: 'Vul je vaste chauffeurcode in.', en: 'Enter your fixed driver code.', de: 'Gib deinen festen Fahrercode ein.', fr: 'Saisissez votre code chauffeur fixe.', es: 'Introduce tu código fijo.') : null),
                  const SizedBox(height: 12),
                  FilledButton(key: const ValueKey('driver_fixed_code_login'), onPressed: _busy ? null : () => unawaited(_submit()),
                    child: Text(_t(nl: 'Aanmelden met chauffeurcode', en: 'Sign in with driver code', de: 'Mit Fahrercode anmelden', fr: 'Connexion avec le code chauffeur', es: 'Entrar con código de conductor'), textAlign: TextAlign.center)),
                  TextButton(onPressed: _busy ? null : () => unawaited(_submitPairingCodeFlow()),
                    child: Text(_t(nl: 'Tijdelijke koppelcode invoeren', en: 'Enter temporary pairing code', de: 'Temporären Koppelcode eingeben', fr: 'Saisir le code de liaison temporaire', es: 'Introducir código temporal'), textAlign: TextAlign.center)),
                ],
                if (canPair) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(key: const ValueKey('driver_pair_vehicle'), onPressed: _busy ? null : () => unawaited(_scanVehicleDeviceQr()),
                    icon: const Icon(Icons.directions_car_outlined), label: Text(_t(nl: 'Toestel activeren met bevoegde voertuig-QR', en: 'Activate device with authorized vehicle QR', de: 'Gerät mit autorisiertem Fahrzeug-QR aktivieren', fr: 'Activer avec un QR véhicule autorisé', es: 'Activar con QR autorizado del vehículo'), textAlign: TextAlign.center)),
                ],
                const SizedBox(height: 10),
                TextButton.icon(key: const ValueKey('driver_login_help'), onPressed: _showLoginHelp,
                  icon: const Icon(Icons.help_outline), label: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(_t(nl: 'Pincode vergeten of eerste keer inloggen?', en: 'Forgotten PIN or first sign-in?', fr: 'PIN oublié ou première connexion ?', es: '¿PIN olvidado o primer acceso?', de: 'PIN vergessen oder erste Anmeldung?'),style:theme.textTheme.bodySmall?.copyWith(fontWeight:FontWeight.w700)),
                    Text(_t(nl:'Gebruik je chauffeurscode of vraag een nieuwe koppeling aan.',en:'Use your driver code or request a new link.',fr:'Utilisez votre code chauffeur ou demandez une nouvelle liaison.',es:'Usa tu código de conductor o solicita un nuevo vínculo.',de:'Nutze deinen Fahrercode oder fordere eine neue Verknüpfung an.'),style:theme.textTheme.bodySmall),
                  ])),
              ]),
            ))),
          )),
        );
      }));
    });
  }
}
