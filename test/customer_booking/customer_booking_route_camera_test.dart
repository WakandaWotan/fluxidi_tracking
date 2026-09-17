import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

void main() {
  test('fit camera frames pickup and dropoff inside the viewport', () {
    const pickup = FluxidiMapLonLat(3.63, 50.80);
    const dropoff = FluxidiMapLonLat(4.48, 50.90);
    final camera = customerBookingFitCamera(
      points: const [pickup, dropoff],
      size: const Size(800, 600),
    );
    final a = customerBookingProject(pickup, camera, const Size(800, 600));
    final b = customerBookingProject(dropoff, camera, const Size(800, 600));
    expect(a.dx, inInclusiveRange(40, 760));
    expect(a.dy, inInclusiveRange(40, 560));
    expect(b.dx, inInclusiveRange(40, 760));
    expect(b.dy, inInclusiveRange(40, 560));
    expect((a - b).distance, greaterThan(80));
  });

  test('route prefix walks along the line once', () {
    const points = <Offset>[
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
    ];
    expect(customerBookingRoutePrefix(points, 0).length, 1);
    final half = customerBookingRoutePrefix(points, 0.5);
    expect(half.last.dx, closeTo(100, 0.01));
    expect(half.last.dy, closeTo(0, 0.01));
    expect(customerBookingRoutePrefix(points, 1), points);
  });

  test('route fingerprint ignores unrelated form fields', () {
    const a = FluxidiMapLonLat(4.35, 50.85);
    const b = FluxidiMapLonLat(4.48, 50.90);
    expect(
      customerBookingRouteFingerprint(pickup: a, dropoff: b),
      customerBookingRouteFingerprint(pickup: a, dropoff: b),
    );
    expect(
      customerBookingRouteFingerprint(pickup: a, dropoff: b),
      isNot(customerBookingRouteFingerprint(pickup: a, dropoff: const FluxidiMapLonLat(4.50, 50.90))),
    );
  });
}
