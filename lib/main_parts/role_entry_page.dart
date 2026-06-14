part of '../main.dart';

class RoleEntryPage extends StatelessWidget {
  const RoleEntryPage({super.key});
  static const Duration _backgroundCarouselInterval = Duration(
    milliseconds: 3200,
  );
  static const Duration _backgroundCrossfadeDuration = Duration(
    milliseconds: 850,
  );
  static final Set<String> _precachedRoleBackgrounds = <String>{};

  bool _isTabletPortrait(Size size) {
    final screenClass = FluxidiBreakpoints.classifyWidth(size.width);
    final isTabletLike =
        screenClass == FluxidiScreenClass.tablet ||
        screenClass == FluxidiScreenClass.desktop;
    return isTabletLike && size.height > size.width && size.height >= 900;
  }

  bool _isTabletLandscape(Size size) {
    final screenClass = FluxidiBreakpoints.classifyWidth(size.width);
    final isTabletLike =
        screenClass == FluxidiScreenClass.tablet ||
        screenClass == FluxidiScreenClass.desktop;
    return isTabletLike && size.width > size.height && size.height >= 700;
  }

  // Compact phone landscape: orientation is landscape AND viewport height is
  // small enough that the cockpit-style portrait carousel cannot fit. This is
  // height-based on purpose: most modern phones in landscape have widths
  // above 768 px, which `FluxidiBreakpoints.classifyWidth` already classifies
  // as tablet, so a width-based gate would never activate on a real phone.
  // Tablet landscape always has height >= 700, so the < 600 ceiling cleanly
  // excludes it.
  bool _isCompactPhoneLandscape(Size size) {
    return size.width > size.height && size.height < 600;
  }

  String _backgroundAssetForSize(Size size) {
    if (size.height > size.width && size.width < 600) {
      return 'assets/fluxidi/background_sign_in_page_phone.png';
    }
    return 'assets/fluxidi/background_sign_in_page.png';
  }

  List<String> _carouselAssetsForSize(Size size) {
    final isTabletPortrait = _isTabletPortrait(size);
    final isTabletLandscape = _isTabletLandscape(size);
    // Compact phone landscape uses a single static landscape-oriented
    // background instead of the rotating per-role carousel. The carousel
    // index (0..3) still cycles for the role-card highlight ring, but
    // returning the same asset for every slot prevents disorienting
    // crossfades on the very limited landscape height. No new assets are
    // generated; this reuses the dedicated phone-landscape image already
    // present in `assets/fluxidi/`.
    if (_isCompactPhoneLandscape(size)) {
      const phoneLandscapeAsset =
          'assets/fluxidi/background_sign_in_page_landscape_gsm.png';
      return const <String>[
        phoneLandscapeAsset,
        phoneLandscapeAsset,
        phoneLandscapeAsset,
        phoneLandscapeAsset,
      ];
    }
    final customerRoleAsset = isTabletPortrait
        ? 'assets/fluxidi/role_customer_bg_tablet_portrait.png'
        : isTabletLandscape
        ? 'assets/fluxidi/role_customer_bg_tablet_landscape.png'
        : 'assets/fluxidi/role_customer_bg.png';
    final businessRoleAsset = isTabletPortrait
        ? 'assets/fluxidi/role_business_bg_tablet_portrait.png'
        : isTabletLandscape
        ? 'assets/fluxidi/role_business_bg_tablet_landscape.png'
        : 'assets/fluxidi/role_business_bg.png';
    final driverRoleAsset = isTabletPortrait
        ? 'assets/fluxidi/role_driver_bg_tablet_portrait.png'
        : isTabletLandscape
        ? 'assets/fluxidi/role_driver_bg_tablet_landscape.png'
        : 'assets/fluxidi/role_driver_bg.png';
    return <String>[
      _backgroundAssetForSize(size),
      customerRoleAsset,
      businessRoleAsset,
      driverRoleAsset,
    ];
  }

  void _precacheCarouselAssets(BuildContext context, List<String> assets) {
    for (final asset in assets) {
      if (_precachedRoleBackgrounds.add(asset)) {
        unawaited(precacheImage(AssetImage(asset), context));
      }
    }
  }

  Widget _buildBackgroundLayer({
    required List<String> assets,
    required int activeBackgroundIndex,
    required bool isTabletPortrait,
    required bool isPhoneLandscape,
  }) {
    final activeAsset = assets[activeBackgroundIndex];
    return AnimatedSwitcher(
      duration: _backgroundCrossfadeDuration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: Image.asset(
        activeAsset,
        key: ValueKey<String>(activeAsset),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        // Compact phone landscape: align center so the dedicated landscape
        // gsm background fills the viewport edge-to-edge without aggressive
        // top-cropping. Tablet portrait already used center; phones in
        // portrait keep the existing top-center alignment for the
        // portrait-oriented hero asset.
        alignment: (isTabletPortrait || isPhoneLandscape)
            ? Alignment.center
            : Alignment.topCenter,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF3ECE1), Color(0xFFE6DACA)],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }

  String _normalizeHumanCompanyId(String raw) {
    var text = raw.trim().toUpperCase();
    text = text.replaceAll(RegExp(r'\s+'), '-');
    text = text.replaceAll(RegExp(r'-+'), '-');
    return text;
  }

