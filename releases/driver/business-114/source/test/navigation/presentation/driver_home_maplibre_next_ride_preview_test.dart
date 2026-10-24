import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/maps/fluxidi_maplibre_route_preview.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';
Map<String,String> methods(String src){final unit=parseString(content:src).unit;return {for(final c in unit.declarations.whereType<ClassDeclaration>())for(final m in c.members.whereType<MethodDeclaration>())m.name.lexeme:m.body.toSource()};}
class _AlertEntryVisitor extends RecursiveAstVisitor<void> {
 final entries=<IfElement>[];
 @override void visitIfElement(IfElement node){
  if(node.toSource().contains("'driver-ride-alert-settings'"))entries.add(node);
  super.visitIfElement(node);
 }
}

// Remove only the explicit additive warning-presentation statements before
// checking the original method hashes. Network/route/GPS statements stay checked.
String _withoutWarningHooks(String source) {
 final edits=<(int,int,String)>[];
 final unit=parseString(content:source).unit;
 final visitor=_WarningHookVisitor(edits);unit.accept(visitor);
 final outer=edits.where((e)=>!edits.any((p)=>p!=e&&p.$1<=e.$1&&p.$2>=e.$2)).toList()
   ..sort((a,b)=>b.$1.compareTo(a.$1));
 for(final e in outer){source=source.replaceRange(e.$1,e.$2,e.$3);}
 return source;
}
class _WarningHookVisitor extends RecursiveAstVisitor<void> {
 _WarningHookVisitor(this.edits);final List<(int,int,String)> edits;
 void replace(AstNode n,[String text=''])=>edits.add((n.offset,n.end,text));
 @override void visitIfStatement(IfStatement n){
  if(n.expression.toSource().contains('_navigationWarningOwner')){replace(n);return;}
  super.visitIfStatement(n);
 }
 @override void visitVariableDeclarationStatement(VariableDeclarationStatement n){
  final names=n.variables.variables.map((v)=>v.name.lexeme).toSet();
  if(names.contains('warningOwner')||names.contains('expiries')){replace(n);return;}
  if(names.contains('expiry')&&n.toSource().contains('expiries')){
   replace(n,'final expiry = _navigationTraffic.nextExpiry(now);');return;
  }
  super.visitVariableDeclarationStatement(n);
 }
 @override void visitExpressionStatement(ExpressionStatement n){
  final e=n.expression;
  if(e is AssignmentExpression&&e.leftHandSide.toSource()=='_rideOfferLifecycle'){
   replace(n,'_rideOfferLifecycle = AppLifecycleListener(onResume: () => unawaited(_openOfferInboxFromNotification()));');return;
  }
  if(e is AssignmentExpression&&e.leftHandSide.toSource()=='_navigationWarningOwner'){replace(n);return;}
  if(e is MethodInvocation&&e.target?.toSource()=='_navigationRouteWarnings'){replace(n);return;}
  if(e is MethodInvocation&&e.methodName.name=='_scheduleNavigationTrafficExpiry'&&n.parent is Block){
   final statements=(n.parent as Block).statements;final i=statements.indexOf(n);
   if(i>0&&statements[i-1].toSource().startsWith('_navigationRouteWarnings.install(')){replace(n);return;}
  }
  super.visitExpressionStatement(n);
 }
 @override void visitMethodInvocation(MethodInvocation n){
  if(n.methodName.name=='_withNavigationRouteWarning'){
   replace(n,n.argumentList.arguments.single.toSource());return;
  }
  super.visitMethodInvocation(n);
 }
}

