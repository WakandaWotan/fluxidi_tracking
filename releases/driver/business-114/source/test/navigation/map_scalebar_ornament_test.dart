// MapLibre has no Mapbox scale-bar ornament. Preserve the original requirement:
// no measurement overlay, no blocking ornament request and attribution retained.
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
 final source=File('lib/main_parts/driver_home_page_state.dart').readAsStringSync();
 final surface=File('lib/navigation/rendering/driver_maplibre_surface.dart').readAsStringSync();
 final unit=parseString(content:source).unit;
 String method(String name)=>unit.declarations.whereType<ClassDeclaration>()
   .expand((c)=>c.members.whereType<MethodDeclaration>()).singleWhere((m)=>m.name.lexeme==name).body.toSource();
 final created=method('_onMapCreated'), helper=method('_hideMapboxScaleBarBestEffort');
 test('Original map creation still runs the nonblocking ornament hook before style apply',(){
  expect(created,contains('unawaited(_hideMapboxScaleBarBestEffort(mapboxMap))'));
  expect(created.indexOf('_hideMapboxScaleBarBestEffort('),lessThan(created.indexOf('_applyMapStyleForMode(')));
 });
 test('MapLibre hook records absence without invoking a nonexistent ornament channel',(){
  expect(helper,contains("debugPrint('[MAPLIBRE][SCALEBAR] absent')"));
  for(final forbidden in ['.scaleBar.', 'invokeMethod', 'http.', 'await ', 'throw ', 'rethrow']){
   expect(helper,isNot(contains(forbidden)));
  }
 });
 test('The actual native surface uses MapLibre without a scale-bar control',(){
  expect(surface,contains('libre.MapLibreMap('));
  expect(surface,isNot(contains('ScaleBarSettings')));
  expect(surface,isNot(contains('.scaleBar')));
 });
 test('Dataset attribution remains attached to the vector source',(){
  expect(surface,contains("'attribution':fluxidiMapAttribution"));
  expect(surface,contains("'type':'vector'"));
  expect(source,isNot(contains('.attribution.updateSettings(')));
  expect(source,isNot(contains('.logo.updateSettings(')));
 });
}
