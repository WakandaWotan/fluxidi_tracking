import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver/authenticated_driver_vehicle.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

VehicleProfile car(String company, String driver, String id) => VehicleProfile(
  id:id, companyId:company, driverId:driver, vehicleName:'Fixture',brandModel:'',
  licensePlate:'',color:'',passengerCapacity:4,luggageCapacity:2,tierId:'COMFORT',
  isActive:true,primaryPhotoRef:'',galleryPhotoRefs:const [],
);
ActiveDriverSession actor({String? vehicle='fluxidi-car'}) => ActiveDriverSession(
 driverId:'fluxidi-driver',employeeNumber:'1',fullName:'Fixture',phone:'',loggedInAt:'',updatedAt:'',
 tenantId:'fluxidi',companyId:'fluxidi',assignedVehicleId:vehicle,
);
void main() {
 test('Fluxidi QR actor uses assigned car on a Mario configured tablet', () {
   expect(authenticatedDriverVehicleId(session:actor(),activeDriverId:'fluxidi-driver',
     vehicles:[car('mario','mario-driver','mario-car')]), 'fluxidi-car');
 });
 test('without assignment only the same company and driver can supply a car', () {
   final vehicles=[car('mario','fluxidi-driver','mario-car'),car('fluxidi','other','other-car')];
   expect(authenticatedDriverVehicleId(session:actor(vehicle:null),activeDriverId:'fluxidi-driver',vehicles:vehicles),'');
   expect(authenticatedDriverVehicleId(session:actor(vehicle:null),activeDriverId:'fluxidi-driver',
     vehicles:[...vehicles,car('fluxidi','fluxidi-driver','own-car')]),'own-car');
 });
 test('switching UI driver cannot borrow another authenticated assignment', () {
   expect(authenticatedDriverVehicleId(session:actor(),activeDriverId:'other',vehicles:const []),'');
 });
}
