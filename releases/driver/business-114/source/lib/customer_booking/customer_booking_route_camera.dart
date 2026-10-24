import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart'
    show EdgeInsets, TextPainter, TextSpan, TextStyle;
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

const double kCustomerBookingMapMinZoom = 4;
const double kCustomerBookingMapMaxZoom = 16;
const double kCustomerBookingRouteWideBreakpoint = 900;

class CustomerBookingMapCamera {
  const CustomerBookingMapCamera({
    required this.center,
    required this.zoom,
    this.bearingDeg = 0,
  });

  final FluxidiMapLonLat center;
  final double zoom;

/// Clockwise degrees from north. Customer booking maps stay north-up.
  final double bearingDeg;

  CustomerBookingMapCamera copyWith({
    FluxidiMapLonLat? center,
    double? zoom,
    double? bearingDeg,
  }) {
    return CustomerBookingMapCamera(
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      bearingDeg: bearingDeg ?? this.bearingDeg,
    );
  }
}

double customerBookingMercatorX(double lon) => (lon + 180.0) / 360.0;

double customerBookingMercatorY(double lat) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180.0;
  return (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2;
}

double customerBookingLonFromX(double x) => x * 360.0 - 180.0;

double customerBookingLatFromY(double y) {
  final n = math.pi - 2 * math.pi * y;
  return 180.0 / math.pi * math.atan((math.exp(n) - math.exp(-n)) / 2);
}

double customerBookingWorldSize(double zoom) => 256.0 * math.pow(2.0, zoom);

Offset customerBookingRotateOffset(Offset offset, double bearingDeg) {
  if (bearingDeg.abs() < 0.01) return offset;
  final rad = -bearingDeg * math.pi / 180.0;
  final cosA = math.cos(rad);
  final sinA = math.sin(rad);
  return Offset(
    offset.dx * cosA - offset.dy * sinA,
    offset.dx * sinA + offset.dy * cosA,
  );
}

double customerBookingRouteUpBearing(
  FluxidiMapLonLat origin,
  FluxidiMapLonLat destination,
) {
  final dx = customerBookingMercatorX(destination.lon) -
      customerBookingMercatorX(origin.lon);
  final dy = customerBookingMercatorY(destination.lat) -
      customerBookingMercatorY(origin.lat);
  if (dx.abs() < 1e-12 && dy.abs() < 1e-12) return 0;
  return math.atan2(dx, -dy) * 180.0 / math.pi;
}

Offset customerBookingProject(
  FluxidiMapLonLat point,
  CustomerBookingMapCamera camera,
  Size size,
) {
  final scale = customerBookingWorldSize(camera.zoom);
  final rotated = customerBookingRotateOffset(
    Offset(
      (customerBookingMercatorX(point.lon) -
              customerBookingMercatorX(camera.center.lon)) *
          scale,
      (customerBookingMercatorY(point.lat) -
              customerBookingMercatorY(camera.center.lat)) *
          scale,
    ),
    camera.bearingDeg,
  );
  return Offset(
    size.width / 2 + rotated.dx,
    size.height / 2 + rotated.dy,
  );
}

FluxidiMapLonLat customerBookingUnproject(
  Offset pixel,
  CustomerBookingMapCamera camera,
  Size size,
) {
  final scale = customerBookingWorldSize(camera.zoom);
  final rotated = customerBookingRotateOffset(
    Offset(pixel.dx - size.width / 2, pixel.dy - size.height / 2),
    -camera.bearingDeg,
  );
  final x = customerBookingMercatorX(camera.center.lon) + rotated.dx / scale;
  final y = customerBookingMercatorY(camera.center.lat) + rotated.dy / scale;
  return FluxidiMapLonLat(customerBookingLonFromX(x), customerBookingLatFromY(y));
}

CustomerBookingMapCamera customerBookingPanCamera(
  CustomerBookingMapCamera camera,
  Offset delta,
) {
  final scale = customerBookingWorldSize(camera.zoom);
  final mercatorDelta = customerBookingRotateOffset(delta, -camera.bearingDeg);
  final x = customerBookingMercatorX(camera.center.lon) - mercatorDelta.dx / scale;
  final y = customerBookingMercatorY(camera.center.lat) - mercatorDelta.dy / scale;
  return camera.copyWith(
    center: FluxidiMapLonLat(
      customerBookingLonFromX(x),
      customerBookingLatFromY(y),
    ),
  );
}

CustomerBookingMapCamera customerBookingZoomCamera({
  required CustomerBookingMapCamera camera,
  required Size size,
  required Offset focal,
  required double nextZoom,
}) {
  final zoom = nextZoom.clamp(
    kCustomerBookingMapMinZoom,
    kCustomerBookingMapMaxZoom,
  );
  if (zoom == camera.zoom) return camera;
  final held = customerBookingUnproject(focal, camera, size);
  final zoomed = camera.copyWith(zoom: zoom);
  final projected = customerBookingProject(held, zoomed, size);
  return customerBookingPanCamera(zoomed, focal - projected);
}

