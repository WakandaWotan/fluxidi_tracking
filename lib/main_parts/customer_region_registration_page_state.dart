part of '../main.dart';

class CustomerRegionRegistrationPage extends StatefulWidget {
  const CustomerRegionRegistrationPage({super.key});

  @override
  State<CustomerRegionRegistrationPage> createState() =>
      _CustomerRegionRegistrationPageState();
}

class _CustomerRegionRegistrationPageState
    extends State<CustomerRegionRegistrationPage> {
  final bool _wantsUpdates = true;
  bool _submitting = false;
  String _profileName = '';
  String _profileEmail = '';
  String _profilePhone = '';
  String _profilePostcode = '';
  String? _radarInterestDisplayCount;
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _themePalette.isDark;
  Color get _bg => _themePalette.background;
  Color get _surface => _themePalette.surface;
  Color get _surfaceAlt => _themePalette.surfaceAlt;
  Color get _textPrimary => _themePalette.textPrimary;
  Color get _textMuted => _themePalette.textMuted;
  Color get _gold => _themePalette.gold;
  Color get _border => _themePalette.border;
  Color get _shadow => _themePalette.shadow;
  Color get _actionOnGold =>
      _isDarkTheme ? const Color(0xFF050505) : const Color(0xFF1F1706);

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    customerThemeNotifier.addListener(_onThemeChanged);
    unawaited(_prefillFromProfile());
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    customerThemeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _prefillFromProfile() async {
    await _refreshCachedCustomerProfile();
    final profile =
        _cachedCustomerProfile ?? await _loadCachedCustomerProfileIfNeeded();
    if (!mounted) return;
    final name = profile?.name.trim() ?? '';
    final email = profile?.email.trim() ?? '';
    final phone = profile?.phone.trim() ?? '';
    final profilePostcode = profile?.preferredPostcode.trim() ?? '';
    final postcode = profilePostcode.isNotEmpty
        ? profilePostcode.toUpperCase()
        : _latestKnownRegionPostcode(email: email, name: name);
    setState(() {
      _profileName = name;
      _profileEmail = email;
      _profilePhone = phone;
      _profilePostcode = postcode;
    });
    unawaited(_refreshRegionInterestRadarCount());
  }

  String _latestKnownRegionPostcode({
    required String email,
    required String name,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = name.trim().toLowerCase();
    for (final row in _customerRegionLeadInbox.reversed) {
      final rowPostcode = (row['postal_code'] ?? '').toString().trim();
      if (rowPostcode.isEmpty) continue;
      final rowEmail = (row['email'] ?? '').toString().trim().toLowerCase();
      final rowName = <String>[
        (row['first_name'] ?? '').toString().trim(),
        (row['last_name'] ?? '').toString().trim(),
      ].where((v) => v.isNotEmpty).join(' ').toLowerCase();
      if (normalizedEmail.isNotEmpty && rowEmail == normalizedEmail) {
        return rowPostcode.toUpperCase();
      }
      if (normalizedName.isNotEmpty && rowName == normalizedName) {
        return rowPostcode.toUpperCase();
      }
    }
    return '';
  }

  bool _hasRequiredProfileData() {
    final name = _profileName.trim();
    final email = _profileEmail.trim();
    final postcode = _profilePostcode.trim();
    final hasValidEmail = email.contains('@') && email.contains('.');
    return name.isNotEmpty && hasValidEmail && postcode.isNotEmpty;
  }

  Future<void> _openProfileForCompletion() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerProfileEditPage()));
    await _refreshCachedCustomerProfile();
    await _prefillFromProfile();
  }

  Future<void> _submitFromProfileGuarded() async {
    await _refreshCachedCustomerProfile();
    await _prefillFromProfile();
    if (!_hasRequiredProfileData()) {
      if (!mounted) return;
      _showThemedSnackBar(
        _t(
          nl: 'Vul eerst je profielgegevens aan zodat we je kunnen verwittigen.',
          en: 'Complete your profile details first so we can notify you.',
          fr: 'Complétez d’abord votre profil afin que nous puissions vous informer.',
          es: 'Completa primero tu perfil para que podamos avisarte.',
        ),
      );
      await _openProfileForCompletion();
      return;
    }
    await _submit();
  }

  String _regionBadgeText() {
    final postcode = _profilePostcode.trim();
    if (postcode.isNotEmpty) {
      return _t(
        nl: '$postcode · jouw regio',
        en: '$postcode · your area',
        fr: '$postcode · votre région',
        es: '$postcode · tu zona',
      );
    }
    return _t(
      nl: 'Jouw regio',
      en: 'Your area',
      fr: 'Votre région',
      es: 'Tu zona',
    );
  }

  InlineSpan _radarHeadlineSpan() {
    final baseStyle = TextStyle(
      color: _textPrimary,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      height: 1.08,
    );
    final highlightStyle = baseStyle.copyWith(color: _gold.withOpacity(0.98));
    switch (appLanguageNotifier.value) {
      case AppLanguage.nl:
        return TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'Fluxidi is nog niet actief in '),
            TextSpan(text: 'jouw regio', style: highlightStyle),
          ],
        );
      case AppLanguage.fr:
        return TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'Fluxidi n’est pas encore actief dans '),
            TextSpan(text: 'votre région', style: highlightStyle),
          ],
        );
      case AppLanguage.es:
        return TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'Fluxidi aún no está activo en '),
            TextSpan(text: 'tu región', style: highlightStyle),
          ],
        );
      case AppLanguage.en:
        return TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'Fluxidi is not active in '),
            TextSpan(text: 'your region', style: highlightStyle),
            const TextSpan(text: ' yet'),
          ],
        );
    }
  }

  bool _hasVerifiedActivePartnersSignal() {
    // Regio Radar currently has no partner availability feed in this view.
    return false;
  }

  String _regionInterestCountryCode() {
    // Customer profile currently has no explicit country field in this flow.
    return 'BE';
  }

  String _normalizedRegionInterestPostcode() {
    return _profilePostcode.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  String _radarCountTileValue() {
    final fromBackend = _radarInterestDisplayCount?.trim() ?? '';
    if (fromBackend.isNotEmpty) return fromBackend;
    return '0+';
  }

  int? _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString().trim());
  }

  Future<void> _refreshRegionInterestRadarCount() async {
    final postcode = _normalizedRegionInterestPostcode();
    if (postcode.isEmpty) {
      if (!mounted) return;
      setState(() {
        _radarInterestDisplayCount = '0+';
      });
      return;
    }
    final country = _regionInterestCountryCode();
    debugPrint(
      '[REGIO_RADAR] fetch aggregate postcode=$postcode country=$country',
    );
    final uri = Uri.parse(
      '$kBookingBaseUrl/region-interest/radar?country=${Uri.encodeQueryComponent(country)}&postcode=${Uri.encodeQueryComponent(postcode)}',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['ok'] != true) return;
      final count = _toSafeInt(decoded['count']);
      final incomingDisplay = (decoded['display_count'] ?? '')
          .toString()
          .trim();
      final display = incomingDisplay.isNotEmpty
          ? incomingDisplay
          : (count == null ? '' : '${count.clamp(0, 999999)}+');
      debugPrint(
        '[REGIO_RADAR] aggregate display_count=${display.isEmpty ? 'n/a' : display}',
      );
      if (!mounted) return;
      setState(() {
        _radarInterestDisplayCount = display.isEmpty ? '0+' : display;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _radarInterestDisplayCount = '0+';
      });
    }
  }

  Future<void> _shareRadar() async {
    await Share.share(
      _t(
        nl: 'Ik volg Regio Radar op Fluxidi. Sluit je aan zodat we Fluxidi sneller in onze regio krijgen.',
        en: 'I am following Region Radar on Fluxidi. Join in so we can get Fluxidi in our area sooner.',
        fr: 'Je suis Radar régional sur Fluxidi. Rejoins-nous pour activer Fluxidi plus vite dans notre région.',
        es: 'Estoy siguiendo Radar regional en Fluxidi. Únete para que Fluxidi llegue antes a nuestra zona.',
      ),
    );
  }

  void _showThemedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _surfaceAlt,
        content: Text(message, style: TextStyle(color: _textPrimary)),
      ),
    );
  }

  Future<void> _submit() async {
    final fullName = _profileName.trim();
    final email = _profileEmail.trim();
    final postcode = _normalizedRegionInterestPostcode();
    final country = _regionInterestCountryCode();
    final phone = _profilePhone.trim();
    final locale = currentLanguageCode.trim().isEmpty
        ? 'nl'
        : currentLanguageCode.trim().toLowerCase();
    setState(() => _submitting = true);

    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    final firstName = parts.isEmpty ? fullName : parts.first;
    final lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';

    bool backendSynced = false;
    String? backendDisplayCount;
    try {
      final uri = Uri.parse('$kBookingBaseUrl/region-interest');
      final res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'country': country,
              'postcode': postcode,
              'name': fullName,
              'email': email,
              'phone': phone,
              'locale': locale,
              'source': 'regio_radar',
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          backendSynced = true;
          final display = (decoded['display_count'] ?? '').toString().trim();
          if (display.isNotEmpty) backendDisplayCount = display;
        }
      }
    } catch (_) {
      backendSynced = false;
    }

    // Keep a local cache entry as safe fallback when backend sync fails.
    _customerRegionLeadInbox.add(<String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'postal_code': postcode,
      'country': country,
      'email': email,
      'phone': phone,
      'locale': locale,
      'source': 'regio_radar',
      'notify_updates': _wantsUpdates,
      'created_at': DateTime.now().toIso8601String(),
    });

    if (backendSynced && mounted) {
      setState(() {
        _radarInterestDisplayCount = backendDisplayCount;
      });
      await _refreshRegionInterestRadarCount();
    }

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _submitting = false);
    _showThemedSnackBar(
      backendSynced
          ? _t(
              nl: 'Je regio is geregistreerd. We houden je op de hoogte.',
              en: 'Your area is registered. We’ll keep you updated.',
              fr: 'Votre région est enregistrée. Nous vous tiendrons informé.',
              es: 'Tu zona está registrada. Te mantendremos informado.',
            )
          : _t(
              nl: 'Je interesse is lokaal bewaard. We proberen later opnieuw te synchroniseren.',
              en: 'Your interest was saved locally. We’ll try to sync it later.',
              fr: 'Votre intérêt a été enregistré localement. Nous réessaierons plus tard.',
              es: 'Tu interés se guardó localmente. Intentaremos sincronizarlo más tarde.',
            ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const partnerColor = Color(0xFF34D29A);
    final hasActivePartnerSignals = _hasVerifiedActivePartnersSignal();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final radarHeight = screenHeight < 760
        ? 220.0
        : screenHeight < 860
        ? 238.0
        : 254.0;
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _textPrimary,
          toolbarHeight: 52,
          title: Text(
            _t(
              nl: 'Regio Radar',
              en: 'Region Radar',
              fr: 'Radar régional',
              es: 'Radar regional',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            children: [
              RichText(text: _radarHeadlineSpan()),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Maar je bent niet alleen. Steeds meer mensen vragen Fluxidi in hun buurt.',
                  en: 'You are not alone. More people are asking for Fluxidi in their area.',
                  fr: 'Vous n’êtes pas seul. De plus en plus de personnes demandent Fluxidi dans leur région.',
                  es: 'No estás solo. Cada vez más personas piden Fluxidi en su zona.',
                ),
                style: TextStyle(
                  color: _textMuted.withOpacity(0.92),
                  fontSize: 12.2,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.98),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withOpacity(0.72),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _regionBadgeText(),
                    style: TextStyle(
                      color: _gold.withOpacity(0.98),
                      fontSize: 12.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _legendDotLabel(
                    color: _gold.withOpacity(0.98),
                    label: _t(
                      nl: 'Klantinteresse',
                      en: 'Customer interest',
                      fr: 'Intérêt clients',
                      es: 'Interés de clientes',
                    ),
                  ),
                  _legendDotLabel(
                    color: partnerColor,
                    label: _t(
                      nl: 'Partners',
                      en: 'Partners',
                      fr: 'Partenaires',
                      es: 'Socios',
                    ),
                  ),
                  _statusLegendChip(
                    text: hasActivePartnerSignals
                        ? _t(
                            nl: 'Partners actief',
                            en: 'Partners active',
                            fr: 'Partenaires actifs',
                            es: 'Socios activos',
                          )
                        : _t(
                            nl: 'Partners gezocht in jouw regio',
                            en: 'Partners wanted in your area',
                            fr: 'Partenaires recherchés dans votre région',
                            es: 'Se buscan socios en tu zona',
                          ),
                    color: hasActivePartnerSignals
                        ? partnerColor
                        : _gold.withOpacity(0.95),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: radarHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      _surfaceAlt.withOpacity(_isDarkTheme ? 0.88 : 0.65),
                      _surface.withOpacity(_isDarkTheme ? 0.96 : 0.78),
                      _surfaceAlt.withOpacity(_isDarkTheme ? 0.95 : 0.72),
                    ],
                  ),
                  border: Border.all(
                    color: _isDarkTheme
                        ? _gold.withOpacity(0.36)
                        : _border.withOpacity(0.95),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _shadow.withOpacity(_isDarkTheme ? 0.2 : 0.1),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RegionRadarPainter(
                          customerColor: _gold.withOpacity(0.98),
                          partnerColor: partnerColor,
                          showPartnerOpportunity: !hasActivePartnerSignals,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _surface.withOpacity(
                            _isDarkTheme ? 0.72 : 0.88,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _isDarkTheme
                                ? _gold.withOpacity(0.44)
                                : _border.withOpacity(1),
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: 'Anonieme interesse in jouw regio',
                            en: 'Anonymous interest in your region',
                            fr: 'Intérêt anonyme dans votre région',
                            es: 'Interés anónimo en tu zona',
                          ),
                          style: TextStyle(
                            color: _textPrimary.withOpacity(0.92),
                            fontSize: 10.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _surface.withOpacity(
                            _isDarkTheme ? 0.9 : 0.94,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isDarkTheme
                                ? _gold.withOpacity(0.36)
                                : _border.withOpacity(0.95),
                          ),
                        ),
                        child: Text(
                          _regionBadgeText(),
                          style: TextStyle(
                            color: _isDarkTheme
                                ? const Color(0xFFFFF1C7)
                                : _textPrimary.withOpacity(0.95),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _radarStatTile(
                      value: _radarCountTileValue(),
                      icon: Icons.groups_rounded,
                      tooltip: _t(
                        nl: 'Geïnteresseerden',
                        en: 'Interested people',
                        fr: 'Personnes intéressées',
                        es: 'Personas interesadas',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _radarStatTile(
                      value: _profilePostcode.trim().isNotEmpty
                          ? _profilePostcode.trim()
                          : _t(
                              nl: 'Jouw regio',
                              en: 'Your area',
                              fr: 'Votre région',
                              es: 'Tu zona',
                            ),
                      icon: Icons.location_on_rounded,
                      tooltip: _t(
                        nl: 'Jouw regio',
                        en: 'Your area',
                        fr: 'Votre région',
                        es: 'Tu zona',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _radarStatTile(
                      value: _t(
                        nl: 'Update',
                        en: 'Update',
                        fr: 'Info',
                        es: 'Aviso',
                      ),
                      icon: Icons.notifications_active_rounded,
                      tooltip: _t(
                        nl: 'Zodra actief',
                        en: 'When active',
                        fr: 'Dès activation',
                        es: 'Cuando esté activo',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submitFromProfileGuarded,
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: _actionOnGold,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(
                  _submitting
                      ? _t(
                          nl: 'Bezig...',
                          en: 'Sending...',
                          fr: 'Envoi...',
                          es: 'Enviando...',
                        )
                      : _t(
                          nl: 'Hou mij op de hoogte',
                          en: 'Keep me updated',
                          fr: 'Me tenir informé',
                          es: 'Mantenerme informado',
                        ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  nl: 'We gebruiken je gegevens enkel om je op de hoogte te houden. Geen spam, enkel belangrijk nieuws.',
                  en: 'We only use your details to keep you updated. No spam, only important news.',
                  fr: 'Nous utilisons vos données uniquement pour vous tenir informé. Pas de spam, seulement les nouvelles importantes.',
                  es: 'Solo usamos tus datos para mantenerte informado. Sin spam, solo noticias importantes.',
                ),
                style: TextStyle(
                  color: _textMuted.withOpacity(0.86),
                  fontSize: 11.1,
                  height: 1.28,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _shareRadar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold.withOpacity(0.98),
                  side: BorderSide(
                    color: _isDarkTheme
                        ? _gold.withOpacity(0.44)
                        : _border.withOpacity(1),
                  ),
                  backgroundColor: _isDarkTheme
                      ? Colors.transparent
                      : _surface.withOpacity(0.7),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(
                  _t(
                    nl: 'Deel met vrienden',
                    en: 'Share with friends',
                    fr: 'Partager avec des amis',
                    es: 'Compartir con amigos',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendDotLabel({required Color color, required String label}) {
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.55),
                  blurRadius: 8,
                  spreadRadius: 0.8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _textPrimary.withOpacity(0.9),
              fontSize: 11.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLegendChip({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.48)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.withOpacity(0.98),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _radarStatTile({
    required String value,
    required IconData icon,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _surfaceAlt.withOpacity(_isDarkTheme ? 0.95 : 0.86),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDarkTheme
                  ? _gold.withOpacity(0.26)
                  : _border.withOpacity(0.95),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _gold.withOpacity(0.98), size: 24),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _gold.withOpacity(0.98),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
