// RELEASE-LANGUAGE-CONSISTENCY-NL-EN-FR-ES-P0
//
// Regression: Fluxidi appLanguage owns UI chrome for NL/EN/FR/ES.
// Fail on known cross-language leaks in release-critical presentation helpers.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main_parts/planned_ride_price_presentation.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_l10n.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';

void main() {
  tearDown(() => setAppLanguage(AppLanguage.en));

  group('Tellers / Counters chrome', () {
    test('titles are four-language and ES never shows NL Tellers leak', () {
      expect(driverTellersTitle(AppLanguage.nl), 'Tellers');
      expect(driverTellersTitle(AppLanguage.en), 'Counters');
      expect(driverTellersTitle(AppLanguage.fr), 'Compteurs');
      expect(driverTellersTitle(AppLanguage.es), 'Contadores');
      expect(driverTellersTitle(AppLanguage.es), isNot('Tellers'));
      expect(driverTellersTitle(AppLanguage.fr), isNot('Tellers'));
      expect(driverTellersTitle(AppLanguage.fr), isNot('Counters'));
    });

    test('meter labels follow language', () {
      expect(driverTellersDistanceLabel(AppLanguage.es), 'Distancia');
      expect(driverTellersFareLabel(AppLanguage.fr), 'Tarif');
      expect(driverTellersFixedPriceLabel(AppLanguage.en), 'Fixed price');
      expect(driverTellersPauseLabel(AppLanguage.nl), 'Pauze');
      expect(driverTellersResumeLabel(AppLanguage.es), 'Reanudar');
    });
  });

  group('Street-ride ready copy matrix', () {
    test('ready toast meanings exist for NL/EN/FR/ES', () {
      const ready = LocalizedText(
        nl: 'Straatrit klaar. Druk START om te rijden.',
        en: 'Street ride is ready. Press START to drive.',
        fr: 'Course de rue prête. Appuyez sur START pour rouler.',
        es: 'El viaje de calle está listo. Pulsa START para conducir.',
      );
      expect(ready.of(AppLanguage.es), contains('viaje de calle'));
      expect(ready.of(AppLanguage.es), isNot(contains('Straatrit')));
      expect(ready.of(AppLanguage.fr), isNot(contains('Street ride')));
      expect(ready.of(AppLanguage.nl), startsWith('Straatrit'));
      expect(ready.of(AppLanguage.en), startsWith('Street ride'));
    });
  });

  group('Offline maps chrome', () {
    const englishLeaks = <String>[
      'Offline map tiles',
      'Downloaded maps',
      'Download map areas for weak mobile signal.',
      'Wi‑Fi only',
      'Europe — search your operating area',
      'Download radius',
      'Preview & download',
      'Shortcuts (existing)',
      'Belgium base map',
      'Download',
      'Refresh',
      'Downloaded regions',
      'Delete',
      'View map',
    ];

    test('ES resolves known chrome without English fallback', () {
      setAppLanguage(AppLanguage.es);
      for (final en in englishLeaks) {
        final resolved = resolveOfflineMapsUiText(
          nl: 'NL_$en',
          en: en,
        );
        expect(
          resolved,
          isNot(equals(en)),
          reason: 'ES must not fall back to EN for "$en"',
        );
        expect(resolved, isNot(startsWith('NL_')));
      }
      expect(
        resolveOfflineMapsUiText(nl: 'Tellers', en: 'Offline map tiles'),
        'Teselas de mapa sin conexión',
      );
      expect(
        resolveOfflineMapsUiText(nl: 'Downloaden', en: 'Download'),
        'Descargar',
      );
      expect(
        resolveOfflineMapsUiText(nl: 'Vernieuwen', en: 'Refresh'),
        'Actualizar',
      );
      expect(
        resolveOfflineMapsUiText(nl: 'Verwijderen', en: 'Delete'),
        'Eliminar',
      );
    });

    test('FR resolves known chrome without English/Dutch leakage', () {
      setAppLanguage(AppLanguage.fr);
      expect(
        resolveOfflineMapsUiText(nl: 'Offline kaarttegels', en: 'Offline map tiles'),
        'Tuiles de carte hors ligne',
      );
      expect(
        resolveOfflineMapsUiText(nl: 'Gedownloade kaarten', en: 'Downloaded maps'),
        isNot(contains('Downloaded')),
      );
      expect(
        resolveOfflineMapsUiText(nl: 'Gedownloade kaarten', en: 'Downloaded maps'),
        isNot(contains('Gedownloade')),
      );
    });

    test('NL and EN stay in their own language', () {
      setAppLanguage(AppLanguage.nl);
      expect(
        resolveOfflineMapsUiText(nl: 'Offline kaarttegels', en: 'Offline map tiles'),
        'Offline kaarttegels',
      );
      setAppLanguage(AppLanguage.en);
      expect(
        resolveOfflineMapsUiText(nl: 'Offline kaarttegels', en: 'Offline map tiles'),
        'Offline map tiles',
      );
    });

    test('region status is four-language', () {
      setAppLanguage(AppLanguage.es);
      expect(
        offlineMapsRegionStatusText(DriverOfflineMapCompletionStatus.complete),
        'Completo',
      );
      setAppLanguage(AppLanguage.fr);
      expect(
        offlineMapsRegionStatusText(DriverOfflineMapCompletionStatus.complete),
        'Complet',
      );
      setAppLanguage(AppLanguage.nl);
      expect(
        offlineMapsRegionStatusText(DriverOfflineMapCompletionStatus.complete),
        'Volledig',
      );
    });

    test('language switch ES -> FR updates newly resolved chrome', () {
      setAppLanguage(AppLanguage.es);
      expect(
        resolveOfflineMapsUiText(nl: 'Downloaden', en: 'Download'),
        'Descargar',
      );
      setAppLanguage(AppLanguage.fr);
      expect(
        resolveOfflineMapsUiText(nl: 'Downloaden', en: 'Download'),
        'Télécharger',
      );
    });

    test('language switch FR -> NL updates newly resolved chrome', () {
      setAppLanguage(AppLanguage.fr);
      expect(
        resolveOfflineMapsUiText(nl: 'Vernieuwen', en: 'Refresh'),
        'Actualiser',
      );
      setAppLanguage(AppLanguage.nl);
      expect(
        resolveOfflineMapsUiText(nl: 'Vernieuwen', en: 'Refresh'),
        'Vernieuwen',
      );
    });
  });

  group('Fare presentation labels', () {
    test('planned fixed price follows app language', () {
      final es = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 42.5,
        liveMeterPreviewEur: 1,
        language: AppLanguage.es,
      );
      expect(es.tellersLabel, 'Precio fijo');
      expect(es.tellersLabel, isNot('Vaste prijs'));

      final fr = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 42.5,
        liveMeterPreviewEur: 1,
        language: AppLanguage.fr,
      );
      expect(fr.tellersLabel, 'Prix fixe');
    });

    test('street meter tellers label follows language', () {
      final en = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: true,
        fixedBookingPriceEur: null,
        liveMeterPreviewEur: 7.8,
        language: AppLanguage.en,
      );
      expect(en.tellersLabel, 'Fare');
      final nl = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: true,
        fixedBookingPriceEur: null,
        liveMeterPreviewEur: 7.8,
        language: AppLanguage.nl,
      );
      expect(nl.tellersLabel, 'Tarief');
    });
  });

  group('device locale must not override app language helper', () {
    test('currentLanguageCode tracks notifier not a hard-coded EN', () {
      setAppLanguage(AppLanguage.es);
      expect(currentLanguageCode, 'es');
      setAppLanguage(AppLanguage.fr);
      expect(currentLanguageCode, 'fr');
      setAppLanguage(AppLanguage.nl);
      expect(currentLanguageCode, 'nl');
    });
  });
}
