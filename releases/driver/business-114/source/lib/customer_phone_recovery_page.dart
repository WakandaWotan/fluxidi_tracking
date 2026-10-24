import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/auth_failure_kind.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';

class CustomerPhoneRecoveryPage extends StatefulWidget {
  const CustomerPhoneRecoveryPage({super.key});

  static const String newCustomerResult = '__customer_new__';
  static const Key newCustomerKey = Key('customer_phone_new_customer');

  @override
  State<CustomerPhoneRecoveryPage> createState() =>
      _CustomerPhoneRecoveryPageState();
}

class _CustomerPhoneRecoveryPageState extends State<CustomerPhoneRecoveryPage> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  bool _busy = false;
  bool _otpStep = false;
  String _challengeId = '';
  String _verificationChannel = 'sms_otp';
  String _maskedPhone = '';
  String _maskedEmail = '';
  String _debugOtp = '';
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (currentLanguageCode.toLowerCase()) {
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      case 'es':
        return es;
      default:
        return en;
    }
  }

  String _normalizePhoneInput(String raw) {
    return normalizeCustomerSessionPhoneE164(raw);
  }

  bool _looksLikeE164(String value) {
    return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(value);
  }

  String _maskPhoneForLog(String phone) {
    final normalized = _normalizePhoneInput(phone);
    if (!_looksLikeE164(normalized)) return '-';
    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 5) return '+**';
    return '+${digits.substring(0, 2)}******${digits.substring(digits.length - 3)}';
  }

  bool get _loopbackAuthHost =>
      isLoopbackBookingBaseUrl(appConfig.bookingBaseUrl);

  String _customerAuthErrorText(AuthFailureKind kind, {required bool verify}) {
    switch (kind) {
      case AuthFailureKind.wrongEnvironment:
        return _t(
          nl: 'Dit nummer hoort niet bij de lokale debug-Worker (${describePublicAuthHost(appConfig.bookingBaseUrl)}). Gebruik een synthetisch lokaal nummer of een productie-build.',
          en: 'This number is not on the local debug Worker (${describePublicAuthHost(appConfig.bookingBaseUrl)}). Use a synthetic local number or a production build.',
          fr: 'Ce numéro n’est pas sur le Worker local (${describePublicAuthHost(appConfig.bookingBaseUrl)}).',
          es: 'Este número no está en el Worker local (${describePublicAuthHost(appConfig.bookingBaseUrl)}).',
        );
      case AuthFailureKind.localWorkerUnreachable:
        return _t(
          nl: 'De lokale Worker is niet bereikbaar. Start eerst de Worker op ${describePublicAuthHost(appConfig.bookingBaseUrl)}.',
          en: 'The local Worker is unreachable. Start the Worker on ${describePublicAuthHost(appConfig.bookingBaseUrl)} first.',
          fr: 'Le Worker local est injoignable. Démarrez le Worker sur ${describePublicAuthHost(appConfig.bookingBaseUrl)}.',
          es: 'El Worker local no responde. Arranca el Worker en ${describePublicAuthHost(appConfig.bookingBaseUrl)}.',
        );
      case AuthFailureKind.networkError:
        return _t(
          nl: 'Geen verbinding met de aanmeldserver. Controleer het netwerk.',
          en: 'No connection to the sign-in server. Check the network.',
          fr: 'Pas de connexion au serveur. Vérifiez le réseau.',
          es: 'Sin conexión con el servidor. Comprueba la red.',
        );
      case AuthFailureKind.localSmsUnavailable:
        return _t(
          nl: 'Deze omgeving kan geen sms versturen. Op de lokale Worker moet de debug-OTP aan staan.',
          en: 'This environment cannot send SMS. The local Worker must enable debug OTP.',
          fr: 'Cet environnement ne peut pas envoyer de SMS. Le Worker local doit activer l’OTP de debug.',
          es: 'Este entorno no puede enviar SMS. El Worker local debe activar el OTP de debug.',
        );
      case AuthFailureKind.smsNotConfigured:
        return _t(
          nl: 'Sms versturen is tijdelijk niet beschikbaar. Probeer e-mail of later opnieuw.',
          en: 'SMS sending is temporarily unavailable. Try email or try again later.',
          fr: 'L’envoi de SMS est temporairement indisponible. Essayez l’e-mail ou réessayez plus tard.',
          es: 'El envío de SMS no está disponible ahora. Prueba el correo o inténtalo más tarde.',
        );
      case AuthFailureKind.unsupportedPhoneRegion:
        return _t(
          nl: 'Dit landnummer wordt hier niet ondersteund.',
          en: 'This country code is not supported here.',
          fr: 'Cet indicatif n’est pas pris en charge ici.',
          es: 'Este prefijo no está admitido aquí.',
        );
      case AuthFailureKind.rateLimited:
        return _t(
          nl: 'Te veel pogingen. Wacht even en probeer opnieuw.',
          en: 'Too many attempts. Wait a moment and try again.',
          fr: 'Trop de tentatives. Attendez un instant et réessayez.',
          es: 'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
        );
      case AuthFailureKind.invalidPhone:
        return _t(
          nl: 'Gebruik internationaal formaat, bijvoorbeeld +32469788891.',
          en: 'Use international format, for example +32469788891.',
          fr: 'Utilisez le format international, par exemple +32469788891.',
          es: 'Usa formato internacional, por ejemplo +32469788891.',
        );
      case AuthFailureKind.emailNotLinked:
        if (_loopbackAuthHost) {
          return _t(
            nl: 'Voor dit nummer is lokaal geen e-mail gekoppeld. Gebruik op deze debug-Worker “Code verzenden”: de sms-OTP verschijnt hier in het scherm. Echte productie-e-mail hoort niet bij 127.0.0.1:8788.',
            en: 'No email is linked for this number on the local Worker. Use “Send code” on this debug Worker: the SMS OTP appears on this screen. Real production email does not belong on 127.0.0.1:8788.',
            fr: 'Aucun e-mail n’est lié à ce numéro sur le Worker local. Utilisez « Envoyer le code » : l’OTP s’affiche ici. L’e-mail de production n’appartient pas à 127.0.0.1:8788.',
            es: 'No hay correo vinculado a este número en el Worker local. Usa «Enviar código»: el OTP aparece aquí. El correo de producción no pertenece a 127.0.0.1:8788.',
          );
        }
        return _t(
          nl: 'Aan dit nummer is geen e-mail gekoppeld. Gebruik sms of koppel eerst een e-mail in je klantprofiel.',
          en: 'No email is linked to this number. Use SMS or add an email in your customer profile first.',
          fr: 'Aucun e-mail n’est lié à ce numéro. Utilisez le SMS ou ajoutez d’abord un e-mail dans votre profil client.',
          es: 'Este número no tiene correo vinculado. Usa SMS o añade primero un correo en tu perfil de cliente.',
        );
      case AuthFailureKind.verificationFailed:
        return _t(
          nl: 'De code klopt niet of is verlopen. Vraag een nieuwe code.',
          en: 'The code is incorrect or expired. Request a new code.',
          fr: 'Le code est incorrect ou expiré. Demandez un nouveau code.',
          es: 'El código es incorrecto o ha caducado. Solicita uno nuevo.',
        );
      default:
        return verify
            ? _t(
                nl: 'Inloggen mislukt. Controleer code en probeer opnieuw.',
                en: 'Login failed. Check the code and try again.',
                fr: 'Connexion échouée. Vérifiez le code et réessayez.',
                es: 'Inicio de sesión fallido. Verifica el código e inténtalo de nuevo.',
              )
            : _t(
                nl: 'Code verzenden mislukt. Probeer opnieuw.',
                en: 'Sending code failed. Please try again.',
                fr: "L'envoi du code a échoué. Réessayez.",
                es: 'No se pudo enviar el código. Inténtalo de nuevo.',
              );
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final rawPhoneInput = _phoneCtrl.text;
    final phone = _normalizePhoneInput(rawPhoneInput);
    final changed = rawPhoneInput.trim() != phone;
    debugPrint('[CUSTOMER_PHONE_LOGIN][PHONE_NORMALIZED] changed=$changed');
    if (!_looksLikeE164(phone)) {
      setState(() {
        _error = _t(
          nl: 'Gebruik internationaal formaat, bijvoorbeeld +32469788891.',
          en: 'Use international format, for example +32469788891.',
          fr: 'Utilisez le format international, par exemple +32469788891.',
          es: 'Usa formato internacional, por ejemplo +32469788891.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _debugOtp = '';
    });
    try {
      debugPrint(
        '[CUSTOMER_PHONE_LOGIN][START] phone=${_maskPhoneForLog(phone)}',
      );
      final started = await startPublicCustomerPhoneAuth(
        payload: <String, dynamic>{'phone_e164': phone},
      );
      final challengeId =
          (started['challenge_id'] ?? started['challengeId'] ?? '')
              .toString()
              .trim();
      final maskedPhone =
          (started['masked_phone'] ?? started['maskedPhone'] ?? '')
              .toString()
              .trim();
      final debugOtp = (started['debug_otp'] ?? started['debugOtp'] ?? '')
          .toString()
          .trim();
      if (challengeId.isEmpty) {
        throw Exception('challenge_missing');
      }
      if (!mounted) return;
      final autoVerify = _loopbackAuthHost && debugOtp.isNotEmpty;
      setState(() {
        _busy = autoVerify;
        _otpStep = true;
        _challengeId = challengeId;
        _verificationChannel = 'sms_otp';
        _maskedPhone = maskedPhone;
        _maskedEmail = '';
        _debugOtp = debugOtp;
        if (debugOtp.isNotEmpty) {
          _otpCtrl.text = debugOtp;
        }
      });
      if (debugOtp.isNotEmpty) {
        debugPrint('[CUSTOMER_PHONE_LOGIN][DEBUG_OTP_VISIBLE] shown=true');
      }
      if (autoVerify) {
        await _verify(continueFromStart: true);
        return;
      }
    } catch (err) {
      if (!mounted) return;
      final kind = classifyThrownAuthFailure(
        err,
        loopbackHost: _loopbackAuthHost,
        customerAuth: true,
      );
      debugPrint(
        '[CUSTOMER_PHONE_LOGIN][START_FAIL] kind=${authFailureCode(kind)} host=${describePublicAuthHost(appConfig.bookingBaseUrl)}',
      );
      setState(() {
        _busy = false;
        _error = _customerAuthErrorText(kind, verify: false);
      });
    }
  }

  Future<CustomerSession> _persistSessionFromVerifiedResponse({
    required Map<String, dynamic> verified,
    required String phone,
  }) async {
    final token =
        (verified['customer_session_token'] ??
                verified['customerSessionToken'] ??
                '')
            .toString()
            .trim();
    final customerId = (verified['customer_id'] ?? verified['customerId'] ?? '')
        .toString()
        .trim();
    final expiresInSeconds =
        int.tryParse(
          (verified['expires_in_seconds'] ?? verified['expiresInSeconds'] ?? '')
              .toString(),
        ) ??
        (30 * 24 * 60 * 60);
    if (token.isEmpty || customerId.isEmpty) {
      final nested = verified['data'];
      if (nested is Map) {
        final nestedMap = Map<String, dynamic>.from(nested);
        final nestedToken =
            (nestedMap['customer_session_token'] ??
                    nestedMap['customerSessionToken'] ??
                    '')
                .toString()
                .trim();
        final nestedCustomerId =
            (nestedMap['customer_id'] ?? nestedMap['customerId'] ?? '')
                .toString()
                .trim();
        if (nestedToken.isNotEmpty && nestedCustomerId.isNotEmpty) {
          return _persistSessionFromVerifiedResponse(
            verified: nestedMap,
            phone: phone,
          );
        }
      }
      throw Exception('session_missing');
    }
    final now = DateTime.now().toUtc();
    final sessionPhone = normalizeCustomerSessionPhoneE164(phone);
    final session = CustomerSession(
      customerSessionToken: token,
      expiresAt: now.add(Duration(seconds: expiresInSeconds)).toIso8601String(),
      customerId: customerId,
      phoneE164: sessionPhone,
      defaultTenantId: null,
      defaultCompanyId: null,
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    await CustomerSessionStore.instance.save(session);
    // Profile merge/fetch is best-effort. A used OTP is already consumed on
    // the Worker; do not fail login after the session file is written.
    try {
      await CustomerProfileStore.instance.mergeBackendProfileForSession(
        const <String, dynamic>{},
        sessionCustomerId: session.customerId,
        sessionPhoneE164: session.phoneE164,
      );
      final backendProfile = await fetchPublicCustomerProfile(
        customerSessionToken: session.customerSessionToken,
      );
      if (backendProfile != null) {
        await CustomerProfileStore.instance.mergeBackendProfileForSession(
          backendProfile,
          sessionCustomerId: session.customerId,
          sessionPhoneE164: session.phoneE164,
        );
        debugPrint(
          '[CUSTOMER_PROFILE_SYNC][AFTER_PHONE_LOGIN] ok=true reason=merged',
        );
      } else {
        debugPrint(
          '[CUSTOMER_PROFILE_SYNC][AFTER_PHONE_LOGIN] ok=false reason=empty_or_unauthorized',
        );
      }
    } catch (_) {
      debugPrint(
        '[CUSTOMER_PROFILE_SYNC][AFTER_PHONE_LOGIN] ok=false reason=merge_or_fetch_failed',
      );
    }
    return session;
  }

  Future<void> _startEmailFallback() async {
    if (_busy) return;
    final phone = _normalizePhoneInput(_phoneCtrl.text);
    if (!_looksLikeE164(phone)) {
      setState(() {
        _error = _t(
          nl: 'Gebruik eerst een geldig gsm-nummer.',
          en: 'Use a valid phone number first.',
          fr: "Utilisez d'abord un numéro valide.",
          es: 'Primero usa un número válido.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _debugOtp = '';
    });
    try {
      final started = await startPublicCustomerEmailAuth(
        payload: <String, dynamic>{'phone_e164': phone},
      );
      final challengeId =
          (started['challenge_id'] ?? started['challengeId'] ?? '')
              .toString()
              .trim();
      final maskedEmail =
          (started['masked_email'] ?? started['maskedEmail'] ?? '')
              .toString()
              .trim();
      final debugOtp = (started['debug_otp'] ?? started['debugOtp'] ?? '')
          .toString()
          .trim();
      if (challengeId.isEmpty) {
        throw Exception('challenge_missing');
      }
      if (!mounted) return;
      final autoVerify = _loopbackAuthHost && debugOtp.isNotEmpty;
      setState(() {
        _busy = autoVerify;
        _otpStep = true;
        _challengeId = challengeId;
        _verificationChannel = 'email_otp';
        _maskedEmail = maskedEmail;
        _debugOtp = debugOtp;
        if (debugOtp.isNotEmpty) {
          _otpCtrl.text = debugOtp;
        }
      });
      if (autoVerify) {
        await _verify(continueFromStart: true);
        return;
      }
    } catch (err) {
      if (!mounted) return;
      final kind = classifyThrownAuthFailure(
        err,
        loopbackHost: _loopbackAuthHost,
        customerAuth: true,
      );
      debugPrint(
        '[CUSTOMER_EMAIL_LOGIN][START_FAIL] kind=${authFailureCode(kind)} host=${describePublicAuthHost(appConfig.bookingBaseUrl)}',
      );
      setState(() {
        _busy = false;
        _error = _customerAuthErrorText(kind, verify: false);
      });
    }
  }

  void _goNewCustomer() {
    if (_busy) return;
    Navigator.of(context).pop<Object>(CustomerPhoneRecoveryPage.newCustomerResult);
  }

  Future<void> _verify({bool continueFromStart = false}) async {
    if (_busy && !continueFromStart) return;
    final rawPhoneInput = _phoneCtrl.text;
    final phone = _normalizePhoneInput(rawPhoneInput);
    final changed = rawPhoneInput.trim() != phone;
    debugPrint('[CUSTOMER_PHONE_LOGIN][PHONE_NORMALIZED] changed=$changed');
    final otp = _otpCtrl.text.trim();
    if (!_looksLikeE164(phone) || _challengeId.trim().isEmpty) {
      setState(() {
        _busy = false;
        _error = _t(
          nl: 'Start eerst met een geldig gsm-nummer.',
          en: 'Start first with a valid phone number.',
          fr: "Commencez d'abord avec un numéro valide.",
          es: 'Primero inicia con un número válido.',
        );
      });
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(otp)) {
      setState(() {
        _busy = false;
        _error = _t(
          nl: 'Vul een geldige code in.',
          en: 'Enter a valid code.',
          fr: 'Saisissez un code valide.',
          es: 'Introduce un código válido.',
        );
      });
      return;
    }
    if (!continueFromStart) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final verified = _verificationChannel == 'email_otp'
          ? await verifyPublicCustomerEmailAuth(
              payload: <String, dynamic>{
                'challenge_id': _challengeId,
                'phone_e164': phone,
                'otp': otp,
              },
            )
          : await verifyPublicCustomerPhoneAuth(
              payload: <String, dynamic>{
                'challenge_id': _challengeId,
                'phone_e164': phone,
                'otp': otp,
              },
            );
      final session = await _persistSessionFromVerifiedResponse(
        verified: verified,
        phone: phone,
      );
      final customerId = session.customerId;
      debugPrint(
        '[CUSTOMER_PHONE_LOGIN][VERIFY_OK] customer=${customerId.length > 4 ? customerId.substring(customerId.length - 4) : customerId}',
      );
      if (!mounted) return;
      Navigator.of(context).pop<Object>(session);
    } catch (err) {
      if (!mounted) return;
      final persistMissed = err.toString().toLowerCase().contains(
        'session_missing',
      );
      final kind = persistMissed
          ? AuthFailureKind.generic
          : classifyThrownAuthFailure(
              err,
              loopbackHost: _loopbackAuthHost,
              customerAuth: true,
            );
      debugPrint(
        '[CUSTOMER_PHONE_LOGIN][VERIFY_FAIL] phone=${_maskPhoneForLog(phone)} kind=${authFailureCode(kind)} persist_missed=$persistMissed',
      );
      setState(() {
        _busy = false;
        _error = persistMissed
            ? _t(
                nl: 'De code was geldig, maar de sessie kon niet worden opgeslagen. Kies Nieuwe klant of vraag een nieuwe code.',
                en: 'The code was valid, but the session could not be saved. Choose New customer or request a new code.',
                fr: 'Le code était valide, mais la session n’a pas pu être enregistrée. Choisissez Nouveau client ou demandez un nouveau code.',
                es: 'El código era válido, pero no se pudo guardar la sesión. Elige Cliente nuevo o pide un código nuevo.',
              )
            : _customerAuthErrorText(kind, verify: true);
        if (kind == AuthFailureKind.verificationFailed || persistMissed) {
          _otpStep = false;
          _challengeId = '';
          _debugOtp = '';
          _otpCtrl.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appConfig.backgroundColor,
      appBar: AppBar(
        backgroundColor: appConfig.backgroundColor,
        elevation: 0,
        title: Text(
          _t(
            nl: 'Inloggen met gsm',
            en: 'Login with phone',
            fr: 'Connexion avec gsm',
            es: 'Iniciar con móvil',
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF121A2E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFE5B641).withOpacity(0.32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _otpStep
                          ? _t(
                              nl: 'Voer je code in',
                              en: 'Enter your code',
                              fr: 'Entrez votre code',
                              es: 'Introduce tu código',
                            )
                          : _t(
                              nl: 'Login met gsm',
                              en: 'Phone login',
                              fr: 'Connexion gsm',
                              es: 'Acceso con móvil',
                            ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        nl: 'Gebruik internationaal formaat (E.164), bijvoorbeeld +32469788891.',
                        en: 'Use international format (E.164), for example +32469788891.',
                        fr: 'Utilisez le format international (E.164), par exemple +32469788891.',
                        es: 'Usa formato internacional (E.164), por ejemplo +32469788891.',
                      ),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loopbackAuthHost
                          ? _t(
                              nl: 'Lokale debug-Worker (${describePublicAuthHost(appConfig.bookingBaseUrl)}). De testcode verschijnt hier op het scherm. Dit nummer blijft op deze Worker.',
                              en: 'Local debug Worker (${describePublicAuthHost(appConfig.bookingBaseUrl)}). The test code appears on this screen. This number stays on this Worker.',
                              fr: 'Worker de debug local (${describePublicAuthHost(appConfig.bookingBaseUrl)}). Le code test s’affiche ici. Ce numéro reste sur ce Worker.',
                              es: 'Worker local de debug (${describePublicAuthHost(appConfig.bookingBaseUrl)}). El código de prueba aparece aquí. Este número se queda en este Worker.',
                            )
                          : _t(
                              nl: 'Productie-aanmeldserver (${describePublicAuthHost(appConfig.bookingBaseUrl)}). Je ontvangt een echte sms- of e-mailcode.',
                              en: 'Production sign-in server (${describePublicAuthHost(appConfig.bookingBaseUrl)}). You will receive a real SMS or email code.',
                              fr: 'Serveur de connexion production (${describePublicAuthHost(appConfig.bookingBaseUrl)}). Vous recevrez un vrai code SMS ou e-mail.',
                              es: 'Servidor de acceso de producción (${describePublicAuthHost(appConfig.bookingBaseUrl)}). Recibirás un código real por SMS o correo.',
                            ),
                      style: TextStyle(
                        color: _loopbackAuthHost
                            ? const Color(0xFFE5B641)
                            : Colors.white.withOpacity(0.72),
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneCtrl,
                      enabled: !_busy && !_otpStep,
                      onChanged: (_) {
                        if (_debugOtp.isEmpty) return;
                        setState(() {
                          _debugOtp = '';
                        });
                      },
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Gsm-nummer',
                          en: 'Phone number',
                          fr: 'Numéro GSM',
                          es: 'Número móvil',
                        ),
                        hintText: '+324...',
                        filled: true,
                        fillColor: const Color(0xFF0B0B0B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_otpStep) ...[
                      const SizedBox(height: 10),
                      if (_verificationChannel == 'email_otp' &&
                          _maskedEmail.trim().isNotEmpty)
                        Text(
                          _t(
                            nl: 'Code verzonden naar: $_maskedEmail',
                            en: 'Code sent to: $_maskedEmail',
                            fr: 'Code envoyé à : $_maskedEmail',
                            es: 'Código enviado a: $_maskedEmail',
                          ),
                          style: TextStyle(
                            color: appConfig.primaryColor.withOpacity(0.95),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (_verificationChannel != 'email_otp' &&
                          _maskedPhone.trim().isNotEmpty)
                        Text(
                          _t(
                            nl: 'Code verzonden naar: $_maskedPhone',
                            en: 'Code sent to: $_maskedPhone',
                            fr: 'Code envoyé à : $_maskedPhone',
                            es: 'Código enviado a: $_maskedPhone',
                          ),
                          style: TextStyle(
                            color: appConfig.primaryColor.withOpacity(0.95),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (_debugOtp.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: appConfig.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: appConfig.primaryColor.withOpacity(0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _t(
                                    nl: 'Testcode: $_debugOtp',
                                    en: 'Test code: $_debugOtp',
                                    fr: 'Code test : $_debugOtp',
                                    es: 'Código de prueba: $_debugOtp',
                                  ),
                                  style: TextStyle(
                                    color: appConfig.primaryColor.withOpacity(
                                      0.98,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  _otpCtrl.text = _debugOtp;
                                },
                                child: Text(
                                  _t(
                                    nl: 'Vul code in',
                                    en: 'Fill code',
                                    fr: 'Remplir code',
                                    es: 'Rellenar código',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _otpCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: _t(
                            nl: 'OTP code',
                            en: 'OTP code',
                            fr: 'Code OTP',
                            es: 'Código OTP',
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0B0B0B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                    if ((_error ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFE88989),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _busy ? null : (_otpStep ? _verify : _start),
                      child: Text(
                        _busy
                            ? _t(
                                nl: 'Even geduld...',
                                en: 'Please wait...',
                                fr: 'Veuillez patienter...',
                                es: 'Espera por favor...',
                              )
                            : _otpStep
                            ? _t(
                                nl: 'Inloggen',
                                en: 'Login',
                                fr: 'Connexion',
                                es: 'Iniciar sesión',
                              )
                            : _t(
                                nl: 'Code verzenden',
                                en: 'Send code',
                                fr: 'Envoyer le code',
                                es: 'Enviar código',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _startEmailFallback,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: appConfig.primaryColor.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        _t(
                          nl: 'Code via e-mail ontvangen',
                          en: 'Receive code via e-mail',
                          fr: 'Recevoir le code par e-mail',
                          es: 'Recibir código por correo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: CustomerPhoneRecoveryPage.newCustomerKey,
                      onPressed: _busy ? null : _goNewCustomer,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: appConfig.primaryColor.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        _t(
                          nl: 'Nieuwe klant',
                          en: 'New customer',
                          fr: 'Nouveau client',
                          es: 'Cliente nuevo',
                        ),
                      ),
                    ),
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
