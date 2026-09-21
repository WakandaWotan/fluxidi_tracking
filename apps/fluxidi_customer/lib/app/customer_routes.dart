import 'package:flutter/material.dart';

import '../screens/customer_payment_return_screen.dart';
import '../screens/customer_shell_screen.dart';
import 'customer_app_config.dart';

/// Named routes for the standalone customer app.
///
/// The services themselves are not routes: taxi, airport, hotels, events and
/// limousine open the existing flows through `bridge/customer_flows.dart`, so
/// there is one implementation of each flow rather than two.
abstract final class CustomerRoutes {
  static const String home = '/';
  static const String bookings = '/bookings';
  static const String profile = '/profile';
  static const String paymentReturn = '/payment-return';

  static const List<String> all = <String>[
    home,
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
    case CustomerRoutes.bookings:
      page = CustomerShellScreen(config: config, initialIndex: 1);
    case CustomerRoutes.profile:
      page = CustomerShellScreen(config: config, initialIndex: 2);
    case CustomerRoutes.paymentReturn:
      page = CustomerPaymentReturnScreen(config: config);
    case CustomerRoutes.home:
    default:
      page = CustomerShellScreen(config: config);
  }
  return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
}
