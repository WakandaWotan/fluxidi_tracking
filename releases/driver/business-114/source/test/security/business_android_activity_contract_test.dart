import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Business local_auth uses FragmentActivity without losing native bridges', () {
    final source = File('android/app/src/main/kotlin/com/fluxidi/tracking/MainActivity.kt').readAsStringSync();
    expect(source, contains('class MainActivity : FlutterFragmentActivity()'));
    expect(source, contains('io.flutter.embedding.android.FlutterFragmentActivity'));
    expect(source, contains('flutterEngine.plugins.add(FluxidiNativeFollowPlugin())'));
    expect(source, contains('flutterEngine.plugins.add(plugin)'));
    for (final callback in ['onNewIntent', 'onResume', 'onPictureInPictureModeChanged']) {
      expect(source, contains('override fun $callback('));
    }
  });
}