double _zoomForSpan(double span01, double pixels, double padding) {
  if (!span01.isFinite || span01 <= 1e-12) return 13.5;
  final usable = math.max(80.0, pixels - 2 * padding);
  final zoom = math.log(usable / (span01 * 256.0)) / math.ln2;
  return zoom.clamp(kCustomerBookingMapMinZoom, kCustomerBookingMapMaxZoom);
}

CustomerBookingMapCamera customerBookingFitCamera({
  required List<FluxidiMapLonLat> points,
  required Size size,
  double padding = 56,
  EdgeInsets contentInsets = EdgeInsets.zero,
  FluxidiMapLonLat? origin,
  FluxidiMapLonLat? destination,
}) {
  final usable = Size(
    math.max(80.0, size.width - contentInsets.horizontal),
    math.max(80.0, size.height - contentInsets.vertical),
  );
  if (points.isEmpty || usable.width <= 0 || usable.height <= 0) {
    return const CustomerBookingMapCamera(
      center: FluxidiMapLonLat(4.35, 50.85),
      zoom: 8,
    );
  }
  const bearing = 0.0;
  var minX = 1.0;
  var maxX = 0.0;
  var minY = 1.0;
  var maxY = 0.0;
  for (final point in points) {
    final x = customerBookingMercatorX(point.lon);
    final y = customerBookingMercatorY(point.lat);
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  final geoCenter = FluxidiMapLonLat(
    customerBookingLonFromX((minX + maxX) / 2),
    customerBookingLatFromY((minY + maxY) / 2),
  );
  var rotMinX = 0.0;
  var rotMaxX = 0.0;
  var rotMinY = 0.0;
  var rotMaxY = 0.0;
  var first = true;
  final cx = customerBookingMercatorX(geoCenter.lon);
  final cy = customerBookingMercatorY(geoCenter.lat);
  for (final point in points) {
    final rotated = customerBookingRotateOffset(
      Offset(
        customerBookingMercatorX(point.lon) - cx,
        customerBookingMercatorY(point.lat) - cy,
      ),
      bearing,
    );
    if (first) {
      rotMinX = rotMaxX = rotated.dx;
      rotMinY = rotMaxY = rotated.dy;
      first = false;
    } else {
      rotMinX = math.min(rotMinX, rotated.dx);
      rotMaxX = math.max(rotMaxX, rotated.dx);
      rotMinY = math.min(rotMinY, rotated.dy);
      rotMaxY = math.max(rotMaxY, rotated.dy);
    }
  }
  final zoom = math.min(
    _zoomForSpan(rotMaxX - rotMinX, usable.width, padding),
    _zoomForSpan(rotMaxY - rotMinY, usable.height, padding),
  );
  final fitted = CustomerBookingMapCamera(
    center: geoCenter,
    zoom: zoom,
    bearingDeg: bearing,
  );
  var sum = Offset.zero;
  for (final point in points) {
    sum += customerBookingProject(point, fitted, size);
  }
  final routeCenter = sum / points.length.toDouble();
  final holeCenter = Offset(
    contentInsets.left + usable.width / 2,
    contentInsets.top + usable.height / 2,
  );
  return customerBookingPanCamera(fitted, holeCenter - routeCenter);
}

List<Offset> customerBookingRoutePrefix(List<Offset> points, double t) {
  if (points.length < 2) return points;
  final progress = t.clamp(0.0, 1.0);
  if (progress <= 0) return <Offset>[points.first];
  if (progress >= 1) return points;
  final distances = <double>[0];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += (points[i] - points[i - 1]).distance;
    distances.add(total);
  }
  if (total <= 0) return <Offset>[points.first, points.last];
  final target = total * progress;
  final out = <Offset>[points.first];
  for (var i = 1; i < points.length; i++) {
    if (distances[i] < target) {
      out.add(points[i]);
      continue;
    }
    final span = distances[i] - distances[i - 1];
    final f = span <= 0 ? 1.0 : ((target - distances[i - 1]) / span);
    out.add(Offset.lerp(points[i - 1], points[i], f.clamp(0.0, 1.0))!);
    break;
  }
  return out;
}

String customerBookingRouteFingerprint({
  required FluxidiMapLonLat? pickup,
  required FluxidiMapLonLat? dropoff,
  List<FluxidiMapLonLat> stops = const <FluxidiMapLonLat>[],
}) {
  String coord(FluxidiMapLonLat? value) {
    if (value == null) return '';
    return '${value.lon.toStringAsFixed(5)},${value.lat.toStringAsFixed(5)}';
  }

  return <String>[
    coord(pickup),
    for (final stop in stops) coord(stop),
    coord(dropoff),
  ].join('|');
}

