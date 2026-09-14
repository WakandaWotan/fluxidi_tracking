import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/navigation/mapbox_platform_support.dart';

const Key kUnsupportedMapboxSurfaceKey = Key('unsupported_mapbox_surface');

/// Keeps existing map callers compiling when the Mapbox plugin has no host.
class UnsupportedMapboxSurface extends StatelessWidget {
  const UnsupportedMapboxSurface({
    super.key,
    this.message,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text =
        message ??
        'De kaartplugin ontbreekt op dit platform. De bestaande rit- en '
            'dekkingslogica blijft ongewijzigd; alleen de kaartweergave is '
            'hier niet beschikbaar.';
    return ColoredBox(
      key: kUnsupportedMapboxSurfaceKey,
      color: const Color(0xFF121318),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB8BDC9),
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

Widget mapboxSurfaceOrUnsupported({
  required Widget Function() buildMap,
  String? unsupportedMessage,
}) {
  if (!kMapboxMapsPluginSupported) {
    return UnsupportedMapboxSurface(message: unsupportedMessage);
  }
  return buildMap();
}