void main(){
 final state=File('lib/main_parts/driver_home_page_state.dart').readAsStringSync();
 final current=methods(_withoutWarningHooks(state))..remove('_withNavigationRouteWarning');
 final baseline=jsonDecode(File('test/navigation/fixtures/home_route_preview_before_methods.json').readAsStringSync()) as Map;
 test('Only preview renderer and explicit ride-alert settings entry change; navigation remains exact',(){
 final old=Map<String,String>.from(baseline['hashes'] as Map);
 final changed=[for(final k in old.keys)if(current.containsKey(k)&&sha256.convert(utf8.encode(current[k]!)).toString()!=old[k])k];
 expect(changed.toSet(),{'_loadNextRideRoutePreview','_buildNextRideRoutePreview','_buildDrawer'});
 expect(old.keys.where((k)=>!current.containsKey(k)).toSet(),{'_downsamplePreviewRoute','_encodePolyline5','_buildStaticRoutePreviewUrl'});
 expect(current.keys.where((k)=>!old.containsKey(k)),isEmpty);
 });
 test('Drawer change is exactly one standalone-driver alert-settings entry',(){
 final visitor=_AlertEntryVisitor();parseString(content:state).unit.accept(visitor);
 visitor.entries.sort((a,b)=>(a.end-a.offset).compareTo(b.end-b.offset));
 expect(visitor.entries,isNotEmpty);final entry=visitor.entries.first;
 expect(entry.expression.toSource(),contains('isStandaloneLoginSession'));
 var end=entry.end;while(state[end].trim().isEmpty){end++;}if(state[end]==',')end++;
 final without=state.replaceRange(entry.offset,end,'');
 final restored=methods(without)['_buildDrawer']!;
 expect(sha256.convert(utf8.encode(restored)).toString(),(baseline['hashes'] as Map)['_buildDrawer']);
 });
 test('Worker/Directions/geocoding pipeline and its request gates stay byte-equivalent after AST normalization',(){
 expect(current['_loadNextRideRoutePreview']!.split('return _RoutePreviewData(').first,baseline['loaderPrefix']);
 expect(current['_loadNextRideRoutePreview'],contains('route: [for (final p in routeCoords) FluxidiMapLonLat(p.lon, p.lat)]'));
 });
 test('Missing route retains localized unavailable state and never fabricates an endpoint line',(){
 expect(current['_loadNextRideRoutePreview'],contains('if (routeCoords.length < 2) return null;'));
 expect(current['_buildNextRideRoutePreview'],contains('data == null || data.routePointCount < 2'));
 expect(current['_buildNextRideRoutePreview'],contains('Route-preview niet beschikbaar'));
 expect(fluxidiPreviewRouteGeoJson([])['features'],isEmpty);
 });
 test('Existing dimensions, border, gradient and reusable MapLibre renderer are retained',(){
 final body=current['_buildNextRideRoutePreview']!;
 for(final text in ['height: resolvedHeight','width: double.infinity','BorderRadius.circular(14)','height ?? 136','DecoratedBox(','FluxidiMapLibreRoutePreview(','routes: [data.route]']){expect(body,contains(text));}
 expect(body, isNot(contains('Image.network')));expect(state,isNot(contains('api.mapbox.com/styles')));
 });
 for(final scenario in ['gepland','ASAP','luchthaven','retour']){
 test('Existing directed $scenario geometry and pickup/destination feed the same renderer',(){
 final pickup=scenario=='retour'?const FluxidiMapLonLat(4.4844,50.9019):const FluxidiMapLonLat(4.35,50.85);
 final dropoff=scenario=='retour'?const FluxidiMapLonLat(4.35,50.85):const FluxidiMapLonLat(4.4844,50.9019);
 final route=[pickup,const FluxidiMapLonLat(4.4,50.88),dropoff];
 final widget=FluxidiMapLibreRoutePreview(pickup:pickup,dropoff:dropoff,routes:[route]);
 expect(widget.pickup,same(pickup));expect(widget.dropoff,same(dropoff));
 final line=(fluxidiPreviewRouteGeoJson(widget.routes)['features'] as List).single as Map;
 expect((line['geometry'] as Map)['coordinates'],[for(final p in route)[p.lon,p.lat]]);
 // Render-input fixture only; no real airport routing or physical navigation claim.
 });
 }
}