FluxidiMapLonLat? customerBookingLonLat(double? lat, double? lon) {
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
    return null;
  }
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return FluxidiMapLonLat(lon, lat);
}

Rect customerBookingVisibleMapHole(Size size, EdgeInsets insets) {
  final left = insets.left.clamp(0.0, size.width);
  final top = insets.top.clamp(0.0, size.height);
  final right = (size.width - insets.right).clamp(left + 48.0, size.width);
  final bottom = (size.height - insets.bottom).clamp(top + 48.0, size.height);
  return Rect.fromLTRB(left, top, right, bottom);
}

bool customerBookingPointInVisibleHole(
  Offset point,
  Size size,
  EdgeInsets insets, {
  double pad = 4,
}) {
  final hole = customerBookingVisibleMapHole(size, insets).deflate(pad);
  return hole.contains(point);
}

/// Real on-screen size of an endpoint chip, so placement reasons about the
/// widget that is actually drawn instead of a fixed guess.
Size customerBookingEndpointChipSize({
  required String text,
  double textScale = 1.0,
  bool hasEditIcon = false,
  double maxWidth = 168,
}) {
  const horizontalPadding = 20.0;
  const iconWidth = 16.0;
  const iconGap = 6.0;
  final editWidth = hasEditIcon ? 18.0 : 0.0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 11 * textScale,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final content = iconWidth + iconGap + painter.width + editWidth;
  // Height follows the taller of the icon and the scaled text, plus the
  // chip's vertical padding, so a larger text scale really grows the chip.
  return Size(
    math.min(maxWidth, horizontalPadding + content),
    math.max(iconWidth, painter.height) + 12.0,
  );
}

/// Where the two endpoint labels go, or the decision to fall back to compact
/// A/B markers with a fixed legend when they cannot both fit.
@immutable
class CustomerBookingEndpointPlacement {
  const CustomerBookingEndpointPlacement({
    this.pickup,
    this.dropoff,
    this.useCompactMarkers = false,
  });

  final Offset? pickup;
  final Offset? dropoff;
  final bool useCompactMarkers;
}

List<Offset> _labelCandidateOffsets(Size labelSize) {
  return <Offset>[
    Offset(12, -labelSize.height - 6),
    Offset(-labelSize.width - 8, -labelSize.height - 6),
    const Offset(12, 14),
    Offset(-labelSize.width - 8, 14),
    Offset(-labelSize.width / 2, -labelSize.height - 12),
    Offset(-labelSize.width / 2, 16),
    Offset(12, -labelSize.height / 2),
    Offset(-labelSize.width - 8, -labelSize.height / 2),
  ];
}

Rect _labelRect(Offset pos, Size labelSize) {
  return Rect.fromLTWH(pos.dx, pos.dy, labelSize.width, labelSize.height);
}

