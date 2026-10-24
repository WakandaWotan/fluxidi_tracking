import 'mapbox_platform_support_stub.dart'
    if (dart.library.io) 'mapbox_platform_support_io.dart'
    as impl;

/// True only where mapbox_maps_flutter registers a native plugin.
bool get kMapboxMapsPluginSupported => impl.mapboxMapsPluginSupported;
