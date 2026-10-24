import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/maps/fluxidi_maplibre_route_preview.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';
void main(){
 test('Outbound and return remain separate road lines without invented connectors',(){
 final data=fluxidiPreviewRouteGeoJson([[const FluxidiMapLonLat(4.3,50.8),const FluxidiMapLonLat(4.4,50.9)],[const FluxidiMapLonLat(5,51),const FluxidiMapLonLat(5.1,51.1)]]);
 expect((data['features'] as List).length,2);
 expect((data['features'] as List).first['geometry']['coordinates'],[[4.3,50.8],[4.4,50.9]]);
 });
 test('Missing or invalid route never becomes a direct pickup-destination line',(){
 expect(fluxidiPreviewRouteGeoJson([])['features'],isEmpty);
 expect(fluxidiPreviewRouteGeoJson([[const FluxidiMapLonLat(4,50)]])['features'],isEmpty);
 expect(fluxidiPreviewRouteGeoJson([[FluxidiMapLonLat(double.nan,50),const FluxidiMapLonLat(4,50)]])['features'],isEmpty);
 });
}
