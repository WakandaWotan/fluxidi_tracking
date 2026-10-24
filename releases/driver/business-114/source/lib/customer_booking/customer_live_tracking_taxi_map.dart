import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_driver_map_frame.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart'
    show kDriverTaxiMarkerAssetPath;

/// The same yellow taxi artwork used by Fluxidi Driver navigation.
/// This is only presentation: it does not own location, requests or timers.
class CustomerLiveTrackingTaxiMap extends StatelessWidget {
  const CustomerLiveTrackingTaxiMap({super.key, required this.frame,
    required this.mapImage, this.heading, this.showVehicle = true});
  final FluxidiStaticDriverMapFrame frame;
  final Widget mapImage;
  final double? heading;
  final bool showVehicle;

  @override
  Widget build(BuildContext context) {
    final angle = heading;
    return AspectRatio(
      aspectRatio: frame.width / frame.height,
      child: LayoutBuilder(builder: (context, size) {
        const taxiSize = 72.0;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(child: mapImage),
          if (showVehicle) Positioned(
            left: frame.driverX * size.maxWidth - taxiSize / 2,
            top: frame.driverY * size.maxHeight - taxiSize / 2,
            width: taxiSize, height: taxiSize,
            child: IgnorePointer(child: Transform.rotate(
              angle: angle != null && angle.isFinite ? angle * math.pi / 180 : 0,
              child: Image.asset(kDriverTaxiMarkerAssetPath,
                key: const ValueKey('customer-live-taxi'), fit: BoxFit.contain),
            )),
          ),
        ]);
      }),
    );
  }
}
