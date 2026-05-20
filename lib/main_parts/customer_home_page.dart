part of '../main.dart';

class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  String _comingSoonMessage() => _t(
    nl: 'Deze functie komt binnenkort.',
    en: 'This feature is coming soon.',
    fr: 'Cette fonction arrive bientôt.',
    es: 'Esta función estará disponible pronto.',
  );

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_comingSoonMessage())));
  }

  String _customerDisplayName() {
    final name = _cachedCustomerProfile?.name.trim() ?? '';
    return name;
  }

  Widget _customerLanguagePill({bool enforceMinTapTarget = false}) {
    final code = currentLanguageCode.toUpperCase();
    final pillVisual = Container(
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
    );
    return PopupMenuButton<String>(
      onSelected: setAppLanguageByCode,
      color: const Color(0xFF111827),
      elevation: 8,
      padding: EdgeInsets.zero,
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
      child: enforceMinTapTarget
          ? SizedBox(
              width: 44,
              height: 44,
              child: Align(alignment: Alignment.topRight, child: pillVisual),
            )
          : pillVisual,
    );
  }

  void _openCalculator(BuildContext context, {required bool scheduledIntent}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: true,
          onGoToStartPage: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const CustomerHomePage()),
              (route) => false,
            );
          },
        ),
      ),
    );
    if (scheduledIntent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Plan rit opent nu de boekingsflow (scheduled intent volgt).',
              en: 'Scheduled ride currently opens the booking flow (scheduled intent pending).',
              fr: 'La course planifiee ouvre actuellement le flux de reservation (option planifiee a venir).',
              es: 'El viaje programado abre actualmente el flujo de reserva (intencion programada pendiente).',
            ),
          ),
        ),
      );
    }
  }

  String _partnerSelectionValue(Map<String, String>? map, String key) {
    if (map == null) return '';
    return (map[key] ?? '').trim();
  }

  Future<void> _openAirportFlow(BuildContext context) async {
    final selected = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => NearbyPartnersPage(
          customerHomeBuilder: (_) => const CustomerHomePage(),
          regionRegistrationBuilder: (_) =>
              const CustomerRegionRegistrationPage(),
          syncCustomerProfileFromBackend:
              _syncCustomerProfileFromBackendBestEffort,
          selectionMode: true,
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final tenantId = _partnerSelectionValue(selected, 'tenant_id');
    final companyId = _partnerSelectionValue(selected, 'company_id');
    final companyName = _partnerSelectionValue(selected, 'company_name');
    final companyCode = _partnerSelectionValue(selected, 'company_code');
    final partnerId = _partnerSelectionValue(selected, 'partner_id');
    if (tenantId.isEmpty || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kies eerst een taxipartner.',
              en: 'Select a taxi partner first.',
              fr: "Sélectionnez d'abord un partenaire taxi.",
              es: 'Selecciona primero un socio de taxi.',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AirportPage(
          bookingBaseUrl: kBookingBaseUrl,
          selectedTenantId: tenantId,
          selectedCompanyId: companyId,
          selectedCompanyName: companyName,
          selectedCompanyCode: companyCode,
          selectedPartnerId: partnerId,
          allowPartnerChange: true,
          onChangePartnerRequested: (selectorContext) async {
            return await Navigator.of(
              selectorContext,
            ).push<Map<String, String>>(
              MaterialPageRoute(
                builder: (_) => NearbyPartnersPage(
                  customerHomeBuilder: (_) => const CustomerHomePage(),
                  regionRegistrationBuilder: (_) =>
                      const CustomerRegionRegistrationPage(),
                  syncCustomerProfileFromBackend:
                      _syncCustomerProfileFromBackendBestEffort,
                  selectionMode: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _customerHomeHero(
    BuildContext context, {
    required String heroAsset,
    required double heroHeight,
    required Alignment heroImageAlignment,
    required double heroImageScale,
    bool enforceLanguagePillTapTarget = false,
  }) {
    final customerName = _customerDisplayName();
    return Container(
      height: heroHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: heroImageScale,
            alignment: heroImageAlignment,
            child: Image.asset(
              heroAsset,
              fit: BoxFit.cover,
              alignment: heroImageAlignment,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/fluxidi/fluxidi_hero_taxi.png',
                fit: BoxFit.cover,
                alignment: heroImageAlignment,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withOpacity(0.58),
                  Colors.black.withOpacity(0.34),
                  Colors.black.withOpacity(0.12),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.06),
                  Colors.black.withOpacity(0.11),
                  Colors.black.withOpacity(0.52),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      kFluxidiLogoAsset,
                      width: 178,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.topRight,
                      child: _customerLanguagePill(
                        enforceMinTapTarget: enforceLanguagePillTapTarget,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _t(
                    nl: 'Welkom!',
                    en: 'Welcome!',
                    fr: 'Bienvenue !',
                    es: '¡Bienvenido!',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (customerName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    customerName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.84),
                      fontSize: 14.2,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerQuickActionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    const quickActionIconContainerSize = 56.0;
    const quickActionIconGlyphSize = 31.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101010), Color(0xFF07080C)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.34),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: kFluxidiYellow.withOpacity(0.035),
              blurRadius: 7,
              spreadRadius: 0.2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: quickActionIconContainerSize,
              height: quickActionIconContainerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF15120A).withOpacity(0.72),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.24)),
              ),
              child: Icon(
                icon,
                color: kFluxidiYellow.withOpacity(0.98),
                size: quickActionIconGlyphSize,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.6,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerQuickActionGrid(
    BuildContext context, {
    required double mainAxisExtent,
    bool includeAirportAndHotels = true,
    bool forceTwoColumns = false,
    bool forceFourColumns = false,
  }) {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.receipt_long_outlined,
        label: _t(
          nl: 'Mijn boekingen',
          en: 'My bookings',
          fr: 'Mes réservations',
          es: 'Mis reservas',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerSavedBookingsPage()),
        ),
      ),
      (
        icon: Icons.person_outline_rounded,
        label: _t(
          nl: 'Mijn gegevens',
          en: 'My details',
          fr: 'Mes données',
          es: 'Mis datos',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerProfileEditPage()),
        ),
      ),
      (
        icon: Icons.local_taxi_outlined,
        label: _t(
          nl: 'Taxi in de buurt',
          en: 'Taxi nearby',
          fr: 'Taxi à proximité',
          es: 'Taxi cerca',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NearbyPartnersPage(
              customerHomeBuilder: (_) => const CustomerHomePage(),
              regionRegistrationBuilder: (_) =>
                  const CustomerRegionRegistrationPage(),
              syncCustomerProfileFromBackend:
                  _syncCustomerProfileFromBackendBestEffort,
            ),
          ),
        ),
      ),
      (
        icon: Icons.app_registration_outlined,
        label: _t(
          nl: 'Regio Radar',
          en: 'Region Radar',
          fr: 'Radar régional',
          es: 'Radar regional',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerRegionRegistrationPage(),
          ),
        ),
      ),
    ];
    if (includeAirportAndHotels) {
      actions.addAll([
        (
          icon: Icons.flight_takeoff_rounded,
          label: _t(
            nl: 'Luchthavenritten',
            en: 'Airport rides',
            fr: 'Trajets aéroport',
            es: 'Traslados aeropuerto',
          ),
          onTap: () => _openAirportFlow(context),
        ),
        (
          icon: Icons.hotel_rounded,
          label: _t(
            nl: 'Hotels & B&B',
            en: 'Hotels & B&B',
            fr: 'Hôtels & B&B',
            es: 'Hoteles & B&B',
          ),
          onTap: () => _comingSoon(context),
        ),
      ]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = forceFourColumns
            ? 4
            : (forceTwoColumns ? 2 : (constraints.maxWidth >= 430 ? 3 : 2));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            mainAxisExtent: mainAxisExtent,
          ),
          itemBuilder: (_, i) => _customerQuickActionCard(
            context: context,
            icon: actions[i].icon,
            label: actions[i].label,
            onTap: actions[i].onTap,
          ),
        );
      },
    );
  }

  Widget _customerWideCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    String? ctaLabel,
    String? visualAsset,
    double? visualHeight,
    Alignment? visualAlignment,
    double visualOverlayOpacityMultiplier = 1.0,
    required VoidCallback onTap,
  }) {
    final hasVisual = visualAsset != null && visualAsset.trim().isNotEmpty;
    final double overlayOpacityFactor = hasVisual
        ? visualOverlayOpacityMultiplier.clamp(0.0, 1.0).toDouble()
        : 1.0;
    final iconChipSize = hasVisual ? 58.0 : 52.0;
    final iconSize = hasVisual ? 31.0 : 28.0;
    final titleFontSize = hasVisual ? 16.8 : 15.2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: hasVisual ? (visualHeight ?? 130.0) : null,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.26)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101010), Color(0xFF07080C)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVisual) ...[
              Positioned.fill(
                child: Image.asset(
                  visualAsset,
                  fit: BoxFit.cover,
                  alignment: visualAlignment ?? Alignment.centerRight,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0.0, 0.46, 0.78, 1.0],
                      colors: [
                        const Color(
                          0xFF07080C,
                        ).withOpacity(0.96 * overlayOpacityFactor),
                        const Color(
                          0xFF07080C,
                        ).withOpacity(0.82 * overlayOpacityFactor),
                        const Color(
                          0xFF07080C,
                        ).withOpacity(0.38 * overlayOpacityFactor),
                        const Color(
                          0xFF07080C,
                        ).withOpacity(0.08 * overlayOpacityFactor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Row(
              children: [
                Container(
                  width: iconChipSize,
                  height: iconChipSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kFluxidiYellow.withOpacity(0.18),
                    border: Border.all(color: kFluxidiYellow.withOpacity(0.45)),
                  ),
                  child: Icon(icon, color: kFluxidiYellow, size: iconSize),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: titleFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 12.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (ctaLabel != null) ...[
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: kFluxidiYellow.withOpacity(0.18),
                            border: Border.all(
                              color: kFluxidiYellow.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            ctaLabel,
                            style: const TextStyle(
                              color: Color(0xFFE5B641),
                              fontSize: 11.7,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: kFluxidiYellow.withOpacity(0.94),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerBottomNav(BuildContext context) {
    const navIconSize = 25.0;
    final items = <String>[
      _t(nl: 'Home', en: 'Home', fr: 'Accueil', es: 'Inicio'),
      _t(nl: 'Taxi’s', en: 'Taxis', fr: 'Taxis', es: 'Taxis'),
      _t(nl: 'Boekingen', en: 'Bookings', fr: 'Réservations', es: 'Reservas'),
      _t(
        nl: 'Meldingen',
        en: 'Notifications',
        fr: 'Notifications',
        es: 'Notificaciones',
      ),
      _t(nl: 'Profiel', en: 'Profile', fr: 'Profil', es: 'Perfil'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        border: Border(
          top: BorderSide(color: kFluxidiYellow.withOpacity(0.2), width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: 0,
          onTap: (i) {
            if (i == 0) return;
            if (i == 1) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NearbyPartnersPage(
                    customerHomeBuilder: (_) => const CustomerHomePage(),
                    regionRegistrationBuilder: (_) =>
                        const CustomerRegionRegistrationPage(),
                    syncCustomerProfileFromBackend:
                        _syncCustomerProfileFromBackendBestEffort,
                  ),
                ),
              );
              return;
            }
            if (i == 2) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerSavedBookingsPage(),
                ),
              );
              return;
            }
            if (i == 4) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerProfileEditPage(),
                ),
              );
              return;
            }
            _comingSoon(context);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          selectedItemColor: kFluxidiYellow,
          unselectedItemColor: Colors.white60,
          showUnselectedLabels: true,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined, size: navIconSize),
              label: items[0],
            ),
            BottomNavigationBarItem(
              icon: const Icon(
                Icons.directions_car_outlined,
                size: navIconSize,
              ),
              label: items[1],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.receipt_long_outlined, size: navIconSize),
              label: items[2],
            ),
            BottomNavigationBarItem(
              icon: const Icon(
                Icons.notifications_none_rounded,
                size: navIconSize,
              ),
              label: items[3],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline_rounded, size: navIconSize),
              label: items[4],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        double clampDouble(double v, double min, double max) =>
            v < min ? min : (v > max ? max : v);
        final media = MediaQuery.of(context);
        final W = media.size.width;
        final H = media.size.height;
        final screenClass = FluxidiBreakpoints.classifyWidth(W);
        final isTabletPortrait =
            (screenClass == FluxidiScreenClass.tablet ||
                screenClass == FluxidiScreenClass.desktop) &&
            W < H &&
            H >= 900;
        final isTabletLandscape =
            (screenClass == FluxidiScreenClass.tablet ||
                screenClass == FluxidiScreenClass.desktop) &&
            W > H &&
            H >= 700;
        final isPhonePortrait =
            W < H && !isTabletPortrait && !isTabletLandscape;
        final usesSplitUtilityAndFeatureCards =
            isPhonePortrait || isTabletPortrait || isTabletLandscape;
        final heroAsset = isTabletLandscape
            ? 'assets/fluxidi/fluxidi_customer_header_picture_landscape_tablet.png'
            : 'assets/fluxidi/fluxidi_customer_home_hero.png';
        final eventsAsset = isTabletLandscape
            ? 'assets/fluxidi/evenementen_picture_landscape_tablet.png'
            : 'assets/fluxidi/fluxidi_event_crowd_night.jpg';
        final businessAsset = isTabletLandscape
            ? 'assets/fluxidi/zakelijke_picture_landscape_tablet.png'
            : 'assets/fluxidi/fluxidi_business_briefcase_night.jpg';
        final customerHeroHeight = isTabletPortrait
            ? clampDouble(H * 0.28, 360.0, 410.0)
            : 312.0;
        final customerHeroImageAlignment = isTabletPortrait
            ? const Alignment(0.42, 0.00)
            : const Alignment(0.55, 0.10);
        final customerHeroImageScale = isTabletPortrait ? 1.02 : 1.12;
        final customerQuickGridMainAxisExtent = isTabletPortrait
            ? clampDouble(H * 0.10, 126.0, 144.0)
            : 112.0;
        final customerPortraitUtilityMainAxisExtent = isTabletPortrait
            ? clampDouble(H * 0.085, 98.0, 118.0)
            : customerQuickGridMainAxisExtent;
        final customerLandscapeUtilityMainAxisExtent = isTabletLandscape
            ? clampDouble(H * 0.09, 86.0, 102.0)
            : customerPortraitUtilityMainAxisExtent;
        final customerWideCardHeight = isTabletLandscape
            ? clampDouble(H * 0.24, 200.0, 230.0)
            : isTabletPortrait
            ? clampDouble(H * 0.155, 205.0, 225.0)
            : 130.0;
        return Scaffold(
          backgroundColor: const Color(0xFF050505),
          bottomNavigationBar: _customerBottomNav(context),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  _customerHomeHero(
                    context,
                    heroAsset: heroAsset,
                    heroHeight: customerHeroHeight,
                    heroImageAlignment: customerHeroImageAlignment,
                    heroImageScale: customerHeroImageScale,
                    enforceLanguagePillTapTarget: isTabletLandscape,
                  ),
                  const SizedBox(height: 14),
                  _customerQuickActionGrid(
                    context,
                    mainAxisExtent: customerLandscapeUtilityMainAxisExtent,
                    includeAirportAndHotels: !usesSplitUtilityAndFeatureCards,
                    forceTwoColumns: isPhonePortrait,
                    forceFourColumns: isTabletPortrait || isTabletLandscape,
                  ),
                  const SizedBox(height: 12),
                  if (isTabletLandscape) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 10.0;
                        final cardWidth = (constraints.maxWidth - spacing) / 2;
                        final cards = <Widget>[
                          _customerWideCard(
                            context: context,
                            icon: Icons.flight_takeoff_rounded,
                            title: _t(
                              nl: 'Luchthavenritten',
                              en: 'Airport rides',
                              fr: 'Trajets aéroport',
                              es: 'Traslados aeropuerto',
                            ),
                            subtitle: '',
                            visualAsset:
                                'assets/fluxidi/airport_portret_background_GSM.png',
                            visualHeight: customerWideCardHeight,
                            visualAlignment: const Alignment(-0.35, -0.15),
                            visualOverlayOpacityMultiplier: 0.82,
                            onTap: () => _openAirportFlow(context),
                          ),
                          _customerWideCard(
                            context: context,
                            icon: Icons.hotel_rounded,
                            title: _t(
                              nl: 'Hotels & B&B',
                              en: 'Hotels & B&B',
                              fr: 'Hôtels & B&B',
                              es: 'Hoteles & B&B',
                            ),
                            subtitle: '',
                            visualAsset:
                                'assets/fluxidi/Hotel&B&B_background.png',
                            visualHeight: customerWideCardHeight,
                            visualAlignment: const Alignment(0.62, 0.08),
                            onTap: () => _comingSoon(context),
                          ),
                          _customerWideCard(
                            context: context,
                            icon: Icons.celebration_outlined,
                            title: _t(
                              nl: 'Evenementen',
                              en: 'Events',
                              fr: 'Événements',
                              es: 'Eventos',
                            ),
                            subtitle: '',
                            visualAsset: eventsAsset,
                            visualHeight: customerWideCardHeight,
                            visualAlignment: Alignment.centerRight,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const EventsPage(),
                              ),
                            ),
                          ),
                          _customerWideCard(
                            context: context,
                            icon: Icons.business_center_outlined,
                            title: _t(
                              nl: 'Zakelijk',
                              en: 'Business',
                              fr: 'Pro',
                              es: 'Empresas',
                            ),
                            subtitle: '',
                            visualAsset: businessAsset,
                            visualHeight: customerWideCardHeight,
                            visualAlignment: const Alignment(0.65, 0.0),
                            onTap: () => _comingSoon(context),
                          ),
                        ];
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final card in cards)
                              SizedBox(width: cardWidth, child: card),
                          ],
                        );
                      },
                    ),
                  ] else ...[
                    if (usesSplitUtilityAndFeatureCards) ...[
                      _customerWideCard(
                        context: context,
                        icon: Icons.flight_takeoff_rounded,
                        title: _t(
                          nl: 'Luchthavenritten',
                          en: 'Airport rides',
                          fr: 'Trajets aéroport',
                          es: 'Traslados aeropuerto',
                        ),
                        subtitle: '',
                        visualAsset:
                            'assets/fluxidi/airport_portret_background_GSM.png',
                        visualHeight: customerWideCardHeight,
                        visualAlignment: isTabletPortrait
                            ? const Alignment(-0.35, -0.15)
                            : const Alignment(0.56, 0.18),
                        visualOverlayOpacityMultiplier: isTabletPortrait
                            ? 0.82
                            : 1.0,
                        onTap: () => _openAirportFlow(context),
                      ),
                      const SizedBox(height: 10),
                      _customerWideCard(
                        context: context,
                        icon: Icons.hotel_rounded,
                        title: _t(
                          nl: 'Hotels & B&B',
                          en: 'Hotels & B&B',
                          fr: 'Hôtels & B&B',
                          es: 'Hoteles & B&B',
                        ),
                        subtitle: '',
                        visualAsset: 'assets/fluxidi/Hotel&B&B_background.png',
                        visualHeight: customerWideCardHeight,
                        visualAlignment: const Alignment(0.62, 0.08),
                        visualOverlayOpacityMultiplier: isTabletPortrait
                            ? 0.9
                            : 1.0,
                        onTap: () => _comingSoon(context),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _customerWideCard(
                      context: context,
                      icon: Icons.celebration_outlined,
                      title: _t(
                        nl: 'Evenementen',
                        en: 'Events',
                        fr: 'Événements',
                        es: 'Eventos',
                      ),
                      subtitle: '',
                      visualAsset: eventsAsset,
                      visualHeight: customerWideCardHeight,
                      visualAlignment: Alignment.centerRight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EventsPage()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _customerWideCard(
                      context: context,
                      icon: Icons.business_center_outlined,
                      title: _t(
                        nl: 'Zakelijk',
                        en: 'Business',
                        fr: 'Pro',
                        es: 'Empresas',
                      ),
                      subtitle: '',
                      visualAsset: businessAsset,
                      visualHeight: customerWideCardHeight,
                      visualAlignment: const Alignment(0.65, 0.0),
                      onTap: () => _comingSoon(context),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const FluxidiBackToStartButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
