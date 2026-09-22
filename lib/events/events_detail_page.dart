import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/discovery/customer_contained_photo.dart';
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
    case AppLanguage.de:
      return en;
    }
  }

  String? get _eventDescription {
    final text = (event.description ?? '').trim();
    if (text.isEmpty || isCustomerTechnicalDiscoveryCopy(text)) return null;
    return text;
  }

  String get _heroImageUrl {
    return preferredCustomerDetailPhotoUrl(
      hero: event.heroImageUrl,
      image: event.imageUrl,
      thumbnail: event.thumbnailUrl,
    );
  }

  String? get _heroSecondaryChipLabel {
    final statusLabel = event.customerTicketStatusLabel;
    if ((statusLabel ?? '').isNotEmpty) return statusLabel;
    final distance = event.isDistanceLabelTrusted
        ? (event.distanceLabel ?? '').trim()
        : '';
    return distance.isNotEmpty ? distance : null;
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
    return CustomerContainedPhoto(
      key: const Key('customer_event_detail_photo'),
      imageUrl: _heroImageUrl,
      backgroundColor: palette.surface,
      borderColor: palette.border.withOpacity(0.85),
      placeholder: Center(
        child: Icon(
          Icons.event_rounded,
          color: palette.gold.withOpacity(0.95),
          size: 64,
        ),
      ),
    );
  }

  Widget _buildPrimaryContent(CustomerThemePalette palette) {
    final description = _eventDescription;
    final secondaryChipLabel = _heroSecondaryChipLabel;
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
            event.title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              if (event.category.trim().isNotEmpty)
                _buildChip(
                  palette: palette,
                  label: event.category,
                  icon: _categoryIcon(event.category),
                ),
              if ((secondaryChipLabel ?? '').isNotEmpty)
                _buildChip(
                  palette: palette,
                  label: secondaryChipLabel!,
                  icon: Icons.event_available_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMetaRow(
            Icons.calendar_today_outlined,
            event.dateTimeLabel,
            palette,
          ),
          const SizedBox(height: 8),
          _buildMetaRow(
            Icons.location_on_outlined,
            '${event.locationName}, ${event.city}',
            palette,
          ),
          const SizedBox(height: 8),
          _buildMetaRow(Icons.pin_drop_outlined, event.address, palette),
          if (description != null) ...[
            const SizedBox(height: 11),
            Divider(color: palette.border.withOpacity(0.75), height: 1),
            const SizedBox(height: 11),
            Text(
              description,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
