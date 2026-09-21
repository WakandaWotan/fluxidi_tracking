import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_open.dart';
import 'package:fluxidi_tracking/customer_phone_recovery_page.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/customer_theme_page.dart';
import 'package:fluxidi_tracking/events/event_taxi_availability.dart';
import 'package:fluxidi_tracking/events/events_page.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/main.dart'
    show
        CustomerOnboardingPage,
        CustomerProfileEditPage,
        CustomerRegionRegistrationPage,
        CustomerSavedBookingsPage;
import 'package:fluxidi_tracking/nearby_partners_page.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_ui.dart';

import 'customer_runtime.dart';

/// Start page the bridged flows return to when the customer taps "home".
///
/// The reused flows were written against the combined app's `CustomerHomePage`.
/// This app has its own start page, so it registers that builder once at boot
/// and the bridged flows land back on it instead of on a second home screen.
WidgetBuilder? _startPageBuilder;

void registerCustomerStartPage(WidgetBuilder builder) {
  _startPageBuilder = builder;
}

WidgetBuilder get _startPage =>
    _startPageBuilder ?? (_) => const SizedBox.shrink();

/// A destination the customer picked before the booking flow opened.
@immutable
class CustomerFlowPlace {
  const CustomerFlowPlace({
    required this.address,
    this.name = '',
    this.latitude,
    this.longitude,
  });

  final String address;
  final String name;
  final double? latitude;
  final double? longitude;

  bool get hasAddress => address.trim().isNotEmpty;

  /// True when the pick carries real coordinates, so the flow can quote and
  /// draw the route without geocoding the text a second time.
  bool get hasCoordinates => latitude != null && longitude != null;

  CustomerBookingPlace toBookingPlace({DateTime? startsAt}) {
    return CustomerBookingPlace(
      name: name.trim(),
      address: address.trim(),
      latitude: latitude,
      longitude: longitude,
      startsAt: startsAt,
    );
  }
}

/// Builds the entry the taxi flow opens with.
///
/// Separate from [openTaxiFlow] so the hand-off can be asserted without a
/// navigator: a destination picked on the start page must reach the flow with
/// its coordinates intact, or the flow would geocode the label a second time
/// and could quote a different point than the customer chose.
CustomerBookingEntryContext customerTaxiEntry({
  CustomerFlowPlace? pickup,
  CustomerFlowPlace? destination,
  DateTime? pickupAt,
  String sourceLabel = 'customer_home_taxi',
}) {
  return CustomerBookingEntryContext(
    kind: CustomerBookingKind.taxi,
    pickup: pickup != null && pickup.hasAddress
        ? pickup.toBookingPlace(startsAt: pickupAt)
        : null,
    destination: destination != null && destination.hasAddress
        ? destination.toBookingPlace(startsAt: pickupAt)
        : null,
    sourceLabel: sourceLabel,
  );
}

/// Builds the entry the airport flow opens with.
CustomerBookingEntryContext customerAirportEntry({
  CustomerFlowPlace? pickup,
  bool toAirport = true,
  String sourceLabel = 'airport_flow',
}) {
  return CustomerBookingEntryContext(
    kind: CustomerBookingKind.airport,
    pickup: pickup != null && pickup.hasAddress
        ? pickup.toBookingPlace()
        : null,
    toAirport: toAirport,
    sourceLabel: sourceLabel,
  );
}

/// Builds the entry a hotel or B&B ride opens with.
CustomerBookingEntryContext customerStayEntry({
  CustomerFlowPlace? destination,
  required String sourceLabel,
}) {
  return CustomerBookingEntryContext(
    kind: CustomerBookingKind.stay,
    destination: destination != null && destination.hasAddress
        ? destination.toBookingPlace()
        : null,
    sourceLabel: sourceLabel,
  );
}

/// Builds the entry an event ride opens with.
CustomerBookingEntryContext customerEventEntry({
  required CustomerFlowPlace destination,
  DateTime? startsAt,
  String sourceLabel = 'event_flow',
}) {
  return CustomerBookingEntryContext(
    kind: CustomerBookingKind.event,
    destination: destination.toBookingPlace(startsAt: startsAt),
    sourceLabel: sourceLabel,
  );
}

/// Opens the existing taxi booking flow.
///
/// [destination] carries its coordinates through unchanged, so a destination
/// chosen on the start page does not have to be resolved again.
Future<void> openTaxiFlow(
  BuildContext context, {
  CustomerFlowPlace? pickup,
  CustomerFlowPlace? destination,
  DateTime? pickupAt,
  String sourceLabel = 'customer_home_taxi',
}) {
  return openCustomerBookingFlow(
    context,
    entry: customerTaxiEntry(
      pickup: pickup,
      destination: destination,
      pickupAt: pickupAt,
      sourceLabel: sourceLabel,
    ),
    onGoToStartPage: _startPage,
  );
}

/// Opens the existing airport flow.
///
/// Country and airport choice, the full published catalog, the six Belgian
/// photo cards, the to/from-airport switch and the fixed airport price all
/// live inside that flow and are reused exactly as they are.
Future<void> openAirportFlow(
  BuildContext context, {
  CustomerFlowPlace? pickup,
  bool toAirport = true,
  String sourceLabel = 'airport_flow',
}) {
  return openCustomerBookingFlow(
    context,
    entry: CustomerBookingEntryContext(
      kind: CustomerBookingKind.airport,
      pickup: pickup?.hasAddress == true ? pickup!.toBookingPlace() : null,
      toAirport: toAirport,
      sourceLabel: sourceLabel,
    ),
    onGoToStartPage: _startPage,
  );
}

