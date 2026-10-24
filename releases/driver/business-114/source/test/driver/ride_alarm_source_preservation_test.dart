import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocalizedLiterals extends RecursiveAstVisitor<void>{
 final values=<String>{};
 @override void visitSimpleStringLiteral(SimpleStringLiteral node){
   if(node.value.runes.any((r)=>r>127))values.add(node.value);
   super.visitSimpleStringLiteral(node);
 }
}
void main(){
 for(final name in ['driver_ride_alert.dart','driver_ride_alert_controller.dart','driver_ride_offer_host.dart','driver_ride_frame_border.dart']){
  test('existing localized literals remain exact in $name',(){
   final old=_LocalizedLiterals(),current=_LocalizedLiterals();
   parseString(content:File('test/driver/fixtures/alarm_before/$name').readAsStringSync()).unit.accept(old);
   parseString(content:File('lib/driver/$name').readAsStringSync()).unit.accept(current);
   expect(current.values,containsAll(old.values));
  });
 }
 test('permission and manifest contracts remain available',(){
   final manifest=File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
   expect(manifest,contains('android.permission.VIBRATE'));expect(manifest,contains('android.permission.POST_NOTIFICATIONS'));
   expect(manifest,contains('android.permission.FOREGROUND_SERVICE_LOCATION'));
 });
}
