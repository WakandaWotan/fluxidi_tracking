// Renderer configuration only. Existing navigation and tracking remain authoritative.
const fluxidiMapAttribution = 'Protomaps · © OpenStreetMap contributors · Natural Earth · © ESA WorldCover project 2020 / Contains modified Copernicus Sentinel data (2020) processed by ESA WorldCover consortium';
String fluxidiMapAssetBase(String value, {bool releaseMode = const bool.fromEnvironment('dart.vm.product')}) {
  var selected = value;
  if (selected.isEmpty) {
    if (releaseMode) throw StateError('FLUXIDI_MAP_ASSET_BASE_URL HTTPS release configuration is required');
    selected = 'http://127.0.0.1:8803';
  }
  final uri = Uri.parse(selected);
  final local = ['127.0.0.1', 'localhost', '::1'].contains(uri.host);
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
      uri.host == 'mapbox.com' || uri.host.endsWith('.mapbox.com') ||
      !(uri.scheme == 'https' || !releaseMode && local && uri.scheme == 'http') ||
      releaseMode && (local || !['maps.fluxidi.com', 'fluxidi-maplibre-be-nl.fluxidi.workers.dev'].contains(uri.host)) || uri.pathSegments.contains('..')) {
    throw ArgumentError('An own HTTPS map origin is required for release');
  }
  if (releaseMode && uri.path != '/r/be-nl-20261013-rectangle-v1') {
    throw ArgumentError('The pinned BE/NL map release path is required');
  }
  return selected.replaceAll(RegExp(r'/+$'), '');
}
