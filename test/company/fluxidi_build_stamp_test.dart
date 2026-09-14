import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_about_labels.dart';
import 'package:fluxidi_tracking/company/fluxidi_about_this_app.dart';
import 'package:fluxidi_tracking/fluxidi_build_stamp.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';

void main() {
  test('build stamp keeps environment, time and revision readable', () {
    final stamp = fluxidiBuildStamp(
      runtimeEnv: 'local_test',
      bookingBaseUrlOverride: 'http://127.0.0.1:8788',
      buildTime: '2026-09-12T20:45:00+02:00',
      revision: 'abc1234def56',
      dirty: 'true',
    );
    expect(stamp.kind, FluxidiRuntimeKind.localTest);
    expect(stamp.environmentLabel, 'Fluxidi — lokale test');
    expect(stamp.builtAtLabel, '12/09/2026 20:45');
    expect(stamp.revisionLabel, 'abc1234def56 · lokale wijzigingen');
  });

  test('empty stamp values stay unknown instead of inventing a build', () {
    final stamp = fluxidiBuildStamp(
      runtimeEnv: 'production',
      bookingBaseUrlOverride: '',
      buildTime: '',
      revision: '',
      dirty: 'false',
    );
    expect(stamp.environmentLabel, 'Fluxidi');
    expect(stamp.builtAtLabel, isEmpty);
    expect(stamp.revisionLabel, isEmpty);
  });

  testWidgets('about this app shows the injected lokale build', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FluxidiAboutThisApp(
            language: AppLanguage.nl,
            stamp: const FluxidiBuildStamp(
              kind: FluxidiRuntimeKind.localTest,
              builtAtRaw: '2026-09-12T20:45:00+02:00',
              sourceRevision: 'abc1234def56',
              dirty: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(kFluxidiAboutThisAppKey), findsOneWidget);
    expect(
      find.text(kFluxidiAboutThisAppTitle.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(kFluxidiAboutEnvironmentValueKey)).data,
      'Fluxidi — lokale test',
    );
    expect(
      tester.widget<Text>(find.byKey(kFluxidiAboutBuiltAtValueKey)).data,
      '12/09/2026 20:45',
    );
    expect(
      tester.widget<Text>(find.byKey(kFluxidiAboutRevisionValueKey)).data,
      'abc1234def56 · lokale wijzigingen',
    );
  });
}
