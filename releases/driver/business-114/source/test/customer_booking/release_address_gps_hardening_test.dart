import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
void main() {
  test('GPS reverse naming does not force a Belgian address for a Dutch fix', () async {
    var calls = 0;
    final lookup = LimousinePlaceLookup(token: 'hermetic-token', client: MockClient((request) async {
      calls++;
      expect(request.url.queryParameters.containsKey('country'), isFalse);
      expect(request.url.path, contains('5.690000,50.870000'));
      return http.Response('{"features":[]}', 200);
    }));
    await lookup.reverseGeocode(50.87, 5.69);
    expect(calls, 1);
  });
  final now = DateTime.utc(2026,10,9,12);
  LimousineCurrentLocationResolver resolver(LimousineCurrentLocationFix fix, {void Function()? afterLookup}) => LimousineCurrentLocationResolver(
    clock: () => now,
    platform: LimousineCurrentLocationPlatform(isLocationServiceEnabled: () async => true,
      checkPermission: () async => LimousineLocationPermission.granted,
      getCurrentPosition: (_) async => fix),
    lookup: LimousinePlaceLookup(reverseOverride: (_,__,___) async {
      afterLookup?.call(); return const LimousinePlaceLookupResult(suggestions: [
        LimousinePlaceSuggestion(label: 'Teststraat 1',lat: 50.86,lon: 4.36,placeId: 'address.test')]);
    }));
  test('GPS naming preserves the actual fix instead of the reverse-geocoded centroid', () async {
    final result = await resolver(LimousineCurrentLocationFix(latitude:50.85,longitude:4.35,capturedAt:now,accuracyMeters:5)).resolve();
    expect(result!.label,'Teststraat 1'); expect(result.lat,50.85); expect(result.lon,4.35);
  });
  for (final entry in <String,LimousineCurrentLocationFix>{
    'stale': LimousineCurrentLocationFix(latitude:50.85,longitude:4.35,capturedAt:now.subtract(const Duration(seconds:31))),
    'future': LimousineCurrentLocationFix(latitude:50.85,longitude:4.35,capturedAt:now.add(const Duration(seconds:1))),
    'inaccurate': const LimousineCurrentLocationFix(latitude:50.85,longitude:4.35,accuracyMeters:51),
    'nan accuracy': const LimousineCurrentLocationFix(latitude:50.85,longitude:4.35,accuracyMeters:double.nan),
    'out of range': const LimousineCurrentLocationFix(latitude:91,longitude:4.35),
    'sentinel': const LimousineCurrentLocationFix(latitude:0,longitude:0),
  }.entries) {
    test('GPS rejects '+entry.key+' before geocoding', () async {
      final r=resolver(entry.value); await expectLater(r.resolve(),throwsA(isA<LimousineCurrentLocationException>()));
      expect(r.reverseGeocodesStarted,0);
    });
  }
  test('invalid address coordinates are incomplete and cannot authorize routing', () {
    for (final coords in [[91.0,4.0],[50.0,181.0],[double.nan,4.0],[0.0,0.0]]) {
      final a=customerBookingAddressFromText('Teststraat 1',latitude:coords[0],longitude:coords[1]);
      expect(a.hasCoordinates,isFalse); expect(a.isRouteReady,isFalse);
      expect(LimousinePlaceSuggestion(label:'X',lat:coords[0],lon:coords[1]).hasCoordinates,isFalse);
    }
  });
  test('changing a house number clears the old routing coordinate', () {
    const a=LimousineAddressValue(displayText:'Teststraat 1',lat:50.85,lon:4.35,acceptance:LimousineAddressAcceptance.selected);
    final b=a.copyWith(displayText:'Teststraat 2',canonicalLabel:'Teststraat 2',clearCoordinates:true,acceptance:LimousineAddressAcceptance.incomplete);
    expect(b.hasCoordinates,isFalse); expect(b.isRouteReady,isFalse);
  });
}