/// Opens the existing hotel and B&B pages, with the same taxi hand-offs the
/// combined app wires up.
Future<void> openHotelsFlow(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => HotelsPage(
        onTaxiToStay: (stay) async {
          final address =
              stay.address.trim().isNotEmpty ? stay.address.trim() : stay.name;
          await _openStayRide(
            context,
            destination: CustomerFlowPlace(
              address: address.trim(),
              name: stay.name.trim(),
              latitude: stay.lat,
              longitude: stay.lng,
            ),
            sourceLabel: 'hotel_stay',
          );
        },
        onTaxiToDestination: (destination) async {
          await _openStayRide(
            context,
            destination: CustomerFlowPlace(
              address: destination.prefillDestinationText,
              name: destination.destinationName,
              latitude: destination.latitude,
              longitude: destination.longitude,
            ),
            sourceLabel: 'hotel_stay',
          );
        },
        onOpenAirportFlow: (destination) => openAirportFlow(
          context,
          pickup: CustomerFlowPlace(
            address: destination.prefillDestinationText,
            name: destination.destinationName,
            latitude: destination.latitude,
            longitude: destination.longitude,
          ),
        ),
        onManualHotelTaxi: () =>
            _openStayRide(context, sourceLabel: 'hotel_return_flow'),
        onOpenAirportReturnFlow: () => openAirportFlow(context),
      ),
    ),
  );
}

Future<void> _openStayRide(
  BuildContext context, {
  CustomerFlowPlace? destination,
  required String sourceLabel,
}) {
  if (!context.mounted) return Future<void>.value();
  return openCustomerBookingFlow(
    context,
    entry: CustomerBookingEntryContext(
      kind: CustomerBookingKind.stay,
      destination: destination?.hasAddress == true
          ? destination!.toBookingPlace()
          : null,
      sourceLabel: sourceLabel,
    ),
    onGoToStartPage: _startPage,
  );
}

/// Opens the existing events pages, with the same event-to-taxi hand-off.
Future<void> openEventsFlow(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => EventsPage(
        dataSource: buildDefaultEventLocatorDataSource(
          baseUrl: kBookingBaseUrl,
        ),
        onBookEvent: (event) {
          final destination = eventTaxiDestination(event);
          if (!context.mounted) return;
          unawaited(
            openCustomerBookingFlow(
              context,
              entry: CustomerBookingEntryContext(
                kind: CustomerBookingKind.event,
                destination: CustomerBookingPlace(
                  address: destination.text,
                  latitude: destination.lat,
                  longitude: destination.lng,
                  startsAt: event.startAtUtc,
                ),
                sourceLabel: 'event_flow',
              ),
              onGoToStartPage: _startPage,
            ),
          );
        },
      ),
    ),
  );
}

/// Opens the existing limousine discovery flow.
void openLimousineFlow(BuildContext context) {
  openLimousineCustomerDiscovery(
    context,
    customerHomeBuilder: _startPage,
  );
}

/// Opens "Mijn boekingen": the existing saved bookings list, which refreshes
/// itself from the customer session and links through to the booking detail.
Future<void> openMyBookings(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const CustomerSavedBookingsPage()),
  );
}

/// Opens Regio Radar: the existing region registration page.
Future<void> openRegionRadar(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const CustomerRegionRegistrationPage(),
    ),
  );
}

/// Opens the company search and public company profiles.
Future<Map<String, String>?> openCompanySearch(
  BuildContext context, {
  bool selectionMode = false,
  bool airportCapableOnly = false,
}) {
  return Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute<Map<String, String>>(
      builder: (_) => NearbyPartnersPage(
        customerHomeBuilder: _startPage,
        regionRegistrationBuilder: (_) => const CustomerRegionRegistrationPage(),
        syncCustomerProfileFromBackend: syncCustomerProfileFromBackend,
        selectionMode: selectionMode,
        airportCapableOnly: airportCapableOnly,
      ),
    ),
  );
}

/// Opens "Mijn gegevens": the existing customer profile editor.
Future<void> openMyDetails(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const CustomerProfileEditPage()),
  );
}

/// Opens the full existing theme picker with all customer theme variants.
Future<void> openThemePicker(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const CustomerThemePage()),
  );
}

/// Opens the existing privacy and account page, including the account deletion
/// request with its own confirmation. Nothing is deleted from here directly.
void openPrivacyAndAccount(BuildContext context) {
  openFluxidiPrivacyAccountPage(
    context,
    audience: FluxidiPrivacyAudience.customer,
  );
}

/// Signs a customer in with the existing phone and one-time-code flow.
///
/// Returns the restored session, or null when the customer cancelled. A new
/// customer is sent through the existing onboarding page first.
Future<CustomerSession?> signInCustomer(BuildContext context) async {
  final result = await Navigator.of(context).push<Object?>(
    MaterialPageRoute<Object?>(
      builder: (_) => const CustomerPhoneRecoveryPage(),
    ),
  );
  if (result == CustomerPhoneRecoveryPage.newCustomerResult) {
    if (!context.mounted) return null;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CustomerOnboardingPage()),
    );
    return CustomerSessionStore.instance.loadValidSession();
  }
  if (result is CustomerSession) return result;
  return CustomerSessionStore.instance.loadValidSession();
}

/// Signs the customer out of this device.
Future<void> signOutCustomer() async {
  await CustomerSessionStore.instance.clear();
}
