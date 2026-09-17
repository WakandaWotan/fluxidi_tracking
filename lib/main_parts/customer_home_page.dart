part of '../main.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  late final LimousinePlaceLookup _homeLookup;
  late final LimousineAddressFieldController _homePickup;
  late final LimousineAddressFieldController _homeDropoff;
  bool _homeWhenNow = true;
  DateTime? _homePickupAt;
  CustomerBookingCompany? _homeCompany;

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
    _homeLookup = LimousinePlaceLookup();
    final resolver = LimousineCurrentLocationResolver(lookup: _homeLookup);
    _homePickup = LimousineAddressFieldController(
      lookup: _homeLookup,
      fieldId: 'home_pickup',
      currentLocation: resolver,
    );
    _homeDropoff = LimousineAddressFieldController(
      lookup: _homeLookup,
      fieldId: 'home_dropoff',
    );
    unawaited(loadCustomerThemePreference());
    unawaited(_prefillHomePickupFromGps());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = CustomerBookingHomeNotice.take();
      if (!mounted || notice == null || notice.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
    });
  }

  @override
  void dispose() {
    _homePickup.dispose();
    _homeDropoff.dispose();
    super.dispose();
  }

  Future<void> _prefillHomePickupFromGps() async {
    try {
      final place = await LimousineCurrentLocationResolver(
        lookup: _homeLookup,
      ).resolve(language: currentLanguageCode);
      if (!mounted || place == null || place.label.trim().isEmpty) return;
      if (_homePickup.textController.text.trim().isNotEmpty) return;
      if (!place.hasCoordinates) return;
      _homePickup.selectSuggestion(place, fromCurrentLocation: true);
    } catch (_) {}
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
      key: const ValueKey<String>('customer_home_language_pill'),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
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
            style: const TextStyle(
              inherit: false,
              color: Color(0xF5FFFFFF),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              height: 1.0,
              letterSpacing: 0.2,
            ),
          ),
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
      splashRadius: 22,
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll<Size>(Size.zero),
      ),
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
          ? ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Align(alignment: Alignment.topRight, child: pillVisual),
            )
          : pillVisual,
    );
  }

  void _openCalculator(
    BuildContext context, {
    required bool scheduledIntent,
    String? initialFromAddress,
    double? initialFromLat,
    double? initialFromLng,
    String? initialToAddress,
    double? initialToLat,
    double? initialToLng,
    String? initialServiceId,
    String? entryContext,
    String? publicPartnerId,
    String? publicPartnerName,
    DateTime? pickupAt,
    bool whenNow = true,
  }) {
    final service = (initialServiceId ?? '').trim().toLowerCase();
    final kind = switch ((entryContext ?? '').trim()) {
      'business_flow' => CustomerBookingKind.business,
      'event_flow' => CustomerBookingKind.event,
      'hotel_stay' || 'hotel_return_flow' => CustomerBookingKind.stay,
      _ => service == 'event'
          ? CustomerBookingKind.event
          : service == 'hotel'
          ? CustomerBookingKind.stay
          : CustomerBookingKind.taxi,
    };
    final scheduled = whenNow ? null : pickupAt;
    unawaited(
      openCustomerBookingFlow(
        context,
        entry: CustomerBookingEntryContext(
          kind: kind,
          company: CustomerBookingCompany(
            partnerId: (publicPartnerId ?? '').trim(),
            companyName: (publicPartnerName ?? '').trim(),
          ),
          pickup: (initialFromAddress ?? '').trim().isEmpty && scheduled == null
              ? null
              : CustomerBookingPlace(
                  address: (initialFromAddress ?? '').trim(),
                  latitude: initialFromLat,
                  longitude: initialFromLng,
                  startsAt: scheduled,
                ),
          destination: (initialToAddress ?? '').trim().isEmpty
              ? null
              : CustomerBookingPlace(
                  address: initialToAddress!.trim(),
                  latitude: initialToLat,
                  longitude: initialToLng,
                  startsAt: scheduled,
                ),
          lockCompany: (publicPartnerId ?? '').trim().isNotEmpty,
          allowModeToggle: kind == CustomerBookingKind.business,
          sourceLabel: (entryContext ?? '').trim(),
        ),
        onGoToStartPage: (_) => const CustomerHomePage(),
      ),
    );
    if ((entryContext ?? '').trim().isNotEmpty) {
      debugPrint('[CUSTOMER_HOME][CALCULATOR] entry_context=$entryContext');
    }
    if (scheduledIntent && scheduled == null) {
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
          airportCapableOnly: false,
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
    _openCalculator(
      context,
      scheduledIntent: false,
      publicPartnerId: _homeCompany?.partnerId,
      publicPartnerName: _homeCompany?.companyName,
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
            final dest = eventTaxiDestination(event);
            _openCalculator(
              context,
              scheduledIntent: event.startAtUtc != null,
              initialToAddress: dest.text,
              initialToLat: dest.lat,
              initialToLng: dest.lng,
              initialServiceId: 'event',
              publicPartnerId: _homeCompany?.partnerId,
              publicPartnerName: _homeCompany?.companyName,
              entryContext: 'event_flow',
              pickupAt: event.startAtUtc,
              whenNow: event.startAtUtc == null,
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
            _openCalculator(
              context,
              scheduledIntent: false,
              initialToAddress: destination,
              initialToLat: stay.lat,
              initialToLng: stay.lng,
              initialServiceId: 'hotel',
              publicPartnerId: _homeCompany?.partnerId,
              publicPartnerName: _homeCompany?.companyName,
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
            _openCalculator(
              context,
              scheduledIntent: false,
              initialServiceId: 'hotel',
              publicPartnerId: _homeCompany?.partnerId,
              publicPartnerName: _homeCompany?.companyName,
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

  void _openLimousineFlow(BuildContext context) {
    openLimousineCustomerDiscovery(
      context,
      customerHomeBuilder: (_) => const CustomerHomePage(),
    );
  }

  Widget? _limousineCustomerCard({
    required BuildContext context,
    required double visualHeight,
  }) {
    return KeyedSubtree(
      key: const ValueKey<String>('limousine_customer_entry_card'),
      child: _customerWideCard(
        context: context,
        icon: Icons.airport_shuttle_outlined,
        title: limousineBookLabelFor(appConfig.currentLanguage),
        subtitle: '',
        visualAsset: LimousineCustomerEntryContract.visualAsset,
        visualHeight: visualHeight,
        visualAlignment: const Alignment(0.55, 0.0),
        onTap: () => _openLimousineFlow(context),
      ),
    );
  }

  Future<void> _openAirportFlow(
    BuildContext context, {
    String? initialPickupAddress,
    String? initialPickupLabel,
    double? initialPickupLat,
    double? initialPickupLng,
  }) async {
    if (!context.mounted) return;
    await openCustomerBookingFlow(
      context,
      entry: CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        company: _homeCompany ?? const CustomerBookingCompany(),
        pickup: (initialPickupAddress ?? '').trim().isEmpty
            ? null
            : CustomerBookingPlace(
                name: (initialPickupLabel ?? '').trim(),
                address: initialPickupAddress!.trim(),
                latitude: initialPickupLat,
                longitude: initialPickupLng,
              ),
        toAirport: true,
        lockCompany: false,
        sourceLabel: 'airport_flow',
      ),
      onGoToStartPage: (_) => const CustomerHomePage(),
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
            child: FluxidiDecodeSizedAssetImage(
              heroAsset,
              fit: BoxFit.cover,
              alignment: heroImageAlignment,
              errorBuilder: (_, __, ___) => FluxidiDecodeSizedAssetImage(
                _isNightGold
                    ? 'assets/fluxidi/customer_home_hero_dark.webp'
                    : 'assets/fluxidi/customer_home_hero_light.webp',
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
          Positioned(
            top: 9,
            right: 16,
            child: _customerLanguagePill(
              enforceMinTapTarget: enforceLanguagePillTapTarget,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 14),
            child: Column(
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
              BoxShadow(color: _premiumGold.withOpacity(0.05), blurRadius: 8),
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
                  overflow: TextOverflow.ellipsis,
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
          unselectedItemColor: _isNightGold
              ? _premiumMuted.withOpacity(0.82)
              : _themePalette.textMuted,
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
                key: Key('customer_home_taxis_nav'),
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

  CustomerBookingPlace? _placeFromHomeAddress(
    LimousineAddressValue value, {
    DateTime? startsAt,
  }) {
    if (value.displayText.trim().isEmpty && startsAt == null) return null;
    return CustomerBookingPlace(
      address: value.displayText.trim(),
      latitude: value.lat,
      longitude: value.lon,
      startsAt: startsAt,
    );
  }

  void _openTaxiFromHomePanel() {
    final scheduled = _homeWhenNow ? null : _homePickupAt;
    unawaited(
      openCustomerBookingFlow(
        context,
        entry: CustomerBookingEntryContext(
          kind: CustomerBookingKind.taxi,
          company: _homeCompany ?? const CustomerBookingCompany(),
          pickup: _placeFromHomeAddress(_homePickup.value, startsAt: scheduled),
          destination: _placeFromHomeAddress(_homeDropoff.value),
          lockCompany: false,
          sourceLabel: 'customer_home.search_ride',
        ),
        onGoToStartPage: (_) => const CustomerHomePage(),
      ),
    );
  }

  Future<void> _pickHomeCompany() async {
    final picked = await pickCustomerBookingCompany(
      context,
      airportCapableOnly: false,
      customerHomeBuilder: (_) => const CustomerHomePage(),
    );
    if (picked == null || !mounted) return;
    setState(() => _homeCompany = picked);
  }

  Future<void> _pickHomeLaterWhen() async {
    final now = DateTime.now();
    final initial = _homePickupAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _homeWhenNow = false;
      _homePickupAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatHomeWhen(DateTime? value) {
    if (value == null) {
      return _t(nl: 'Later', en: 'Later', fr: 'Plus tard', es: 'Más tarde');
    }
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  Widget _desktopShell({
    required BuildContext context,
    required String heroAsset,
  }) {
    final name = _customerDisplayName();
    final greeting = name.isEmpty
        ? _t(nl: 'Welkom', en: 'Welcome', fr: 'Bienvenue', es: 'Bienvenido')
        : _t(
            nl: 'Welkom, $name',
            en: 'Welcome, $name',
            fr: 'Bienvenue, $name',
            es: 'Bienvenido, $name',
          );
    final tokens = LimousineUxTokens.fromCustomer(_themePalette);
    return Row(
      key: kCustomerHomeDesktopShellKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _desktopSidebar(),
        Expanded(
          child: ColoredBox(
            color: _premiumBg,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 980;
                  final pad = compact ? 16.0 : 22.0;
                  final headerReserve = compact ? 54.0 : 68.0;
                  final bookingReserve = compact ? 288.0 : 316.0;
                  final titleReserve = compact ? 30.0 : 38.0;
                  final gapReserve = compact ? 20.0 : 28.0;
                  final gridHeight = (constraints.maxHeight -
                          headerReserve -
                          bookingReserve -
                          titleReserve -
                          gapReserve)
                      .clamp(240.0, 460.0);
                  return CustomScrollView(
                    key: kCustomerHomeDesktopScrollKey,
                    cacheExtent: 2800,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(pad, compact ? 10 : 14, pad, 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _desktopHeader(greeting: greeting),
                              SizedBox(height: compact ? 8 : 12),
                              _desktopBookingPanel(
                                heroAsset: heroAsset,
                                tokens: tokens,
                                compact: compact,
                              ),
                              SizedBox(height: compact ? 10 : 14),
                              Text(
                                _t(
                                  nl: 'Ontdek Fluxidi',
                                  en: 'Discover Fluxidi',
                                  fr: 'Découvrir Fluxidi',
                                  es: 'Descubre Fluxidi',
                                ),
                                style: TextStyle(
                                  color: _premiumText,
                                  fontSize: compact ? 18 : 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 10),
                              _desktopDiscoverGrid(targetHeight: gridHeight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktopSidebar() {
    return ColoredBox(
      key: kCustomerHomeDesktopSidebarKey,
      color: const Color(0xFF111111),
      child: SizedBox(
        width: 220,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 22),
                child: Image.asset(
                  'assets/fluxidi/fluxidi_logo_horizontal_gold.png',
                  height: 28,
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
              CustomerHomeSidebarItem(
                key: kCustomerHomeNavHomeKey,
                icon: Icons.home_outlined,
                label: _t(nl: 'Home', en: 'Home', fr: 'Accueil', es: 'Inicio'),
                selected: true,
                palette: _themePalette,
                onTap: () {},
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomeNavTaxiKey,
                icon: Icons.local_taxi_outlined,
                label: _t(
                  nl: 'Taxi boeken',
                  en: 'Book a taxi',
                  fr: 'Réserver un taxi',
                  es: 'Reservar un taxi',
                ),
                palette: _themePalette,
                onTap: _openTaxiFromHomePanel,
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomeNavBookingsKey,
                icon: Icons.receipt_long_outlined,
                label: _t(
                  nl: 'Mijn boekingen',
                  en: 'My bookings',
                  fr: 'Mes réservations',
                  es: 'Mis reservas',
                ),
                palette: _themePalette,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerSavedBookingsPage(),
                  ),
                ),
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomeNavProfileKey,
                icon: Icons.person_outline_rounded,
                label: _t(
                  nl: 'Mijn profiel',
                  en: 'My profile',
                  fr: 'Mon profil',
                  es: 'Mi perfil',
                ),
                palette: _themePalette,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerProfileEditPage(),
                  ),
                ),
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomeNearbyKey,
                icon: Icons.local_taxi_outlined,
                label: _t(
                  nl: 'Taxi in de buurt',
                  en: 'Taxi nearby',
                  fr: 'Taxi à proximité',
                  es: 'Taxi cerca',
                ),
                palette: _themePalette,
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
              CustomerHomeSidebarItem(
                key: kCustomerHomeRadarKey,
                icon: Icons.app_registration_outlined,
                label: _t(
                  nl: 'Regio Radar',
                  en: 'Region Radar',
                  fr: 'Radar régional',
                  es: 'Radar regional',
                ),
                palette: _themePalette,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerRegionRegistrationPage(),
                  ),
                ),
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomePrivacyKey,
                icon: Icons.privacy_tip_outlined,
                label: _t(
                  nl: 'Mijn gegevens & account',
                  en: 'My data & delete account',
                  fr: 'Mes données & compte',
                  es: 'Mis datos y cuenta',
                ),
                palette: _themePalette,
                onTap: () => openFluxidiPrivacyAccountPage(
                  context,
                  audience: FluxidiPrivacyAudience.customer,
                ),
              ),
                  ],
                ),
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomeNavThemeKey,
                icon: Icons.palette_outlined,
                label: _t(nl: 'Thema', en: 'Theme', fr: 'Thème', es: 'Tema'),
                palette: _themePalette,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CustomerThemePage()),
                ),
              ),
              CustomerHomeSidebarItem(
                key: kCustomerHomeNavStartKey,
                icon: Icons.keyboard_return_rounded,
                label: _t(
                  nl: 'Terug naar start',
                  en: 'Back to start',
                  fr: 'Retour à l’accueil',
                  es: 'Volver al inicio',
                ),
                palette: _themePalette,
                onTap: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const RoleEntryPage()),
                  (route) => false,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopHeader({required String greeting}) {
    final name = _customerDisplayName();
    final initial = name.isEmpty ? '' : name.substring(0, 1).toUpperCase();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                key: kCustomerHomeGreetingKey,
                style: TextStyle(
                  color: _premiumText,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  nl: 'Waar brengt je dag je naartoe?',
                  en: 'Where is your day taking you?',
                  fr: 'Où votre journée vous emmène-t-elle ?',
                  es: '¿Adónde te lleva el día?',
                ),
                key: kCustomerHomeTaglineKey,
                style: TextStyle(
                  color: _premiumMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _customerLanguagePill(enforceMinTapTarget: true),
        const SizedBox(width: 10),
        Material(
          color: _premiumSurface,
          shape: const CircleBorder(),
          child: InkWell(
            key: kCustomerHomeProfileAvatarKey,
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerProfileEditPage()),
            ),
            child: Ink(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _premiumBorder),
                color: _premiumSurface,
              ),
              child: Center(
                child: initial.isEmpty
                    ? Icon(Icons.person_outline, color: _premiumText, size: 20)
                    : Text(
                        initial,
                        style: TextStyle(
                          color: _premiumText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktopBookingPanel({
    required String heroAsset,
    required LimousineUxTokens tokens,
    bool compact = false,
  }) {
    return DecoratedBox(
      key: kCustomerHomeDesktopBookingPanelKey,
      decoration: BoxDecoration(
        color: _premiumSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _premiumBorder.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 18,
                  compact ? 10 : 12,
                  compact ? 12 : 14,
                  compact ? 10 : 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t(
                        nl: 'Waar wil je naartoe?',
                        en: 'Where do you want to go?',
                        fr: 'Où voulez-vous aller ?',
                        es: '¿Adónde quieres ir?',
                      ),
                      style: TextStyle(
                        color: _premiumText,
                        fontSize: compact ? 17 : 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    LimousineAddressField(
                      controller: _homePickup,
                      label: _t(
                        nl: 'Huidige locatie',
                        en: 'Current location',
                        fr: 'Position actuelle',
                        es: 'Ubicación actual',
                      ),
                      tokens: tokens,
                      language: appConfig.currentLanguage,
                      showCurrentLocation: true,
                      showCanonicalEcho: false,
                      inputKey: kCustomerHomePickupKey,
                      decoration: _desktopAddressDecoration(
                        tokens: tokens,
                        label: _t(
                          nl: 'Huidige locatie',
                          en: 'Current location',
                          fr: 'Position actuelle',
                          es: 'Ubicación actual',
                        ),
                        icon: Icons.place_outlined,
                      ),
                    ),
                    LimousineAddressField(
                      controller: _homeDropoff,
                      label: _t(
                        nl: 'Bestemming invoeren',
                        en: 'Enter destination',
                        fr: 'Saisir la destination',
                        es: 'Introducir destino',
                      ),
                      tokens: tokens,
                      language: appConfig.currentLanguage,
                      showCanonicalEcho: false,
                      inputKey: kCustomerHomeDropoffKey,
                      decoration: _desktopAddressDecoration(
                        tokens: tokens,
                        label: _t(
                          nl: 'Bestemming invoeren',
                          en: 'Enter destination',
                          fr: 'Saisir la destination',
                          es: 'Introducir destino',
                        ),
                        icon: Icons.crop_square_rounded,
                      ),
                    ),
                    _desktopWhenField(tokens: tokens),
                    const SizedBox(height: 8),
                    _desktopCompanyField(tokens: tokens),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: FilledButton(
                        key: kCustomerHomeSearchRideKey,
                        onPressed: _openTaxiFromHomePanel,
                        style: FilledButton.styleFrom(
                          backgroundColor: customerHomeDesktopAccent(
                            _themePalette,
                          ),
                          foregroundColor: customerOnGold(_themePalette),
                          disabledBackgroundColor: _premiumGold.withValues(
                            alpha: 0.35,
                          ),
                          disabledForegroundColor: customerOnGold(
                            _themePalette,
                          ).withValues(alpha: 0.55),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _t(
                                nl: 'Zoek mijn rit',
                                en: 'Find my ride',
                                fr: 'Trouver ma course',
                                es: 'Buscar mi viaje',
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: ColoredBox(
                    color: _themePalette.surfaceAlt,
                    child: Image.asset(
                      heroAsset,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.35, 0.0),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _desktopDiscoverGrid({required double targetHeight}) {
    final items = <({
      Key key,
      String title,
      String asset,
      IconData icon,
      Alignment alignment,
      VoidCallback onTap,
    })>[
      (
        key: const ValueKey<String>('customer_home_discover_taxi'),
        title: _t(nl: 'Taxi', en: 'Taxi', fr: 'Taxi', es: 'Taxi'),
        asset: 'assets/fluxidi/customer_home_hero_light.webp',
        icon: Icons.local_taxi_outlined,
        alignment: const Alignment(0.4, 0.0),
        onTap: _openTaxiFromHomePanel,
      ),
      (
        key: const ValueKey<String>('customer_home_discover_airport'),
        title: _t(
          nl: 'Luchthaven',
          en: 'Airport',
          fr: 'Aéroport',
          es: 'Aeropuerto',
        ),
        asset: 'assets/fluxidi/customer_home_airport_banner.webp',
        icon: Icons.flight_takeoff_rounded,
        alignment: const Alignment(-0.2, -0.1),
        onTap: () => _openAirportFlow(context),
      ),
      (
        key: const ValueKey<String>('customer_home_discover_hotels'),
        title: _t(
          nl: 'Hotels & B&B',
          en: 'Hotels & B&B',
          fr: 'Hôtels & B&B',
          es: 'Hoteles & B&B',
        ),
        asset: 'assets/fluxidi/customer_home_hotel_bb_banner.webp',
        icon: Icons.hotel_rounded,
        alignment: const Alignment(0.5, 0.05),
        onTap: () => _openHotelsPage(context),
      ),
      (
        key: const ValueKey<String>('customer_home_discover_events'),
        title: _t(
          nl: 'Evenementen',
          en: 'Events',
          fr: 'Événements',
          es: 'Eventos',
        ),
        asset: 'assets/fluxidi/customer_home_events_banner.webp',
        icon: Icons.celebration_outlined,
        alignment: Alignment.center,
        onTap: () => _openEventsPage(context),
      ),
      (
        key: const ValueKey<String>('customer_home_discover_business'),
        title: _t(
          nl: 'Zakelijk',
          en: 'Business',
          fr: 'Professionnel',
          es: 'Empresas',
        ),
        asset: _themePalette.isDark
            ? 'assets/fluxidi/zakelijke_picture_landscape_tablet.webp'
            : 'assets/fluxidi/zakelijke_tablet_header_foto_landscape_daytime.webp',
        icon: Icons.business_center_outlined,
        alignment: const Alignment(0.2, 0.0),
        onTap: () => unawaited(_openBusinessTaxiFlow(context)),
      ),
      (
        key: const ValueKey<String>('limousine_customer_entry_card'),
        title: _t(
          nl: 'Limousine',
          en: 'Limousine',
          fr: 'Limousine',
          es: 'Limusina',
        ),
        asset: LimousineCustomerEntryContract.visualAsset,
        icon: Icons.airport_shuttle_outlined,
        alignment: const Alignment(0.45, 0.0),
        onTap: () => _openLimousineFlow(context),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        final rowsCount = (items.length / columns).ceil();
        final itemHeight =
            ((targetHeight - spacing * (rowsCount - 1)) / rowsCount)
                .clamp(132.0, 230.0);
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += columns) {
          final slice = items.skip(i).take(columns).toList();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: j < slice.length
                        ? SizedBox(
                            height: itemHeight,
                            child: CustomerHomeDiscoverCard(
                              key: slice[j].key,
                              title: slice[j].title,
                              asset: slice[j].asset,
                              icon: slice[j].icon,
                              alignment: slice[j].alignment,
                              palette: _themePalette,
                              onTap: slice[j].onTap,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
          if (i + columns < items.length) {
            rows.add(const SizedBox(height: spacing));
          }
        }
        return Column(
          key: kCustomerHomeDesktopDiscoverKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  InputDecoration _desktopAddressDecoration({
    required LimousineUxTokens tokens,
    required String label,
    required IconData icon,
  }) {
    final fill = _themePalette.isDark
        ? tokens.fieldFill
        : const Color(0xFFF3F1EB);
    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: Icon(icon, color: _premiumMuted),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: TextStyle(color: tokens.muted),
      labelStyle: TextStyle(color: tokens.muted, fontWeight: FontWeight.w600),
      floatingLabelStyle: TextStyle(
        color: tokens.gold,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: fill,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.border.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.gold, width: 1.6),
      ),
    );
  }

  Widget _desktopWhenField({required LimousineUxTokens tokens}) {
    final fill = _themePalette.isDark
        ? tokens.fieldFill
        : const Color(0xFFF3F1EB);
    final label = _homeWhenNow
        ? _t(
            nl: 'Nu vertrekken',
            en: 'Leave now',
            fr: 'Partir maintenant',
            es: 'Salir ahora',
          )
        : _formatHomeWhen(_homePickupAt);
    return MenuAnchor(
      builder: (context, controller, _) {
        return Material(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: tokens.border.withValues(alpha: 0.55),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_outlined, color: _premiumMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: _premiumText,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Icon(Icons.expand_more_rounded, color: _premiumMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          onPressed: () => setState(() => _homeWhenNow = true),
          child: Text(
            _t(
              nl: 'Nu vertrekken',
              en: 'Leave now',
              fr: 'Partir maintenant',
              es: 'Salir ahora',
            ),
            key: kCustomerHomeWhenNowKey,
          ),
        ),
        MenuItemButton(
          onPressed: () => unawaited(_pickHomeLaterWhen()),
          child: Text(
            _t(nl: 'Later', en: 'Later', fr: 'Plus tard', es: 'Más tarde'),
            key: kCustomerHomeWhenLaterKey,
          ),
        ),
      ],
    );
  }

  Widget _desktopCompanyField({required LimousineUxTokens tokens}) {
    final fill = _themePalette.isDark
        ? tokens.fieldFill
        : const Color(0xFFF3F1EB);
    final chosen = _homeCompany != null &&
        customerBookingCompanyIsChosen(_homeCompany!);
    final name = chosen
        ? customerBookingCompanyVisibleName(_homeCompany!)
        : '';
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: kCustomerHomeCompanyKey,
        borderRadius: BorderRadius.circular(14),
        onTap: () => unawaited(_pickHomeCompany()),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border.withValues(alpha: 0.55)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.apartment_outlined, color: _premiumMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chosen
                          ? '${_t(nl: 'Je boekt bij', en: 'You are booking with', fr: 'Vous réservez chez', es: 'Reservas con')}: $name'
                          : _t(
                              nl: 'Kies een taxibedrijf',
                              en: 'Choose a taxi company',
                              fr: 'Choisissez une compagnie de taxi',
                              es: 'Elige una empresa de taxi',
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _premiumText,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  Text(
                    chosen
                        ? _t(
                            nl: 'Wijzigen',
                            en: 'Change',
                            fr: 'Modifier',
                            es: 'Cambiar',
                          )
                        : _t(
                            nl: 'Kiezen',
                            en: 'Choose',
                            fr: 'Choisir',
                            es: 'Elegir',
                          ),
                    style: TextStyle(
                      color: customerHomeDesktopAccent(_themePalette),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                ? 'assets/fluxidi/customer_home_hero_dark.webp'
                : 'assets/fluxidi/customer_home_hero_light.webp';
            final eventsAsset = isTabletLandscape
                ? 'assets/fluxidi/evenementen_picture_landscape_tablet.webp'
                : 'assets/fluxidi/customer_home_events_banner.webp';
            final businessAsset = isTabletLandscape
                ? 'assets/fluxidi/zakelijke_picture_landscape_tablet.webp'
                : _themePalette.isDark
                ? 'assets/fluxidi/customer_home_business_banner_dark.webp'
                : 'assets/fluxidi/customer_home_business_banner.webp';
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
            final useDesktop = customerHomeUsesDesktopLayout(W);
            return Scaffold(
              backgroundColor: _premiumBg,
              bottomNavigationBar:
                  useDesktop ? null : _customerBottomNav(context),
              body: useDesktop
                  ? _desktopShell(context: context, heroAsset: heroAsset)
                  : SafeArea(
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
                                    'assets/fluxidi/customer_home_airport_banner.webp',
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
                                    'assets/fluxidi/customer_home_hotel_bb_banner.webp',
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
                              if (_limousineCustomerCard(
                                    context: context,
                                    visualHeight: customerWideCardHeight,
                                  )
                                  case final limousineCard?)
                                limousineCard,
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
                                'assets/fluxidi/customer_home_airport_banner.webp',
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
                                'assets/fluxidi/customer_home_hotel_bb_banner.webp',
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
                        if (_limousineCustomerCard(
                              context: context,
                              visualHeight: customerWideCardHeight,
                            )
                            case final limousineCard?) ...[
                          const SizedBox(height: 8),
                          limousineCard,
                        ],
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
