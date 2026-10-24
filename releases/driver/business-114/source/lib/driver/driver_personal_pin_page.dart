import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../app_strings.dart';
import '../driver_session_store.dart';
import 'vehicle_device_store.dart';
import 'vehicle_driver_pin_store.dart';
import 'driver_pin_verified_session.dart';

/// Personal-device settings, available only to the authenticated driver.
/// Reverification issues an ordinary server credential; it does not replace
/// the active session, change duty/GPS ownership, or log in another actor.
class DriverPersonalPinPage extends StatefulWidget {
  const DriverPersonalPinPage({
    super.key,
    required this.session,
    this.freshVerification,
  });
  final ActiveDriverSession session;
  final FreshDriverPinSetup? freshVerification;

  @override
  State<DriverPersonalPinPage> createState() => _DriverPersonalPinPageState();
}

class _DriverPersonalPinPageState extends State<DriverPersonalPinPage> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _store = DriverPersonalPinStore();
  bool _busy = false, _hasPin = false, _recoverWithQr = false;
  String? _error;
  String? _mode;
  bool get _fresh =>
      _current && widget.freshVerification?.matches(widget.session) == true;
  Map<String, dynamic> get _scope => {
    'tenant_id': widget.session.tenantId,
    'company_id': widget.session.companyId,
  };
  String _text(String nl, String en) =>
      appLanguageNotifier.value == AppLanguage.nl ? nl : en;

  bool get _current {
    final expected = widget.session;
    final now = activeDriverSessionNotifier.value;
    return expected.isStandaloneLoginSession &&
        (expected.driverSessionToken ?? '').isNotEmpty &&
        (expected.tenantId ?? '').isNotEmpty &&
        (expected.companyId ?? '').isNotEmpty &&
        (expected.companyCode ?? '').isNotEmpty &&
        now != null &&
        now.isStandaloneLoginSession &&
        now.driverId == expected.driverId &&
        now.tenantId == expected.tenantId &&
        now.companyId == expected.companyId &&
        now.driverSessionToken == expected.driverSessionToken;
  }

  @override
  void initState() {
    super.initState();
    activeDriverSessionNotifier.addListener(_sessionChanged);
    _load();
  }

  void _sessionChanged() {
    if (!mounted || _current) return;
    _code.clear();
    _pin.clear();
    _confirm.clear();
    setState(
      () => _error = _text(
        'Je chauffeurssessie is gewijzigd. Open je eigen PIN-instellingen opnieuw.',
        'Your driver session changed. Reopen your own PIN settings.',
      ),
    );
  }

  Future<void> _load() async {
    if (!_current) {
      _sessionChanged();
      return;
    }
    try {
      final has = await _store.hasPin(_scope, widget.session.driverId);
      final credential = _fresh
          ? await _store.credentialsForReverification(
              _scope,
              widget.session.driverId,
            )
          : null;
      if (!mounted || !_current) return;
      setState(() {
        _hasPin = has;
        _recoverWithQr = credential != null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = _text(
            'PIN-gegevens konden niet worden gelezen. Je vaste chauffeurcode blijft bruikbaar.',
            'PIN data could not be read. Your fixed driver code remains available.',
          ),
        );
    }
  }

  Future<void> _save() async {
    if (_busy || !_current || !_form.currentState!.validate()) return;
    final requestedPin = _pin.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final usesFreshVerification = _fresh;
      bool authorized() => _current && (!usesFreshVerification || _fresh);
      final recovered = _recoverWithQr && _fresh
          ? await _store.credentialsForReverification(
              _scope,
              widget.session.driverId,
            )
          : null;
      final companyCode = widget.session.companyCode!.trim();
      final driverCode = recovered?.driverCode ?? _code.text.trim();
      if (_fresh && recovered == null) {
        final verified = await widget.freshVerification!.credential.verify();
        if (!mounted || !_fresh) throw StateError('pin_setup_expired');
        await _store.enrollServerSession(
          DriverPinServerSession.fromVerifiedSession(verified),
          requestedPin,
          stillAuthorized: () async => _fresh,
        );
      } else {
        if (!authorized() ||
            driverCode.isEmpty ||
            (recovered != null &&
                recovered.companyCode.trim().toUpperCase() !=
                    companyCode.toUpperCase())) {
          throw StateError('pin_reverification_required');
        }
        // Do not send a PIN, temporary QR code, vehicle-device ownership command,
        // or company-admin credential. Normal server login remains authoritative.
        final response = await http
            .post(
              Uri.parse('${appConfig.bookingBaseUrl}/public/driver/login'),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'company_code': companyCode,
                'driver_code': driverCode,
                'selected_driver_id': widget.session.driverId,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (!mounted || !authorized()) throw StateError('pin_setup_expired');
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 200 ||
            data is! Map ||
            data['ok'] != true ||
            data['role'] != 'driver' ||
            data['tenant_id'] != widget.session.tenantId ||
            data['company_id'] != widget.session.companyId ||
            data['driver_id'] != widget.session.driverId ||
            '${data['driver_session_token'] ?? data['driverSessionToken'] ?? ''}'
                .isEmpty) {
          throw StateError('pin_reverification_failed');
        }
        if (!authorized()) throw StateError('pin_setup_expired');
        await _store.enroll(
          _scope,
          widget.session.driverId,
          companyCode,
          driverCode,
          requestedPin,
          stillAuthorized: () async => authorized(),
        );
      }
      if (!_current) return;
      await _store.rememberDriver(
        _scope,
        widget.session.driverId,
        widget.session.fullName,
      );
      // New personal PIN takes precedence; retire only this driver's matching
      // legacy vehicle PIN after successful reauthentication and durable setup.
      try {
        final paired = await VehicleDeviceStore().pinScope();
        if (_current &&
            paired != null &&
            paired['tenant_id'] == _scope['tenant_id'] &&
            paired['company_id'] == _scope['company_id']) {
          await VehicleDriverPinStore().forget(paired, widget.session.driverId);
        }
      } catch (_) {
        /* Expired pairing does not invalidate the saved personal PIN. */
      }
      if (!mounted || !_current) return;
      _code.clear();
      _pin.clear();
      _confirm.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Je persoonlijke PIN is opgeslagen voor jouw profiel op dit toestel.',
              'Your personal PIN is saved for your profile on this device.',
            ),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted && _current)
        setState(() {
          _recoverWithQr = false;
          _error = widget.freshVerification != null
              ? _text(
                  'Verificatie of opslaan mislukt. Scan je QR-code opnieuw of meld je aan met je vaste chauffeurcode. Je bestaande aanmelding blijft behouden.',
                  'Verification or saving failed. Rescan your QR or sign in with your fixed driver code. Your current session is kept.',
                )
              : _text(
                  'Verificatie of opslaan mislukt. Controleer je vaste chauffeurcode en probeer opnieuw. Je bestaande aanmelding blijft behouden.',
                  'Verification or saving failed. Check your fixed driver code and retry. Your current session is kept.',
                );
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    activeDriverSessionNotifier.removeListener(_sessionChanged);
    _code.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_text('Persoonlijke PIN', 'Personal PIN'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.session.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _text(
                        'Alleen voor jouw chauffeurprofiel op dit toestel. Andere chauffeurs houden hun eigen PIN. Aanmelden blijft altijd door de server gecontroleerd.',
                        'Only for your driver profile on this device. Other drivers keep their own PIN. The server always verifies sign-in.',
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          key: const ValueKey('personal-pin-error'),
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    if (_current && _mode == null) ...[
                      const SizedBox(height: 20),
                      if (!_hasPin)
                        FilledButton.icon(
                          key: const ValueKey('personal-pin-set'),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _mode = 'set'),
                          icon: const Icon(Icons.lock_outline),
                          label: Text(_text('PIN instellen', 'Set PIN')),
                        ),
                      if (_hasPin) ...[
                        OutlinedButton(
                          key: const ValueKey('personal-pin-change'),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _mode = 'change'),
                          child: Text(_text('PIN wijzigen', 'Change PIN')),
                        ),
                        TextButton(
                          key: const ValueKey('personal-pin-reset'),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _mode = 'reset'),
                          child: Text(
                            _text(
                              'PIN vergeten? Veilig opnieuw instellen',
                              'Forgot PIN? Reset securely',
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (_current && _mode != null) ...[
                      const SizedBox(height: 20),
                      if (_fresh)
                        Text(
                          _text(
                            'Je chauffeur is veilig geverifieerd. Kies en bevestig nu je persoonlijke PIN.',
                            'Your driver identity is verified. Choose and confirm your personal PIN.',
                          ),
                        )
                      else
                        TextFormField(
                          key: const ValueKey('personal-pin-driver-code'),
                          controller: _code,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: _text(
                              'Vaste chauffeurcode',
                              'Fixed driver code',
                            ),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? _text(
                                  'Vul je vaste chauffeurcode in.',
                                  'Enter your fixed driver code.',
                                )
                              : null,
                        ),
                      TextFormField(
                        key: const ValueKey('personal-pin-new'),
                        controller: _pin,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: _text(
                            'Nieuwe PIN: zes cijfers',
                            'New PIN: six digits',
                          ),
                        ),
                        validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                            ? null
                            : _text('Gebruik zes cijfers.', 'Use six digits.'),
                      ),
                      TextFormField(
                        key: const ValueKey('personal-pin-confirm'),
                        controller: _confirm,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: _text('Herhaal PIN', 'Repeat PIN'),
                        ),
                        validator: (v) => v == _pin.text
                            ? null
                            : _text('Pincodes verschillen.', 'PINs differ.'),
                      ),
                      FilledButton(
                        key: const ValueKey('personal-pin-save'),
                        onPressed: _busy ? null : _save,
                        child: Text(
                          _busy
                              ? _text('Controleren…', 'Verifying…')
                              : _text(
                                  'PIN veilig opslaan',
                                  'Save PIN securely',
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
