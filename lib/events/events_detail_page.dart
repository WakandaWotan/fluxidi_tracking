import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/calculator_page.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/discovery/discovery_geo.dart';
import 'package:fluxidi_tracking/discovery/discovery_labels.dart';
import 'package:fluxidi_tracking/discovery/discovery_nearby.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotel_seed_data.dart';
import 'package:fluxidi_tracking/nearby_partners_page.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'event_models.dart';

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({required this.event, this.onBookEvent, super.key});

  final EventDetailData event;
  final EventBookCallback? onBookEvent;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
        return nl;
    }
  }

  String get _mobiliteitsvraag {
    switch (event.category.toLowerCase()) {
      case 'zakelijk':
        return _t(
          nl: 'Hoog in de piekuren, met nadruk op gedeelde ritten.',
          en: 'High during peak hours, with focus on shared rides.',
          fr: 'Elevee aux heures de pointe, avec accent sur les trajets partages.',
          es: 'Alta en horas punta, con enfoque en viajes compartidos.',
        );
      case 'sport':
        return _t(
          nl: 'Middelmatig tot hoog rondom start- en eindmomenten.',
          en: 'Medium to high around start and end times.',
          fr: 'Moyenne a elevee autour des debuts et fins d evenement.',
          es: 'Media a alta alrededor del inicio y cierre del evento.',
        );
      case 'muziek':
        return _t(
          nl: 'Hoog in de avond, met geconcentreerde uitstroom na afloop.',
          en: 'High in the evening, with concentrated outflow afterwards.',
          fr: 'Elevee en soiree, avec une sortie concentree apres la fin.',
          es: 'Alta por la noche, con salida concentrada al finalizar.',
        );
      default:
        return _t(
          nl: 'Middelmatig, met gespreide vraag over de dag.',
          en: 'Medium, with demand spread across the day.',
          fr: 'Moyenne, avec une demande etalee sur la journee.',
          es: 'Media, con demanda repartida durante el dia.',
        );
    }
  }

  String get _eventStartGuidance {
    return _t(
      nl: '${event.dateTimeLabel}. Plan je ophaaltijd op basis van je vertreklocatie en reistijd.',
      en: '${event.dateTimeLabel}. Plan pickup time based on your departure location and travel time.',
      fr: '${event.dateTimeLabel}. Planifiez l heure de prise en charge selon votre lieu de depart et le temps de trajet.',
      es: '${event.dateTimeLabel}. Planifica la hora de recogida segun tu ubicacion de salida y el tiempo de viaje.',
    );
  }

  String? get _eventDescription {
    final text = (event.description ?? '').trim();
    if (text.isEmpty) return null;
    return text;
  }

  String get _emptyDescriptionLabel {
    return _t(
      nl: 'Meer informatie vind je via de ticketaanbieder.',
      en: 'More information can be found via the ticket provider.',
      fr: 'Plus d informations sont disponibles via le fournisseur de billets.',
      es: 'Encontraras mas informacion a traves del proveedor de entradas.',
    );
  }

  String get _heroImageUrl {
    return (event.heroImageUrl ?? event.thumbnailUrl ?? event.imageUrl ?? '')
        .trim();
  }

  String? get _heroSecondaryChipLabel {
    final statusLabel = event.customerTicketStatusLabel;
    if ((statusLabel ?? '').isNotEmpty) return statusLabel;
    final distance = event.isDistanceLabelTrusted
        ? (event.distanceLabel ?? '').trim()
        : '';
    return distance.isNotEmpty ? distance : null;
  }

  bool _hasValidCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    return true;
  }

  double _degToRad(double value) => value * (math.pi / 180.0);

  double _distanceKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(toLat - fromLat);
    final dLng = _degToRad(toLng - fromLng);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(fromLat)) *
            math.cos(_degToRad(toLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  List<HotelStay> _nearbyStays() {
    final eventCity = normalizeDiscoveryText(event.city);
    final eventLat = event.lat;
    final eventLng = event.lng;
    final canDistanceRank = _hasValidCoordinates(eventLat, eventLng);

    final sameCity = <HotelStay>[
      for (final stay in kBelgiumHotelSeedData)
        if (normalizeDiscoveryText(stay.city) == eventCity) stay,
    ];

    if (!canDistanceRank) {
      return topUniqueById(items: sameCity, idOf: (stay) => stay.id, limit: 3);
    }

    final distanceRanked = <({HotelStay stay, double km})>[
      for (final stay in kBelgiumHotelSeedData)
        if (_hasValidCoordinates(
          stay.latitude ?? stay.lat,
          stay.longitude ?? stay.lng,
        ))
          (
            stay: stay,
            km: _distanceKm(
              fromLat: eventLat,
              fromLng: eventLng,
              toLat: stay.latitude ?? stay.lat,
              toLng: stay.longitude ?? stay.lng,
            ),
          ),
    ]..sort((a, b) => a.km.compareTo(b.km));

    List<HotelStay> withinBand(double minKmExclusive, double maxKmInclusive) {
      return <HotelStay>[
        for (final item in distanceRanked)
          if (item.km > minKmExclusive && item.km <= maxKmInclusive) item.stay,
      ];
    }

    final merged = <HotelStay>[
      ...sameCity,
      ...withinBand(-1, 15),
      ...withinBand(15, 30),
      ...withinBand(30, 50),
    ];
    return topUniqueById(items: merged, idOf: (stay) => stay.id, limit: 3);
  }

  String _stayTypeLabel(String typeKey) {
    if (typeKey == HotelStayType.aparthotel) {
      return _t(
        nl: 'Aparthotel',
        en: 'Aparthotel',
        fr: 'Aparthotel',
        es: 'Aparthotel',
      );
    }
    if (typeKey == HotelStayType.guesthouse) {
      return _t(
        nl: 'Guesthouse',
        en: 'Guesthouse',
        fr: 'Guesthouse',
        es: 'Guesthouse',
      );
    }
    if (typeKey == HotelStayType.hotel) return 'Hotel';
    if (typeKey == HotelStayType.bedAndBreakfast) {
      return discoveryStayTypeLabel(
        HotelStayType.bedAndBreakfast,
        (nl, en, fr, es) => _t(nl: nl, en: en, fr: fr, es: es),
      );
    }
    return typeKey;
  }

  String _stayPriceLabel(HotelStay stay) {
    return formatDiscoveryPriceHint(
      stay.priceHint,
      fromLabel: _t(nl: 'Vanaf', en: 'From', fr: 'À partir de', es: 'Desde'),
    );
  }

  String _formatRoutePrefillAddress({
    required String rawAddress,
    required String label,
    required String city,
    required String region,
    required String country,
  }) {
    final raw = rawAddress.trim();
    final safeLabel = label.trim();
    final safeCity = city.trim();
    final safeRegion = region.trim();
    final safeCountry = country.trim();
    final normalizedRaw = normalizeDiscoveryText(raw);
    final normalizedCity = normalizeDiscoveryText(safeCity);
    final normalizedCountry = normalizeDiscoveryText(safeCountry);

    bool containsNormalized(String value) {
      final normalized = normalizeDiscoveryText(value);
      return normalized.isNotEmpty && normalizedRaw.contains(normalized);
    }

    if (raw.isEmpty) {
      if (safeLabel.isNotEmpty) return safeLabel;
      final locality = <String>[
        if (safeCity.isNotEmpty) safeCity,
        if (safeRegion.isNotEmpty &&
            normalizeDiscoveryText(safeRegion) !=
                normalizeDiscoveryText(safeCity))
          safeRegion,
        if (safeCountry.isNotEmpty) safeCountry,
      ];
      return locality.join(', ');
    }

    if ((normalizedCity.isNotEmpty && containsNormalized(safeCity)) ||
        (normalizedCountry.isNotEmpty && containsNormalized(safeCountry))) {
      return raw;
    }

    final segments = <String>[raw];
    void addIfUseful(String segment) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) return;
      final normalized = normalizeDiscoveryText(trimmed);
      if (normalized.isEmpty) return;
      if (segments.any(
        (item) => normalizeDiscoveryText(item).contains(normalized),
      )) {
        return;
      }
      segments.add(trimmed);
    }

    addIfUseful(safeCity);
    addIfUseful(safeRegion);
    addIfUseful(safeCountry);
    return segments.join(', ');
  }

  Future<void> _openStayUrl(BuildContext context, HotelStay stay) async {
    final url = (stay.effectiveBookingUrl ?? '').trim();
    final uri = Uri.tryParse(url);
    final valid =
        uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'https' || uri.scheme == 'http');
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Geen verblijflink beschikbaar.',
              en: 'No stay link available.',
              fr: 'Aucun lien d’hébergement disponible.',
              es: 'No hay enlace de alojamiento disponible.',
            ),
          ),
        ),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Kon verblijflink niet openen.',
            en: 'Could not open stay link.',
            fr: 'Impossible d’ouvrir le lien du séjour.',
            es: 'No se pudo abrir el enlace del alojamiento.',
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>?> _selectTaxiPartnerForEventFlow(
    BuildContext context,
  ) async {
    final selected = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => NearbyPartnersPage(
          customerHomeBuilder: (_) => const SizedBox.shrink(),
          regionRegistrationBuilder: (_) => const SizedBox.shrink(),
          syncCustomerProfileFromBackend: ({required String reason}) async {
            return CustomerProfileStore.instance.load();
          },
          selectionMode: true,
        ),
      ),
    );
    if (selected == null || !context.mounted) return null;
    final partnerId = (selected['partner_id'] ?? '').trim();
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

  Future<void> _onStayTaxiTap(BuildContext context, HotelStay stay) async {
    final destination = stay.toDiscoveryDestination();
    final eventAddress = event.address.trim();
    final eventLocation = event.locationName.trim();
    final eventTitle = event.title.trim();
    final originAddress = eventAddress.isNotEmpty
        ? eventAddress
        : (eventLocation.isNotEmpty ? eventLocation : eventTitle);
    final originLabel = event.destinationLabel.trim().isNotEmpty
        ? event.destinationLabel.trim()
        : (eventTitle.isNotEmpty ? eventTitle : originAddress);
    final formattedOriginAddress = _formatRoutePrefillAddress(
      rawAddress: originAddress,
      label: originLabel,
      city: event.city,
      region: '',
      country: (event.countryCode ?? '').trim(),
    );
    final formattedDestinationAddress = _formatRoutePrefillAddress(
      rawAddress: destination.prefillDestinationText,
      label: destination.destinationName,
      city: destination.city,
      region: destination.region,
      country: destination.country,
    );
    debugPrint(
      '[events.nearby_stay_handoff] stayId=${stay.id} '
      'name="${destination.destinationName}" city="${destination.city}"',
    );
    final selectedPartner = await _selectTaxiPartnerForEventFlow(context);
    if (selectedPartner == null || !context.mounted) return;
    final publicPartnerId = (selectedPartner['partner_id'] ?? '').trim();
    final publicPartnerName = (selectedPartner['company_name'] ?? '').trim();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CalculatorPage(
              bookingBaseUrl: appConfig.bookingBaseUrl,
              mapboxToken: kMapboxToken,
              initialFromAddress: formattedOriginAddress,
              initialFromLabel: originLabel,
              initialFromLat: event.lat,
              initialFromLng: event.lng,
              initialToAddress: formattedDestinationAddress,
              initialDestinationLabel: destination.destinationName,
              initialToLat: destination.latitude,
              initialToLng: destination.longitude,
              initialServiceId: 'passenger',
              publicPartnerId: publicPartnerId.isEmpty ? null : publicPartnerId,
              publicPartnerName: publicPartnerName.isEmpty
                  ? null
                  : publicPartnerName,
            ),
          ),
        )
        .catchError((_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  nl: 'Kon taxi-navigatie niet openen.',
                  en: 'Could not open taxi navigation.',
                  fr: 'Impossible d’ouvrir la navigation taxi.',
                  es: 'No se pudo abrir la navegación de taxi.',
                ),
              ),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, __) {
        final palette = paletteForCustomerTheme(themeVariant);
        final bottomInset = MediaQuery.of(context).padding.bottom;
        final nearbyStays = _nearbyStays();
        return Scaffold(
          backgroundColor: palette.background,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(context, palette),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      10,
                      14,
                      18 + bottomInset * 0.35,
                    ),
                    children: [
                      _buildHeroVisual(palette),
                      const SizedBox(height: 14),
                      _buildPrimaryContent(palette),
                      const SizedBox(height: 13),
                      _buildInfoPanel(palette),
                      if (nearbyStays.isNotEmpty) ...[
                        const SizedBox(height: 13),
                        _buildNearbyStaysSection(context, nearbyStays, palette),
                      ],
                      const SizedBox(height: 15),
                      _buildCtaArea(context, palette),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, CustomerThemePalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: palette.gold,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: palette.surface.withOpacity(
                  palette.isDark ? 0.92 : 0.98,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.border.withOpacity(0.7)),
              ),
              child: Text(
                _t(
                  nl: 'Evenementdetail',
                  en: 'Event details',
                  fr: 'Details de l evenement',
                  es: 'Detalle del evento',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroVisual(CustomerThemePalette palette) {
    final heroImageUrl = _heroImageUrl;
    final secondaryChipLabel = _heroSecondaryChipLabel;
    return Container(
      height: 236,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border.withOpacity(0.85)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: event.gradient,
        ),
      ),
      child: Stack(
        children: [
          if (heroImageUrl.isNotEmpty)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  heroImageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 1280,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (heroImageUrl.isNotEmpty)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      palette.shadow.withOpacity(0.25),
                      palette.shadow.withOpacity(0.58),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: -14,
            top: -14,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.gold.withOpacity(0.30),
                    palette.gold.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -8,
            bottom: -10,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [palette.gold.withOpacity(0.20), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 14,
            child: _buildChip(
              palette: palette,
              label: event.category,
              icon: _categoryIcon(event.category),
            ),
          ),
          if ((secondaryChipLabel ?? '').isNotEmpty)
            Positioned(
              left: 16,
              top: 48,
              child: _buildChip(
                palette: palette,
                label: secondaryChipLabel!,
                icon: Icons.local_taxi_rounded,
              ),
            ),
          Positioned(
            right: 18,
            top: 18,
            child: Icon(
              Icons.workspace_premium_rounded,
              color: palette.gold.withOpacity(0.90),
              size: 28,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.isDark ? Colors.white : palette.textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryContent(CustomerThemePalette palette) {
    final description = _eventDescription;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border.withOpacity(0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaRow(
            Icons.calendar_today_outlined,
            event.dateTimeLabel,
            palette,
          ),
          const SizedBox(height: 8),
          _buildMetaRow(
            Icons.location_on_outlined,
            event.locationName,
            palette,
          ),
          const SizedBox(height: 8),
          _buildMetaRow(Icons.pin_drop_outlined, event.address, palette),
          const SizedBox(height: 11),
          Divider(color: palette.border.withOpacity(0.75), height: 1),
          const SizedBox(height: 11),
          Text(
            _t(
              nl: 'Evenementinformatie',
              en: 'Event information',
              fr: 'Informations sur l evenement',
              es: 'Informacion del evento',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description ?? _emptyDescriptionLabel,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(CustomerThemePalette palette) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border.withOpacity(0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            _t(
              nl: 'Evenementlocatie',
              en: 'Event venue',
              fr: 'Lieu de l evenement',
              es: 'Lugar del evento',
            ),
            '${event.locationName}, ${event.city}',
            palette,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            _t(nl: 'Adres', en: 'Address', fr: 'Adresse', es: 'Direccion'),
            event.address,
            palette,
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              nl: 'Mobiliteitsadvies',
              en: 'Mobility advice',
              fr: 'Conseil de mobilite',
              es: 'Consejo de movilidad',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            _t(
              nl: 'Verwachte mobiliteitsvraag',
              en: 'Expected mobility demand',
              fr: 'Demande de mobilite attendue',
              es: 'Demanda de movilidad esperada',
            ),
            _mobiliteitsvraag,
            palette,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            _t(
              nl: 'Start evenement',
              en: 'Event start',
              fr: 'Debut de l evenement',
              es: 'Inicio del evento',
            ),
            _eventStartGuidance,
            palette,
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyStaysSection(
    BuildContext context,
    List<HotelStay> nearbyStays,
    CustomerThemePalette palette,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border.withOpacity(0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Verblijven in de buurt',
              en: 'Nearby stays',
              fr: 'Hebergements a proximite',
              es: 'Alojamientos cerca',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < nearbyStays.length; i++) ...[
            _buildNearbyStayCard(context, nearbyStays[i], palette),
            if (i != nearbyStays.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildNearbyStayCard(
    BuildContext context,
    HotelStay stay,
    CustomerThemePalette palette,
  ) {
    final price = _stayPriceLabel(stay);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withOpacity(0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stay.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _stayTypeLabel(stay.type),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.gold.withOpacity(0.94),
              fontSize: 11.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${stay.city}, ${stay.region}, ${stay.country}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (stay.rating != null) ...[
            const SizedBox(height: 3),
            Text(
              '★ ${stay.rating!.toStringAsFixed(1)}',
              style: TextStyle(
                color: palette.gold.withOpacity(0.92),
                fontSize: 11.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (price.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              price,
              style: TextStyle(
                color: palette.textMuted.withOpacity(0.9),
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openStayUrl(context, stay),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: palette.surface.withOpacity(
                      palette.isDark ? 0.98 : 0.95,
                    ),
                    foregroundColor: palette.textPrimary.withOpacity(0.95),
                    side: BorderSide(color: palette.border.withOpacity(0.8)),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: palette.gold.withOpacity(0.92),
                  ),
                  label: Text(
                    _t(
                      nl: 'Bekijk verblijf',
                      en: 'View stay',
                      fr: 'Voir le sejour',
                      es: 'Ver alojamiento',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _onStayTaxiTap(context, stay),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: palette.surface.withOpacity(
                      palette.isDark ? 0.98 : 0.95,
                    ),
                    foregroundColor: palette.textPrimary.withOpacity(0.95),
                    side: BorderSide(color: palette.border.withOpacity(0.8)),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(
                    Icons.local_taxi_rounded,
                    size: 16,
                    color: palette.gold.withOpacity(0.92),
                  ),
                  label: Text(
                    _t(
                      nl: 'Taxi naar verblijf',
                      en: 'Taxi to stay',
                      fr: 'Taxi vers le sejour',
                      es: 'Taxi al alojamiento',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCtaArea(BuildContext context, CustomerThemePalette palette) {
    return _EventDetailActionPanel(
      event: event,
      onBookEvent: onBookEvent,
      palette: palette,
      t: _t,
    );
  }

  Widget _buildMetaRow(
    IconData icon,
    String value,
    CustomerThemePalette palette,
  ) {
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.gold.withOpacity(0.95)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textMuted, fontSize: 12.8),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    CustomerThemePalette palette,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: palette.gold,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12.2,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required CustomerThemePalette palette,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surface.withOpacity(palette.isDark ? 0.42 : 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.gold.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.gold, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: palette.gold,
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'muziek':
        return Icons.graphic_eq_rounded;
      case 'zakelijk':
        return Icons.apartment_rounded;
      case 'sport':
        return Icons.sports_soccer_rounded;
      case 'vandaag':
        return Icons.schedule_rounded;
      default:
        return Icons.event_rounded;
    }
  }
}

class _EventDetailActionPanel extends StatefulWidget {
  const _EventDetailActionPanel({
    required this.event,
    required this.onBookEvent,
    required this.palette,
    required this.t,
  });

  final EventDetailData event;
  final EventBookCallback? onBookEvent;
  final CustomerThemePalette palette;
  final String Function({
    required String nl,
    required String en,
    required String fr,
    required String es,
  })
  t;

  @override
  State<_EventDetailActionPanel> createState() =>
      _EventDetailActionPanelState();
}

class _EventDetailActionPanelState extends State<_EventDetailActionPanel> {
  final EventLocalSavedStore _savedStore = const EventLocalSavedStore();
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final all = await _savedStore.loadAll();
    if (!mounted) return;
    final key = buildSavedEventIdentityKey(widget.event);
    setState(() => _isSaved = all[key]?.saved == true);
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onSavePressed() async {
    if (_isSaved) {
      _showInfoSnackBar(
        widget.t(
          nl: 'Details zijn al opgeslagen',
          en: 'Details are already saved',
          fr: 'Les details sont deja enregistres',
          es: 'Los detalles ya estan guardados',
        ),
      );
      return;
    }
    final all = await _savedStore.saveEventDetails(widget.event);
    if (!mounted) return;
    final key = buildSavedEventIdentityKey(widget.event);
    setState(() => _isSaved = all[key]?.saved == true);
    _showInfoSnackBar(
      widget.t(
        nl: 'Eventdetails opgeslagen',
        en: 'Event details saved',
        fr: 'Details de l evenement enregistres',
        es: 'Detalles del evento guardados',
      ),
    );
  }

  void _onBookPressed() {
    if (widget.onBookEvent != null) {
      widget.onBookEvent!.call(widget.event);
      return;
    }
    _showInfoSnackBar(
      widget.t(
        nl: 'Boekingsflow voor dit event is binnenkort beschikbaar.',
        en: 'Booking flow for this event is coming soon.',
        fr: 'Le flux de réservation pour cet événement arrive bientôt.',
        es: 'El flujo de reserva para este evento estará disponible pronto.',
      ),
    );
  }

  Future<void> _onOpenTicketsPressed() async {
    final rawUrl = (widget.event.sourceUrl ?? '').trim();
    final uri = Uri.tryParse(rawUrl);
    final isHttp =
        uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'https' || uri.scheme == 'http');
    if (!isHttp) {
      _showInfoSnackBar(
        widget.t(
          nl: 'Geen ticketlink beschikbaar voor dit evenement.',
          en: 'No ticket link is available for this event.',
          fr: 'Aucun lien de billet disponible pour cet evenement.',
          es: 'No hay enlace de entradas disponible para este evento.',
        ),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      _showInfoSnackBar(
        widget.t(
          nl: 'Kon de ticketaanbieder niet openen.',
          en: 'Could not open the ticket provider.',
          fr: 'Impossible d ouvrir le fournisseur de billets.',
          es: 'No se pudo abrir el proveedor de entradas.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 16),
      decoration: BoxDecoration(
        color: widget.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.palette.border.withOpacity(0.82)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _onBookPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.palette.gold,
                foregroundColor: Colors.black,
                elevation: 0,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.local_taxi_rounded, size: 18),
              label: Text(
                widget.t(
                  nl: 'Taxi naar dit event boeken',
                  en: 'Book a taxi to this event',
                  fr: 'Réserver un taxi vers cet événement',
                  es: 'Reservar un taxi a este evento',
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _onSavePressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: widget.palette.surfaceAlt.withOpacity(
                  widget.palette.isDark ? 0.9 : 0.96,
                ),
                foregroundColor: widget.palette.gold,
                side: BorderSide(
                  color: widget.palette.border.withOpacity(
                    widget.palette.isDark ? 0.9 : 0.95,
                  ),
                ),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                _isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 18,
              ),
              label: Text(
                _isSaved
                    ? widget.t(
                        nl: 'Details opgeslagen',
                        en: 'Details saved',
                        fr: 'Details enregistres',
                        es: 'Detalles guardados',
                      )
                    : widget.t(
                        nl: 'Details opslaan',
                        en: 'Save details',
                        fr: 'Enregistrer les details',
                        es: 'Guardar detalles',
                      ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _onOpenTicketsPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: widget.palette.surfaceAlt.withOpacity(
                  widget.palette.isDark ? 0.9 : 0.96,
                ),
                foregroundColor: widget.palette.gold,
                side: BorderSide(
                  color: widget.palette.border.withOpacity(
                    widget.palette.isDark ? 0.9 : 0.95,
                  ),
                ),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                widget.t(
                  nl: 'Tickets bekijken',
                  en: 'View tickets',
                  fr: 'Voir les billets',
                  es: 'Ver entradas',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
