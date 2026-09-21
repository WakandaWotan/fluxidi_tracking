import 'package:flutter/material.dart';

import '../app/customer_app_config.dart';
import '../app/customer_routes.dart';

@immutable
class CustomerDestination {
  const CustomerDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.caption = 'Aansluiting volgt',
  });

  final String label;
  final IconData icon;
  final String route;

  /// Honest one-line state of this destination.
  final String caption;
}

const List<CustomerDestination> kCustomerDestinations = <CustomerDestination>[
  CustomerDestination(
    label: 'Taxi',
    icon: Icons.local_taxi_outlined,
    route: CustomerRoutes.taxi,
    caption: 'Zoeken en prijs opvragen',
  ),
  CustomerDestination(
    label: 'Luchthaven',
    icon: Icons.flight_takeoff_outlined,
    route: CustomerRoutes.airport,
  ),
  CustomerDestination(
    label: 'Hotels',
    icon: Icons.hotel_outlined,
    route: CustomerRoutes.hotels,
  ),
  CustomerDestination(
    label: 'Events',
    icon: Icons.celebration_outlined,
    route: CustomerRoutes.events,
  ),
  CustomerDestination(
    label: 'Mijn boekingen',
    icon: Icons.receipt_long_outlined,
    route: CustomerRoutes.bookings,
  ),
  CustomerDestination(
    label: 'Profiel',
    icon: Icons.person_outline,
    route: CustomerRoutes.profile,
  ),
];

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key, this.config = kCustomerAppConfig});

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = _columnsForWidth(constraints.maxWidth);
            final padding = constraints.maxWidth >= 800 ? 24.0 : 16.0;
            return SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Header(config: config),
                      const SizedBox(height: 20),
                      GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        // Fixed tile height keeps the card readable at every
                        // width instead of letting an aspect ratio squeeze it.
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: _tileHeight(
                                MediaQuery.textScalerOf(context),
                              ),
                            ),
                        children: <Widget>[
                          for (final destination in kCustomerDestinations)
                            _DestinationCard(destination: destination),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _PhaseNotice(config: config),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static int _columnsForWidth(double width) {
    if (width >= 1000) return 4;
    if (width >= 700) return 3;
    return 2;
  }

  /// Grows with the user's text size so a larger font cannot clip the card.
  static double _tileHeight(TextScaler textScaler) {
    return textScaler.scale(20) * 6.2;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.config});

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: config.brand.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text(
                'F',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                config.appName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: config.brand.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: config.brand.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                config.environmentLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: config.brand.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Waar wil je naartoe?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Onder Taxi kun je echte taxibedrijven zoeken en een prijs opvragen. '
          'Boeken, betalen en een klantaccount zijn nog niet aangesloten.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: config.brand.textSoft,
          ),
        ),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination});

  final CustomerDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(destination.route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                destination.icon,
                size: 26,
                color: theme.colorScheme.primary,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    destination.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kCustomerAppConfig.brand.textSoft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseNotice extends StatelessWidget {
  const _PhaseNotice({required this.config});

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: config.brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Developmentbuild',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Losstaand van de bestaande Fluxidi-app, met een echte verbinding '
            'naar de publieke zoek- en prijsdiensten. Nog niet aangesloten: '
            'boeken, betalen, aanmelden en mijn boekingen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Dit tegelscherm is tijdelijk. Het Fluxidi-ontwerp met fotokaarten, '
            'paletknop, Regio Radar en Home, Boekingen en Profiel volgt in de '
            'aparte UI-stap.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}
