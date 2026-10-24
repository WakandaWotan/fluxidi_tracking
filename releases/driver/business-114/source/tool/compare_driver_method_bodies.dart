import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

Map<String,String> bodies(String path) {
  final unit=parseString(content:File(path).readAsStringSync(),
      path:path,throwIfDiagnostics:false).unit;
  return {for(final declaration in unit.declarations.whereType<ClassDeclaration>())
    for(final member in declaration.members.whereType<MethodDeclaration>())
      '${declaration.name.lexeme}.${member.name.lexeme}':member.body.toSource()};
}
void main() {
  final original=bodies('D:/Projecten/_flutter_work/fluxidi_business_driver_offer_ui_20261014/lib/main_parts/driver_home_page_state.dart');
  final candidate=bodies('lib/main_parts/driver_home_page_state.dart');
  final changed=original.keys.where((name)=>candidate[name]!=original[name]).toList();
  final report={'scope':'Exact AST method-body comparison; not runtime or end-to-end acceptance',
    'originalMethods':original.length,'candidateMethods':candidate.length,
    'identicalBodies':original.length-changed.length,'changedBodies':changed,
    'removed':original.keys.where((name)=>!candidate.containsKey(name)).toList(),
    'added':candidate.keys.where((name)=>!original.containsKey(name)).toList()};
  File('../driver-method-body-comparison.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(jsonEncode(report));
}
