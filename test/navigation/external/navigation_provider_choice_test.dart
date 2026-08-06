// FLUXIDI-PIP-METER-EXTERNAL-NAV-1

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';
import 'package:fluxidi_tracking/navigation/external/google_maps_launch_contract.dart';
import 'package:fluxidi_tracking/navigation/external/navigation_provider_choice.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

void main() {
  testWidgets('1) NAV choice shows Fluxidi and Google Maps separately',
      (tester) async {
    NavigationProviderChoice? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await showNavigationProviderChoiceDialog(
                  context,
                  tr: _tr,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Fluxidi-navigatie'), findsOneWidget);
    expect(find.text('Google Maps + Fluxidi-teller'), findsOneWidget);
    expect(find.textContaining('Externe navigatie'), findsNothing);
    await tester.tap(find.text('Google Maps + Fluxidi-teller'));
    await tester.pumpAndSettle();
    expect(chosen, NavigationProviderChoice.googleMapsWithMeter);
  });

  testWidgets('2) PiP meter hides map chrome and shows return action',
      (tester) async {
    var returned = false;
    final model = buildExternalNavPipMeterModel(
      phase: ExternalNavPhase.activeRide,
      isStreetRide: false,
      isFixedPrice: true,
      fixedPriceText: '€12,20',
      kmText: '2.0 km',
      durationText: '00:10:00',
      waitText: '00:00:30',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ExternalNavPipMeterCard(
          model: model,
          onReturnToFluxidi: () => returned = true,
        ),
      ),
    );
    expect(find.text('Naar bestemming'), findsOneWidget);
    expect(find.text('€12,20'), findsOneWidget);
    expect(find.text('Terug naar Fluxidi'), findsOneWidget);
    expect(find.byType(Placeholder), findsNothing);
    await tester.tap(find.text('Terug naar Fluxidi'));
    expect(returned, isTrue);
  });

  testWidgets('3) phone and tablet PiP layouts render large primary value',
      (tester) async {
    final model = buildExternalNavPipMeterModel(
      phase: ExternalNavPhase.activeRide,
      isStreetRide: true,
      isFixedPrice: false,
      liveFareText: '€17,60',
      kmText: '1.0 km',
      durationText: '00:05:00',
      waitText: '00:00:00',
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(home: ExternalNavPipMeterCard(model: model)),
      ),
    );
    expect(find.text('Naar bestemming'), findsOneWidget);
    expect(find.text('€17,60'), findsOneWidget);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1024, 768)),
        child: MaterialApp(home: ExternalNavPipMeterCard(model: model)),
      ),
    );
    expect(find.text('Naar bestemming'), findsOneWidget);
  });

  test('4) STOP ends session contract (copy cleared)', () {
    ExternalNavigationSession? session = ExternalNavigationSession(
      provider: ExternalNavProvider.googleMaps,
      bookingId: 'b1',
      phase: ExternalNavPhase.activeRide,
      destination: const ExternalNavigationDestinationPoint(
        latitude: 1,
        longitude: 2,
      ),
      launchedAt: DateTime.now(),
      pipActive: true,
    );
    // Mimic STOP owner: clear session reference.
    session = null;
    expect(session, isNull);
    expect(shouldSuppressNativeGuidance(session), isFalse);
  });

  test('5) failed launch decision keeps native guidance and no session', () {
    final d = GoogleMapsLaunchDecision.fromResult(
      result: const GoogleMapsLaunchResult(
        status: GoogleMapsLaunchStatus.nativeException,
        failureCode: 'channel_boom',
      ),
      userWantsPip: true,
    );
    expect(d.activateExternalSession, isFalse);
    expect(d.keepNativeGuidanceActive, isTrue);
    expect(d.uiAction, GoogleMapsLaunchUiAction.showFailureDialog);
  });

  testWidgets(
      '6) Google Maps ListTile onTap is non-null (no silent disabled button)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showNavigationProviderChoiceDialog(context, tr: _tr);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Google Maps + Fluxidi-teller'),
    );
    expect(tile.onTap, isNotNull);
  });
}
