import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_phone_recovery_page.dart';
import 'package:fluxidi_tracking/affiliate/company_referral_registration.dart';

/// Collects mandatory company identifiers before entering the admin/business hub.
class CompanyOnboardingPage extends StatefulWidget {
  const CompanyOnboardingPage({
    super.key,
    required this.onCompleted,
    this.initialCompanyId,
    this.lockCompanyId = false,
    this.initialReferralCode,
  });

  /// Called after local profile + session are saved. Should replace with [BusinessHomePage].
  final void Function(BuildContext context) onCompleted;
  final String? initialCompanyId;
  final bool lockCompanyId;
  final String? initialReferralCode;

  @override
  State<CompanyOnboardingPage> createState() => _CompanyOnboardingPageState();
}

class _CompanyOnboardingPageState extends State<CompanyOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _companyIdCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  final _referralRegistration = CompanyReferralRegistrationClient();
  String _country = 'BE';
  bool _saving = false;

  String _t({required String nl, required String en, String? fr, String? es}) {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) return en;
    if (lang == AppLanguage.fr) return fr ?? en;
    if (lang == AppLanguage.es) return es ?? en;
    return nl;
  }

  String _normalizeHumanCompanyId(String raw) {
    var text = raw.trim().toUpperCase();
    text = text.replaceAll(RegExp(r'\s+'), '-');
    text = text.replaceAll(RegExp(r'-+'), '-');
    return text;
  }

  String? _validateHumanCompanyId(String raw, {required bool required}) {
    final value = _normalizeHumanCompanyId(raw);
    if (value.isEmpty) {
      if (!required) return null;
      return _t(
        nl: 'Vul een bedrijfs-ID in.',
        en: 'Enter a company ID.',
        fr: 'Saisissez un ID d’entreprise.',
        es: 'Introduce un ID de empresa.',
      );
    }
    if (value.length < 4 || value.length > 24) {
      return _t(
        nl: 'Bedrijfs-ID moet tussen 4 en 24 tekens zijn.',
        en: 'Company ID must be between 4 and 24 characters.',
        fr: 'L’ID d’entreprise doit contenir entre 4 et 24 caractères.',
        es: 'El ID de empresa debe tener entre 4 y 24 caracteres.',
      );
    }
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(value)) {
      return _t(
        nl: 'Gebruik alleen A-Z, 0-9 en koppelteken (-).',
        en: 'Use only A-Z, 0-9 and hyphen (-).',
        fr: 'Utilisez uniquement A-Z, 0-9 et le tiret (-).',
        es: 'Usa solo A-Z, 0-9 y guion (-).',
      );
    }
    if (!RegExp(r'[A-Z0-9]').hasMatch(value)) {
      return _t(
        nl: 'Bedrijfs-ID moet letters of cijfers bevatten.',
        en: 'Company ID must contain letters or digits.',
        fr: 'L’ID d’entreprise doit contenir des lettres ou des chiffres.',
        es: 'El ID de empresa debe contener letras o dígitos.',
      );
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCompanyId?.trim() ?? '';
    if (initial.isNotEmpty) {
      _companyIdCtrl.text = _normalizeHumanCompanyId(initial);
    }
    _referralCtrl.text = widget.initialReferralCode?.trim().toUpperCase() ?? '';
  }

  @override
  void dispose() {
    _companyIdCtrl.dispose();
    _companyCtrl.dispose();
    _ownerCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _vatCtrl.dispose();
    _cityCtrl.dispose();
    _referralCtrl.dispose();
    _referralRegistration.dispose();
    super.dispose();
  }

  String _registrationErrorMessage(String code) {
    switch (code) {
      case 'affiliate_personal_login_required':
        return _t(
          nl: 'Log persoonlijk in om je affiliatecode te gebruiken.',
          en: 'Sign in personally to use your affiliate code.',
          fr: 'Connectez-vous à votre compte personnel pour utiliser le code.',
          es: 'Inicia sesión con tu cuenta personal para usar el código.',
        );
      case 'affiliate_registration_intent_locked':
      case 'affiliate_registration_completion_pending':
        return _t(
          nl: 'Een eerdere aanvraag wacht op afronding. Gebruik dezelfde gegevens; neem contact op als dit blijft staan.',
          en: 'A previous application is awaiting completion. Use the same details; contact us if this persists.',
          fr: 'Une demande précédente attend sa finalisation. Utilisez les mêmes données ; contactez-nous si cela persiste.',
          es: 'Una solicitud anterior está pendiente. Usa los mismos datos; contacta si el problema continúa.',
        );
      case 'affiliate_program_not_enabled':
      case 'affiliate_terms_not_configured':
      case 'affiliate_not_configured':
        return _t(
          nl: 'Het affiliateprogramma is nog niet beschikbaar. Je affiliatecode blijft ingevuld.',
          en: 'The affiliate programme is not available yet. Your affiliate code is preserved.',
          fr: 'Le programme d’affiliation n’est pas encore disponible. Votre code est conservé.',
          es: 'El programa de afiliados aún no está disponible. Tu código se conserva.',
        );
      case 'affiliate_referral_unavailable':
        return _t(
          nl: 'Deze affiliatecode is niet actief. Controleer de code.',
          en: 'This affiliate code is not active. Check the code.',
          fr: 'Ce code n’est pas actif. Vérifiez le code.',
          es: 'Este código no está activo. Comprueba el código.',
        );
      case 'invalid_belgian_vat_number':
        return _t(
          nl: 'Ongeldig Belgisch BTW/KBO-nummer. Controleer het formaat (BE########## of 10 cijfers).',
          en: 'Invalid Belgian VAT/KBO number. Check format (BE########## or 10 digits).',
          fr: 'Numéro TVA/KBO belge invalide. Vérifiez le format (BE########## ou 10 chiffres).',
          es: 'Número de IVA/KBO belga no válido. Revisa el formato (BE########## o 10 dígitos).',
        );
      case 'missing_company_name':
        return _t(
          nl: 'Bedrijfsnaam is verplicht.',
          en: 'Company name is required.',
          fr: 'Le nom de l’entreprise est obligatoire.',
          es: 'El nombre de la empresa es obligatorio.',
        );
      default:
        return _t(
          nl: 'Registratie mislukt. Probeer opnieuw.',
          en: 'Registration failed. Please try again.',
          fr: 'Échec de l’inscription. Réessayez.',
          es: 'El registro falló. Inténtalo de nuevo.',
        );
    }
  }

  String _parseRegistrationErrorCode(Object error) {
    if (error is CompanyReferralException) return error.code;
    if (error is CompanyRegistrationPersistenceException) {
      return error.code == 'session_changed'
          ? 'affiliate_session_changed'
          : 'affiliate_registration_storage_unavailable';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('invalid_belgian_vat_number')) {
      return 'invalid_belgian_vat_number';
    }
    if (text.contains('missing_company_name')) {
      return 'missing_company_name';
    }
    if (text.contains('registration_failed')) {
      return 'registration_failed';
    }
    return 'registration_failed';
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    var expectedProfile = companyProfileNotifier.value;
    var expectedCompanySession = activeCompanySessionNotifier.value;
    var guardedStoreIsAdopting = false;
    bool currentRegistrationOwner() =>
        mounted &&
        (guardedStoreIsAdopting ||
            identical(companyProfileNotifier.value, expectedProfile) &&
                identical(
                  activeCompanySessionNotifier.value,
                  expectedCompanySession,
                ));
    CompanyReferralAttempt? referralAttempt;
    void checkReferralOwner() {
      if (referralAttempt != null &&
          (!mounted || !_referralRegistration.owns(referralAttempt))) {
        throw const CompanyReferralException('affiliate_session_changed');
      }
    }

    try {
      final payload = <String, dynamic>{
        'company_name': _companyCtrl.text.trim(),
        'companyName': _companyCtrl.text.trim(),
        'legal_name': _companyCtrl.text.trim(),
        'legalName': _companyCtrl.text.trim(),
        'vat_number': _vatCtrl.text.trim(),
        'vatNumber': _vatCtrl.text.trim(),
        'company_registration_number': _vatCtrl.text.trim(),
        'companyRegistrationNumber': _vatCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'companyEmail': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'owner_phone': _phoneCtrl.text.trim(),
        'country': _country.trim().isEmpty
            ? 'BE'
            : _country.trim().toUpperCase(),
        'city': _cityCtrl.text.trim(),
        'postcode': '',
        'address': '',
      };
      debugPrint('[COMPANY_REGISTER][REQ] company=${payload['company_name']}');
      final referralCode = _referralCtrl.text.trim();
      final Map<String, dynamic> result;
      if (referralCode.isEmpty) {
        await _referralRegistration.ensureNoPendingReferral();
        if (!mounted) return;
        result = await registerPublicCompany(payload: payload);
      } else {
        referralAttempt = await _referralRegistration.register(
          payload: payload,
          referralCode: referralCode,
          isCurrentRegistration: currentRegistrationOwner,
        );
        checkReferralOwner();
        result = referralAttempt.result;
      }
      final tenantId = (result['tenant_id'] ?? result['tenantId'] ?? '')
          .toString()
          .trim();
      final companyId = (result['company_id'] ?? result['companyId'] ?? '')
          .toString()
          .trim();
      final companyCode =
          (result['public_company_code'] ??
                  result['publicCompanyCode'] ??
                  result['company_code'] ??
                  result['companyCode'] ??
                  '')
              .toString()
              .trim();
      final companySessionToken =
          (result['company_session_token'] ??
                  result['companySessionToken'] ??
                  '')
              .toString()
              .trim();
      if (tenantId.isEmpty ||
          companyId.isEmpty ||
          companyCode.isEmpty ||
          companySessionToken.isEmpty) {
        throw Exception('registration_failed');
      }
      final businessProfileNode = result['business_profile'];
      final businessProfileMap = businessProfileNode is Map
          ? Map<String, dynamic>.from(businessProfileNode)
          : <String, dynamic>{};
      for (final key in const <String>[
        'company_code',
        'companyCode',
        'public_company_code',
        'publicCompanyCode',
        'public_company_slug',
        'publicCompanySlug',
        'public_display_code',
        'publicDisplayCode',
      ]) {
        final value = (result[key] ?? '').toString().trim();
        if (value.isNotEmpty &&
            (businessProfileMap[key] ?? '').toString().trim().isEmpty) {
          businessProfileMap[key] = value;
        }
      }
      if (businessProfileMap.isNotEmpty && referralAttempt == null) {
        final backendBusinessProfile = BackendBusinessProfile.fromJson(
          businessProfileMap,
        );
        checkReferralOwner();
        await updateLocalBackendBusinessProfileCache(backendBusinessProfile);
        checkReferralOwner();
      }
      final companyName =
          (businessProfileMap['companyName'] ??
                  businessProfileMap['company_name'] ??
                  _companyCtrl.text)
              .toString()
              .trim();
      final countryCode = (businessProfileMap['country'] ?? _country)
          .toString()
          .trim()
          .toUpperCase();
      final ownerName = _ownerCtrl.text.trim();
      final email =
          (businessProfileMap['email'] ??
                  businessProfileMap['companyEmail'] ??
                  _emailCtrl.text)
              .toString()
              .trim();
      final phone = (businessProfileMap['phone'] ?? _phoneCtrl.text)
          .toString()
          .trim();
      final vatNumber =
          (businessProfileMap['vatNumber'] ??
                  businessProfileMap['vat_number'] ??
                  _vatCtrl.text)
              .toString()
              .trim();
      final city = (businessProfileMap['city'] ?? _cityCtrl.text)
          .toString()
          .trim();
      final postcode = (businessProfileMap['postcode'] ?? '').toString().trim();
      final address = (businessProfileMap['address'] ?? '').toString().trim();
      final issuedAtRaw = (result['issued_at'] ?? '').toString().trim();
      final expiresAtRaw = (result['expires_at'] ?? '').toString().trim();
      final expiresInSeconds = int.tryParse(
        (result['expires_in'] ?? result['expiresIn'] ?? '').toString().trim(),
      );
      checkReferralOwner();
      // Entry is synchronous after the pre-HTTP fence. The guarded store then
      // checks its own captured company references through IO and adoption.
      guardedStoreIsAdopting = referralAttempt != null;
      await CompanySessionStore.instance.savePublicCompanyRegistrationSession(
        tenantId: tenantId,
        companyId: companyId,
        companyCode: companyCode,
        companyName: companyName,
        countryCode: countryCode,
        companySessionToken: companySessionToken,
        ownerName: ownerName,
        email: email,
        phone: phone,
        vatNumber: vatNumber,
        addressLine: address,
        postalCode: postcode,
        city: city,
        issuedAt: DateTime.tryParse(issuedAtRaw),
        expiresAt: DateTime.tryParse(expiresAtRaw),
        expiresInSeconds: expiresInSeconds,
        isCurrentRegistration: referralAttempt == null
            ? null
            : () => mounted && _referralRegistration.owns(referralAttempt!),
      );
      if (referralAttempt != null) {
        final savedProfile = companyProfileNotifier.value;
        final savedSession = activeCompanySessionNotifier.value;
        if (savedProfile?.companyId != companyId ||
            savedSession?.companyId != companyId ||
            savedSession?.companySessionToken != companySessionToken) {
          throw const CompanyReferralException('affiliate_session_changed');
        }
        expectedProfile = savedProfile;
        expectedCompanySession = savedSession;
      }
      guardedStoreIsAdopting = false;
      checkReferralOwner();
      // Referral persistence uses its guarded store commit. The normal hub
      // loads bootstrap afterwards; the legacy cache helpers adopt globals
      // internally and cannot fence a different personal login mid-await.
      if (referralAttempt == null) {
        final bootstrap = await fetchCompanyBootstrapWithToken(
          companySessionToken: companySessionToken,
        );
        if (bootstrap != null)
          await hydrateCompanyStateFromBootstrap(bootstrap);
      }
      if (referralAttempt != null) {
        await _referralRegistration.complete(referralAttempt);
        checkReferralOwner();
      }
      debugPrint('[COMPANY_REGISTER][OK] company=$companyId');
    } catch (e) {
      final errorCode = _parseRegistrationErrorCode(e);
      debugPrint('[COMPANY_REGISTER][FAIL] code=$errorCode');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_registrationErrorMessage(errorCode))),
      );
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    widget.onCompleted(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        title: Text(
          _t(
            nl: 'Bedrijf instellen',
            en: 'Set up your business',
            fr: 'Configurer votre entreprise',
            es: 'Configurar su empresa',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop();
                },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
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
                          nl: 'Vul je bedrijfsgegevens in. Je krijgt een vaste bedrijfs-ID op dit toestel.',
                          en: 'Enter your business details. You will receive a stable company ID on this device.',
                          fr: 'Saisissez les données de votre entreprise. Vous recevrez un ID d’entreprise stable sur cet appareil.',
                          es: 'Introduce los datos de tu empresa. Recibirás un ID de empresa estable en este dispositivo.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _companyIdCtrl,
                        readOnly: widget.lockCompanyId,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white),
                        decoration:
                            _decoration(
                              _t(
                                nl: 'Bedrijfs-ID',
                                en: 'Company ID',
                                fr: 'ID d’entreprise',
                                es: 'ID de empresa',
                              ),
                            ).copyWith(
                              suffixIcon: widget.lockCompanyId
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Center(
                                        widthFactor: 1,
                                        child: Text(
                                          _t(
                                            nl: 'ID vergrendeld',
                                            en: 'ID locked',
                                            fr: 'ID verrouillé',
                                            es: 'ID bloqueado',
                                          ),
                                          style: TextStyle(
                                            color: const Color(0xFFE5B641),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                        onChanged: widget.lockCompanyId
                            ? null
                            : (value) {
                                final normalized = _normalizeHumanCompanyId(
                                  value,
                                );
                                if (normalized == value) return;
                                _companyIdCtrl.value = TextEditingValue(
                                  text: normalized,
                                  selection: TextSelection.collapsed(
                                    offset: normalized.length,
                                  ),
                                );
                              },
                        validator: (value) => _validateHumanCompanyId(
                          value ?? '',
                          required: widget.lockCompanyId,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          nl: 'Dit is de eenvoudige code waarmee uw bedrijf later op tablets of chauffeursapparaten kan worden gekoppeld.',
                          en: 'This is the simple code used to link your company later on tablets or driver devices.',
                          fr: 'Il s’agit du code simple utilisé pour lier votre entreprise plus tard sur des tablettes ou appareils chauffeurs.',
                          es: 'Es el código simple que se usa para vincular su empresa más adelante en tablets o dispositivos de conductores.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 11.7,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _companyCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'Bedrijfsnaam',
                            en: 'Company name',
                            fr: 'Nom de l’entreprise',
                            es: 'Nombre de la empresa',
                          ),
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? _t(
                                nl: 'Vul je bedrijfsnaam in.',
                                en: 'Enter your company name.',
                                fr: 'Saisissez le nom de votre entreprise.',
                                es: 'Introduce el nombre de tu empresa.',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ownerCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'Naam contactpersoon',
                            en: 'Contact name',
                            fr: 'Nom du contact',
                            es: 'Nombre del contacto',
                          ),
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? _t(
                                nl: 'Vul een contactnaam in.',
                                en: 'Enter a contact name.',
                                fr: 'Saisissez un nom de contact.',
                                es: 'Introduce un nombre de contacto.',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'E-mail',
                            en: 'Email',
                            fr: 'E-mail',
                            es: 'Correo electrónico',
                          ),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) {
                            return _t(
                              nl: 'Vul je e-mail in.',
                              en: 'Enter your email.',
                              fr: 'Saisissez votre e-mail.',
                              es: 'Introduce tu correo electrónico.',
                            );
                          }
                          if (!t.contains('@')) {
                            return _t(
                              nl: 'Vul een geldig e-mailadres in.',
                              en: 'Enter a valid email address.',
                              fr: 'Saisissez une adresse e-mail valide.',
                              es: 'Introduce una dirección de correo válida.',
                            );
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'Telefoon',
                            en: 'Phone',
                            fr: 'Téléphone',
                            es: 'Teléfono',
                          ),
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? _t(
                                nl: 'Vul je telefoonnummer in.',
                                en: 'Enter your phone number.',
                                fr: 'Saisissez votre numéro de téléphone.',
                                es: 'Introduce tu número de teléfono.',
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _vatCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'BTW-nummer (optioneel)',
                            en: 'VAT number (optional)',
                            fr: 'Numéro TVA (optionnel)',
                            es: 'Número de IVA (opcional)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('company_referral_code'),
                        controller: _referralCtrl,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'Affiliatecode (optioneel)',
                            en: 'Affiliate code (optional)',
                            fr: 'Code d’affiliation (facultatif)',
                            es: 'Código de afiliado (opcional)',
                          ),
                        ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ||
                                RegExp(
                                  r'^[A-Za-z0-9-]{3,40}$',
                                ).hasMatch((value ?? '').trim())
                            ? null
                            : _t(
                                nl: 'Controleer de affiliatecode.',
                                en: 'Check the affiliate code.',
                                fr: 'Vérifiez le code.',
                                es: 'Comprueba el código.',
                              ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('company_referral_personal_signin'),
                          icon: const Icon(Icons.person_outline),
                          label: Text(
                            _t(
                              nl: 'Inloggen om je affiliatecode te gebruiken',
                              en: 'Sign in to use your affiliate code',
                              fr: 'Se connecter pour utiliser votre code d’affiliation',
                              es: 'Inicia sesión para usar tu código de afiliado',
                            ),
                          ),
                          onPressed: _saving
                              ? null
                              : () async {
                                  final result = await Navigator.of(context)
                                      .push<Object?>(
                                        MaterialPageRoute<Object?>(
                                          builder: (_) =>
                                              const CustomerPhoneRecoveryPage(),
                                        ),
                                      );
                                  if (!mounted || !context.mounted) return;
                                  if (result ==
                                      CustomerPhoneRecoveryPage
                                          .newCustomerResult) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _t(
                                            nl: 'Maak eerst je persoonlijke klantenaccount aan.',
                                            en: 'Create your personal customer account first.',
                                            fr: 'Créez d’abord votre compte client personnel.',
                                            es: 'Crea primero tu cuenta personal de cliente.',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cityCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(
                            nl: 'Stad (optioneel)',
                            en: 'City (optional)',
                            fr: 'Ville (optionnel)',
                            es: 'Ciudad (opcional)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _country,
                        dropdownColor: const Color(0xFF111111),
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                          _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'BE', child: Text('BE')),
                          DropdownMenuItem(value: 'NL', child: Text('NL')),
                          DropdownMenuItem(value: 'FR', child: Text('FR')),
                          DropdownMenuItem(value: 'ES', child: Text('ES')),
                          DropdownMenuItem(value: 'LU', child: Text('LU')),
                          DropdownMenuItem(value: 'DE', child: Text('DE')),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _country = v);
                              },
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _saving ? null : () => _save(),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE5B641),
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black54,
                                ),
                              )
                            : Text(
                                _t(
                                  nl: 'Opslaan en verder',
                                  en: 'Save and continue',
                                  fr: 'Enregistrer et continuer',
                                  es: 'Guardar y continuar',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
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
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
      filled: true,
      fillColor: const Color(0xFF141B2F),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

/// Edit full local company profile; preserves [CompanyProfile.companyId] and [createdAt].
class CompanyProfileEditPage extends StatefulWidget {
  const CompanyProfileEditPage({
    super.key,
    this.fetchBusinessProfile,
    this.saveBusinessProfile,
    this.confirmPendingEmail,
  });

  final Future<BackendBusinessProfile> Function()? fetchBusinessProfile;
  final Future<BackendBusinessProfile> Function(BackendBusinessProfile profile)?
  saveBusinessProfile;
  final Future<BackendBusinessProfile> Function({
    required String email,
    required String challengeId,
    required String otp,
    required String companyCode,
  })?
  confirmPendingEmail;

  @override
  State<CompanyProfileEditPage> createState() => _CompanyProfileEditPageState();
}

class _CompanyProfileEditPageState extends State<CompanyProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _companyEmailCtrl = TextEditingController();
  final _supportEmailCtrl = TextEditingController();
  final _billingEmailCtrl = TextEditingController();
  final _bookingEmailCtrl = TextEditingController();
  final _notificationEmailCtrl = TextEditingController();
  String _country = 'BE';
  bool _loading = true;
  bool _saving = false;
  String? _companyId;
  String? _createdAt;
  String _verificationStatus = CompanyVerificationStatus.pendingVerification;
  String? _saveError;
  String? _pendingNotice;
  String? _confirmSuccess;
  String _pendingEmail = '';
  String _emailChallengeId = '';
  final _otpCtrl = TextEditingController();
  bool _confirming = false;

  Future<BackendBusinessProfile> _fetchBusinessProfile() {
    final fetch = widget.fetchBusinessProfile;
    if (fetch != null) return fetch();
    return fetchBackendBusinessProfile(companyId: _companyId);
  }

  Future<BackendBusinessProfile> _persistBusinessProfile(
    BackendBusinessProfile profile,
  ) {
    final save = widget.saveBusinessProfile;
    if (save != null) return save(profile);
    return saveBackendBusinessProfile(profile, companyId: _companyId);
  }

  String _t({required String nl, required String en}) {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) return en;
    return nl;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activeCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    final p = activeCompanyId.isNotEmpty
        ? await CompanySessionStore.instance.loadProfileForCompany(
            activeCompanyId,
          )
        : companyProfileNotifier.value ??
              await CompanySessionStore.instance.loadProfile();
    if (!mounted) return;
    if (p == null) {
      setState(() => _loading = false);
      return;
    }
    _companyId = p.companyId;
    _createdAt = p.createdAt;
    _verificationStatus = p.verificationStatus;
    BackendBusinessProfile? backend;
    try {
      backend = await _fetchBusinessProfile();
    } catch (_) {
      final cached = localBackendBusinessProfileNotifier.value;
      if (cached?.companyId == p.companyId) backend = cached;
    }
    if (!mounted) return;
    if (backend != null &&
        backend.companyId.isNotEmpty &&
        backend.companyId != p.companyId) {
      setState(() {
        _loading = false;
        _saveError = 'Bedrijfsgegevens horen bij een ander bedrijf.';
      });
      return;
    }
    if (backend != null) {
      localBackendBusinessProfileNotifier.value = backend;
      unawaited(updateLocalBackendBusinessProfileCache(backend));
    }
    final shown = backend == null
        ? p
        : reconcileCompanyProfileWithBackend(local: p, backend: backend);
    _companyCtrl.text = shown.companyName;
    _ownerCtrl.text = shown.ownerName;
    _phoneCtrl.text = shown.phone;
    _vatCtrl.text = shown.vatNumber;
    _addressCtrl.text = shown.addressLine;
    _postalCtrl.text = shown.postalCode;
    _cityCtrl.text = shown.city;
    _companyEmailCtrl.text = shown.companyEmail;
    _supportEmailCtrl.text = shown.supportEmail;
    _billingEmailCtrl.text = shown.billingEmail;
    _bookingEmailCtrl.text = shown.bookingEmail;
    _notificationEmailCtrl.text = shown.notificationEmail;
    _country = shown.countryCode.isNotEmpty ? shown.countryCode : 'BE';
    _emailCtrl.text = resolvePrimaryCompanyContactEmail(
      backend: backend,
      local: p,
    );
    _pendingEmail = (backend?.pendingEmail ?? '').trim();
    _emailChallengeId = (backend?.emailChallengeId ?? '').trim();
    if (_pendingEmail.isNotEmpty) {
      _pendingNotice = _t(
        nl: 'Nieuwe e-mail wacht op bevestiging. De huidige herstelmail blijft actief tot de code is bevestigd.',
        en: 'The new email is waiting for confirmation. The current recovery email stays active until the code is confirmed.',
      );
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _ownerCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _vatCtrl.dispose();
    _addressCtrl.dispose();
    _postalCtrl.dispose();
    _cityCtrl.dispose();
    _companyEmailCtrl.dispose();
    _supportEmailCtrl.dispose();
    _billingEmailCtrl.dispose();
    _bookingEmailCtrl.dispose();
    _notificationEmailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _companyId == null || _createdAt == null) return;
    if (activeCompanySessionNotifier.value != null &&
        activeCompanySessionNotifier.value!.companyId != _companyId)
      return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _confirmSuccess = null;
    });
    final draftEmail = _emailCtrl.text.trim();
    final result = await savePrimaryCompanyContactEmail(
      email: draftEmail,
      fetchCurrent: _fetchBusinessProfile,
      persist: (profile) {
        if (profile.companyId.isNotEmpty && profile.companyId != _companyId) {
          throw StateError('company_profile_scope_mismatch');
        }
        return _persistBusinessProfile(
          profile.copyWith(
            companyName: _companyCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            vatNumber: _vatCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            postcode: _postalCtrl.text.trim(),
            city: _cityCtrl.text.trim(),
            country: _country,
            companyEmail: _companyEmailCtrl.text.trim(),
            supportEmail: _supportEmailCtrl.text.trim(),
            invoiceEmail: _billingEmailCtrl.text.trim(),
            bookingEmail: _bookingEmailCtrl.text.trim(),
            notificationEmail: _notificationEmailCtrl.text.trim(),
          ),
        );
      },
    );
    if (!mounted) return;
    if (result.confirmationRequired && result.saved != null) {
      localBackendBusinessProfileNotifier.value = result.saved;
      unawaited(updateLocalBackendBusinessProfileCache(result.saved));
      _emailCtrl.text = resolvePrimaryCompanyContactEmail(
        backend: result.saved,
        local: null,
      );
      setState(() {
        _saving = false;
        _pendingEmail = result.saved!.pendingEmail.trim().isNotEmpty
            ? result.saved!.pendingEmail.trim()
            : result.draftEmail;
        _emailChallengeId = result.saved!.emailChallengeId.trim();
        _pendingNotice = _t(
          nl: 'Bevestiging nodig. Voer de code in die naar de nieuwe e-mail is gestuurd. Beide schermen worden pas na bevestiging bijgewerkt.',
          en: 'Confirmation required. Enter the code sent to the new email. Both screens update only after confirmation.',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pendingNotice!)));
      return;
    }
    if (!result.ok || result.saved == null) {
      _emailCtrl.text = result.draftEmail;
      setState(() {
        _saving = false;
        _saveError = _t(
          nl: 'Opslaan/synchroniseren niet gelukt. Controleer de verbinding en probeer opnieuw.',
          en: 'Save/sync failed. Check the connection and try again.',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveError!)));
      return;
    }
    final syncedEmail = resolvePrimaryCompanyContactEmail(
      backend: result.saved,
      local: null,
    );
    localBackendBusinessProfileNotifier.value = result.saved;
    unawaited(updateLocalBackendBusinessProfileCache(result.saved));
    final next = applyPrimaryCompanyContactEmailToLocal(
      CompanyProfile(
        companyId: _companyId!,
        companyName: _companyCtrl.text.trim(),
        ownerName: _ownerCtrl.text.trim(),
        email: syncedEmail.isNotEmpty ? syncedEmail : draftEmail,
        phone: _phoneCtrl.text.trim(),
        vatNumber: _vatCtrl.text.trim(),
        addressLine: _addressCtrl.text.trim(),
        postalCode: _postalCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        countryCode: _country,
        companyEmail: _companyEmailCtrl.text.trim(),
        supportEmail: _supportEmailCtrl.text.trim(),
        billingEmail: _billingEmailCtrl.text.trim(),
        bookingEmail: _bookingEmailCtrl.text.trim(),
        notificationEmail: _notificationEmailCtrl.text.trim(),
        createdAt: _createdAt!,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        isActive: true,
        verificationStatus: _verificationStatus,
      ),
      syncedEmail.isNotEmpty ? syncedEmail : draftEmail,
    );
    await CompanySessionStore.instance.updateSavedProfile(
      next,
      preservedCompanyId: _companyId!,
      preservedCreatedAt: _createdAt!,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(nl: 'Opgeslagen.', en: 'Saved.')),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _confirmPending() async {
    if (_confirming || _pendingEmail.isEmpty || _emailChallengeId.isEmpty) {
      return;
    }
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) return;
    final companyCode = (activeCompanySessionNotifier.value?.companyCode ?? '')
        .trim();
    if (companyCode.isEmpty) {
      setState(() {
        _saveError = _t(
          nl: 'Bevestigen niet gelukt. Bedrijfscode ontbreekt.',
          en: 'Confirmation failed. Company code is missing.',
        );
      });
      return;
    }
    setState(() {
      _confirming = true;
      _saveError = null;
    });
    try {
      final confirm = widget.confirmPendingEmail;
      final confirmed = confirm != null
          ? await confirm(
              email: _pendingEmail,
              challengeId: _emailChallengeId,
              otp: otp,
              companyCode: companyCode,
            )
          : await confirmPendingCompanyContactEmail(
              email: _pendingEmail,
              challengeId: _emailChallengeId,
              otp: otp,
              companyCode: companyCode,
              fetchConfirmed: _fetchBusinessProfile,
            );
      if (!mounted) return;
      final syncedEmail = resolvePrimaryCompanyContactEmail(
        backend: confirmed,
        local: null,
      );
      localBackendBusinessProfileNotifier.value = confirmed;
      _emailCtrl.text = syncedEmail;
      final currentLocal = companyProfileNotifier.value;
      if (currentLocal != null && syncedEmail.isNotEmpty) {
        companyProfileNotifier.value = currentLocal.copyWith(
          email: syncedEmail,
        );
      }
      try {
        unawaited(updateLocalBackendBusinessProfileCache(confirmed));
      } catch (_) {}
      if (_companyId != null && _createdAt != null) {
        unawaited(
          CompanySessionStore.instance.updatePrimaryContactEmailFromBackend(
            syncedEmail,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _pendingEmail = '';
        _emailChallengeId = '';
        _pendingNotice = null;
        _saveError = null;
        _confirmSuccess = _t(nl: 'E-mail bevestigd.', en: 'Email confirmed.');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_confirmSuccess!)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _saveError = _t(
          nl: 'Bevestiging mislukt. Controleer de code en probeer opnieuw.',
          en: 'Confirmation failed. Check the code and try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1020),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_companyId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(_t(nl: 'Fout', en: 'Error')),
        ),
        body: Center(
          child: Text(
            _t(
              nl: 'Geen bedrijfsprofiel gevonden.',
              en: 'No company profile found.',
            ),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        title: Text(_t(nl: 'Mijn bedrijfsgegevens', en: 'Company details')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_t(nl: 'Bedrijfs-ID', en: 'Company ID')}  $_companyId',
                  style: TextStyle(color: Colors.white.withOpacity(0.78)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _companyCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(_t(nl: 'Bedrijfsnaam', en: 'Company name')),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? _t(nl: 'Verplicht', en: 'Required')
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ownerCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(
                    _t(nl: 'Contactpersoon', en: 'Contact person'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(_t(nl: 'E-mail', en: 'Email')),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? _t(nl: 'Verplicht', en: 'Required')
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(_t(nl: 'Telefoon', en: 'Phone')),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? _t(nl: 'Verplicht', en: 'Required')
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _vatCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(_t(nl: 'BTW-nummer', en: 'VAT number')),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(_t(nl: 'Adres', en: 'Address')),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _postalCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inp(_t(nl: 'Postcode', en: 'Postal code')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _cityCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inp(_t(nl: 'Stad', en: 'City')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _country,
                  dropdownColor: const Color(0xFF111111),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(_t(nl: 'Land', en: 'Country')),
                  items: const [
                    DropdownMenuItem(value: 'BE', child: Text('BE')),
                    DropdownMenuItem(value: 'NL', child: Text('NL')),
                    DropdownMenuItem(value: 'FR', child: Text('FR')),
                    DropdownMenuItem(value: 'ES', child: Text('ES')),
                    DropdownMenuItem(value: 'LU', child: Text('LU')),
                    DropdownMenuItem(value: 'DE', child: Text('DE')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _country = v);
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  _t(
                    nl: 'E-mailroutes (optioneel)',
                    en: 'Email routing (optional)',
                  ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _companyEmailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(
                    _t(nl: 'Bedrijfs-e-mail', en: 'Company email'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _supportEmailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(
                    _t(nl: 'Support e-mail', en: 'Support email'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _billingEmailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(
                    _t(nl: 'Facturatie e-mail', en: 'Billing email'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _bookingEmailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(
                    _t(nl: 'Boekings-e-mail', en: 'Booking email'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notificationEmailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inp(
                    _t(nl: 'Meldingen e-mail', en: 'Notification email'),
                  ),
                ),
                if (_pendingNotice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _pendingNotice!,
                    style: const TextStyle(color: Color(0xFFE5D4A1)),
                  ),
                  if (_pendingEmail.isNotEmpty)
                    Text(
                      _pendingEmail,
                      style: const TextStyle(color: Color(0xFFE5D4A1)),
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _otpCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inp(
                      _t(nl: 'Bevestigingscode', en: 'Confirmation code'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _confirming ? null : _confirmPending,
                    child: Text(_t(nl: 'Code bevestigen', en: 'Confirm code')),
                  ),
                ],
                if (_confirmSuccess != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _confirmSuccess!,
                    style: const TextStyle(color: Color(0xFFE5D4A1)),
                  ),
                ],
                if (_saveError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _saveError!,
                    style: const TextStyle(color: Color(0xFFFFB4B4)),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE5B641),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        )
                      : Text(
                          _t(nl: 'Opslaan', en: 'Save'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inp(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.78)),
      filled: true,
      fillColor: const Color(0xFF141B2F),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}
