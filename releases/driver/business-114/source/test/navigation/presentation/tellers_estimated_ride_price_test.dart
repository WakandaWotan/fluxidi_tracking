// FLUXIDI-TELLERS-PRICE-SOT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters_notifier.dart';
import 'package:fluxidi_tracking/navigation/presentation/tellers_estimated_ride_price.dart';

String _fmtEur(double amount, String currency) {
  final c = currency.trim().isEmpty ? 'EUR' : currency.trim().toUpperCase();
  if (c == 'EUR') return '€ ${amount.toStringAsFixed(2)}';
  return '$c ${amount.toStringAsFixed(2)}';
}

TellersEstimatedRidePriceInput _input({
  bool usesFixedPrice = false,
  String fixedPriceText = '€ 3.20',
  double? estimatedFare = 17.20,
  String currency = 'EUR',
  bool isLoading = false,
}) {
  return TellersEstimatedRidePriceInput(
    usesFixedPrice: usesFixedPrice,
    fixedPriceText: fixedPriceText,
    estimatedFare: estimatedFare,
    currency: currency,
    isLoading: isLoading,
    formatAmount: _fmtEur,
    loadingText: 'Prijs berekenen…',
    unavailableText: 'Schatting niet beschikbaar',
  );
}

void main() {
  group('FLUXIDI-TELLERS-PRICE-SOT', () {
    test('live meter €3.20 + calculator €17.20 → estimate wins for bottom card',
        () {
      final text = resolveTellersEstimatedRidePriceText(
        _input(fixedPriceText: '€ 3.20', estimatedFare: 17.20),
      );
      expect(text, '€ 17.20');
      expect(text, isNot('€ 3.20'));
    });

    test('valid calculator estimate wins over start/live fare text', () {
      expect(
        resolveTellersEstimatedRidePriceText(
          _input(fixedPriceText: '€ 3.20', estimatedFare: 17.20),
        ),
        '€ 17.20',
      );
    });

    test('fixed-price authority wins over latched estimate', () {
      expect(
        resolveTellersEstimatedRidePriceText(
          _input(
            usesFixedPrice: true,
            fixedPriceText: '€ 48.00',
            estimatedFare: 17.20,
          ),
        ),
        '€ 48.00',
      );
    });

    test('no estimate → honest unavailable, not live meter', () {
      expect(
        resolveTellersEstimatedRidePriceText(
          _input(fixedPriceText: '€ 3.20', estimatedFare: null),
        ),
        'Schatting niet beschikbaar',
      );
    });

    test('loading without latched estimate → loading copy', () {
      expect(
        resolveTellersEstimatedRidePriceText(
          _input(
            fixedPriceText: '€ 3.20',
            estimatedFare: null,
            isLoading: true,
          ),
        ),
        'Prijs berekenen…',
      );
    });

    test('loading keeps latched estimate when already present', () {
      expect(
        resolveTellersEstimatedRidePriceText(
          _input(
            fixedPriceText: '€ 3.20',
            estimatedFare: 17.20,
            isLoading: true,
          ),
        ),
        '€ 17.20',
      );
    });

    test('EUR formatting matches ordinary Navigatie pattern', () {
      expect(_fmtEur(17.2, 'EUR'), '€ 17.20');
      expect(
        resolveTellersEstimatedRidePriceText(_input(estimatedFare: 17.2)),
        '€ 17.20',
      );
    });

    test('snapshot: Tarief live vs bottom estimate stay distinct', () {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 3.20',
        fareLabel: 'Tarief',
        usesFixedPrice: false,
        estimatedRidePriceText: '€ 17.20',
        estimatedRidePriceNote: 'Incl. btw • Definitieve prijs bij STOP',
        distanceTravelledText: '0.0 km',
        rideDurationText: '00:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      expect(snap.fareText, '€ 3.20');
      expect(snap.priceSummaryAmountText, '€ 17.20');
      expect(snap.estimatedRidePriceNote, contains('btw'));
    });

    test('fixed snapshot: KPI and summary share fixed amount', () {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 48.00',
        fareLabel: 'Vaste prijs',
        usesFixedPrice: true,
        estimatedRidePriceText: '€ 48.00',
        distanceTravelledText: '5.0 km',
        rideDurationText: '20:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      expect(snap.priceSummaryAmountText, '€ 48.00');
      expect(snap.fareText, snap.priceSummaryAmountText);
    });

    testWidgets('Tellers UI: Tarief €3.20 and Geschatte ritprijs €17.20', (
      tester,
    ) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 3.20',
        fareLabel: 'Tarief',
        usesFixedPrice: false,
        estimatedRidePriceText: '€ 17.20',
        estimatedRidePriceNote: 'Incl. btw • Definitieve prijs bij STOP',
        distanceTravelledText: '0.0 km',
        rideDurationText: '00:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 1280)),
            child: Scaffold(
              body: DriverRideMetersView(
                snapshot: snap,
                themeListenable: driverThemeNotifier,
                isTablet: true,
                isLandscape: false,
                isWaiting: false,
                showLiveWindow: true,
                showVehicleMarker: false,
                onBackToNavigation: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('€ 3.20'), findsOneWidget);
      expect(find.text('€ 17.20'), findsOneWidget);
      expect(find.text('Tarief'), findsWidgets);
      expect(find.text('Geschatte ritprijs'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary_note')),
        findsOneWidget,
      );
    });

    test('notifier publishes when estimatedRidePriceText changes', () {
      final notifier = DriverRideMetersNotifier(emptyDriverRideMetersSnapshot());
      var ticks = 0;
      notifier.addListener(() => ticks++);
      notifier.publish(
        const DriverRideMetersSnapshot(
          fareText: '€ 3.20',
          distanceTravelledText: '0.0 km',
          rideDurationText: '00:00',
          waitingTimeText: '00:00',
          statusText: 'Rit actief',
          estimatedRidePriceText: '€ 17.20',
        ),
      );
      expect(ticks, 1);
      notifier.publish(
        const DriverRideMetersSnapshot(
          fareText: '€ 3.20',
          distanceTravelledText: '0.0 km',
          rideDurationText: '00:00',
          waitingTimeText: '00:00',
          statusText: 'Rit actief',
          estimatedRidePriceText: '€ 17.20',
        ),
      );
      expect(ticks, 1);
      notifier.publish(
        const DriverRideMetersSnapshot(
          fareText: '€ 3.20',
          distanceTravelledText: '0.0 km',
          rideDurationText: '00:00',
          waitingTimeText: '00:00',
          statusText: 'Rit actief',
          estimatedRidePriceText: '€ 18.40',
        ),
      );
      expect(ticks, 2);
    });
  });
}
