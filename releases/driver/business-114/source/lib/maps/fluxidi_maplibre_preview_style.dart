import 'fluxidi_map_source_config.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
String customerTrackingMapAssetBase(String value) => fluxidiMapAssetBase(value);

Future<String> customerBookingBasemapStyle(bool dark) async {
    
    final data=jsonDecode(await rootBundle.loadString(
        'assets/fluxidi_maplibre/styles/${dark?'dark':'light'}.json')) as Map<String,dynamic>;
    // Match the already validated country-server style/license scope.
    data['layers']=(data['layers'] as List).where(
        (layer)=>layer['source-layer']!='landcover').toList();
    final base=customerTrackingMapAssetBase(const String.fromEnvironment(
        'FLUXIDI_MAP_ASSET_BASE_URL',defaultValue:''));
    data['glyphs']='$base/data/full/fonts/{fontstack}/{range}.pbf';
    data['sprite']='$base/data/full/sprites/${dark?'dark':'light'}';
    data['sources']={'osm':{'type':'vector','tiles':[
      '$base/country/releases/be-nl-20261013-rectangle-v1/tiles/{z}/{x}/{y}.mvt'],
      'minzoom':0,'maxzoom':15,'bounds':[2,49.1,7.8,54],
      'attribution':fluxidiMapAttribution}};

return jsonEncode(data);
}
