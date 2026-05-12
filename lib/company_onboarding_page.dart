import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

/// Collects mandatory company identifiers before entering the admin/business hub.
class CompanyOnboardingPage extends StatefulWidget {
  const CompanyOnboardingPage({
    super.key,
    required this.onCompleted,
    this.initialCompanyId,
    this.lockCompanyId = false,
  });

  /// Called after local profile + session are saved. Should replace with [BusinessHomePage].
  final void Function(BuildContext context) onCompleted;
  final String? initialCompanyId;
  final bool lockCompanyId;

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
    super.dispose();
  }

  String _registrationErrorMessage(String code) {
    switch (code) {
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
        'country': _country.trim().isEmpty ? 'BE' : _country.trim().toUpperCase(),
        'city': _cityCtrl.text.trim(),
        'postcode': '',
        'address': '',
      };
      debugPrint('[COMPANY_REGISTER][REQ] company=${payload['company_name']}');
      final result = await registerPublicCompany(payload: payload);
      final tenantId = (result['tenant_id'] ?? result['tenantId'] ?? '')
          .toString()
          .trim();
      final companyId = (result['company_id'] ?? result['companyId'] ?? '')
          .toString()
          .trim();
      final companyCode = (result['public_company_code'] ??
              result['publicCompanyCode'] ??
              result['company_code'] ??
              result['companyCode'] ??
              '')
          .toString()
          .trim();
      final companySessionToken =
          (result['company_session_token'] ?? result['companySessionToken'] ?? '')
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
        if (value.isNotEmpty && (businessProfileMap[key] ?? '').toString().trim().isEmpty) {
          businessProfileMap[key] = value;
        }
      }
      if (businessProfileMap.isNotEmpty) {
        final backendBusinessProfile =
            BackendBusinessProfile.fromJson(businessProfileMap);
        await updateLocalBackendBusinessProfileCache(backendBusinessProfile);
      }
      final companyName = (businessProfileMap['companyName'] ??
              businessProfileMap['company_name'] ??
              _companyCtrl.text)
          .toString()
          .trim();
      final countryCode =
          (businessProfileMap['country'] ?? _country).toString().trim().toUpperCase();
      final ownerName = _ownerCtrl.text.trim();
      final email = (businessProfileMap['email'] ??
              businessProfileMap['companyEmail'] ??
              _emailCtrl.text)
          .toString()
          .trim();
      final phone = (businessProfileMap['phone'] ?? _phoneCtrl.text)
          .toString()
          .trim();
      final vatNumber = (businessProfileMap['vatNumber'] ??
              businessProfileMap['vat_number'] ??
              _vatCtrl.text)
          .toString()
          .trim();
      final city = (businessProfileMap['city'] ?? _cityCtrl.text).toString().trim();
      final postcode =
          (businessProfileMap['postcode'] ?? '').toString().trim();
      final address =
          (businessProfileMap['address'] ?? '').toString().trim();
      final issuedAtRaw = (result['issued_at'] ?? '').toString().trim();
      final expiresAtRaw = (result['expires_at'] ?? '').toString().trim();
      final expiresInSeconds = int.tryParse(
        (result['expires_in'] ?? result['expiresIn'] ?? '').toString().trim(),
      );
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
      );
      final bootstrap = await fetchCompanyBootstrapWithToken(
        companySessionToken: companySessionToken,
      );
      if (bootstrap != null) {
        await hydrateCompanyStateFromBootstrap(bootstrap);
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
  const CompanyProfileEditPage({super.key});

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
    final p = await CompanySessionStore.instance.loadProfile();
    if (!mounted) return;
    if (p == null) {
      setState(() => _loading = false);
      return;
    }
    _companyId = p.companyId;
    _createdAt = p.createdAt;
    _verificationStatus = p.verificationStatus;
    _companyCtrl.text = p.companyName;
    _ownerCtrl.text = p.ownerName;
    _emailCtrl.text = p.email;
    _phoneCtrl.text = p.phone;
    _vatCtrl.text = p.vatNumber;
    _addressCtrl.text = p.addressLine;
    _postalCtrl.text = p.postalCode;
    _cityCtrl.text = p.city;
    _companyEmailCtrl.text = p.companyEmail;
    _supportEmailCtrl.text = p.supportEmail;
    _billingEmailCtrl.text = p.billingEmail;
    _bookingEmailCtrl.text = p.bookingEmail;
    _notificationEmailCtrl.text = p.notificationEmail;
    _country = p.countryCode.isNotEmpty ? p.countryCode : 'BE';
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
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _companyId == null || _createdAt == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final next = CompanyProfile(
      companyId: _companyId!,
      companyName: _companyCtrl.text.trim(),
      ownerName: _ownerCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
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