  String? _validateHumanCompanyId(String raw) {
    final value = _normalizeHumanCompanyId(raw);
    if (value.isEmpty) {
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

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  Widget _roleCard({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required IconData icon,
    required double height,
    bool highlighted = false,
    // Compact form used by phone landscape (3 cards side-by-side). Reduces
    // icon, fonts and inner padding so each card fits comfortably in
    // ~200 px width without affecting portrait or tablet layouts.
    bool compact = false,
  }) {
    const double normalFillOpacity = 0.09;
    const double activeFillOpacity = 0.14;
    const double normalBorderOpacity = 0.56;
    const double activeBorderOpacity = 0.76;
    const double normalGlowOpacity = 0.08;
    const double activeGlowOpacity = 0.15;
    final fillOpacity = highlighted ? activeFillOpacity : normalFillOpacity;
    final borderOpacity = highlighted
        ? activeBorderOpacity
        : normalBorderOpacity;
    final glowOpacity = highlighted ? activeGlowOpacity : normalGlowOpacity;
    final double iconCircleSize = compact ? 48.0 : 74.0;
    final double iconGlyphSize = compact ? 26.0 : 40.0;
    final double iconRowGap = compact ? 8.0 : 10.0;
    final double horizontalPadding = compact ? 9.0 : 12.0;
    final double verticalPadding = compact ? 6.0 : 8.0;
    final double titleFontSize = compact ? 14.0 : 18.2;
    final double subtitleFontSize = compact ? 9.6 : 10.8;
    final double chevronSize = compact ? 16.0 : 21.0;
    final double chevronGap = compact ? 2.0 : 4.0;

    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFFFFFF).withOpacity(fillOpacity),
                  const Color(0xFFFFFFFF).withOpacity(fillOpacity * 0.52),
                  const Color(0xFF111827).withOpacity(highlighted ? 0.1 : 0.08),
                ],
              ),
              border: Border.all(
                color: kFluxidiYellow.withOpacity(borderOpacity),
                width: highlighted ? 1.1 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: kFluxidiYellow.withOpacity(glowOpacity),
                  blurRadius: highlighted ? 12 : 9,
                  spreadRadius: highlighted ? 0.26 : 0.12,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 9,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.06),
                  blurRadius: 2,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                children: [
                  Container(
                    width: iconCircleSize,
                    height: iconCircleSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827).withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kFluxidiYellow.withOpacity(0.64),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: kFluxidiYellow,
                      size: iconGlyphSize,
                    ),
                  ),
                  SizedBox(width: iconRowGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFFDFDFD),
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.15,
                            shadows: const [
                              Shadow(
                                color: Color(0x8A000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: subtitleFontSize,
                            fontWeight: FontWeight.w600,
                            height: 1.14,
                            shadows: const [
                              Shadow(
                                color: Color(0x70000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: chevronGap),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: kFluxidiYellow.withOpacity(0.98),
                    size: chevronSize,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageSelectorPill() {
    final code = currentLanguageCode.toUpperCase();
    return PopupMenuButton<String>(
      onSelected: setAppLanguageByCode,
      color: const Color(0xFF111827),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kFluxidiYellow.withOpacity(0.35)),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'nl', child: Text('🇳🇱 NL')),
        PopupMenuItem(value: 'en', child: Text('🇬🇧 EN')),
        PopupMenuItem(value: 'fr', child: Text('🇫🇷 FR')),
        PopupMenuItem(value: 'es', child: Text('🇪🇸 ES')),
      ],
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1524).withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: 14,
              color: kFluxidiYellow.withOpacity(0.95),
            ),
            const SizedBox(width: 5),
            Text(
              code,
              style: TextStyle(
                color: Colors.white.withOpacity(0.96),
                fontWeight: FontWeight.w800,
                fontSize: 10.8,
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: kFluxidiYellow.withOpacity(0.9),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goCustomer(BuildContext context) async {
    setAppRole(AppRole.customer);
    final validSession = await CustomerSessionStore.instance.loadValidSession();
    if (validSession != null) {
      await ActiveLocalCustomerStore.instance.setActiveCustomerId(
        validSession.customerId,
      );
      _clearCachedCustomerProfile();
      CustomerProfileStore.instance.invalidateCache();
      CustomerBookingsStore.instance.invalidateCache();
      await _bootstrapCustomerSessionAndMergeBookings(
        reason: 'customer_role_entry',
      );
      await _syncCustomerProfileFromBackendBestEffort(
        reason: 'customer_role_entry',
      );
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerHomePage()),
      );
      return;
    }
    await CustomerProfileStore.instance.ensureLegacyMigration();
    final hasExistingLocalProfile = await CustomerProfileStore.instance
        .hasResolvableLocalProfile();
    if (!context.mounted) return;
    final entryIntent = await _promptCustomerEntryIntent(
      context,
      hasExistingLocalProfile: hasExistingLocalProfile,
    );
    if (!context.mounted || entryIntent == null) return;
    if (entryIntent == _customerEntryPhoneLoginIntent) {
      final sessionResult = await Navigator.of(context).push<CustomerSession?>(
        MaterialPageRoute(builder: (_) => const CustomerPhoneRecoveryPage()),
      );
      if (!context.mounted || sessionResult == null) return;
      await ActiveLocalCustomerStore.instance.setActiveCustomerId(
        sessionResult.customerId,
      );
      _clearCachedCustomerProfile();
      CustomerProfileStore.instance.invalidateCache();
      CustomerBookingsStore.instance.invalidateCache();
      await _bootstrapCustomerSessionAndMergeBookings(
        reason: 'customer_phone_login',
      );
      await _syncCustomerProfileFromBackendBestEffort(
        reason: 'customer_phone_login',
      );
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerHomePage()),
      );
      return;
    }
    if (entryIntent == _customerEntryNewIntent) {
      await ActiveLocalCustomerStore.instance.createNewLocalCustomerId();
      _clearCachedCustomerProfile();
      CustomerProfileStore.instance.invalidateCache();
      CustomerBookingsStore.instance.invalidateCache();
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerOnboardingPage()),
      );
      return;
    }
    if (!context.mounted) return;
    if (entryIntent == _customerEntryContinueIntent ||
        hasExistingLocalProfile) {
      final profile = await CustomerProfileStore.instance.load();
      if (profile != null) {
        await ActiveLocalCustomerStore.instance.setActiveCustomerId(
          profile.customerId,
        );
      }
      _clearCachedCustomerProfile();
      CustomerProfileStore.instance.invalidateCache();
      CustomerBookingsStore.instance.invalidateCache();
      await _refreshCachedCustomerProfile();
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerHomePage()),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerOnboardingPage()),
    );
  }

  static const String _customerEntryPhoneLoginIntent =
      '__customer_phone_login__';
  static const String _customerEntryNewIntent = '__customer_new__';
  static const String _customerEntryContinueIntent = '__customer_continue__';
  static const String _companyPairingOnboardingIntent =
      '__open_company_onboarding__';
  static const String _companyRecoveryIntent = '__open_company_recovery__';

  Future<String?> _promptCustomerEntryIntent(
    BuildContext context, {
    required bool hasExistingLocalProfile,
  }) {
    return FluxidiResponsiveDialog.show<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
          ),
          title: Text(
            _t(
              nl: 'Klant starten',
              en: 'Start as customer',
              fr: 'Démarrer en client',
              es: 'Iniciar como cliente',
            ),
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasExistingLocalProfile) ...[
                OutlinedButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_customerEntryContinueIntent),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: Text(
                    _t(
                      nl: 'Doorgaan',
                      en: 'Continue',
                      fr: 'Continuer',
                      es: 'Continuar',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_customerEntryPhoneLoginIntent),
                child: Text(
                  _t(
                    nl: 'Inloggen met gsm',
                    en: 'Login with phone',
                    fr: 'Connexion avec gsm',
                    es: 'Iniciar con móvil',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_customerEntryNewIntent),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptExistingCompanyId(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    final result = await FluxidiResponsiveDialog.show<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
              ),
              title: Text(
                _t(
                  nl: 'Bedrijf koppelen',
                  en: 'Link company',
                  fr: 'Lier l’entreprise',
                  es: 'Vincular empresa',
                ),
                style: const TextStyle(color: Colors.white),
              ),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Vul de bedrijfscode in die je van Fluxidi of je beheerder kreeg.',
                      en: 'Enter the company code you received from Fluxidi or your administrator.',
                      fr: 'Saisissez le code entreprise reçu de Fluxidi ou de votre administrateur.',
                      es: 'Introduce el código de empresa que recibiste de Fluxidi o de tu administrador.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'Bedrijfscode',
                        en: 'Company code',
                        fr: 'Code entreprise',
                        es: 'Código de empresa',
                      ),
                      labelStyle: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                      ),
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.38),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.32),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(12),
                        ),
                        borderSide: BorderSide(
                          color: kFluxidiYellow,
                          width: 1.1,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      final normalized = _normalizeHumanCompanyId(value);
                      if (normalized != value) {
                        controller.value = TextEditingValue(
                          text: normalized,
                          selection: TextSelection.collapsed(
                            offset: normalized.length,
                          ),
                        );
                      }
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final normalized = _normalizeHumanCompanyId(
                      controller.text,
                    );
                    final validationError = _validateHumanCompanyId(normalized);
                    if (validationError != null) {
                      setDialogState(() => errorText = validationError);
                      return;
                    }
                    Navigator.of(dialogContext).pop(normalized);
                  },
                  child: Text(
                    _t(
                      nl: 'Volgende',
                      en: 'Next',
                      fr: 'Suivant',
                      es: 'Siguiente',
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(_companyRecoveryIntent),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
                  ),
                  child: Text(
                    _t(
                      nl: 'Ik heb mijn toestel niet meer',
                      en: 'Recover company account',
                      fr: 'Je n’ai plus mon appareil',
                      es: 'Ya no tengo mi dispositivo',
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_companyPairingOnboardingIntent),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
                  ),
                  child: Text(
                    _t(
                      nl: 'Ik wil mijn bedrijfsgegevens invullen',
                      en: 'I want to enter my company details',
                      fr: 'Je veux saisir les données de mon entreprise',
                      es: 'Quiero introducir los datos de mi empresa',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<bool?> _confirmResolvedCompanyPreview(
    BuildContext context, {
    required String companyCode,
    required String displayName,
    required String country,
    required String maskedPhone,
  }) {
    return FluxidiResponsiveDialog.show<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
          ),
          title: Text(
            _t(
              nl: 'Bedrijf gevonden',
              en: 'Company found',
              fr: 'Entreprise trouvée',
              es: 'Empresa encontrada',
            ),
            style: const TextStyle(color: Colors.white),
          ),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (displayName.isNotEmpty)
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (companyCode.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  companyCode,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.84),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
              if (country.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _t(
                    nl: 'Land: $country',
                    en: 'Country: $country',
                    fr: 'Pays : $country',
                    es: 'País: $country',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12,
                  ),
                ),
              ],
              if (maskedPhone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _t(
                    nl: 'Contact: $maskedPhone',
                    en: 'Contact: $maskedPhone',
                    fr: 'Contact : $maskedPhone',
                    es: 'Contacto: $maskedPhone',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
              ),
              child: Text(
                _t(
                  nl: 'Andere code gebruiken',
                  en: 'Use another code',
                  fr: 'Utiliser un autre code',
                  es: 'Usar otro código',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                _t(
                  nl: 'Dit is mijn bedrijf',
                  en: 'This is my company',
                  fr: 'C’est mon entreprise',
                  es: 'Esta es mi empresa',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _safePairingText(dynamic value) => (value ?? '').toString().trim();

  bool _looksLikeEmail(String value) {
    final email = value.trim().toLowerCase();
    if (email.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  Future<Map<String, String>?> _promptCompanyRecoveryStart(
    BuildContext context,
  ) async {
    final companyController = TextEditingController();
    final emailController = TextEditingController();
    String? companyError;
    String? emailError;
    final result = await FluxidiResponsiveDialog.show<Map<String, String>?>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
              ),
              title: Text(
                _t(
                  nl: 'Bedrijf herstellen',
                  en: 'Recover company account',
                  fr: 'Récupérer le compte entreprise',
                  es: 'Recuperar cuenta de empresa',
                ),
                style: const TextStyle(color: Colors.white),
              ),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Vul je Fluxidi-code en geregistreerde e-mail in.',
                      en: 'Enter your Fluxidi code and registered email.',
                      fr: 'Saisissez votre code Fluxidi et e-mail enregistré.',
                      es: 'Introduce tu código Fluxidi y correo registrado.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: companyController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'Fluxidi-code',
                        en: 'Fluxidi code',
                        fr: 'Code Fluxidi',
                        es: 'Código Fluxidi',
                      ),
                      errorText: companyError,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.38),
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (companyError != null) {
                        setDialogState(() => companyError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'Geregistreerde e-mail',
                        en: 'Registered email',
                        fr: 'E-mail enregistré',
                        es: 'Correo registrado',
                      ),
                      errorText: emailError,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.38),
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (emailError != null) {
                        setDialogState(() => emailError = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final code = _normalizeHumanCompanyId(
                      companyController.text,
                    );
                    final codeError = _validateHumanCompanyId(code);
                    final email = emailController.text.trim().toLowerCase();
                    final validEmail = _looksLikeEmail(email);
                    if (codeError != null || !validEmail) {
                      setDialogState(() {
                        companyError = codeError;
                        emailError = validEmail
                            ? null
                            : _t(
                                nl: 'Vul een geldig e-mailadres in.',
                                en: 'Enter a valid email address.',
                                fr: 'Saisissez une adresse e-mail valide.',
                                es: 'Introduce un correo electrónico válido.',
                              );
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(<String, String>{
                      'companyCode': code,
                      'email': email,
                    });
                  },
                  child: Text(
                    _t(
                      nl: 'Start herstel',
                      en: 'Start recovery',
                      fr: 'Démarrer la récupération',
                      es: 'Iniciar recuperación',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    companyController.dispose();
    emailController.dispose();
    return result;
  }

  Future<String?> _promptCompanyRecoveryOtp(
    BuildContext context, {
    String? maskedEmail,
    String? debugOtp,
  }) async {
    final otpController = TextEditingController(text: debugOtp ?? '');
    String? errorText;
    final result = await FluxidiResponsiveDialog.show<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
              ),
              title: Text(
                _t(
                  nl: 'Bevestig herstelcode',
                  en: 'Confirm recovery code',
                  fr: 'Confirmer le code de récupération',
                  es: 'Confirmar código de recuperación',
                ),
                style: const TextStyle(color: Colors.white),
              ),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Vul de code in die naar je e-mail is gestuurd.',
                      en: 'Enter the code sent to your email.',
                      fr: 'Saisissez le code envoyé à votre e-mail.',
                      es: 'Introduce el código enviado a tu correo.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  if ((maskedEmail ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      (maskedEmail ?? '').trim(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'Herstelcode',
                        en: 'Recovery code',
                        fr: 'Code de récupération',
                        es: 'Código de recuperación',
                      ),
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.38),
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final otp = otpController.text.trim();
                    if (!RegExp(r'^\d{4,8}$').hasMatch(otp)) {
                      setDialogState(
                        () => errorText = _t(
                          nl: 'Vul een geldige herstelcode in.',
                          en: 'Enter a valid recovery code.',
                          fr: 'Saisissez un code de récupération valide.',
                          es: 'Introduce un código de recuperación válido.',
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(otp);
                  },
                  child: Text(
                    _t(
                      nl: 'Bevestigen',
                      en: 'Verify',
                      fr: 'Vérifier',
                      es: 'Verificar',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    otpController.dispose();
    return result;
  }

  Future<void> _runCompanyRecoveryFlow(BuildContext context) async {
    final startInput = await _promptCompanyRecoveryStart(context);
    if (!context.mounted || startInput == null) return;
    final companyCode = _safePairingText(startInput['companyCode']);
    final email = _safePairingText(startInput['email']).toLowerCase();
    if (companyCode.isEmpty || !_looksLikeEmail(email)) return;
    Map<String, dynamic> started;
    try {
      started = await startPublicCompanyRecovery(
        payload: <String, dynamic>{
          'company_code': companyCode,
          'email': email,
          'device_label': 'Nieuw toestel',
          'device_type': 'mobile',
        },
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Herstel starten lukt niet. Probeer opnieuw.',
              en: 'Could not start recovery. Please try again.',
              fr: 'Impossible de démarrer la récupération. Réessayez.',
              es: 'No se pudo iniciar la recuperación. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }
    final challengeId = _safePairingText(
      started['challenge_id'] ?? started['challengeId'],
    );
    if (challengeId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Herstelcode kon niet worden gestart. Probeer opnieuw.',
              en: 'Recovery could not be started. Please retry.',
              fr: 'La récupération n’a pas pu démarrer. Réessayez.',
              es: 'No se pudo iniciar la recuperación. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final otp = await _promptCompanyRecoveryOtp(
      context,
      maskedEmail: _safePairingText(
        started['masked_email'] ?? started['maskedEmail'],
      ),
      debugOtp: _safePairingText(
        started['recovery_code'] ?? started['recoveryCode'],
      ),
    );
    if (!context.mounted || otp == null) return;
    Map<String, dynamic> verified;
    try {
      verified = await verifyPublicCompanyRecovery(
        payload: <String, dynamic>{
          'challenge_id': challengeId,
          'company_code': companyCode,
          'email': email,
          'otp': otp,
          'device_label': 'Nieuw toestel',
          'device_type': 'mobile',
        },
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Herstel mislukt. Controleer code en e-mail en probeer opnieuw.',
              en: 'Recovery failed. Check code and email and try again.',
              fr: 'La récupération a échoué. Vérifiez le code et l’e-mail puis réessayez.',
              es: 'La recuperación falló. Verifica el código y el correo e inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final opened = await _openVerifiedCompanySession(context, verified, true);
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Herstel mislukt. Probeer opnieuw.',
              en: 'Recovery failed. Please try again.',
              fr: 'La récupération a échoué. Réessayez.',
              es: 'La recuperación falló. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _resolveCompanyCode(String companyCode) async {
    final uri = Uri.parse(
      '$kBookingBaseUrl/public/company/resolve?code=${Uri.encodeQueryComponent(companyCode)}',
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode == 200 && body['ok'] == true) {
        return <String, dynamic>{
          'ok': true,
          'company_code': _safePairingText(body['company_code']),
          'display_name': _safePairingText(body['display_name']),
          'country': _safePairingText(body['country']),
          'masked_phone': _safePairingText(body['masked_phone']),
        };
      }
      final error = _safePairingText(body['error']).toLowerCase();
      if (response.statusCode == 404 || error == 'company_not_found') {
        return <String, dynamic>{'ok': false, 'error': 'company_not_found'};
      }
      return <String, dynamic>{'ok': false, 'error': 'verification_failed'};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'error': 'verification_failed'};
    }
  }

  Future<String?> _promptCompanyPairingCode(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    final result = await FluxidiResponsiveDialog.show<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
              ),
              title: Text(
                _t(
                  nl: 'Verificatiecode invoeren',
                  en: 'Enter verification code',
                  fr: 'Saisir le code de vérification',
                  es: 'Introducir código de verificación',
                ),
                style: const TextStyle(color: Colors.white),
              ),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Vul de 6-cijferige code in die je van je beheerder kreeg.',
                      en: 'Enter the 6-digit code you received from your administrator.',
                      fr: 'Saisissez le code à 6 chiffres reçu de votre administrateur.',
                      es: 'Introduce el código de 6 dígitos que recibiste de tu administrador.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'Verificatiecode',
                        en: 'Verification code',
                        fr: 'Code de vérification',
                        es: 'Código de verificación',
                      ),
                      labelStyle: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                      ),
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.38),
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final pairingCode = controller.text.trim();
                    if (!RegExp(r'^\d{6}$').hasMatch(pairingCode)) {
                      setDialogState(
                        () => errorText = _t(
                          nl: 'Vul een geldige 6-cijferige verificatiecode in.',
                          en: 'Enter a valid 6-digit verification code.',
                          fr: 'Saisissez un code de vérification valide à 6 chiffres.',
                          es: 'Introduce un código de verificación válido de 6 dígitos.',
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(pairingCode);
                  },
                  child: Text(
                    _t(
                      nl: 'Toestel koppelen',
                      en: 'Link device',
                      fr: 'Lier l’appareil',
                      es: 'Vincular dispositivo',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<String?> _promptCompanyActivationCode(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    final result = await FluxidiResponsiveDialog.show<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
              ),
              title: Text(
                _t(
                  nl: 'Activatiecode invoeren',
                  en: 'Enter activation code',
                  fr: "Saisir le code d'activation",
                  es: 'Introducir código de activación',
                ),
                style: const TextStyle(color: Colors.white),
              ),
              scrollable: true,
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t(
                        nl: 'Vul je activatiecode in. Voorbeeld: FLX-4821-123456',
                        en: 'Enter your activation code. Example: FLX-4821-123456',
                        fr: "Saisissez votre code d'activation. Exemple : FLX-4821-123456",
                        es: 'Introduce tu código de activación. Ejemplo: FLX-4821-123456',
                      ),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Activatiecode',
                          en: 'Activation code',
                          fr: "Code d'activation",
                          es: 'Código de activación',
                        ),
                        labelStyle: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                        ),
                        errorText: errorText,
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: kFluxidiYellow.withOpacity(0.38),
                          ),
                        ),
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final activationCode = controller.text.trim();
                        if (activationCode.isEmpty) {
                          setDialogState(
                            () => errorText = _t(
                              nl: 'Vul je activatiecode in.',
                              en: 'Enter your activation code.',
                              fr: "Saisissez votre code d'activation.",
                              es: 'Introduce tu código de activación.',
                            ),
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(activationCode);
                      },
                      child: Text(
                        _t(
                          nl: 'Toestel koppelen',
                          en: 'Link device',
                          fr: 'Lier l’appareil',
                          es: 'Vincular dispositivo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(_companyRecoveryIntent),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        _t(
                          nl: 'Ik heb mijn toestel niet meer',
                          en: 'Recover company account',
                          fr: 'Je n’ai plus mon appareil',
                          es: 'Ya no tengo mi dispositivo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(_companyPairingOnboardingIntent),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        _t(
                          nl: 'Nieuw bedrijf aanmaken',
                          en: 'Create new company account',
                          fr: 'Créer un nouveau compte entreprise',
                          es: 'Crear nueva cuenta de empresa',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  ({String companyCode, String pairingCode})? _parseCompanyActivationCode(
    String input,
  ) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final normalized = raw
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isEmpty) return null;
    final parts = normalized
        .split('-')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return null;
    final pairingCode = parts.last.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pairingCode)) return null;
    final companyCodeCandidate = parts
        .sublist(0, parts.length - 1)
        .join('-')
        .trim();
    if (companyCodeCandidate.isEmpty) return null;
    final normalizedCompanyCode = _normalizeHumanCompanyId(
      companyCodeCandidate,
    );
    final companyValidationError = _validateHumanCompanyId(
      normalizedCompanyCode,
    );
    if (companyValidationError != null) return null;
    return (companyCode: normalizedCompanyCode, pairingCode: pairingCode);
  }

  Future<void> _showCompanyPairingSuccessDialog(BuildContext context) {
    return FluxidiResponsiveDialog.show<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
          ),
          title: Text(
            _t(
              nl: 'Toestel gekoppeld',
              en: 'Device linked',
              fr: 'Appareil lié',
              es: 'Dispositivo vinculado',
            ),
            style: const TextStyle(color: Colors.white),
          ),
          scrollable: true,
          content: Text(
            _t(
              nl: 'Je toestel is veilig gekoppeld aan je bedrijf.',
              en: 'Your device has been securely linked to your company.',
              fr: 'Votre appareil est lié en toute sécurité à votre entreprise.',
              es: 'Tu dispositivo se vinculó de forma segura a tu empresa.',
            ),
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                _t(
                  nl: 'Verder naar dashboard',
                  en: 'Continue to dashboard',
                  fr: 'Continuer vers le tableau de bord',
                  es: 'Continuar al panel',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showCompanyPairingTestModeDialog(BuildContext context) {
    return FluxidiResponsiveDialog.show<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
          ),
          title: Text(
            _t(
              nl: 'Testmodus',
              en: 'Test mode',
              fr: 'Mode test',
              es: 'Modo de prueba',
            ),
            style: const TextStyle(color: Colors.white),
          ),
          scrollable: true,
          content: Text(
            _t(
              nl: 'Dit toestel wordt gekoppeld zonder verificatiecode. Gebruik dit alleen voor ontwikkeling en testen.',
              en: 'This device will be linked without a verification code. Use this only for development and testing.',
              fr: 'Cet appareil sera lié sans code de vérification. Utilisez ceci uniquement pour le développement et les tests.',
              es: 'Este dispositivo se vinculará sin código de verificación. Úsalo solo para desarrollo y pruebas.',
            ),
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                _t(
                  nl: 'Koppelen in testmodus',
                  en: 'Link in test mode',
                  fr: 'Lier en mode test',
                  es: 'Vincular en modo de prueba',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _verifyCompanyPairingCode({
    required String companyCode,
    required String pairingCode,
  }) async {
    final uri = Uri.parse('$kBookingBaseUrl/public/company/link/verify');
    try {
      final response = await http
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'company_code': companyCode,
              'pairing_code': pairingCode,
              'device_label': 'Bedrijf tablet',
              'device_type': 'tablet',
            }),
          )
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final ok = body['ok'] == true;
      final role = _safePairingText(body['role']);
      if (response.statusCode == 200 && ok && role == 'companyAdmin') {
        return <String, dynamic>{'ok': true, 'payload': body};
      }
      final error = _safePairingText(body['error']).toLowerCase();
      if (error == 'company_not_found') {
        return <String, dynamic>{'ok': false, 'error': 'company_not_found'};
      }
      return <String, dynamic>{'ok': false, 'error': 'verification_failed'};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'error': 'verification_failed'};
    }
  }

  Future<bool> _openVerifiedCompanySession(
    BuildContext context,
    Map<String, dynamic> payload, [
    bool enforcePinGateOnEntry = false,
  ]) async {
    if (payload['ok'] != true) return false;
    if (_safePairingText(payload['role']) != 'companyAdmin') return false;
    final tenantId = _safePairingText(payload['tenant_id']);
    final companyId = _safePairingText(payload['company_id']);
    final companyCode = _safePairingText(payload['company_code']);
    if (tenantId.isEmpty || companyId.isEmpty || companyCode.isEmpty) {
      return false;
    }
    final companyMap = payload['company'] is Map
        ? Map<String, dynamic>.from(payload['company'] as Map)
        : <String, dynamic>{};
    final companyName = _safePairingText(companyMap['display_name']);
    final countryCode = _safePairingText(companyMap['country']);
    final issuedAt = DateTime.tryParse(_safePairingText(payload['issued_at']));
    final expiresAt = DateTime.tryParse(
      _safePairingText(payload['expires_at']),
    );
    final companySessionToken = _safePairingText(
      payload['company_session_token'] ?? payload['companySessionToken'],
    );
    final expiresInSeconds = int.tryParse(
      _safePairingText(payload['expires_in'] ?? payload['expiresIn']),
    );
    final linkMethod = _safePairingText(
      payload['link_method'] ?? payload['linkMethod'],
    );
    await CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
      tenantId: tenantId,
      companyId: companyId,
      companyCode: companyCode,
      companyName: companyName,
      countryCode: countryCode,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      companySessionToken: companySessionToken,
      expiresInSeconds: expiresInSeconds,
      linkMethod: linkMethod,
    );
    await DriverSessionStore.instance.clearStandaloneSessionIfScopeMismatch(
      tenantId: tenantId,
      companyId: companyId,
    );
    if (companySessionToken.isNotEmpty) {
      final normalizedLinkMethod = linkMethod.trim().toLowerCase();
      final restoredSource = normalizedLinkMethod.contains('recovery')
          ? 'recovery'
          : 'pairing';
      debugPrint('[COMPANY_SESSION][TOKEN_RESTORED] source=$restoredSource');
      await _hydrateCompanyBootstrapFromActiveSession(
        reason: 'pairing_success',
      );
      unawaited(
        _triggerCompanyInventoryBackfillRestore(reason: 'company_home_restore'),
      );
    }
    final hasToken = await _hasUsableCompanyBootstrapToken(
      reason: 'pairing_success',
      logDegraded: true,
    );
    if (!hasToken) return false;
    if (!context.mounted) return false;
    if (!CompanySessionStore.instance.hasValidCompanyContext) return false;
    setAppRole(AppRole.companyAdmin);
    final Widget nextPage = enforcePinGateOnEntry
        ? const FluxidiAppLockGatePage(
            target: BusinessHomePage(),
            shouldGate: true,
          )
        : const BusinessHomePage();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => nextPage));
    return true;
  }

  Future<bool> _openDevBypassCompanySession(
    BuildContext context, {
    required String resolvedCompanyCode,
    required String resolvedDisplayName,
    required String resolvedCountry,
  }) async {
    final companyCode = resolvedCompanyCode.trim();
    if (companyCode.isEmpty) return false;
    final tenantId = _fluxidiDevTenantId.trim().isNotEmpty
        ? _fluxidiDevTenantId.trim()
        : companyCode;
    final companyId = _fluxidiDevCompanyId.trim().isNotEmpty
        ? _fluxidiDevCompanyId.trim()
        : companyCode;
    final companyName = resolvedDisplayName.trim().isEmpty
        ? companyCode
        : resolvedDisplayName.trim();
    final country = resolvedCountry.trim().toUpperCase();
    debugPrint(
      '[COMPANY_PAIRING][DEV_BYPASS] tenant=$tenantId company=$companyId code=$companyCode',
    );
    await CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
      tenantId: tenantId,
      companyId: companyId,
      companyCode: companyCode,
      companyName: companyName,
      countryCode: country,
      issuedAt: DateTime.now().toUtc(),
      linkMethod: 'dev_pairing_bypass',
    );
    final hasToken = await _hasUsableCompanyBootstrapToken(
      reason: 'dev_pairing_bypass',
      logDegraded: true,
    );
    if (!hasToken) return false;
    unawaited(
      _triggerCompanyInventoryBackfillRestore(reason: 'company_home_restore'),
    );
    if (!context.mounted) return false;
    if (!CompanySessionStore.instance.hasValidCompanyContext) return false;
    setAppRole(AppRole.companyAdmin);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const BusinessHomePage()),
    );
    return true;
  }

  String _companyPairingErrorText(String code) {
    if (code == 'company_not_found') {
      return _t(
        nl: 'We vinden geen bedrijf met deze code. Controleer de code en probeer opnieuw.',
        en: 'We could not find a company with this code. Check the code and try again.',
        fr: 'Aucune entreprise trouvée avec ce code. Vérifiez le code et réessayez.',
        es: 'No encontramos una empresa con este código. Verifica el código e inténtalo de nuevo.',
      );
    }
    if (code == 'verification_failed') {
      return _t(
        nl: 'De verificatiecode klopt niet of is verlopen. Vraag een nieuwe code aan je beheerder.',
        en: 'The verification code is incorrect or expired. Ask your administrator for a new code.',
        fr: 'Le code de vérification est incorrect ou expiré. Demandez un nouveau code à votre administrateur.',
        es: 'El código de verificación es incorrecto o ha caducado. Solicita un nuevo código a tu administrador.',
      );
    }
    return _t(
      nl: 'Koppelen lukt niet. Controleer de gegevens en probeer opnieuw.',
      en: 'Linking failed. Check your details and try again.',
      fr: 'La liaison a échoué. Vérifiez les données et réessayez.',
      es: 'No se pudo vincular. Revisa los datos e inténtalo de nuevo.',
    );
  }

  void _openBusinessOnboarding(
    BuildContext context, {
    String? initialCompanyId,
    bool lockCompanyId = false,
  }) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CompanyOnboardingPage(
          initialCompanyId: initialCompanyId,
          lockCompanyId: lockCompanyId,
          onCompleted: (ctx) async {
            await CompanySessionStore.instance.bootstrap();
            final hasContext =
                CompanySessionStore.instance.hasValidCompanyContext;
            if (!ctx.mounted) return;
            if (!hasContext) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      nl: 'Bedrijfstoegang vereist eerst activatie of herstel.',
                      en: 'Business access requires activation or recovery first.',
                      fr: "L'accès entreprise nécessite d'abord une activation ou récupération.",
                      es: 'El acceso de empresa requiere primero activación o recuperación.',
                    ),
                  ),
                ),
              );
              Navigator.of(ctx).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const RoleEntryPage()),
                (route) => false,
              );
              return;
            }
            final hasToken = await _hasUsableCompanyBootstrapToken(
              reason: 'onboarding_complete',
              logDegraded: true,
            );
            if (!ctx.mounted) return;
            if (!hasToken) {
              await _blockBusinessHomeEntryWithoutBootstrapToken(
                ctx,
                blockLog: '[COMPANY_SESSION][ONBOARDING_BLOCKED_NO_TOKEN]',
                recoveryReason: 'onboarding_blocked_no_token',
                retryReason: 'onboarding_after_recovery',
              );
              if (!ctx.mounted) return;
              final hasTokenAfter = await _hasUsableCompanyBootstrapToken(
                reason: 'onboarding_after_recovery',
              );
              if (!hasTokenAfter) {
                if (!ctx.mounted) return;
                Navigator.of(ctx).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                    builder: (_) => const RoleEntryPage(),
                  ),
                  (route) => false,
                );
              }
              return;
            }
            // After a fresh public-company registration succeeded and the
            // bootstrap token is usable, push the first-run setup choice
            // page so the operator can pick between:
            //   - the deterministic step-by-step wizard
            //     (BusinessFirstRunWizardPage),
            //   - the full settings cockpit (const BusinessSettingsPage()),
            //   - or skipping straight to BusinessHomePage.
            // Each path eventually flows through the same existing
            // _navigateToBusinessHomeWithBootstrapHydration call so token
            // hydration, role flagging, and inventory backfill stay
            // identical to the pre-wizard behavior. Existing companies
            // with a valid session enter via [_goBusiness] and never reach
            // this branch, so they are NOT pushed into this flow.
            if (!ctx.mounted) return;
            debugPrint('[FIRST_RUN_WIZARD][CHOICE_OPEN]');
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute<void>(
                builder: (choiceCtx) => BusinessFirstRunSetupChoicePage(
                  onStartStepWizard: () {
                    if (!choiceCtx.mounted) return;
                    debugPrint('[FIRST_RUN_WIZARD][CHOICE_STEP_BY_STEP]');
                    Navigator.of(choiceCtx).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (wizardCtx) => BusinessFirstRunWizardPage(
                          // Successful wizard completion now routes
                          // through the new lightweight Fluxidi
                          // orientation/product-tour flow before the
                          // operator lands on BusinessHomePage. The
                          // helper `_navigateToBusinessHomeWithBootstrapHydration`
                          // still runs at the very end so token
                          // hydration, role flagging, and inventory
                          // backfill stay byte-identical to the
                          // pre-orientation behavior.
                          onFinished: () {
                            if (!wizardCtx.mounted) return;
                            debugPrint(
                              '[FIRST_RUN_WIZARD][AFTER_FINISH] '
                              '-> orientation_flow',
                            );
                            Navigator.of(wizardCtx).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (orientationCtx) =>
                                    BusinessOrientationFlowPage(
                                      // Opened right after the guided
                                      // setup flow completed → show the
                                      // "Setup voltooid" reward framing.
                                      entryMode: BusinessOrientationEntryMode
                                          .setupCompleted,
                                      onFinish: () {
                                        if (!orientationCtx.mounted) return;
                                        unawaited(
                                          _navigateToBusinessHomeWithBootstrapHydration(
                                            orientationCtx,
                                            reason:
                                                'business_orientation_finish',
                                          ),
                                        );
                                      },
                                      onSkip: () {
                                        if (!orientationCtx.mounted) return;
                                        unawaited(
                                          _navigateToBusinessHomeWithBootstrapHydration(
                                            orientationCtx,
                                            reason: 'business_orientation_skip',
                                          ),
                                        );
                                      },
                                    ),
                              ),
                            );
                          },
                          // "Finish setup later" (overflow menu in the
                          // wizard) intentionally bypasses the
                          // orientation flow — the operator explicitly
                          // chose to defer setup, so we land them
                          // straight on BusinessHomePage as before.
                          onSkipped: () {
                            if (!wizardCtx.mounted) return;
                            unawaited(
                              _navigateToBusinessHomeWithBootstrapHydration(
                                wizardCtx,
                                reason: 'first_run_wizard_skipped',
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  onOpenFullSettings: () {
                    if (!choiceCtx.mounted) return;
                    debugPrint('[FIRST_RUN_WIZARD][OPEN_FULL_SETTINGS]');
                    // Capture the navigator BEFORE the await: the
                    // bootstrap-hydration call ends with a pushReplacement
                    // that disposes the choice page, so choiceCtx becomes
                    // unmounted. The NavigatorState itself stays alive
                    // (it's the MaterialApp's navigator).
                    final navigator = Navigator.of(choiceCtx);
                    unawaited(() async {
                      await _navigateToBusinessHomeWithBootstrapHydration(
                        choiceCtx,
                        reason: 'first_run_open_full_settings',
                      );
                      if (!navigator.mounted) return;
                      // Push the normal full-cockpit settings page on top
                      // of BusinessHomePage so the system back button
                      // returns the operator to BusinessHomePage. No
                      // wizard, no stepMode — `const BusinessSettingsPage()`
                      // is byte-identical to the existing Settings quick
                      // action.
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BusinessSettingsPage(),
                        ),
                      );
                    }());
                  },
                  onSkip: () {
                    if (!choiceCtx.mounted) return;
                    debugPrint('[FIRST_RUN_WIZARD][CHOICE_LATER]');
                    unawaited(
                      _navigateToBusinessHomeWithBootstrapHydration(
                        choiceCtx,
                        reason: 'first_run_choice_later',
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _goBusiness(BuildContext context) async {
    await CompanySessionStore.instance.bootstrap();
    if (CompanySessionStore.instance.hasValidCompanyContext) {
      final hasToken = await _hasUsableCompanyBootstrapToken(
        reason: 'role_entry',
        logDegraded: true,
      );
      if (!context.mounted) return;
      if (hasToken) {
        await _navigateToBusinessHomeWithBootstrapHydration(
          context,
          reason: 'role_entry',
        );
        return;
      }
      await _blockBusinessHomeEntryWithoutBootstrapToken(
        context,
        blockLog: '[COMPANY_SESSION][ROLE_ENTRY_BLOCKED_NO_TOKEN]',
        recoveryReason: 'role_entry_blocked_no_token',
        retryReason: 'role_entry_after_recovery',
      );
      return;
    }
    if (!context.mounted) return;
    while (true) {
      final activationCode = await _promptCompanyActivationCode(context);
      if (!context.mounted || activationCode == null) return;
      if (activationCode == _companyPairingOnboardingIntent) {
        await CompanySessionStore.instance.clearLocalCompanyState();
        if (!context.mounted) return;
        _openBusinessOnboarding(context);
        return;
      }
      if (activationCode == _companyRecoveryIntent) {
        await _runCompanyRecoveryFlow(context);
        return;
      }
      final parsed = _parseCompanyActivationCode(activationCode);
      if (parsed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Ongeldige activatiecode. Gebruik bijvoorbeeld FLX-4821-123456.',
                en: 'Invalid activation code. Use for example FLX-4821-123456.',
                fr: 'Code d’activation invalide. Utilisez par exemple FLX-4821-123456.',
                es: 'Código de activación no válido. Usa por ejemplo FLX-4821-123456.',
              ),
            ),
          ),
        );
        continue;
      }
      if (_effectiveFluxidiDevPairingBypass) {
        final bypassConfirmed = await _showCompanyPairingTestModeDialog(
          context,
        );
        if (!context.mounted || bypassConfirmed != true) return;
        final opened = await _openDevBypassCompanySession(
          context,
          resolvedCompanyCode: parsed.companyCode,
          resolvedDisplayName: parsed.companyCode,
          resolvedCountry: '',
        );
        if (!context.mounted) return;
        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_companyPairingErrorText('verification_failed')),
            ),
          );
        }
        return;
      }
      final verified = await _verifyCompanyPairingCode(
        companyCode: parsed.companyCode,
        pairingCode: parsed.pairingCode,
      );
      if (!context.mounted) return;
      if (verified['ok'] != true) {
        final errorCode = _safePairingText(verified['error']).toLowerCase();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_companyPairingErrorText(errorCode))),
        );
        return;
      }
      final payload = verified['payload'] is Map
          ? Map<String, dynamic>.from(verified['payload'] as Map)
          : <String, dynamic>{};
      await _showCompanyPairingSuccessDialog(context);
      if (!context.mounted) return;
      final opened = await _openVerifiedCompanySession(context, payload);
      if (!context.mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_companyPairingErrorText('verification_failed')),
          ),
        );
      }
      return;
    }
  }

  Future<void> _goDriver(BuildContext context) async {
    DriverSessionStore.instance.prepareStandaloneDriverEntry();
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    await DriverDocumentsStore.instance.load();
    if (!context.mounted) return;
    final activeSession = activeDriverSessionNotifier.value;
    if (activeSession != null &&
        !_isCompanyAdminDriverViewSession(activeSession)) {
      setAppRole(AppRole.driver);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverHomePage()),
      );
    } else {
      if (_isCompanyAdminDriverViewSession(activeSession)) {
        debugPrint('[DRIVER_ADMIN_VIEW][IGNORE_FOR_NORMAL_LOGIN]');
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final carouselAssets = _carouselAssetsForSize(viewportSize);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _precacheCarouselAssets(context, carouselAssets);
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        if (disableAnimations) {
          return _buildScaffoldWithBackground(
            context: context,
            assets: carouselAssets,
            activeBackgroundIndex: 0,
          );
        }
        return StreamBuilder<int>(
          initialData: 0,
          stream: Stream<int>.periodic(
            _backgroundCarouselInterval,
            (tick) => (tick + 1) % carouselAssets.length,
          ),
          builder: (context, snapshot) {
            final activeBackgroundIndex = snapshot.data ?? 0;
            return _buildScaffoldWithBackground(
              context: context,
              assets: carouselAssets,
              activeBackgroundIndex: activeBackgroundIndex,
            );
          },
        );
      },
    );
  }

  Widget _buildScaffoldWithBackground({
    required BuildContext context,
    required List<String> assets,
    required int activeBackgroundIndex,
  }) {
    final viewportSize = MediaQuery.sizeOf(context);
    final isTabletPortrait = _isTabletPortrait(viewportSize);
    // Height-based detection so it activates on real phones in landscape
    // even when the viewport width (typically 800-960 px) crosses the
    // tablet width breakpoint. Tablet landscape always has height >= 700,
    // so this < 600 ceiling cannot match a tablet.
    final isScaffoldPhoneLandscape = _isCompactPhoneLandscape(viewportSize);
    return Scaffold(
      backgroundColor: kFluxidiBlack,
      body: SafeArea(
        bottom: !isTabletPortrait,
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildBackgroundLayer(
                assets: assets,
                activeBackgroundIndex: activeBackgroundIndex,
                isTabletPortrait: isTabletPortrait,
                isPhoneLandscape: isScaffoldPhoneLandscape,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.44, 0.78, 1.0],
                      colors: [
                        Colors.black.withOpacity(0.0),
                        Colors.black.withOpacity(0.06),
                        Colors.black.withOpacity(0.10),
                        Colors.black.withOpacity(0.14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                double clampDouble(double v, double min, double max) =>
                    v < min ? min : (v > max ? max : v);

                final W = constraints.maxWidth;
                final H = constraints.maxHeight;
                final veryCompact = constraints.maxHeight < 680;
                final narrow = constraints.maxWidth < 390;
                final screenClass = FluxidiBreakpoints.classifyWidth(W);
                final isTabletLike =
                    screenClass == FluxidiScreenClass.tablet ||
                    screenClass == FluxidiScreenClass.desktop;
                final isLandscape = W > H;
                final isTabletPortrait =
                    isTabletLike && !isLandscape && H >= 900;
                final isTabletLandscape =
                    isTabletLike && isLandscape && H >= 700;
                // Compact phone landscape: detected purely from height so
                // that real phones in landscape (which often classify as
                // "tablet" by width because viewport width is 800-960 px)
                // still hit this branch. Tablet landscape always has
                // H >= 700 so the < 600 ceiling cannot accidentally match
                // a tablet. Used ONLY by this start page to swap to a
                // compact 3-column role card row, smaller header and a
                // top-right language pill so all 3 roles + language stay
                // visible/tappable above the gesture bar. Phone portrait,
                // tablet portrait and tablet landscape stay byte-identical.
                final isPhoneLandscape = isLandscape && H < 600;
                final contentHorizontalPadding = narrow ? 14.0 : 18.0;
                final logoTop = isTabletLandscape
                    ? 6.0
                    : isPhoneLandscape
                    ? 6.0
                    : (veryCompact ? 16.0 : 24.0);
                final languageTop = veryCompact ? 4.0 : 6.0;
                final logoMaxBySpace =
                    constraints.maxWidth -
                    (contentHorizontalPadding * 2) -
                    84.0;
                // Phone landscape uses a smaller logo so it sits cleanly
                // next to the language pill in the very limited top band.
                final logoWidth = isPhoneLandscape
                    ? clampDouble(constraints.maxWidth * 0.22, 110.0, 140.0)
                    : math.max(
                        170.0,
                        math.min(
                          logoMaxBySpace,
                          constraints.maxWidth * (narrow ? 0.62 : 0.55),
                        ),
                      );
                final logoLeft = isTabletLandscape
                    ? -clampDouble(logoWidth * 0.16, 64.0, 96.0)
                    : 0.0;
                const contentMaxWidth = 470.0;
                // Phone landscape gets a wider content column so the 3
                // compact role cards plus inter-card gaps share the row
                // comfortably without clipping the right-most card.
                final phoneLandscapeMaxWidth = clampDouble(
                  W - 24.0,
                  480.0,
                  720.0,
                );
                final effectiveMaxContentWidth = isPhoneLandscape
                    ? phoneLandscapeMaxWidth
                    : contentMaxWidth;
                final languageRight = isTabletLandscape
                    ? -clampDouble(
                        ((W - contentMaxWidth) / 2.0) - 36.0,
                        0.0,
                        520.0,
                      )
                    : isTabletPortrait
                    ? -clampDouble(
                        ((W - contentMaxWidth) / 2.0) - 26.0,
                        0.0,
                        520.0,
                      )
                    : 0.0;
                final resolvedLanguageTop = isTabletPortrait
                    ? math.max(20.0, languageTop + 14.0)
                    : isPhoneLandscape
                    ? 8.0
                    : languageTop;
                final basePhoneContentTop = veryCompact ? 112.0 : 136.0;
                final contentTop = isTabletLandscape
                    ? clampDouble(H * 0.40, 330.0, 365.0)
                    : isTabletPortrait
                    ? clampDouble(H * 0.35, 360.0, 500.0)
                    : isPhoneLandscape
                    // Phone landscape: tuck content close under the small
                    // logo so the 3 cards + reassurance fit above the
                    // gesture bar without scrolling on common ~360 px tall
                    // landscape phones.
                    ? clampDouble(H * 0.18, 50.0, 78.0)
                    : basePhoneContentTop;

                final roleCardHeight = isTabletLandscape
                    ? 88.0
                    : isTabletPortrait
                    ? 98.0
                    : isPhoneLandscape
                    ? 72.0
                    : (veryCompact ? 92.0 : 98.0);
                final cardGap = isTabletLandscape
                    ? 4.0
                    : isTabletPortrait
                    ? 6.0
                    : isPhoneLandscape
                    // Used as horizontal spacing between the 3 cards in
                    // the phone-landscape Row.
                    ? 8.0
                    : (veryCompact ? 5.0 : 6.0);
                final sectionGap = isTabletLandscape
                    ? 6.0
                    : isTabletPortrait
                    ? 8.0
                    : isPhoneLandscape
                    ? 6.0
                    : (veryCompact ? 7.0 : 8.0);
                final scrollBottomPadding = isTabletLandscape
                    ? 92.0
                    : isTabletPortrait
                    ? 148.0
                    : isPhoneLandscape
                    ? 18.0
                    : (veryCompact ? 118.0 : 136.0);
                final startPrompt = _t(
                  nl: 'Hoe wil je starten?',
                  en: 'How do you want to start?',
                  fr: 'Comment voulez-vous commencer ?',
                  es: '¿Cómo quieres empezar?',
                );
                final roleCardWidth = math.min(
                  392.0,
                  constraints.maxWidth * (narrow ? 0.85 : 0.8),
                );
                final reassuranceWidth = isPhoneLandscape
                    ? math.min(280.0, constraints.maxWidth * 0.42)
                    : math.min(
                        280.0,
                        constraints.maxWidth * (narrow ? 0.78 : 0.66),
                      );
                // Phone landscape lifts the pill out of the centered
                // content column so it sits at the screen's top-right
                // corner (inside SafeArea), exactly where the user
                // expects the language switcher in landscape.
                final useTopLevelLanguagePill =
                    isTabletPortrait || isTabletLandscape || isPhoneLandscape;
                final topLevelLanguageRight = isTabletLandscape
                    ? 54.0
                    : isPhoneLandscape
                    ? 14.0
                    : 44.0;

                return Stack(
                  children: [
                    if (useTopLevelLanguagePill)
                      Positioned(
                        right: topLevelLanguageRight,
                        top: resolvedLanguageTop,
                        child: _languageSelectorPill(),
                      ),
                    Center(
                      child: ConstrainedBox(
                        // Phone landscape widens the inner content column
                        // so the 3 compact role cards fit comfortably in
                        // a single row. Portrait/tablet keep the 470 px
                        // ceiling untouched.
                        constraints: BoxConstraints(
                          maxWidth: effectiveMaxContentWidth,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: contentHorizontalPadding,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: logoLeft,
                                top: logoTop,
                                child: SizedBox(
                                  width: logoWidth,
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Image.asset(
                                      'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
                                      fit: BoxFit.contain,
                                      alignment: Alignment.topLeft,
                                      errorBuilder: (_, __, ___) => const Text(
                                        'FLUXIDI',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (!useTopLevelLanguagePill)
                                Positioned(
                                  right: languageRight,
                                  top: resolvedLanguageTop,
                                  child: _languageSelectorPill(),
                                ),
                              Positioned.fill(
                                top: contentTop,
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.only(
                                    bottom: scrollBottomPadding,
                                  ),
                                  child: Column(
                                    children: [
                                      Center(
                                        child: Column(
                                          children: [
                                            Text(
                                              _t(
                                                nl: 'Welkom bij Fluxidi',
                                                en: 'Welcome to Fluxidi',
                                                fr: 'Bienvenue chez Fluxidi',
                                                es: 'Bienvenido a Fluxidi',
                                              ),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.97,
                                                ),
                                                fontSize: narrow ? 18 : 19,
                                                fontWeight: FontWeight.w900,
                                                height: 1.08,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black
                                                        .withOpacity(0.45),
                                                    blurRadius: 10,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              _t(
                                                nl: 'Kies je rol en vertrek.',
                                                en: 'Choose your role and go.',
                                                fr: 'Choisissez votre rôle et démarrez.',
                                                es: 'Elige tu rol y empieza.',
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.82,
                                                ),
                                                fontSize: 11.2,
                                                fontWeight: FontWeight.w600,
                                                height: 1.2,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black
                                                        .withOpacity(0.4),
                                                    blurRadius: 8,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: sectionGap),
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Text(
                                            startPrompt,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13.2,
                                              fontWeight: FontWeight.w800,
                                              foreground: Paint()
                                                ..style = PaintingStyle.stroke
                                                ..strokeWidth = 2.2
                                                ..color = const Color(
                                                  0xFFF8F8F8,
                                                ),
                                            ),
                                          ),
                                          Text(
                                            startPrompt,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Color(0xFF1F2933),
                                              fontSize: 13.2,
                                              fontWeight: FontWeight.w800,
                                              shadows: [
                                                Shadow(
                                                  color: Color(0x4D000000),
                                                  blurRadius: 2,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (isPhoneLandscape)
                                        // Phone landscape: 3 compact role
                                        // cards on a single row so all
                                        // three labels stay visible above
                                        // the gesture bar without
                                        // scrolling on common ~360 px tall
                                        // landscape phones.
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: _roleCard(
                                                title: _t(
                                                  nl: 'Klant',
                                                  en: 'Customer',
                                                  fr: 'Client',
                                                  es: 'Cliente',
                                                ),
                                                subtitle: _t(
                                                  nl: 'Boek je rit.',
                                                  en: 'Book your ride.',
                                                  fr: 'Réservez votre course.',
                                                  es: 'Reserva tu viaje.',
                                                ),
                                                icon: Icons
                                                    .person_outline_rounded,
                                                height: roleCardHeight,
                                                compact: true,
                                                highlighted:
                                                    activeBackgroundIndex == 1,
                                                onTap: () =>
                                                    _goCustomer(context),
                                              ),
                                            ),
                                            SizedBox(width: cardGap),
                                            Expanded(
                                              child: _roleCard(
                                                title: _t(
                                                  nl: 'Bedrijf',
                                                  en: 'Business',
                                                  fr: 'Entreprise',
                                                  es: 'Empresa',
                                                ),
                                                subtitle: _t(
                                                  nl: 'Beheer je vloot.',
                                                  en: 'Manage your fleet.',
                                                  fr: 'Gérez votre flotte.',
                                                  es: 'Gestiona tu flota.',
                                                ),
                                                icon: Icons
                                                    .business_center_rounded,
                                                height: roleCardHeight,
                                                compact: true,
                                                highlighted:
                                                    activeBackgroundIndex == 2,
                                                onTap: () => unawaited(
                                                  _goBusiness(context),
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: cardGap),
                                            Expanded(
                                              child: _roleCard(
                                                title: _t(
                                                  nl: 'Chauffeur',
                                                  en: 'Driver',
                                                  fr: 'Chauffeur',
                                                  es: 'Conductor',
                                                ),
                                                subtitle: _t(
                                                  nl: 'Start en rij ritten.',
                                                  en: 'Start and drive rides.',
                                                  fr: 'Démarrez et roulez.',
                                                  es: 'Inicia y conduce viajes.',
                                                ),
                                                icon: Icons.local_taxi_rounded,
                                                height: roleCardHeight,
                                                compact: true,
                                                highlighted:
                                                    activeBackgroundIndex == 3,
                                                onTap: () => _goDriver(context),
                                              ),
                                            ),
                                          ],
                                        )
                                      else ...[
                                        Center(
                                          child: SizedBox(
                                            width: roleCardWidth,
                                            child: _roleCard(
                                              title: _t(
                                                nl: 'Klant',
                                                en: 'Customer',
                                                fr: 'Client',
                                                es: 'Cliente',
                                              ),
                                              subtitle: _t(
                                                nl: 'Boek je rit.',
                                                en: 'Book your ride.',
                                                fr: 'Réservez votre course.',
                                                es: 'Reserva tu viaje.',
                                              ),
                                              icon:
                                                  Icons.person_outline_rounded,
                                              height: roleCardHeight,
                                              highlighted:
                                                  activeBackgroundIndex == 1,
                                              onTap: () => _goCustomer(context),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: cardGap),
                                        Center(
                                          child: SizedBox(
                                            width: roleCardWidth,
                                            child: _roleCard(
                                              title: _t(
                                                nl: 'Bedrijf',
                                                en: 'Business',
                                                fr: 'Entreprise',
                                                es: 'Empresa',
                                              ),
                                              subtitle: _t(
                                                nl: 'Beheer je vloot.',
                                                en: 'Manage your fleet.',
                                                fr: 'Gérez votre flotte.',
                                                es: 'Gestiona tu flota.',
                                              ),
                                              icon:
                                                  Icons.business_center_rounded,
                                              height: roleCardHeight,
                                              highlighted:
                                                  activeBackgroundIndex == 2,
                                              onTap: () => unawaited(
                                                _goBusiness(context),
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: cardGap),
                                        Center(
                                          child: SizedBox(
                                            width: roleCardWidth,
                                            child: _roleCard(
                                              title: _t(
                                                nl: 'Chauffeur',
                                                en: 'Driver',
                                                fr: 'Chauffeur',
                                                es: 'Conductor',
                                              ),
                                              subtitle: _t(
                                                nl: 'Start en rij ritten.',
                                                en: 'Start and drive rides.',
                                                fr: 'Démarrez et roulez.',
                                                es: 'Inicia y conduce viajes.',
                                              ),
                                              icon: Icons.local_taxi_rounded,
                                              height: roleCardHeight,
                                              highlighted:
                                                  activeBackgroundIndex == 3,
                                              onTap: () => _goDriver(context),
                                            ),
                                          ),
                                        ),
                                      ],
                                      SizedBox(height: sectionGap),
                                      Center(
                                        child: SizedBox(
                                          width: reassuranceWidth,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.shield_outlined,
                                                color: kFluxidiYellow
                                                    .withOpacity(0.86),
                                                size: 17,
                                              ),
                                              const SizedBox(width: 5),
                                              Flexible(
                                                child: Text(
                                                  _t(
                                                    nl: 'Keuze wordt onthouden.',
                                                    en: 'Choice remembered.',
                                                    fr: 'Choix mémorisé.',
                                                    es: 'Elección recordada.',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.78),
                                                    fontSize: 10.6,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
