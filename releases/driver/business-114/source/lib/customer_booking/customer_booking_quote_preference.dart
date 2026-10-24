import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_service_capacity.dart';

/// Fleet preferences only. No driver, online state, assignment or reservation.
List<CustomerBookingVehicleOffer> customerQuoteVehiclePreferences(
  List<Map<String, dynamic>> vehicles, {
  required int passengers,
  required int baggage,
  required String service,
}) {
  final seen = <String>{};
  return [
    for (final vehicle in vehicles)
      if (companyAgendaVehicleIsActive(vehicle) &&
          companyAgendaVehicleId(vehicle).isNotEmpty &&
          seen.add(companyAgendaVehicleId(vehicle)) &&
          vehicleEnabledForService(vehicle, service))
        CustomerBookingVehicleOffer(
          vehicle: Map<String, dynamic>.from(vehicle)
            ..remove('assigned_driver')
            ..remove('assignedDriver'),
          passengerSeats: resolveVehicleServiceCapacity(
            vehicle,
            service,
          ).passengers,
          baggageCapacity: resolveVehicleServiceCapacity(
            vehicle,
            service,
          ).baggage,
          available: vehicleServiceCapacityRefusal(
            vehicle,
            service: service,
            passengers: passengers,
            baggage: baggage,
          ).isEmpty,
          reason: vehicleServiceCapacityRefusal(
            vehicle,
            service: service,
            passengers: passengers,
            baggage: baggage,
          ),
        ),
  ];
}

Uri customerQuoteEmailUri(String email, String summary) => Uri(
  scheme: 'mailto',
  path: email,
  query:
      'subject=${Uri.encodeComponent('Offerteaanvraag taxi')}&body=${Uri.encodeComponent(summary)}',
);
