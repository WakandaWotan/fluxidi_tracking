/// Prepared public-map expansion. Not sent by the live Worker today.
///
/// Current `GET /region-interest/radar` answers with:
/// `{ ok, country, postcode, count, display_count, status }`.
/// There are no cells, names, emails, phones, or house coordinates.
///
/// A later bounded response may add regional aggregations only:
///
/// ```
/// {
///   "ok": true,
///   "country": "BE",
///   "postcode": "9688",
///   "count": 3,
///   "display_count": "3+",
///   "cells": [
///     {
///       "postcode": "9688",
///       "display_count": "3+",
///       "lat": 50.770,
///       "lon": 3.656
///     }
///   ]
/// }
/// ```
///
/// Rules for that change, when it is rolled out separately:
/// - cells are regional centroids or postcode centres, never a street address
/// - `display_count` stays a category (`3+`), never an exact invented total
/// - response is bounded (one region or a small bbox), no full registration scan
/// - no person, contact, or profile fields
/// - the customer app already reads [RegionRadarApproximateCell] when present
class RegionRadarMapExpansion {
  const RegionRadarMapExpansion._();
}
