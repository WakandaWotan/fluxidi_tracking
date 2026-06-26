part of '../main.dart';

class CustomerProfileEditPage extends StatefulWidget {
  const CustomerProfileEditPage({super.key});

  @override
  State<CustomerProfileEditPage> createState() =>
      _CustomerProfileEditPageState();
}

class _CustomerProfileEditPageState extends State<CustomerProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  final _invoiceEmailCtrl = TextEditingController();
  final _billingStreetCtrl = TextEditingController();
  final _billingPostalCodeCtrl = TextEditingController();
  final _billingCityCtrl = TextEditingController();
  final _billingCountryCtrl = TextEditingController();
  final _peppolEndpointIdCtrl = TextEditingController();
  final _peppolSchemeCtrl = TextEditingController();
  bool _saving = false;
  bool _peppolExpanded = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  String _pageTitle() => _t(
    nl: 'Mijn gegevens',
    en: 'My details',
    fr: 'Mes informations',
    es: 'Mis datos',
  );

  int _completedProfileFields() {
    // Personal/contact + legacy company/VAT only. New optional billing address /
    // Peppol fields are intentionally excluded so existing profiles never look
    // "incomplete" just because the new optional fields are blank.
    return <TextEditingController>[
      _nameCtrl,
      _postcodeCtrl,
      _phoneCtrl,
      _emailCtrl,
      _companyNameCtrl,
      _vatNumberCtrl,
    ].where((ctrl) => ctrl.text.trim().isNotEmpty).length;
  }

  bool _hasAnyBillingAddressInput() {
    return _billingStreetCtrl.text.trim().isNotEmpty ||
        _billingPostalCodeCtrl.text.trim().isNotEmpty ||
        _billingCityCtrl.text.trim().isNotEmpty;
  }

  Widget _profileHeader(CustomerThemePalette palette) {
    final isDarkTheme = palette.isDark;
    final completed = _completedProfileFields();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surfaceAlt, palette.surface, palette.background],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDarkTheme ? palette.gold : palette.border).withOpacity(
            isDarkTheme ? 0.34 : 0.9,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(isDarkTheme ? 0.26 : 0.12),
            blurRadius: 16,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.gold.withOpacity(isDarkTheme ? 0.30 : 0.22),
                  palette.surfaceAlt,
                ],
              ),
              border: Border.all(
                color: palette.gold.withOpacity(isDarkTheme ? 0.54 : 0.46),
              ),
            ),
            child: Icon(
              Icons.person_outline_rounded,
              color: palette.gold.withOpacity(0.98),
              size: 29,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _pageTitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.gold.withOpacity(
                          isDarkTheme ? 0.12 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: palette.gold.withOpacity(
                            isDarkTheme ? 0.44 : 0.38,
                          ),
                        ),
                      ),
                      child: Text(
                        '$completed/6 ${_t(nl: 'compleet', en: 'complete', fr: 'complet', es: 'completo')}',
                        style: TextStyle(
                          color: isDarkTheme ? palette.gold : palette.bronze,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _t(
                    nl: 'Deze gegevens gebruiken we voor boekingen, contact en ritbonnen.',
                    en: 'We use these details for bookings, contact, and receipts.',
                    fr: 'Ces informations servent aux réservations, au contact et aux reçus.',
                    es: 'Usamos estos datos para reservas, contacto y recibos.',
                  ),
                  style: TextStyle(
                    color: palette.textMuted,
                    height: 1.28,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required CustomerThemePalette palette,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    final isDarkTheme = palette.isDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surface, palette.surfaceAlt],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDarkTheme ? palette.gold : palette.border).withOpacity(
            isDarkTheme ? 0.22 : 0.95,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(isDarkTheme ? 0.16 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: palette.surfaceAlt,
                  border: Border.all(
                    color: palette.gold.withOpacity(isDarkTheme ? 0.34 : 0.30),
                  ),
                ),
                child: Icon(icon, color: palette.gold, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _postcodeCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    _invoiceEmailCtrl.dispose();
    _billingStreetCtrl.dispose();
    _billingPostalCodeCtrl.dispose();
    _billingCityCtrl.dispose();
    _billingCountryCtrl.dispose();
    _peppolEndpointIdCtrl.dispose();
    _peppolSchemeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await CustomerProfileStore.instance.load();
    final session = await CustomerSessionStore.instance.loadValidSession();
    final sessionPhone = normalizeCustomerSessionPhoneE164(
      session?.phoneE164 ?? '',
    );
    final profilePhone = (profile?.phone ?? '').trim();
    final phoneForForm = profilePhone.isNotEmpty ? profilePhone : sessionPhone;
    debugPrint(
      '[CUSTOMER_PROFILE][PHONE_READY_FOR_FORM] source=${profilePhone.isNotEmpty ? "profile" : (sessionPhone.isNotEmpty ? "session" : "empty")} ready=${phoneForForm.isNotEmpty}',
    );
    if (!mounted) return;
    if (profile != null) {
      _nameCtrl.text = profile.name;
      _postcodeCtrl.text = profile.preferredPostcode;
      _emailCtrl.text = profile.email;
      _companyNameCtrl.text = profile.companyName;
      _vatNumberCtrl.text = profile.vatNumber;
      _invoiceEmailCtrl.text = profile.invoiceEmail;
      _billingStreetCtrl.text = profile.billingStreet;
      _billingPostalCodeCtrl.text = profile.billingPostalCode;
      _billingCityCtrl.text = profile.billingCity;
      _billingCountryCtrl.text = profile.billingCountry;
      _peppolEndpointIdCtrl.text = profile.peppolEndpointId;
      _peppolSchemeCtrl.text = profile.peppolScheme;
      _peppolExpanded =
          profile.peppolEndpointId.trim().isNotEmpty ||
          profile.peppolScheme.trim().isNotEmpty;
    }
    _phoneCtrl.text = phoneForForm;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final session = await CustomerSessionStore.instance.loadValidSession();
    final billingCountryToSave = _billingCountryCtrl.text.trim().isNotEmpty
        ? _billingCountryCtrl.text.trim()
        : (_hasAnyBillingAddressInput() ? 'BE' : '');
    final saved = await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      preferredPostcode: _postcodeCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
      invoiceEmail: _invoiceEmailCtrl.text,
      billingStreet: _billingStreetCtrl.text,
      billingPostalCode: _billingPostalCodeCtrl.text,
      billingCity: _billingCityCtrl.text,
      billingCountry: billingCountryToSave,
      peppolEndpointId: _peppolEndpointIdCtrl.text,
      peppolScheme: _peppolSchemeCtrl.text,
      sessionCustomerId: session?.customerId,
    );
    _setCachedCustomerProfile(saved);
    final synced = await _syncCustomerProfileToBackendBestEffort(
      reason: 'customer_profile_edit_save',
      localProfile: saved,
    );
    if (synced != null) {
      _setCachedCustomerProfile(synced);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Gegevens opgeslagen.',
            en: 'Details saved.',
            fr: 'Informations enregistrées.',
            es: 'Datos guardados.',
          ),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  Widget _field({
    required CustomerThemePalette palette,
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final isDarkTheme = palette.isDark;
    final baseBorderColor = (isDarkTheme ? palette.border : palette.border)
        .withOpacity(isDarkTheme ? 0.55 : 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDarkTheme ? palette.bronze : palette.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            height: 1.15,
          ),
          cursorColor: palette.gold,
          decoration: InputDecoration(
            filled: true,
            fillColor: isDarkTheme
                ? palette.background.withOpacity(0.86)
                : palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: baseBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: baseBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                color: palette.gold.withOpacity(isDarkTheme ? 0.78 : 0.72),
                width: 1.2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: palette.danger.withOpacity(0.78)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: palette.danger.withOpacity(0.92)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 11,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, __) {
        final palette = paletteForCustomerTheme(themeVariant);
        final isDarkTheme = palette.isDark;
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: appLanguageNotifier,
          builder: (context, _, __) => Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              backgroundColor: palette.background,
              foregroundColor: palette.textPrimary,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              title: Text(
                _pageTitle(),
                style: TextStyle(color: palette.textPrimary),
              ),
            ),
            body: SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      palette.surface,
                      palette.background,
                      palette.background,
                    ],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnimatedBuilder(
                              animation: Listenable.merge([
                                _nameCtrl,
                                _postcodeCtrl,
                                _phoneCtrl,
                                _emailCtrl,
                                _companyNameCtrl,
                                _vatNumberCtrl,
                              ]),
                              builder: (context, _) => _profileHeader(palette),
                            ),
                            const SizedBox(height: 12),
                            _sectionCard(
                              palette: palette,
                              title: _t(
                                nl: 'Persoonlijk',
                                en: 'Personal',
                                fr: 'Personnel',
                                es: 'Personal',
                              ),
                              subtitle: _t(
                                nl: 'Naam voor boekingen',
                                en: 'Name for bookings',
                                fr: 'Nom pour les réservations',
                                es: 'Nombre para reservas',
                              ),
                              icon: Icons.badge_outlined,
                              children: [
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Naam',
                                    en: 'Name',
                                    fr: 'Nom',
                                    es: 'Nombre',
                                  ),
                                  controller: _nameCtrl,
                                  validator: (v) {
                                    final text = (v ?? '').trim();
                                    if (text.isEmpty) {
                                      return _t(
                                        nl: 'Vul je naam in',
                                        en: 'Enter your name',
                                        fr: 'Saisissez votre nom',
                                        es: 'Introduce tu nombre',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Postcode',
                                    en: 'Postcode',
                                    fr: 'Code postal',
                                    es: 'Código postal',
                                  ),
                                  controller: _postcodeCtrl,
                                  validator: (v) {
                                    final text = (v ?? '').trim();
                                    if (text.isEmpty) {
                                      return _t(
                                        nl: 'Vul je postcode in',
                                        en: 'Enter your postcode',
                                        fr: 'Saisissez votre code postal',
                                        es: 'Introduce tu código postal',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _sectionCard(
                              palette: palette,
                              title: _t(
                                nl: 'Contact',
                                en: 'Contact',
                                fr: 'Contact',
                                es: 'Contacto',
                              ),
                              subtitle: _t(
                                nl: 'Telefoon en e-mail',
                                en: 'Phone and email',
                                fr: 'Téléphone et e-mail',
                                es: 'Teléfono y correo',
                              ),
                              icon: Icons.alternate_email_rounded,
                              children: [
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Telefoonnummer',
                                    en: 'Phone number',
                                    fr: 'Numéro de téléphone',
                                    es: 'Número de teléfono',
                                  ),
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  validator: (v) {
                                    final text = (v ?? '').trim();
                                    if (text.isEmpty) {
                                      return _t(
                                        nl: 'Vul je telefoonnummer in',
                                        en: 'Enter your phone number',
                                        fr: 'Saisissez votre numéro de téléphone',
                                        es: 'Introduce tu número de teléfono',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'E-mailadres',
                                    en: 'Email address',
                                    fr: 'Adresse e-mail',
                                    es: 'Correo electrónico',
                                  ),
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    final text = (v ?? '').trim();
                                    if (text.isEmpty) {
                                      return _t(
                                        nl: 'Vul je e-mail in',
                                        en: 'Enter your email',
                                        fr: 'Saisissez votre e-mail',
                                        es: 'Introduce tu correo',
                                      );
                                    }
                                    if (!text.contains('@') ||
                                        !text.contains('.')) {
                                      return _t(
                                        nl: 'Vul een geldig e-mailadres in',
                                        en: 'Enter a valid email address',
                                        fr: 'Saisissez une adresse e-mail valide',
                                        es: 'Introduce un correo electrónico válido',
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _sectionCard(
                              palette: palette,
                              title: _t(
                                nl: 'Facturatie optioneel',
                                en: 'Optional billing',
                                fr: 'Facturation facultative',
                                es: 'Facturación opcional',
                              ),
                              subtitle: _t(
                                nl: 'Voor zakelijke ritbonnen',
                                en: 'For business receipts',
                                fr: 'Pour les reçus professionnels',
                                es: 'Para recibos empresariales',
                              ),
                              icon: Icons.receipt_long_outlined,
                              children: [
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Bedrijfsnaam (optioneel)',
                                    en: 'Company name (optional)',
                                    fr: 'Nom de l’entreprise (facultatif)',
                                    es: 'Nombre de la empresa (opcional)',
                                  ),
                                  controller: _companyNameCtrl,
                                ),
                                const SizedBox(height: 10),
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'BTW-nummer (optioneel)',
                                    en: 'VAT number (optional)',
                                    fr: 'Numéro de TVA (facultatif)',
                                    es: 'Número de IVA (opcional)',
                                  ),
                                  controller: _vatNumberCtrl,
                                ),
                                const SizedBox(height: 10),
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Factuur e-mail (optioneel)',
                                    en: 'Invoice email (optional)',
                                    fr: 'E-mail de facturation (facultatif)',
                                    es: 'Correo de factura (opcional)',
                                  ),
                                  controller: _invoiceEmailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 10),
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Straat en nummer (optioneel)',
                                    en: 'Street and number (optional)',
                                    fr: 'Rue et numéro (facultatif)',
                                    es: 'Calle y número (opcional)',
                                  ),
                                  controller: _billingStreetCtrl,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _field(
                                        palette: palette,
                                        label: _t(
                                          nl: 'Postcode (optioneel)',
                                          en: 'Postal code (optional)',
                                          fr: 'Code postal (facultatif)',
                                          es: 'Código postal (opcional)',
                                        ),
                                        controller: _billingPostalCodeCtrl,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: _field(
                                        palette: palette,
                                        label: _t(
                                          nl: 'Gemeente (optioneel)',
                                          en: 'City (optional)',
                                          fr: 'Ville (facultatif)',
                                          es: 'Ciudad (opcional)',
                                        ),
                                        controller: _billingCityCtrl,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _field(
                                  palette: palette,
                                  label: _t(
                                    nl: 'Land (optioneel, bv. BE)',
                                    en: 'Country (optional, e.g. BE)',
                                    fr: 'Pays (facultatif, ex. BE)',
                                    es: 'País (opcional, p. ej. BE)',
                                  ),
                                  controller: _billingCountryCtrl,
                                ),
                                const SizedBox(height: 10),
                                InkWell(
                                  onTap: () => setState(
                                    () => _peppolExpanded = !_peppolExpanded,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _peppolExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 18,
                                        color: palette.gold,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _t(
                                          nl: 'Geavanceerd (Peppol) - optioneel',
                                          en: 'Advanced (Peppol) - optional',
                                          fr: 'Avancé (Peppol) - facultatif',
                                          es: 'Avanzado (Peppol) - opcional',
                                        ),
                                        style: TextStyle(
                                          color: palette.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_peppolExpanded) ...[
                                  const SizedBox(height: 10),
                                  _field(
                                    palette: palette,
                                    label: _t(
                                      nl: 'Peppol endpoint-ID (optioneel)',
                                      en: 'Peppol endpoint ID (optional)',
                                      fr: 'ID de point d’accès Peppol (facultatif)',
                                      es: 'ID de endpoint Peppol (opcional)',
                                    ),
                                    controller: _peppolEndpointIdCtrl,
                                  ),
                                  const SizedBox(height: 10),
                                  _field(
                                    palette: palette,
                                    label: _t(
                                      nl: 'Peppol scheme (optioneel)',
                                      en: 'Peppol scheme (optional)',
                                      fr: 'Schéma Peppol (facultatif)',
                                      es: 'Esquema Peppol (opcional)',
                                    ),
                                    controller: _peppolSchemeCtrl,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: isDarkTheme
                                    ? palette.gold
                                    : palette.bronze,
                                foregroundColor: Colors.black.withOpacity(0.92),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                _saving
                                    ? _t(
                                        nl: 'Opslaan...',
                                        en: 'Saving...',
                                        fr: 'Enregistrement...',
                                        es: 'Guardando...',
                                      )
                                    : _t(
                                        nl: 'Opslaan',
                                        en: 'Save',
                                        fr: 'Enregistrer',
                                        es: 'Guardar',
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
          ),
        );
      },
    );
  }
}
