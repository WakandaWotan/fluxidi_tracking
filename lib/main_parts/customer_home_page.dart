part of '../main.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isNightGold =>
      customerThemeNotifier.value == CustomerThemeVariant.nightGold;
  Color get _premiumBg => _themePalette.background;
  Color get _premiumSurface => _themePalette.surface;
  Color get _premiumText => _themePalette.textPrimary;
  Color get _premiumMuted => _themePalette.textMuted;
  Color get _premiumGold => _themePalette.gold;
  Color get _premiumBronze => _themePalette.bronze;
  Color get _premiumBorder => _themePalette.border;

  @override
  void initState() {
    super.initState();
    unawaited(loadCustomerThemePreference());
  }

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

  void _openCalculator(
    BuildContext context, {
    required bool scheduledIntent,
    String? initialToAddress,
    double? initialToLat,
    double? initialToLng,
    String? initialServiceId,
    String? entryContext,
    String? publicPartnerId,
    String? publicPartnerName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: true,
          initialToAddress: initialToAddress,
          initialToLat: initialToLat,
          initialToLng: initialToLng,
          initialServiceId: initialServiceId,
          publicPartnerId: (publicPartnerId ?? '').trim().isEmpty
              ? null
              : publicPartnerId!.trim(),
          publicPartnerName: (publicPartnerName ?? '').trim().isEmpty
              ? null
              : publicPartnerName!.trim(),
          onGoToStartPage: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const CustomerHomePage()),
              (route) => false,
            );
          },
        ),
      ),
    );
    if ((entryContext ?? '').trim().isNotEmpty) {
      debugPrint('[CUSTOMER_HOME][CALCULATOR] entry_context=$entryContext');
    }
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

  Future<Map<String, String>?> _selectTaxiPartner(BuildContext context) async {
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
    if (selected == null || !context.mounted) return null;
    final partnerId = _partnerSelectionValue(selected, 'partner_id');
    if (partnerId.isEmpty) {
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
      return null;
    }
    return selected;
  }

  Future<void> _openBusinessTaxiFlow(BuildContext context) async {
    final selected = await _selectTaxiPartner(context);
    if (selected == null || !context.mounted) return;

    final partnerId = _partnerSelectionValue(selected, 'partner_id');
    final partnerName = _partnerSelectionValue(selected, 'company_name');

    _openCalculator(
      context,
      scheduledIntent: false,
      publicPartnerId: partnerId,
      publicPartnerName: partnerName,
      entryContext: 'business_flow',
    );
  }

  void _openEventsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventsPage(
          dataSource: buildDefaultEventLocatorDataSource(
            baseUrl: kBookingBaseUrl,
          ),
          onBookEvent: (event) async {
            final destination = event.address.trim().isNotEmpty
                ? event.address.trim()
                : (event.locationName.trim().isNotEmpty
                      ? event.locationName.trim()
                      : event.title.trim());
            final selected = await _selectTaxiPartner(context);
            if (selected == null || !context.mounted) return;
            final partnerId = _partnerSelectionValue(selected, 'partner_id');
            final partnerName = _partnerSelectionValue(
              selected,
              'company_name',
            );
            _openCalculator(
              context,
              scheduledIntent: false,
              initialToAddress: destination,
              initialToLat: event.lat,
              initialToLng: event.lng,
              initialServiceId: 'event',
              publicPartnerId: partnerId,
              publicPartnerName: partnerName,
              entryContext: 'event_flow',
            );
          },
        ),
      ),
    );
  }

  void _openHotelsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HotelsPage(
          onTaxiToStay: (stay) async {
            final destination = stay.address.trim().isNotEmpty
                ? stay.address.trim()
                : stay.name.trim();
            final selected = await _selectTaxiPartner(context);
            if (selected == null || !context.mounted) return;
            final partnerId = _partnerSelectionValue(selected, 'partner_id');
            final partnerName = _partnerSelectionValue(
              selected,
              'company_name',
            );
            _openCalculator(
              context,
              scheduledIntent: false,
              initialToAddress: destination,
              initialToLat: stay.lat,
              initialToLng: stay.lng,
              initialServiceId: 'hotel',
              publicPartnerId: partnerId,
              publicPartnerName: partnerName,
              entryContext: 'hotel_stay',
            );
          },
          onOpenAirportFlow: (destination) => _openAirportFlow(
            context,
            initialPickupAddress: destination.prefillDestinationText,
            initialPickupLabel: destination.destinationName,
            initialPickupLat: destination.latitude,
            initialPickupLng: destination.longitude,
          ),
          onManualHotelTaxi: () async {
            final selected = await _selectTaxiPartner(context);
            if (selected == null || !context.mounted) return;
            final partnerId = _partnerSelectionValue(selected, 'partner_id');
            final partnerName = _partnerSelectionValue(
              selected,
              'company_name',
            );
            _openCalculator(
              context,
              scheduledIntent: false,
              initialServiceId: 'hotel',
              publicPartnerId: partnerId,
              publicPartnerName: partnerName,
              entryContext: 'hotel_return_flow',
            );
          },
          onOpenAirportReturnFlow: () => _openAirportFlow(context),
        ),
      ),
    );
  }

  String _partnerSelectionValue(Map<String, String>? map, String key) {
    if (map == null) return '';
    return (map[key] ?? '').trim();
  }

  Future<void> _openAirportFlow(
    BuildContext context, {
    String? initialPickupAddress,
    String? initialPickupLabel,
    double? initialPickupLat,
    double? initialPickupLng,
  }) async {
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
          initialPickupAddress: initialPickupAddress,
          initialPickupLabel: initialPickupLabel,
          initialPickupLatitude: initialPickupLat,
          initialPickupLongitude: initialPickupLng,
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
        color: _premiumSurface,
        border: Border.all(color: _premiumBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
                _isNightGold
                    ? 'assets/fluxidi/customer_home_hero_dark.png'
                    : 'assets/fluxidi/customer_home_hero_light.png',
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
                  const Color(
                    0xFF253443,
                  ).withOpacity(_isNightGold ? 0.42 : 0.28),
                  const Color(
                    0xFF253443,
                  ).withOpacity(_isNightGold ? 0.24 : 0.14),
                  const Color(
                    0xFF253443,
                  ).withOpacity(_isNightGold ? 0.09 : 0.03),
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
                  Colors.white.withOpacity(_isNightGold ? 0.05 : 0.16),
                  Colors.white.withOpacity(_isNightGold ? 0.02 : 0.06),
                  Colors.black.withOpacity(_isNightGold ? 0.34 : 0.2),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.62,
                  heightFactor: 0.36,
                  alignment: Alignment.bottomLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(
                            0xFF111827,
                          ).withOpacity(_isNightGold ? 0.42 : 0.32),
                          const Color(
                            0xFF111827,
                          ).withOpacity(_isNightGold ? 0.26 : 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
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
                      _themePalette.isDark
                          ? 'assets/fluxidi/fluxidi_logo_horizontal_gold.png'
                          : 'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
                      width: 166,
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
                  style: TextStyle(
                    color: _premiumBronze,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    shadows: _isNightGold
                        ? const [
                            Shadow(
                              color: Color(0xFFFFFFFF),
                              blurRadius: 2,
                              offset: Offset(0, 0),
                            ),
                            Shadow(
                              color: Color(0xE6FFFFFF),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                            Shadow(
                              color: Color(0x80000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : const [
                            Shadow(
                              color: Color(0xB3FFFFFF),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                            Shadow(
                              color: Color(0x4D000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                  ),
                ),
                if (customerName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    customerName,
                    style: TextStyle(
                      color: _isNightGold
                          ? _premiumBronze.withOpacity(0.95)
                          : Colors.white,
                      fontSize: 14.2,
                      fontWeight: FontWeight.w600,
                      shadows: _isNightGold
                          ? const [
                              Shadow(
                                color: Color(0xFFFFFFFF),
                                blurRadius: 2,
                                offset: Offset(0, 0),
                              ),
                              Shadow(
                                color: Color(0xD9FFFFFF),
                                blurRadius: 5,
                                offset: Offset(0, 1),
                              ),
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : const [
                              Shadow(
                                color: Color(0x99000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
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
    const quickActionIconContainerSize = 50.0;
    const quickActionIconGlyphSize = 24.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _premiumSurface,
              _isNightGold ? _themePalette.surfaceAlt : const Color(0xFFFFF9EE),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _premiumBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
            BoxShadow(color: _premiumGold.withOpacity(0.05), blurRadius: 8),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: quickActionIconContainerSize,
              height: quickActionIconContainerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isNightGold
                    ? _themePalette.surfaceAlt.withOpacity(0.92)
                    : const Color(0xFFFFF7E8),
                border: Border.all(color: _premiumGold.withOpacity(0.36)),
              ),
              child: Icon(
                icon,
                color: _premiumGold,
                size: quickActionIconGlyphSize,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: _premiumText,
                  fontSize: 11.2,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.fade,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: _premiumGold.withOpacity(0.9),
            ),
          ],
        ),
      ),
    );
  }

  /// PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
  /// Full-width Fluxidi-styled action card that opens the shared customer
  /// privacy / account-deletion flow. Reuses the same design tokens as
  /// [_customerQuickActionCard] (gradient, border, radius, shadow, gold
  /// icon chip, chevron) but stretches to fill the available content width
  /// via [SizedBox.width == double.infinity], so the Dutch label never
  /// truncates on a phone.
  ///
  /// The handler always opens the shared privacy flow with the customer
  /// audience — no owner/admin authority, no driver id, no company copy.
  Widget _customerPrivacyDeleteWideCard(BuildContext context) {
    const wideActionIconContainerSize = 52.0;
    const wideActionIconGlyphSize = 26.0;
    final label = _t(
      nl: 'Mijn gegevens & account verwijderen',
      en: 'My data & delete account',
      fr: 'Mes données & supprimer le compte',
      es: 'Mis datos y eliminar la cuenta',
    );
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        key: const Key('customer_privacy_delete_wide_card'),
        behavior: HitTestBehavior.opaque,
        onTap: () => openFluxidiPrivacyAccountPage(
          context,
          audience: FluxidiPrivacyAudience.customer,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _premiumSurface,
                _isNightGold
                    ? _themePalette.surfaceAlt
                    : const Color(0xFFFFF9EE),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _premiumBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: _premiumGold.withOpacity(0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: wideActionIconContainerSize,
                height: wideActionIconContainerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isNightGold
                      ? _themePalette.surfaceAlt.withOpacity(0.92)
                      : const Color(0xFFFFF7E8),
                  border: Border.all(color: _premiumGold.withOpacity(0.36)),
                ),
                child: Icon(
                  Icons.privacy_tip_outlined,
                  color: _premiumGold,
                  size: wideActionIconGlyphSize,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: _premiumText,
                    fontSize: 13.6,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.fade,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: _premiumGold.withOpacity(0.9),
              ),
            ],
          ),
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
      // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
      // The customer privacy / delete-account entry is intentionally rendered
      // as a separate full-width card below this quick-action grid (see
      // `_customerPrivacyDeleteWideCard`), not as a half-width tile inside
      // the grid, because on a phone the two-column grid truncated the
      // Dutch label. The grid keeps exactly the four canonical customer
      // quick actions in phone portrait: bookings, details, taxi, radar.
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
          onTap: () => _openHotelsPage(context),
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
    final bannerImageScale = _isNightGold ? 1.02 : 1.0;
    final cardBorderColor = _isNightGold
        ? _premiumGold.withOpacity(hasVisual ? 0.32 : 0.26)
        : (hasVisual
              ? _premiumBorder.withOpacity(0.5)
              : _premiumBorder.withOpacity(0.84));
    final cardGradientColors = _isNightGold && hasVisual
        ? <Color>[_themePalette.surface, _themePalette.surface]
        : <Color>[
            _premiumSurface,
            _isNightGold ? _themePalette.surfaceAlt : const Color(0xFFFFF8EC),
          ];
    final cardShadowColor = _isNightGold
        ? Colors.black.withOpacity(0.3)
        : Colors.black.withOpacity(0.08);
    final iconChipSize = hasVisual ? 58.0 : 52.0;
    final iconSize = hasVisual ? 31.0 : 28.0;
    final titleFontSize = hasVisual ? 16.8 : 15.2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: hasVisual ? (visualHeight ?? 130.0) : null,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _isNightGold && hasVisual ? _themePalette.surface : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cardBorderColor,
            width: hasVisual ? 0.7 : 0.9,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cardGradientColors,
          ),
          boxShadow: [
            BoxShadow(
              color: cardShadowColor,
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVisual) ...[
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Transform.scale(
                    scale: bannerImageScale,
                    alignment: visualAlignment ?? Alignment.centerRight,
                    child: Image.asset(
                      visualAsset,
                      fit: BoxFit.cover,
                      alignment: visualAlignment ?? Alignment.centerRight,
                    ),
                  ),
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
                          0xFF111827,
                        ).withOpacity(0.82 * overlayOpacityFactor),
                        const Color(
                          0xFF111827,
                        ).withOpacity(0.62 * overlayOpacityFactor),
                        const Color(
                          0xFF111827,
                        ).withOpacity(0.26 * overlayOpacityFactor),
                        const Color(
                          0xFF111827,
                        ).withOpacity(0.03 * overlayOpacityFactor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: hasVisual ? 12 : 14,
                vertical: hasVisual ? 11 : 14,
              ),
              child: Row(
                children: [
                  Container(
                    width: iconChipSize,
                    height: iconChipSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isNightGold
                          ? _themePalette.surfaceAlt.withOpacity(0.9)
                          : Colors.white.withOpacity(0.84),
                      border: Border.all(color: _premiumGold.withOpacity(0.5)),
                    ),
                    child: Icon(icon, color: _premiumGold, size: iconSize),
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
                              color: _isNightGold
                                  ? _themePalette.surfaceAlt.withOpacity(0.92)
                                  : Colors.white.withOpacity(0.8),
                              border: Border.all(
                                color: _premiumGold.withOpacity(0.45),
                              ),
                            ),
                            child: Text(
                              ctaLabel,
                              style: TextStyle(
                                color: _premiumGold,
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
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _isNightGold
                          ? _themePalette.surfaceAlt.withOpacity(0.92)
                          : Colors.white.withOpacity(0.86),
                      shape: BoxShape.circle,
                      border: Border.all(color: _premiumGold.withOpacity(0.45)),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: _premiumGold,
                    ),
                  ),
                ],
              ),
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
      _t(nl: 'Start', en: 'Start', fr: 'Accueil', es: 'Inicio'),
      _t(nl: 'Thema', en: 'Theme', fr: 'Thème', es: 'Tema'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _isNightGold
            ? _themePalette.surfaceAlt.withOpacity(0.98)
            : _premiumSurface.withOpacity(0.97),
        border: Border(
          top: BorderSide(
            color: _isNightGold
                ? _premiumGold.withOpacity(0.22)
                : _premiumBorder,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isNightGold ? 0.22 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
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
            if (i == 3) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RoleEntryPage()),
                (route) => false,
              );
              return;
            }
            if (i == 4) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomerThemePage()),
              );
              return;
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          selectedItemColor: _premiumGold,
          unselectedItemColor: _premiumMuted.withOpacity(0.82),
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
                Icons.keyboard_return_rounded,
                size: navIconSize,
              ),
              label: items[3],
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.palette_outlined, size: navIconSize),
              label: items[4],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, __) {
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
            final heroAsset = themeVariant == CustomerThemeVariant.nightGold
                ? 'assets/fluxidi/customer_home_hero_dark.png'
                : 'assets/fluxidi/customer_home_hero_light.png';
            final eventsAsset = isTabletLandscape
                ? 'assets/fluxidi/evenementen_picture_landscape_tablet.png'
                : 'assets/fluxidi/customer_home_events_banner.png';
            final businessAsset = isTabletLandscape
                ? 'assets/fluxidi/zakelijke_picture_landscape_tablet.png'
                : _themePalette.isDark
                ? 'assets/fluxidi/customer_home_business_banner_dark.png'
                : 'assets/fluxidi/customer_home_business_banner.png';
            final customerHeroHeight = isTabletPortrait
                ? clampDouble(H * 0.255, 330.0, 385.0)
                : 288.0;
            final customerHeroImageAlignment = isTabletPortrait
                ? const Alignment(0.42, 0.00)
                : const Alignment(0.55, 0.10);
            final customerHeroImageScale = isTabletPortrait ? 1.02 : 1.12;
            final customerQuickGridMainAxisExtent = isTabletPortrait
                ? clampDouble(H * 0.07, 86.0, 102.0)
                : 86.0;
            final customerPortraitUtilityMainAxisExtent = isTabletPortrait
                ? clampDouble(H * 0.067, 82.0, 96.0)
                : customerQuickGridMainAxisExtent;
            final customerLandscapeUtilityMainAxisExtent = isTabletLandscape
                ? clampDouble(H * 0.066, 68.0, 78.0)
                : customerPortraitUtilityMainAxisExtent;
            final customerWideCardHeight = isTabletLandscape
                ? clampDouble(H * 0.215, 180.0, 210.0)
                : isTabletPortrait
                ? clampDouble(H * 0.14, 185.0, 210.0)
                : 118.0;
            return Scaffold(
              backgroundColor: _premiumBg,
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
                      const SizedBox(height: 10),
                      if (isTabletLandscape) ...[
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 10.0;
                            final cardWidth =
                                (constraints.maxWidth - spacing) / 2;
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
                                    'assets/fluxidi/customer_home_airport_banner.png',
                                visualHeight: customerWideCardHeight,
                                visualAlignment: const Alignment(-0.35, -0.15),
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
                                    'assets/fluxidi/customer_home_hotel_bb_banner.png',
                                visualHeight: customerWideCardHeight,
                                visualAlignment: const Alignment(0.62, 0.08),
                                onTap: () => _openHotelsPage(context),
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
                                onTap: () => _openEventsPage(context),
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
                                onTap: () =>
                                    unawaited(_openBusinessTaxiFlow(context)),
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
                                'assets/fluxidi/customer_home_airport_banner.png',
                            visualHeight: customerWideCardHeight,
                            visualAlignment: isTabletPortrait
                                ? const Alignment(-0.35, -0.15)
                                : const Alignment(0.56, 0.18),
                            onTap: () => _openAirportFlow(context),
                          ),
                          const SizedBox(height: 8),
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
                                'assets/fluxidi/customer_home_hotel_bb_banner.png',
                            visualHeight: customerWideCardHeight,
                            visualAlignment: const Alignment(0.62, 0.08),
                            onTap: () => _openHotelsPage(context),
                          ),
                          const SizedBox(height: 8),
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
                          onTap: () => _openEventsPage(context),
                        ),
                        const SizedBox(height: 8),
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
                          visualAlignment: const Alignment(-0.20, 0.0),
                          onTap: () =>
                              unawaited(_openBusinessTaxiFlow(context)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _t(
                            nl: 'Mijn Fluxidi',
                            en: 'My Fluxidi',
                            fr: 'Mon Fluxidi',
                            es: 'Mi Fluxidi',
                          ),
                          style: TextStyle(
                            color: _premiumText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _customerQuickActionGrid(
                        context,
                        mainAxisExtent: customerLandscapeUtilityMainAxisExtent,
                        includeAirportAndHotels:
                            !usesSplitUtilityAndFeatureCards,
                        forceTwoColumns: isPhonePortrait,
                        forceFourColumns: isTabletPortrait || isTabletLandscape,
                      ),
                      // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
                      // Full-width customer privacy / delete-account card.
                      // Rendered as its own row under the quick-action grid so
                      // the Dutch label never truncates on a phone, and it
                      // reuses the same Fluxidi design tokens as the tiles
                      // above (gradient, border, radius, shadow, gold icon
                      // chip, chevron).
                      const SizedBox(height: 9),
                      _customerPrivacyDeleteWideCard(context),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
