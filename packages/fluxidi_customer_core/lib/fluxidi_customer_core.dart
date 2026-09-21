/// Shared customer ride core for the Fluxidi customer apps.
///
/// Extracted from the existing app at golden commit
/// 9df7e7b92ecc86a11184ee995e255da7b8f6fb68. See `EXTRACTED.md` for the exact
/// source file and symbol behind every piece.
///
/// Pricing is server-side only. This package builds the request and reads the
/// answer; it never calculates a fare.
library;

export 'src/address_value.dart';
export 'src/address_search.dart';
export 'src/availability.dart';
export 'src/lon_lat.dart';
export 'src/partner_scope.dart';
export 'src/quote_request.dart';
export 'src/quote_result.dart';
export 'src/quote_wire.dart';
export 'src/route_geometry.dart';
export 'src/ride_options.dart';
export 'src/schedule.dart';
export 'src/vehicle_offer.dart';
