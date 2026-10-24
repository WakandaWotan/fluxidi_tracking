// GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1
//
// Contract checks against the committed AndroidManifest (no device needed).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String manifest;

  setUpAll(() {
    final file = File('android/app/src/main/AndroidManifest.xml');
    expect(file.existsSync(), isTrue, reason: 'AndroidManifest must exist');
    manifest = file.readAsStringSync();
  });

  test('package visibility targets Google Maps only', () {
    expect(
      manifest.contains(
        'android:name="com.google.android.apps.maps"',
      ),
      isTrue,
    );
    expect(manifest.contains('QUERY_ALL_PACKAGES'), isFalse);
  });

  test('MainActivity supports PiP with required configChanges', () {
    expect(manifest.contains('android:supportsPictureInPicture="true"'), isTrue);
    expect(manifest.contains('orientation'), isTrue);
    expect(manifest.contains('screenLayout'), isTrue);
    expect(manifest.contains('screenSize'), isTrue);
    expect(manifest.contains('smallestScreenSize'), isTrue);
    expect(manifest.contains('android:launchMode="singleTop"'), isTrue);
  });

  test('PIP-RETURN-TO-FLUXIDI-P0-4: empty taskAffinity + singleTop', () {
    // Bring existing task to front; do not spawn a sibling affinity task.
    expect(manifest.contains('android:taskAffinity=""'), isTrue);
    expect(manifest.contains('android:launchMode="singleTop"'), isTrue);
  });

  test('no SYSTEM_ALERT_WINDOW / overlay permission', () {
    expect(manifest.contains('SYSTEM_ALERT_WINDOW'), isFalse);
    expect(manifest.contains('SYSTEM_OVERLAY_WINDOW'), isFalse);
  });
}
