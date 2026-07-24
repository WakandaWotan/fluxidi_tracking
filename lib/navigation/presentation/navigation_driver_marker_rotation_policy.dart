// NAV-TELLERS-STREETLEVEL-SCREEN-UP-MARKER-1
//
// The pure driver-marker rotation policy is defined inline in
// `driver_ride_meters.dart` alongside its sibling
// `DriverVehicleMarkerPresentationOwner` enum. Placing it there keeps the
// policy reachable from `driver_home_page_state.dart`
// (`part of '../main.dart'`) via `main.dart`'s pre-existing import of
// `driver_ride_meters.dart` — no new `main.dart` import is required.
//
// This file re-exports the policy symbols so callers and tests can import
// the marker-rotation policy via a dedicated module path.
export 'driver_ride_meters.dart'
    show
        DriverMarkerRotationAlignment,
        DriverMarkerRotationPolicy,
        DriverVehicleMarkerPresentationOwner,
        resolveDriverMarkerRotationPolicy;
