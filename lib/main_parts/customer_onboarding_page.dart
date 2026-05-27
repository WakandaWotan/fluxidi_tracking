part of '../main.dart';

class CustomerOnboardingPage extends StatefulWidget {
  const CustomerOnboardingPage({super.key});

  @override
  State<CustomerOnboardingPage> createState() => _CustomerOnboardingPageState();
}

class _CustomerOnboardingPageState extends State<CustomerOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToCustomerHome() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerHomePage()),
    );
  }

  Future<void> _saveAndContinue() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final session = await CustomerSessionStore.instance.loadValidSession();
    final saved = await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
      sessionCustomerId: session?.customerId,
    );
    _setCachedCustomerProfile(saved);
    final synced = await _syncCustomerProfileToBackendBestEffort(
      reason: 'customer_onboarding_save',
      localProfile: saved,
    );
    if (synced != null) {
      _setCachedCustomerProfile(synced);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await _goToCustomerHome();
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
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
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
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          title: const Text('FLUXIDI'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
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
                            nl: 'Maak je ritten makkelijker',
                            en: 'Make your rides easier',
                            fr: 'Simplifiez vos trajets',
                            es: 'Haz tus viajes más fáciles',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            nl: 'Vul één keer je gegevens in. Dan hoef je ze bij je volgende boeking niet opnieuw te typen.',
                            en: 'Enter your details once, so you do not have to type them again for your next booking.',
                            fr: 'Saisissez vos informations une seule fois pour ne plus devoir les retaper lors de votre prochaine réservation.',
                            es: 'Introduce tus datos una vez para no tener que escribirlos de nuevo en tu próxima reserva.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 12),
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
                            if (!text.contains('@') || !text.contains('.')) {
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
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Bedrijfsnaam (optioneel)',
                            en: 'Company name (optional)',
                            fr: 'Nom de l’entreprise (facultatif)',
                            es: 'Nombre de la empresa (opcional)',
                          ),
                          controller: _companyNameCtrl,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'BTW-nummer (optioneel)',
                            en: 'VAT number (optional)',
                            fr: 'Numéro de TVA (facultatif)',
                            es: 'Número de IVA (opcional)',
                          ),
                          controller: _vatNumberCtrl,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _saving ? null : _saveAndContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
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
                                    nl: 'Opslaan en doorgaan',
                                    en: 'Save and continue',
                                    fr: 'Enregistrer et continuer',
                                    es: 'Guardar y continuar',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _saving ? null : _goToCustomerHome,
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
                              nl: 'Later invullen',
                              en: 'Fill in later',
                              fr: 'Compléter plus tard',
                              es: 'Completar más tarde',
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

class BusinessHomePage extends StatefulWidget {
  const BusinessHomePage({super.key});

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}
