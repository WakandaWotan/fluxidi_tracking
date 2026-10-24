import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class Buttons extends RecursiveAstVisitor<void> {
  final values = <String, String>{};
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.toSource();
    if (name == 'FilledButton.icon' || name == 'OutlinedButton.icon') {
      final onPressed = node.argumentList.arguments.whereType<NamedExpression>()
          .singleWhere((e) => e.name.label.name == 'onPressed');
      values[name] = onPressed.expression.toSource();
    }
    super.visitInstanceCreationExpression(node);
  }
}

void main() {
  const out = 'D:/Projecten/outputs/business_driver_offer_ui_20261014';
  const before = '$out/checkpoint';
  final checks = <String, Object>{};
  String read(String root, String path) => File('$root/$path').readAsStringSync();
  CompilationUnit unit(String root, String path) => parseString(content: read(root, path)).unit;
  const host = 'lib/driver/driver_ride_offer_host.dart';
  Map<String, String> methods(CompilationUnit u) => {
    for (final cls in u.declarations.whereType<ClassDeclaration>())
      for (final m in cls.members.whereType<MethodDeclaration>())
        '${cls.name.lexeme}.${m.name.lexeme}': m.toSource(),
  };
  final oldMethods = methods(unit(before, host));
  final newMethods = methods(unit(Directory.current.path, host));
  final changed = oldMethods.keys.where((k) => oldMethods[k] != newMethods[k]).toList();
  checks['hostMethodsChanged'] = changed;
  checks['hostOnlyBuildChanged'] = changed.length == 1 && changed.single == '_DriverRideOfferHostState.build';
  checks['hostNoMethodAddedOrRemoved'] = oldMethods.keys.toSet().difference(newMethods.keys.toSet()).isEmpty &&
    newMethods.keys.toSet().difference(oldMethods.keys.toSet()).isEmpty;
  const panel = 'lib/driver/driver_ride_offer_panel.dart';
  final a = Buttons(); final b = Buttons(); unit(before, panel).accept(a); unit(Directory.current.path, panel).accept(b);
  checks['buttonGuardsAndCallbacksSame'] = jsonEncode(a.values) == jsonEncode(b.values);
  final oldPanel = methods(unit(before, panel)); final newPanel = methods(unit(Directory.current.path, panel));
  checks['pickupTimeFormattingSame'] = oldPanel['DriverRideOfferPanel._pickupTime'] == newPanel['DriverRideOfferPanel._pickupTime'];
  checks['offerModelAndClientByteSame'] = read(before, 'lib/driver/driver_ride_offer.dart') == read(Directory.current.path, 'lib/driver/driver_ride_offer.dart');
  checks['noHttpAsyncOrTimerInPresentationHelper'] = !RegExp(r'http|Timer|Future<|async|fetch\(')
    .hasMatch(read(Directory.current.path, 'lib/driver/driver_ride_offer_presentation.dart'));
  File('$out/CONTROL_PRESERVATION.json').writeAsStringSync('${jsonEncode(checks)}\n');
  stdout.writeln(jsonEncode(checks));
  if (checks.values.whereType<bool>().any((v) => !v)) throw StateError('operational_drift');
}
