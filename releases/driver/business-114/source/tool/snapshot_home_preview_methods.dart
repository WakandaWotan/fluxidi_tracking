import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';
void main(){
 final src=File('D:/Projecten/fluxidi_maplibre_poc_20261014/evidence/home-route-preview/driver-state-before.dart').readAsStringSync();
 final unit=parseString(content:src).unit;
 final methods={for(final c in unit.declarations.whereType<ClassDeclaration>())for(final m in c.members.whereType<MethodDeclaration>())m.name.lexeme:m.body.toSource()};
 Directory('test/navigation/fixtures').createSync(recursive:true);
 File('test/navigation/fixtures/home_route_preview_before_methods.json').writeAsStringSync(jsonEncode({'hashes':methods.map((k,v)=>MapEntry(k,sha256.convert(utf8.encode(v)).toString())),'loaderPrefix':methods['_loadNextRideRoutePreview']!.split('final staticUrl =').first}));
}
