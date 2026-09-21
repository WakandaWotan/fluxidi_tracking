import 'package:flutter/material.dart';

import '../api/public_partner_api.dart';
import '../screens/customer_home_screen.dart';
import '../screens/customer_payment_return_screen.dart';
import '../screens/customer_placeholder_screen.dart';
import '../screens/customer_taxi_search_screen.dart';
import 'customer_app_config.dart';

/// Named routes for the standalone customer app.
abstract final class CustomerRoutes {
  static const String home = '/';
  static const String taxi = '/taxi';
  static const String airport = '/airport';
  static const String hotels = '/hotels';
  static const String events = '/events';
  static const String bookings = '/bookings';
  static const String profile = '/profile';
  static const String paymentReturn = '/payment-return';

  static const List<String> all = <String>[
    home,
    taxi,
    airport,
    hotels,
    events,
    bookings,
    profile,
    paymentReturn,
  ];
}

/// Single place that turns a route name into a screen.
Route<dynamic> generateCustomerRoute(
  RouteSettings settings, {
  CustomerAppConfig config = kCustomerAppConfig,
}) {
  Widget page;
  switch (settings.name) {
    case CustomerRoutes.taxi:
      page = CustomerTaxiSearchScreen(
        api: PublicPartnerApi(baseUrl: config.publicBookingBaseUrl),
        config: config,
      );
    case CustomerRoutes.airport:
      page = const CustomerPlaceholderScreen(
        title: 'Luchthavenvervoer',
        icon: Icons.flight_takeoff_outlined,
        pending: <String>[
          'Land- en luchthavenkeuze uit de volledige catalogus',
          'Naar of van de luchthaven, met vluchtgegevens',
          'Retourrit en wachttijdregels',
          'Vaste luchthavenprijs van het taxibedrijf',
          'Boeking en betaling',
        ],
      );
    case CustomerRoutes.hotels:
      page = const CustomerPlaceholderScreen(
        title: 'Hotels en B&B',
        icon: Icons.hotel_outlined,
        pending: <String>[
          'Verblijf zoeken',
          'Vervoer naar het verblijf',
        ],
      );
    case CustomerRoutes.events:
      page = const CustomerPlaceholderScreen(
        title: 'Events',
        icon: Icons.celebration_outlined,
        pending: <String>[
          'Evenementen in de buurt',
          'Vervoer naar de locatie',
        ],
      );
    case CustomerRoutes.bookings:
      page = const CustomerPlaceholderScreen(
        title: 'Mijn boekingen',
        icon: Icons.receipt_long_outlined,
        pending: <String>[
          'Boekingen van je klantaccount',
          'Boekingsdetail en status',
          'Online betaling hervatten',
          'Annuleren wanneer dat mag',
          'Beoordeling na de rit',
        ],
      );
    case CustomerRoutes.profile:
      page = const CustomerPlaceholderScreen(
        title: 'Profiel',
        icon: Icons.person_outline,
        pending: <String>[
          'Registreren en aanmelden als klant',
          'Klantgegevens en voorkeuren',
          'Taal en thema',
        ],
      );
    case CustomerRoutes.paymentReturn:
      page = const CustomerPaymentReturnScreen();
    case CustomerRoutes.home:
    default:
      page = const CustomerHomeScreen();
  }
  return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
}
