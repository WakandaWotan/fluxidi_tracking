import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';

void main() {
  const euMarkets = <String>{
    'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE',
    'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT',
    'RO', 'SK', 'SI', 'ES', 'SE',
  };

  test('paid subscription markets cover EU member states only', () {
    for (final market in euMarkets) {
      expect(isFluxidiLaunchMarket(market), isTrue, reason: market);
    }
    expect(isFluxidiLaunchMarket('GB'), isFalse);
    expect(isFluxidiLaunchMarket('CH'), isFalse);
  });

  test('EU add-on prices and included base entitlements are consistent', () {
    for (final market in euMarkets) {
      final catalog = resolveSubscriptionCatalogEntryForMarket(market);
      expect(catalog.extraVehiclePriceCents, 1900, reason: market);
      expect(catalog.extraDriverPriceCents, 900, reason: market);
      expect(catalog.includedVehicleCount, 1, reason: market);
      expect(catalog.includedDriversPerVehicle, 3, reason: market);
      expect(catalog.includedPdfCreationsPerVehicleMonth, 200, reason: market);
    }
    final nonEu = resolveSubscriptionCatalogEntryForMarket('CH');
    expect(nonEu.market, 'BE');
  });
}
