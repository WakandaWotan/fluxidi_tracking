import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

typedef EventBookCallback = void Function(EventDetailData event);

class EventDetailData {
  const EventDetailData({
    required this.id,
    required this.title,
    required this.category,
    required this.dateTimeLabel,
    required this.locationName,
    required this.city,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceOrStatus,
    required this.gradient,
    this.visualAssetPath,
    this.sourceLabel,
  });

  final String id;
  final String title;
  final String category;
  final String dateTimeLabel;
  final String locationName;
  final String city;
  final String address;
  final double lat;
  final double lng;
  final String distanceOrStatus;
  final List<Color> gradient;
  final String? visualAssetPath;
  final String? sourceLabel;

  String get destinationLabel {
    final location = locationName.trim();
    final destination = address.trim();
    if (location.isEmpty) return destination;
    if (destination.isEmpty) return location;
    return '$location, $destination';
  }
}

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({required this.event, this.onBookEvent, super.key});

  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

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

  String get _vervoersmoment {
    if (event.dateTimeLabel.toLowerCase().contains('vandaag')) {
      return _t(
        nl: 'Vandaag, operationele monitoring aanbevolen.',
        en: 'Today, operational monitoring is recommended.',
        fr: 'Aujourd hui, un suivi operationnel est recommande.',
        es: 'Hoy se recomienda seguimiento operativo.',
      );
    }
    return _t(
      nl: '${event.dateTimeLabel}, capaciteit vooraf reserveren.',
      en: '${event.dateTimeLabel}, reserve capacity in advance.',
      fr: '${event.dateTimeLabel}, reserver la capacite a l avance.',
      es: '${event.dateTimeLabel}, reservar capacidad con antelacion.',
    );
  }

  String get _description {
    return _t(
      nl: 'Dit evenement trekt een professioneel publiek en vraagt om betrouwbare mobiliteitsplanning. Fluxidi ondersteunt een vlotte instroom, gecontroleerde uitstroom en heldere operationele regie.',
      en: 'This event attracts a professional audience and requires reliable mobility planning. Fluxidi supports smooth arrival flows, controlled departures, and clear operational coordination.',
      fr: 'Cet evenement attire un public professionnel et demande une planification de mobilite fiable. Fluxidi soutient des arrivees fluides, des departs controles et une coordination operationnelle claire.',
      es: 'Este evento atrae a un publico profesional y requiere una planificacion de movilidad fiable. Fluxidi apoya llegadas fluidas, salidas controladas y una coordinacion operativa clara.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                children: [
                  _buildHeroVisual(),
                  const SizedBox(height: 12),
                  _buildPrimaryContent(),
                  const SizedBox(height: 12),
                  _buildInfoPanel(),
                  const SizedBox(height: 14),
                  _buildCtaArea(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: _gold,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              _t(
                nl: 'Evenementdetail',
                en: 'Event details',
                fr: 'Details de l evenement',
                es: 'Detalle del evento',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroVisual() {
    return Container(
      height: 196,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold.withOpacity(0.32)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: event.gradient,
        ),
      ),
      child: Stack(
        children: [
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
                    _gold.withOpacity(0.30),
                    _gold.withOpacity(0.08),
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
                  colors: [_gold.withOpacity(0.20), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 14,
            child: _buildChip(
              label: event.category,
              icon: _categoryIcon(event.category),
            ),
          ),
          Positioned(
            left: 16,
            top: 48,
            child: _buildChip(
              label: event.distanceOrStatus,
              icon: Icons.local_taxi_rounded,
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: Icon(
              Icons.workspace_premium_rounded,
              color: _gold.withOpacity(0.90),
              size: 28,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryContent() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaRow(Icons.calendar_today_outlined, event.dateTimeLabel),
          const SizedBox(height: 8),
          _buildMetaRow(Icons.location_on_outlined, event.locationName),
          const SizedBox(height: 8),
          _buildMetaRow(Icons.pin_drop_outlined, event.address),
          const SizedBox(height: 10),
          const Divider(color: Color(0x33E5B641), height: 1),
          const SizedBox(height: 10),
          Text(
            _description,
            style: const TextStyle(
              color: _softText,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            _t(
              nl: 'Evenementlocatie',
              en: 'Event venue',
              fr: 'Lieu de l evenement',
              es: 'Lugar del evento',
            ),
            '${event.locationName}, ${event.city}',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            _t(nl: 'Adres', en: 'Address', fr: 'Adresse', es: 'Direccion'),
            event.address,
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
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            _t(
              nl: 'Vervoersmoment',
              en: 'Transport timing',
              fr: 'Moment du transport',
              es: 'Momento del transporte',
            ),
            _vervoersmoment,
          ),
        ],
      ),
    );
  }

  void _onBookPressed(BuildContext context) {
    if (onBookEvent != null) {
      onBookEvent!.call(event);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Boekingsflow wordt hier gekoppeld in de volgende stap.',
            en: 'Booking flow will be connected here in the next step.',
            fr: 'Le flux de reservation sera connecte ici a l etape suivante.',
            es: 'El flujo de reserva se conectara aqui en el siguiente paso.',
          ),
        ),
      ),
    );
  }

  Widget _buildCtaArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _onBookPressed(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                elevation: 0,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.local_taxi_rounded, size: 18),
              label: Text(
                _t(
                  nl: 'Taxi naar dit event boeken',
                  en: 'Book a taxi to this event',
                  fr: 'Reserver un taxi vers cet evenement',
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
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withOpacity(0.6)),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.bookmark_border_rounded, size: 18),
              label: Text(
                _t(
                  nl: 'Details opslaan',
                  en: 'Save details',
                  fr: 'Enregistrer les details',
                  es: 'Guardar detalles',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _gold.withOpacity(0.95)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _softText, fontSize: 12.8),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 5),
          decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: _softText,
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

  Widget _buildChip({required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _gold, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: _gold,
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
