// P3P — hide taxi street-ride QR in limousine context.
// Does not delete or change the taxi QR engine. Mixed companies keep the
// existing taxi QR on taxi surfaces only.

import '../app_config.dart';
import '../company/company_fleet_operational.dart';
import 'limousine_business_setup.dart';

bool companyHasTaxiStreetRideVehicles([Iterable<VehicleProfile>? vehicles]) {
  return limousineSetupTaxiVehicles(
    vehicles ?? companyOperationalVehicles(),
  ).isNotEmpty;
}

bool companyHasLimousineVehicles([Iterable<VehicleProfile>? vehicles]) {
  return limousineSetupLimousineVehicles(
    vehicles ?? companyOperationalVehicles(),
  ).isNotEmpty;
}

/// True when the committed fleet is limousine-only. Empty or unknown fleets
/// stay false so taxi first-run / taxi-only companies keep the existing QR.
bool companyIsLimousineOnlyFleet([Iterable<VehicleProfile>? vehicles]) {
  final fleet = vehicles ?? companyOperationalVehicles();
  return companyHasLimousineVehicles(fleet) &&
      !companyHasTaxiStreetRideVehicles(fleet);
}

/// Taxi booking-link / street-ride QR visibility.
///
/// * limousine context never presents the taxi QR
/// * limousine-only companies never see it
/// * taxi-only and mixed companies keep it on taxi surfaces
bool companyShouldShowTaxiBookingQr({
  Iterable<VehicleProfile>? vehicles,
  bool limousineContext = false,
}) {
  if (limousineContext) return false;
  return !companyIsLimousineOnlyFleet(vehicles);
}
