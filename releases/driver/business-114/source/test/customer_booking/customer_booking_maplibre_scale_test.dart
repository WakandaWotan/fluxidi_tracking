import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_maplibre_basemap.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';
void main(){test('native world scale matches existing booking route projection at fractional zooms',(){
 for(final z in [1.0,8.0,12.25,15.8,18.0]){
 expect(512*math.pow(2,customerBookingNativeZoom(z)),closeTo(customerBookingWorldSize(z),0.0001));
 }
});}
