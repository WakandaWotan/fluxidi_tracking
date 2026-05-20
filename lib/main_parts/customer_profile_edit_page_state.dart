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
  bool _saving = false;

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
    return <TextEditingController>[
      _nameCtrl,
      _postcodeCtrl,
      _phoneCtrl,
      _emailCtrl,
      _companyNameCtrl,
      _vatNumberCtrl,
    ].where((ctrl) => ctrl.text.trim().isNotEmpty).length;
  }

  Widget _profileHeader() {
    final completed = _completedProfileFields();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15120A), Color(0xFF101010), Color(0xFF07080C)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.34)),
        boxShadow: [
          BoxShadow(
            color: kFluxidiYellow.withOpacity(0.10),
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
                  kFluxidiYellow.withOpacity(0.30),
                  const Color(0xFF15120A),
                ],
              ),
              border: Border.all(color: kFluxidiYellow.withOpacity(0.54)),
            ),
            child: Icon(
              Icons.person_outline_rounded,
              color: kFluxidiYellow.withOpacity(0.98),
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
                        style: const TextStyle(
                          color: Colors.white,
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
                        color: kFluxidiYellow.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: kFluxidiYellow.withOpacity(0.44),
                        ),
                      ),
                      child: Text(
                        '$completed/6 ${_t(nl: 'compleet', en: 'complete', fr: 'complet', es: 'completo')}',
                        style: TextStyle(
                          color: kFluxidiYellow.withOpacity(0.98),
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
                    color: Colors.white.withOpacity(0.72),
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
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101010), Color(0xFF07080C)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.18)),
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
                  color: const Color(0xFF15120A),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.34)),
                ),
                child: Icon(icon, color: kFluxidiYellow, size: 19),
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
                      style: const TextStyle(
                        color: Colors.white,
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
                        color: Colors.white.withOpacity(0.62),
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
    }
    _phoneCtrl.text = phoneForForm;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final session = await CustomerSessionStore.instance.loadValidSession();
    final saved = await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      preferredPostcode: _postcodeCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
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
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE5D4A1),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.15,
          ),
          cursorColor: kFluxidiYellow,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0B0B0B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                color: kFluxidiYellow.withOpacity(0.72),
                width: 1.2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: Colors.redAccent.withOpacity(0.75)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: Colors.redAccent.withOpacity(0.85)),
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
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF07080C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07080C),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(_pageTitle()),
        ),
        body: SafeArea(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF101010),
                  Color(0xFF07080C),
                  Color(0xFF07080C),
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
                          builder: (context, _) => _profileHeader(),
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
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
                              label: _t(
                                nl: 'BTW-nummer (optioneel)',
                                en: 'VAT number (optional)',
                                fr: 'Numéro de TVA (facultatif)',
                                es: 'Número de IVA (opcional)',
                              ),
                              controller: _vatNumberCtrl,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: kFluxidiYellow,
                            foregroundColor: Colors.black,
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
  }
}
