import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/app_strings.dart';

double _contrast(Color a, Color b) {
 final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
 final darker = a.computeLuminance() > b.computeLuminance() ? b : a;
 return (lighter.computeLuminance()+0.05)/(darker.computeLuminance()+0.05);
}
void main() {
 for (final edit in [false,true]) {
 testWidgets('fallback picker and preview in ${edit ? "edit" : "add"} vehicle form',(tester) async {
 final old=vehiclesNotifier.value;
 addTearDown(()=>vehiclesNotifier.value=old);
 for(final name in ['plugins.flutter.io/shared_preferences','plugins.it_nomads.com/flutter_secure_storage']) {
 final channel=MethodChannel(name);
 TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async=>call.method=='getAll'?<String,Object>{}:null);
 addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));
 }
 const vehicle=VehicleProfile(id:'fixture_vito',vehicleName:'Fixture Vito',brandModel:'Mercedes Vito',licensePlate:'FIXTURE',color:'black',passengerCapacity:8,luggageCapacity:8,tierId:'comfort',isActive:true,driverId:null,primaryPhotoRef:'',galleryPhotoRefs:[],fallbackAsset:kCompanyPlanFallbackMinibus);
 vehiclesNotifier.value=edit?[vehicle]:[];
 tester.view.physicalSize=const Size(1000,1800);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
 await http.runWithClient(() async {
 await tester.pumpWidget(MaterialApp(home:VehicleManagementPage(autoOpenNewVehicleEditor:!edit,openVehicleId:edit?vehicle.id:null)));
 await tester.pumpAndSettle();
 final picker=find.byKey(const ValueKey('vehicle_fallback_picker'));
 expect(picker,findsOneWidget);
 final field=tester.widget<DropdownButtonFormField<String>>(picker);
 expect(field.initialValue,edit?kCompanyPlanFallbackMinibus:'');
 final initialPreview=tester.widget<Image>(find.byKey(const ValueKey('vehicle_fallback_preview')));
 expect((initialPreview.image as AssetImage).assetName,edit?kCompanyPlanFallbackMinibus:kCompanyPlanFallbackSedan);
 field.onChanged!(kCompanyPlanFallbackSedan);
 await tester.pump();
 final preview=tester.widget<Image>(find.byKey(const ValueKey('vehicle_fallback_preview')));
 expect((preview.image as AssetImage).assetName,kCompanyPlanFallbackSedan);expect(preview.fit,BoxFit.contain);
 field.onChanged!(kCompanyPlanFallbackHummerStretch);
 await tester.pump();
 final hummerPreview=tester.widget<Image>(find.byKey(const ValueKey('vehicle_fallback_preview')));
 expect((hummerPreview.image as AssetImage).assetName,kCompanyPlanFallbackHummerStretch);
 expect(vehiclesNotifier.value,edit?[vehicle]:isEmpty);
 await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
 },()=>MockClient((request) async=>http.Response('{}',200)));
 });
 }

 testWidgets('disabled public-photo action remains readable in the light editor',(tester) async {
  final oldVehicles=vehiclesNotifier.value;
  final oldTheme=businessThemeNotifier.value;
  final oldLanguage=appLanguageNotifier.value;
  addTearDown(() { vehiclesNotifier.value=oldVehicles; businessThemeNotifier.value=oldTheme; appLanguageNotifier.value=oldLanguage; });
  appLanguageNotifier.value=AppLanguage.nl;
  businessThemeNotifier.value=BusinessThemeVariant.cleanProfessional;
  vehiclesNotifier.value=[];
  for(final name in ['plugins.flutter.io/shared_preferences','plugins.it_nomads.com/flutter_secure_storage']) {
   final channel=MethodChannel(name);
   TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async=>call.method=='getAll'?<String,Object>{}:null);
   addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));
  }
  tester.view.physicalSize=const Size(1000,1800);
  tester.view.devicePixelRatio=1;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
   await tester.pumpWidget(const MaterialApp(home:VehicleManagementPage(autoOpenNewVehicleEditor:true)));
   await tester.pumpAndSettle();
   final action=find.ancestor(
    of:find.text('Gebruik als publieke foto'),
    matching:find.byWidgetPredicate((widget)=>widget is OutlinedButton),
   );
   expect(action,findsOneWidget);
   final button=tester.widget<OutlinedButton>(action);
   expect(button.onPressed,isNull);
   final foreground=button.style!.foregroundColor!.resolve({MaterialState.disabled})!;
   final background=button.style!.backgroundColor!.resolve({MaterialState.disabled})!;
   expect(_contrast(foreground,background),greaterThanOrEqualTo(4.5));
   await tester.pumpWidget(const SizedBox());
   await tester.pumpAndSettle();
  },()=>MockClient((request) async=>http.Response('{}',200)));
 });
}
