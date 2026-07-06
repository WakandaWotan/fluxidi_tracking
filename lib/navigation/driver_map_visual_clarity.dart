import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'driver_navigation_map_config.dart';

/// Best-effort POI / label clutter reduction after a style load.
///
/// Layer IDs vary by Mapbox style revision; failures are ignored silently.
Future<void> applyDriverMapVisualClarity({
  required mb.StyleManager style,
  required DriverMapVisualMode visualMode,
}) async {
  if (!kDriverMapClutterReductionEnabled) return;
  if (visualMode == DriverMapVisualMode.satellite) return;

  for (final layerId in kDriverMapClutterLayerIds) {
    try {
      await style.setStyleLayerProperty(layerId, 'visibility', 'none');
    } catch (_) {}
  }
}

String driverMapVisualModeLogLabel(DriverMapVisualMode mode) {
  switch (mode) {
    case DriverMapVisualMode.street:
      return 'street';
    case DriverMapVisualMode.satellite:
      return 'satellite';
  }
}
