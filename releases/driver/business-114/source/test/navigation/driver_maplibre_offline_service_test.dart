import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_maplibre_service.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';

const native = MethodChannel('fluxidi/offline_maps');
const sdk = MethodChannel('plugins.flutter.io/maplibre_gl');
final geometry = <String, dynamic>{
  'type': 'Polygon',
  'coordinates': [
    [
      [3.5, 50.5],
      [3.6, 50.5],
      [3.6, 50.6],
      [3.5, 50.6],
      [3.5, 50.5],
    ],
  ],
};
DriverOfflineMapRegionRequest request({
  List<String>? styles,
  Map<String, dynamic>? shape,
}) => DriverOfflineMapRegionRequest(
  displayName: 'Test region',
  geometry: shape ?? geometry,
  styleUris: styles ?? kDriverOfflineMapsDefaultStyleUris,
  wifiOnly: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> stored;
  late List<MethodCall> downloads;
  late List<int> deleted;
  var incomplete = false, zero = false;
  setUp(() {
    stored = [];
    downloads = [];
    deleted = [];
    incomplete = false;
    zero = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
          switch (call.method) {
            case 'getListOfRegions':
              return jsonEncode(stored);
            case 'getOfflineRegionStatus':
              return jsonEncode({
                'completedResourceCount': zero ? 0 : 10,
                'requiredResourceCount': zero ? 0 : 10,
                'completedResourceSize': 1024,
                'isComplete': !incomplete,
                'downloadProgress': incomplete ? 50 : 100,
              });
            case 'deleteOfflineRegion':
              final id = (call.arguments as Map)['id'] as int;
              deleted.add(id);
              stored.removeWhere((r) => r['id'] == id);
              return null;
            default:
              fail('Unexpected native map operation ${call.method}');
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
          downloads.add(call);
          expect(call.method, 'download');
          final a = call.arguments as Map;
          expect(
            a['style'],
            startsWith(
              'https://fluxidi-maplibre-be-nl.fluxidi.workers.dev/r/be-nl-20261013-rectangle-v1/',
            ),
          );
          expect(a['wifiOnly'], true);
          expect(a['remainingResources'], greaterThan(0));
          final id = stored.length + 1;
          stored.add({
            'id': id,
            'metadata': a['metadata'],
            'definition': {
              'mapStyleUrl': a['style'],
              'bounds': [
                [a['south'], a['west']],
                [a['north'], a['east']],
              ],
              'minZoom': a['minZoom'],
              'maxZoom': a['maxZoom'],
            },
          });
          return {'id': id, 'complete': true};
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
  });
  test(
    'downloads both own styles through wifi-aware native adapter and verifies actual statuses',
    () async {
      final service = DriverMapLibreOfflineMapsService();
      final r = await service.downloadRegion(request());
      expect(downloads.length, 2);
      expect(r.isComplete, true);
      expect(r.requiredResourceCount, 20);
      expect(r.completedResourceSize, 2048);
      expect(r.styleUris.length, 2);
      expect((await service.listDownloadedRegions()).single.isComplete, true);
    },
  );
  test(
    'missing style or incomplete native resources cannot become complete',
    () async {
      final service = DriverMapLibreOfflineMapsService();
      await service.downloadRegion(request());
      stored.removeLast();
      expect((await service.listDownloadedRegions()).single.isComplete, false);
      incomplete = true;
      expect((await service.listDownloadedRegions()).single.isComplete, false);
    },
  );
  test(
    'zero counters cannot certify a pack despite native result complete',
    () async {
      zero = true;
      final service = DriverMapLibreOfflineMapsService();
      await expectLater(
        service.downloadRegion(request()),
        throwsA(isA<DriverOfflineMapsException>()),
      );
      expect(downloads.length, 1);
      expect(stored.length, 1);
    },
  );
  test(
    'no Mapbox style or outside coverage starts a native download',
    () async {
      final service = DriverMapLibreOfflineMapsService();
      await expectLater(
        service.downloadRegion(
          request(styles: ['mapbox://styles/mapbox/streets-v12']),
        ),
        throwsA(isA<DriverOfflineMapsException>()),
      );
      await expectLater(
        service.downloadRegion(
          request(
            shape: {
              'type': 'Polygon',
              'coordinates': [
                [
                  [1, 48],
                  [1.1, 48],
                  [1.1, 48.1],
                  [1, 48.1],
                  [1, 48],
                ],
              ],
            },
          ),
        ),
        throwsA(isA<DriverOfflineMapsException>()),
      );
      expect(downloads, isEmpty);
      expect(stored, isEmpty);
    },
  );
  test(
    'provider estimate absence is explicit and never a fabricated zero-byte estimate',
    () async {
      final service = DriverMapLibreOfflineMapsService();
      await expectLater(
        service.estimateRegion(request()),
        throwsA(isA<DriverOfflineMapsException>()),
      );
      expect(downloads, isEmpty);
    },
  );
  test('only owned regions are listed or deleted', () async {
    final service = DriverMapLibreOfflineMapsService();
    final r = await service.downloadRegion(request());
    stored.add({
      ...stored.first,
      'id': 999,
      'metadata': {'source': 'legacy_mapbox', 'region_id': r.id},
    });
    expect((await service.listDownloadedRegions()).length, 1);
    await service.deleteRegion(r.id);
    expect(deleted, [1, 2]);
    expect(stored.single['id'], 999);
  });
  test(
    'wifi denial retains partial data and releases owner for a retry',
    () async {
      final service = DriverMapLibreOfflineMapsService();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            throw PlatformException(code: 'wifiRequired');
          });
      await expectLater(
        service.downloadRegion(request()),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        service.downloadRegion(request()),
        throwsA(isA<PlatformException>()),
      );
      expect(deleted, isEmpty);
    },
  );
  test(
    'simultaneous caller is refused before a second native operation',
    () async {
      final service = DriverMapLibreOfflineMapsService(),
          gate = Completer<Map<String, dynamic>>();
      var started = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (call) async {
            started++;
            return gate.future;
          });
      final first = service.downloadRegion(request());
      await expectLater(
        service.downloadRegion(request()),
        throwsA(isA<DriverOfflineMapsException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(started, 1);
      gate.complete({'complete': false});
      await expectLater(first, throwsA(isA<DriverOfflineMapsException>()));
    },
  );
}
