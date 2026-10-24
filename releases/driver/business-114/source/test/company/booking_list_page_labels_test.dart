import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/booking_list_page_labels.dart';

void main() {
  test(
    'load-more chrome exists for NL/FR/EN/ES and is not hardcoded Dutch-only',
    () {
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.nl), 'Meer laden');
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.en), 'Load more');
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.fr), 'Charger plus');
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.es), 'Cargar más');
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.en), isNot('Meer laden'));
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.fr), isNot('Meer laden'));
      expect(kBookingPageLoadMoreLabel.of(AppLanguage.es), isNot('Meer laden'));
      expect(kBookingPageRetryPageLabel.of(AppLanguage.nl), 'Opnieuw proberen');
      expect(
        kBookingPageRetryPageLabel.of(AppLanguage.es),
        'Intentar de nuevo',
      );
    },
  );
}
