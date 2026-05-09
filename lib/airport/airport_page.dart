import 'package:flutter/material.dart';

class AirportPage extends StatelessWidget {
  const AirportPage({super.key});

  static const Color _bg = Color(0xFF07080C);
  static const Color _panel = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _soft = Color(0xFFB4B4B4);

  static const List<String> _airports = <String>[
    'Brussels Airport',
    'Charleroi Airport',
    'Amsterdam Schiphol',
    'Paris Charles de Gaulle',
    'London Heathrow',
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : 14.0;
    final stackedActions = width < 385;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  16,
                ),
                children: [
                  _buildHero(),
                  const SizedBox(height: 10),
                  _buildDirectionActions(stacked: stackedActions),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Populaire luchthavens',
                    icon: Icons.flight_land_rounded,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _airports
                          .map(
                            (name) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _gold.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _gold.withOpacity(0.45),
                                ),
                              ),
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: _gold,
                                  fontSize: 11.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Vluchtgegevens optioneel',
                    icon: Icons.confirmation_number_outlined,
                    subtitle:
                        'Vluchtcode en aankomsttijd kunnen later worden toegevoegd voor een nauwkeurige planning.',
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Meet & greet / naam bordje',
                    icon: Icons.person_pin_circle_outlined,
                    subtitle:
                        'Professionele ontvangst op de luchthaven met optioneel naam bordje.',
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Bagage & passagiers',
                    icon: Icons.luggage_outlined,
                    subtitle:
                        'Capaciteit voor passagiers en bagage wordt in een volgende fase aan de boekingsstap gekoppeld.',
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Vaste prijs / offerte later',
                    icon: Icons.price_change_outlined,
                    subtitle:
                        'Prijsberekening en offerte worden in de volgende modulefase geactiveerd.',
                  ),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Luchthavenvervoer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Premium transfers voor comfortabele ritten van en naar de luchthaven',
                  style: TextStyle(color: _soft, fontSize: 11.5, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.28)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF12110A), Color(0xFF07080C)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.45)),
              color: _gold.withOpacity(0.14),
            ),
            child: const Icon(Icons.local_taxi_rounded, color: _gold, size: 30),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zakelijk en privé luchthavenvervoer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Plan binnenkort direct uw transfer met heldere serviceopties en betrouwbare chauffeurs.',
                  style: TextStyle(color: _soft, fontSize: 11.8, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionActions({required bool stacked}) {
    final first = _actionCard(
      title: 'Naar de luchthaven',
      subtitle: 'Vertrek op tijd met comfortabele ophaalservice.',
      icon: Icons.flight_takeoff_rounded,
    );
    final second = _actionCard(
      title: 'Van de luchthaven',
      subtitle: 'Aankomsttransfer met duidelijke afhaalafspraken.',
      icon: Icons.flight_land_rounded,
    );
    if (stacked) {
      return Column(children: [first, const SizedBox(height: 8), second]);
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 8),
        Expanded(child: second),
      ],
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _gold.withOpacity(0.14),
                    border: Border.all(color: _gold.withOpacity(0.4)),
                  ),
                  child: Icon(icon, color: _gold, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _soft,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gold.withOpacity(0.96), size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: _soft,
                fontSize: 11.7,
                height: 1.25,
              ),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}
