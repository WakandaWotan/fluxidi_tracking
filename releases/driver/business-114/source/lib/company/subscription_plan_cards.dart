import 'package:flutter/material.dart';

/// Public plan comparison. Actual access and collected amounts remain owned by
/// the server subscription, not by this informational widget.
class SubscriptionPlanCards extends StatelessWidget {
  const SubscriptionPlanCards({
    super.key,
    required this.languageCode,
    required this.accent,
    required this.textColor,
    required this.secondaryTextColor,
    this.currentPlanCode = '',
  });

  final String languageCode;
  final Color accent;
  final Color textColor;
  final Color secondaryTextColor;
  final String currentPlanCode;

  String _text(String nl, String en, String fr, String es) =>
      switch (languageCode) {
        'en' => en,
        'fr' => fr,
        'es' => es,
        _ => nl,
      };

  Widget _plan(String code, int price, List<String> features) {
    final name = code == 'smart' ? 'Smart' : 'Standard';
    return Container(
      key: ValueKey('subscription_plan_$code'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: accent.withValues(alpha: .65)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              color: textColor,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '€$price',
            style: TextStyle(
              color: accent,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            _text(
              'per maand · excl. btw',
              'per month · excl. VAT',
              'par mois · hors TVA',
              'al mes · sin IVA',
            ),
            style: TextStyle(color: secondaryTextColor),
          ),
          if (currentPlanCode.toLowerCase() == code) ...[
            const SizedBox(height: 8),
            Text(
              _text(
                'Huidig abonnement',
                'Current subscription',
                'Abonnement actuel',
                'Suscripción actual',
              ),
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(feature, style: TextStyle(color: textColor)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final standard = _plan('standard', 69, [
      _text(
        'Eigen, telefonische en straatritten',
        'Own, phone and street rides',
        'Courses propres, téléphoniques et de rue',
        'Viajes propios, telefónicos y de calle',
      ),
      _text(
        'Planning, rooster en reguliere dispatch',
        'Planning, shifts and regular dispatch',
        'Planning, horaires et dispatch classique',
        'Planificación, turnos y despacho habitual',
      ),
      _text(
        'Chauffeurs, voertuigen en administratie',
        'Drivers, vehicles and administration',
        'Chauffeurs, véhicules et administration',
        'Conductores, vehículos y administración',
      ),
      _text(
        'Online- en luchthavenboekingen',
        'Online and airport bookings',
        'Réservations en ligne et aéroport',
        'Reservas en línea y de aeropuerto',
      ),
    ]);
    final smart = _plan('smart', 89, [
      _text(
        'Alles van Standard',
        'Everything in Standard',
        'Tout Standard',
        'Todo Standard',
      ),
      _text(
        'Live tracking voor klanten',
        'Live customer tracking',
        'Suivi en direct pour les clients',
        'Seguimiento en vivo para clientes',
      ),
      _text(
        'Verkeers-ETA en planningsbuffers',
        'Traffic ETA and planning buffers',
        'ETA trafic et marges de planning',
        'ETA de tráfico y márgenes de planificación',
      ),
      _text(
        'AI-dispatch en automatische chauffeurselectie',
        'AI dispatch and automatic driver selection',
        'Dispatch IA et sélection automatique du chauffeur',
        'Despacho IA y selección automática del conductor',
      ),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 650)
              return Column(
                children: [standard, const SizedBox(height: 12), smart],
              );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: standard),
                const SizedBox(width: 12),
                Expanded(child: smart),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          _text(
            '1 voertuig en 3 chauffeurs inbegrepen.',
            '1 vehicle and 3 drivers included.',
            '1 véhicule et 3 chauffeurs inclus.',
            '1 vehículo y 3 conductores incluidos.',
          ),
          style: TextStyle(color: secondaryTextColor),
        ),
        const SizedBox(height: 8),
        Text(
          _text(
            'Smart kun je vrijwillig 14 dagen testen. Zonder betaald abonnement val je daarna terug op FREE. '
                'Aanvragen blijven ontvangen en bekijken is gratis; behandelen vereist Standard of Smart.',
            'You can choose a 14-day Smart trial. Without a paid subscription you return to FREE. '
                'Receiving and viewing requests remains free; handling requires Standard or Smart.',
            'Vous pouvez choisir un essai Smart de 14 jours. Sans abonnement payant, vous revenez à FREE. '
                'Recevoir et consulter les demandes reste gratuit ; les traiter exige Standard ou Smart.',
            'Puedes elegir una prueba Smart de 14 días. Sin suscripción de pago vuelves a FREE. '
                'Recibir y ver solicitudes sigue siendo gratis; gestionarlas requiere Standard o Smart.',
          ),
          style: TextStyle(color: secondaryTextColor),
        ),
      ],
    );
  }
}
