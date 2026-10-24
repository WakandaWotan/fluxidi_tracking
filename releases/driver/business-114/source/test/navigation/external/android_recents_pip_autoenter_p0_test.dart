// ANDROID-RECENTS-PIP-AUTOENTER-P0 — Flutter source contracts.
//
// Run:
//   flutter test test/navigation/external/android_recents_pip_autoenter_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Missing $relativePath');
  return file.readAsStringSync();
}

void main() {
  group('ANDROID-RECENTS-PIP-AUTOENTER-P0 contracts', () {
    test('plugin clears sticky auto-enter and gates force-to-front', () {
      final plugin = _read(
        'android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/ExternalNavigationPlugin.kt',
      );
      expect(plugin.contains('fun clearPipAutoEnter'), isTrue);
      expect(plugin.contains('activity_resumed_not_in_pip'), isTrue);
      expect(plugin.contains('pip_mode_exited'), isTrue);
      expect(plugin.contains('pip_enter_failed'), isTrue);
      expect(plugin.contains('exit_fluxidi_pip_cleanup'), isTrue);
      expect(plugin.contains('shouldHandlePipReturn'), isTrue);
      expect(plugin.contains('force_to_front=false'), isTrue);
      expect(plugin.contains('method_channel_explicit_return'), isTrue);

      final exitIdx = plugin.indexOf('private fun exitFluxidiPip');
      expect(exitIdx, greaterThan(0));
      final exitChunk = plugin.substring(exitIdx, exitIdx + 900);
      expect(exitChunk.contains('bringFluxidiTaskToFront'), isFalse);

      final enterIdx = plugin.indexOf('private fun enterFluxidiPip');
      expect(enterIdx, greaterThan(0));
      final enterChunk = plugin.substring(enterIdx, enterIdx + 1600);
      expect(enterChunk.contains('autoEnter = true'), isFalse);
    });

    test('MainActivity clears auto-enter on resume', () {
      final main = _read(
        'android/app/src/main/kotlin/com/fluxidi/tracking/MainActivity.kt',
      );
      expect(main.contains('onActivityResumed'), isTrue);
      expect(main.contains('handleReturnFromPipIntent'), isTrue);
    });

    test('return intent helpers support consume-once semantics', () {
      final intents = _read(
        'android/app/src/main/kotlin/com/fluxidi/tracking/externalnav/GoogleMapsNavigationIntents.kt',
      );
      expect(intents.contains('EXTRA_PIP_RETURN_HANDLED'), isTrue);
      expect(intents.contains('shouldHandlePipReturnSnapshot'), isTrue);
      expect(intents.contains('consumePipReturnSnapshot'), isTrue);
      expect(intents.contains('shouldHandlePipReturn'), isTrue);
      expect(intents.contains('consumePipReturnIntent'), isTrue);
    });

    test('Flutter still uses exitFluxidiPip for session cleanup (no UI steal)', () {
      final host = _read('lib/navigation/external/external_navigation_host.dart');
      final driver = _read('lib/main_parts/driver_home_page_state.dart');
      expect(host.contains('exitFluxidiPip'), isTrue);
      expect(host.contains('returnToFluxidi'), isTrue);
      expect(driver.contains('exitFluxidiPip'), isTrue);
    });
  });
}
