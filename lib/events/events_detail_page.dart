import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, __) {
        final palette = paletteForCustomerTheme(themeVariant);
        final bottomInset = MediaQuery.of(context).padding.bottom;
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
                      // TODO(H1-F): Add in-app nearby stay cards only when approved
                      // provider/API hotel content is available.
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
  static const String _stay22Aid = 'fluxidi';
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

  bool _hasValidCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    if (latitude == 0.0 && longitude == 0.0) return false;
    return true;
  }

  String _eventMapSearchQuery() {
    final title = widget.event.title.trim();
    final location = widget.event.locationName.trim();
    final address = widget.event.address.trim();
    final city = widget.event.city.trim();
    final country = (widget.event.countryCode ?? '').trim();
    final query = <String>[
      if (title.isNotEmpty) title,
      if (location.isNotEmpty) location,
      if (address.isNotEmpty) address,
      if (city.isNotEmpty) city,
      if (country.isNotEmpty) country,
    ].join(', ');
    return query;
  }

  Uri _stay22EventMapUri({
    required String eventTitle,
    String? address,
    String? city,
    String? country,
    double? lat,
    double? lng,
    DateTime? date,
    String? campaign,
  }) {
    final effectiveCampaign = (campaign ?? '').trim().isEmpty
        ? 'fluxidi_events_event_detail'
        : campaign!.trim();
    final query = <String>[
      eventTitle.trim(),
      (address ?? '').trim(),
      (city ?? '').trim(),
      (country ?? '').trim(),
    ].where((segment) => segment.isNotEmpty).join(', ');
    final hasCoords =
        lat != null && lng != null && _hasValidCoordinates(lat, lng);
    final params = <String, String>{
      'aid': _stay22Aid,
      'campaign': effectiveCampaign,
      'product_medium': 'apps',
      if (query.isNotEmpty) 'address': query,
      if (hasCoords) 'lat': lat.toStringAsFixed(6),
      if (hasCoords) 'lng': lng.toStringAsFixed(6),
    };
    // TODO(H1-F): Verify exact Stay22 Hub AID and final customer-facing map params.
    // TODO(H1-F): Add date/check-in parameter when the canonical Stay22 key is confirmed.
    // ignore: unused_local_variable
    final ignoredDate = date;
    return Uri.https('www.stay22.com', '/embed/gm', params);
  }

  Future<void> _openStay22EventMap() async {
    final hasCoords = _hasValidCoordinates(widget.event.lat, widget.event.lng);
    final query = _eventMapSearchQuery();
    if (!hasCoords && query.isEmpty) {
      _showInfoSnackBar(
        widget.t(
          nl: 'Locatie voor verblijven rond dit event is niet beschikbaar.',
          en: 'Location is unavailable for stays around this event.',
          fr: 'La localisation pour les séjours autour de cet événement est indisponible.',
          es: 'La ubicación para alojamientos cerca de este evento no está disponible.',
        ),
      );
      return;
    }
    final uri = _stay22EventMapUri(
      eventTitle: widget.event.title,
      address: widget.event.address,
      city: widget.event.city,
      country: widget.event.countryCode,
      lat: hasCoords ? widget.event.lat : null,
      lng: hasCoords ? widget.event.lng : null,
      date: widget.event.startAtUtc,
      campaign: 'fluxidi_events_event_detail',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || launched) return;
    _showInfoSnackBar(
      widget.t(
        nl: 'Kon verblijven rond dit event niet openen.',
        en: 'Could not open stays around this event.',
        fr: 'Impossible d’ouvrir les séjours autour de cet événement.',
        es: 'No se pudieron abrir alojamientos cerca de este evento.',
      ),
    );
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
              onPressed: _openStay22EventMap,
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
              icon: const Icon(Icons.hotel_rounded, size: 18),
              label: Text(
                widget.t(
                  nl: 'Verblijven rond dit event',
                  en: 'Stays around this event',
                  fr: 'Séjours autour de cet événement',
                  es: 'Alojamientos cerca de este evento',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.t(
                nl: 'Bekijk hotels en B&B’s rond de locatie. Beschikbaarheid en prijzen worden extern getoond.',
                en: 'View hotels and stays around the venue. Availability and prices are shown externally.',
                fr: 'Voir des hôtels et séjours autour du lieu. Les disponibilités et les prix sont affichés en externe.',
                es: 'Consulta hoteles y alojamientos cerca del lugar. La disponibilidad y los precios se muestran externamente.',
              ),
              style: TextStyle(
                color: widget.palette.textMuted.withOpacity(0.9),
                fontSize: 11.6,
                fontWeight: FontWeight.w600,
                height: 1.3,
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
