import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();late Directory temp;
 const scope={'tenant_id':'T','company_id':'C','vehicle_id':'V0','device_id':'old'};
 setUp(() {temp=Directory.systemTemp.createTempSync('fluxidi-transition-cleanup-');FlutterSecureStorage.setMockInitialValues({});activeDriverSessionNotifier.value=null;nativeDriverDutySessionNotifier.value=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),(_)async=>temp.path);});
 tearDown(()async{activeDriverSessionNotifier.value=null;nativeDriverDutySessionNotifier.value=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),null);if(!temp.absolute.path.startsWith(Directory.systemTemp.absolute.path))throw StateError('outside temp');await temp.delete(recursive:true);});
 Future<void> save(String company,{String vehicle='V0'})=>DriverSessionStore.instance.saveVerifiedDriverPairingSession(tenantId:'T',companyId:company,companyCode:'SYNTHETIC',driverId:'D',driverName:'Synthetic',employeeNumber:'TEST',assignedVehicleId:vehicle,driverSessionToken:'SYNTHETIC_ONLY',driverSessionExpiresAtUtc:DateTime.now().toUtc().add(const Duration(hours:1)),issuedAt:DateTime.now().toUtc(),expiresAt:DateTime.now().toUtc().add(const Duration(minutes:5)));
 test('active personal session prevents cleanup',()async{await save('C');await expectLater(DriverSessionStore.instance.clearAfterDeviceTransition(scope),throwsStateError);expect(activeDriverSessionNotifier.value?.driverId,'D');});
 test('idle exact scope clears persisted session and pointer',()async{await save('C');activeDriverSessionNotifier.value=null;await DriverSessionStore.instance.clearAfterDeviceTransition(scope);expect(await DriverSessionStore.instance.loadStandaloneScopePointer(),null);});
 test('different vehicle cannot be cleared',()async{await save('C',vehicle:'V1');activeDriverSessionNotifier.value=null;await expectLater(DriverSessionStore.instance.clearAfterDeviceTransition(scope),throwsStateError);expect((await DriverSessionStore.instance.loadStandaloneScopePointer())?.companyId,'C');});
 test('other company credentials and pointer remain intact',()async{await save('OTHER');activeDriverSessionNotifier.value=null;await DriverSessionStore.instance.clearAfterDeviceTransition(scope);expect((await DriverSessionStore.instance.loadStandaloneScopePointer())?.companyId,'OTHER');});
}
