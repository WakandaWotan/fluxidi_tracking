import 'package:flutter/material.dart';

class EventDetailData {
  const EventDetailData({
    required this.title,
    required this.category,
    required this.dateTime,
    required this.location,
    required this.distanceOrStatus,
    required this.ctaLabel,
    required this.gradient,
  });

  final String title;
  final String category;
  final String dateTime;
  final String location;
  final String distanceOrStatus;
  final String ctaLabel;
  final List<Color> gradient;
}

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({required this.event, super.key});

  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  final EventDetailData event;

  String get _city {
    final parts = event.location.split(',');
    return parts.isEmpty ? event.location : parts.last.trim();
  }

  String get _mobiliteitsvraag {
    switch (event.category.toLowerCase()) {
      case 'zakelijk':
        return 'Hoog in de piekuren, met nadruk op gedeelde ritten.';
      case 'sport':
        return 'Middelmatig tot hoog rondom start- en eindmomenten.';
      case 'muziek':
        return 'Hoog in de avond, met geconcentreerde uitstroom na afloop.';
      default:
        return 'Middelmatig, met gespreide vraag over de dag.';
    }
  }

  String get _vervoersmoment {
    if (event.dateTime.toLowerCase().contains('vandaag')) {
      return 'Vandaag, operationele monitoring aanbevolen.';
    }
    return '${event.dateTime}, capaciteit vooraf reserveren.';
  }

  String get _description {
    return 'Dit evenement trekt een professioneel publiek en vraagt om '
        'betrouwbare mobiliteitsplanning. Fluxidi ondersteunt een vlotte '
        'instroom, gecontroleerde uitstroom en heldere operationele regie.';
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
                  _buildCtaArea(),
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
            tooltip: 'Terug',
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Text(
              'Evenementdetail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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
          _buildMetaRow(Icons.calendar_today_outlined, event.dateTime),
          const SizedBox(height: 8),
          _buildMetaRow(Icons.location_on_outlined, event.location),
          const SizedBox(height: 8),
          _buildMetaRow(Icons.location_city_rounded, _city),
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
          _buildInfoRow('Evenementlocatie', event.location),
          const SizedBox(height: 10),
          _buildInfoRow('Verwachte mobiliteitsvraag', _mobiliteitsvraag),
          const SizedBox(height: 10),
          _buildInfoRow('Vervoersmoment', _vervoersmoment),
        ],
      ),
    );
  }

  Widget _buildCtaArea() {
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
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                elevation: 0,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.local_taxi_rounded, size: 18),
              label: const Text(
                'Rit plannen',
                style: TextStyle(fontWeight: FontWeight.w800),
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
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.bookmark_border_rounded, size: 18),
              label: const Text(
                'Details opslaan',
                style: TextStyle(fontWeight: FontWeight.w700),
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