/// Places pickup and destination together. A pair is only accepted when the
/// two rectangles do not touch each other, the route markers or the metrics
/// badge; otherwise the caller switches to A/B markers plus a legend.
CustomerBookingEndpointPlacement customerBookingPlaceEndpointLabels({
  required Offset? pickupAnchor,
  required Offset? dropoffAnchor,
  required Size pickupSize,
  required Size dropoffSize,
  required Size size,
  required EdgeInsets visibleInsets,
  Rect? avoid,
  double minAnchorSeparation = 64,
}) {
  final hole = customerBookingVisibleMapHole(size, visibleInsets).deflate(6);

  Offset clampPos(Offset raw, Size labelSize) {
    final maxLeft = math.max(hole.left, hole.right - labelSize.width);
    final maxTop = math.max(hole.top, hole.bottom - labelSize.height);
    return Offset(
      raw.dx.clamp(hole.left, maxLeft),
      raw.dy.clamp(hole.top, maxTop),
    );
  }

  bool hitsMarker(Offset pos, Size labelSize, Offset? anchor) {
    if (anchor == null) return false;
    return _labelRect(pos, labelSize).inflate(4).contains(anchor);
  }

  bool hitsAvoid(Offset pos, Size labelSize) {
    if (avoid == null || avoid.isEmpty) return false;
    return _labelRect(pos, labelSize).inflate(6).overlaps(avoid);
  }

  if (pickupAnchor == null || dropoffAnchor == null) {
    final anchor = pickupAnchor ?? dropoffAnchor;
    final labelSize = pickupAnchor == null ? dropoffSize : pickupSize;
    if (anchor == null) return const CustomerBookingEndpointPlacement();
    Offset best = clampPos(anchor + _labelCandidateOffsets(labelSize).first, labelSize);
    var bestScore = -1e9;
    for (final candidate in _labelCandidateOffsets(labelSize)) {
      final pos = clampPos(anchor + candidate, labelSize);
      final score =
          (hitsMarker(pos, labelSize, anchor) ? -400.0 : 200.0) +
          (hitsAvoid(pos, labelSize) ? -500.0 : 80.0) -
          (pos - (anchor + candidate)).distance;
      if (score > bestScore) {
        bestScore = score;
        best = pos;
      }
    }
    return CustomerBookingEndpointPlacement(
      pickup: pickupAnchor == null ? null : best,
      dropoff: pickupAnchor == null ? best : null,
    );
  }

  // Two anchors this close leave no room for two readable address chips.
  if ((pickupAnchor - dropoffAnchor).distance < minAnchorSeparation) {
    return const CustomerBookingEndpointPlacement(useCompactMarkers: true);
  }

  Offset? bestPickup;
  Offset? bestDropoff;
  var bestScore = -1e9;
  for (final pickupCandidate in _labelCandidateOffsets(pickupSize)) {
    final pickupPos = clampPos(pickupAnchor + pickupCandidate, pickupSize);
    final pickupRect = _labelRect(pickupPos, pickupSize);
    final pickupPenalty =
        (hitsMarker(pickupPos, pickupSize, pickupAnchor) ? -400.0 : 100.0) +
        (hitsMarker(pickupPos, pickupSize, dropoffAnchor) ? -300.0 : 60.0) +
        (hitsAvoid(pickupPos, pickupSize) ? -500.0 : 60.0) -
        (pickupPos - (pickupAnchor + pickupCandidate)).distance;
    for (final dropoffCandidate in _labelCandidateOffsets(dropoffSize)) {
      final dropoffPos = clampPos(dropoffAnchor + dropoffCandidate, dropoffSize);
      final dropoffRect = _labelRect(dropoffPos, dropoffSize);
      // The whole point of pairwise placement: the two chips must not touch.
      if (pickupRect.inflate(4).overlaps(dropoffRect.inflate(4))) continue;
      final score =
          pickupPenalty +
          (hitsMarker(dropoffPos, dropoffSize, dropoffAnchor) ? -400.0 : 100.0) +
          (hitsMarker(dropoffPos, dropoffSize, pickupAnchor) ? -300.0 : 60.0) +
          (hitsAvoid(dropoffPos, dropoffSize) ? -500.0 : 60.0) -
          (dropoffPos - (dropoffAnchor + dropoffCandidate)).distance;
      if (score > bestScore) {
        bestScore = score;
        bestPickup = pickupPos;
        bestDropoff = dropoffPos;
      }
    }
  }

  if (bestPickup == null || bestDropoff == null) {
    return const CustomerBookingEndpointPlacement(useCompactMarkers: true);
  }
  return CustomerBookingEndpointPlacement(
    pickup: bestPickup,
    dropoff: bestDropoff,
  );
}

/// Keeps a compact label near [anchor] inside the visible map hole, away from
/// the route marker itself.
Offset customerBookingClampMapLabel({
  required Offset anchor,
  required Size size,
  required EdgeInsets visibleInsets,
  required Size labelSize,
  Offset nudge = const Offset(10, -38),
  Rect? avoid,
}) {
  final hole = customerBookingVisibleMapHole(size, visibleInsets).deflate(6);
  final maxLeft = math.max(hole.left, hole.right - labelSize.width);
  final maxTop = math.max(hole.top, hole.bottom - labelSize.height);

  Offset clampPos(Offset raw) {
    return Offset(
      raw.dx.clamp(hole.left, maxLeft),
      raw.dy.clamp(hole.top, maxTop),
    );
  }

  bool overlapsMarker(Offset pos) {
    return Rect.fromLTWH(
      pos.dx,
      pos.dy,
      labelSize.width,
      labelSize.height,
    ).inflate(4).contains(anchor);
  }

  bool overlapsAvoid(Offset pos) {
    if (avoid == null || avoid.isEmpty) return false;
    return Rect.fromLTWH(
      pos.dx,
      pos.dy,
      labelSize.width,
      labelSize.height,
    ).inflate(6).overlaps(avoid);
  }

  final candidates = <Offset>[
    nudge,
    Offset(-labelSize.width - 8, -36),
    const Offset(12, 14),
    Offset(-labelSize.width - 8, 14),
    Offset(-labelSize.width / 2, -40),
    Offset(12, -labelSize.height - 12),
  ];
  Offset best = clampPos(anchor + nudge);
  var bestScore = -1e9;
  for (final candidate in candidates) {
    final pos = clampPos(anchor + candidate);
    final overlap = overlapsMarker(pos);
    final blocked = overlapsAvoid(pos);
    final clampedAway = (pos - (anchor + candidate)).distance;
    final score =
        (overlap ? -400.0 : 200.0) + (blocked ? -500.0 : 80.0) - clampedAway;
    if (score > bestScore) {
      bestScore = score;
      best = pos;
    }
  }
  return best;
}
