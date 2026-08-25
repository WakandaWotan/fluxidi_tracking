import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/stay22_search.dart';

const String _testAid = 'test_aid';

Uri _uri({
  required String address,
  int adults = 2,
  int children = 0,
  String languageCode = 'nl',
  String currency = 'EUR',
  String campaign = kStay22CampaignHotelsSearch,
  DateTime? checkin,
  DateTime? checkout,
  double? latitude,
  double? longitude,
}) {
  return buildStay22SearchbarUri(
    aid: _testAid,
    request: Stay22SearchRequest(
      address: address,
      adults: adults,
      children: children,
      languageCode: languageCode,
      currency: currency,
      campaign: campaign,
      checkin: checkin,
      checkout: checkout,
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

void _assertDocumentedQuery(Uri uri) {
  expect(uri.host, kStay22SearchbarHost);
  expect(uri.path, kStay22SearchbarPath);
  expect(uri.queryParameters.containsKey('aid'), isTrue);
  expect(uri.queryParameters['aid'], isNotEmpty);
  expect(
    uri.queryParameters.keys.toSet().difference(kStay22AllowedQueryKeys),
    isEmpty,
  );
  expect(uri.queryParameters.containsKey('rooms'), isFalse);
  expect(uri.queryParameters.containsKey('product_medium'), isFalse);
  expect(
    uri.queryParameters.keys.length,
    uri.queryParameters.keys.toSet().length,
  );
}

void main() {
  test('destination is required before a live search can launch', () {
    final missing = validateStay22Search(
      address: '   ',
      adults: 2,
      children: 0,
      checkin: DateTime(2099, 8, 20),
      checkout: DateTime(2099, 8, 22),
    );
    expect(missing.canLaunch, isFalse);
    expect(missing.issues, contains(Stay22SearchIssue.missingDestination));

    final valid = validateStay22Search(
      address: 'Paris, France',
      adults: 2,
      children: 0,
      checkin: DateTime(2099, 8, 20),
      checkout: DateTime(2099, 8, 22),
      now: DateTime(2099, 8, 1),
    );
    expect(valid.canLaunch, isTrue);
  });

  test('destination is encoded once and decoded as the original address', () {
    const address = 'Costa del Sol, Spain';
    final uri = _uri(address: address);
    _assertDocumentedQuery(uri);
    expect(uri.queryParameters['address'], address);
    expect(uri.query.contains(address), isFalse);
    expect(uri.query.toLowerCase().contains('costa'), isTrue);
  });

  test('check-in and checkout use YYYY-MM-DD', () {
    final uri = _uri(
      address: 'Vienna, Austria',
      checkin: DateTime(2099, 3, 4),
      checkout: DateTime(2099, 3, 9),
    );
    expect(uri.queryParameters['checkin'], '2099-03-04');
    expect(uri.queryParameters['checkout'], '2099-03-09');
  });

  test('adults, children, language, currency and campaign are transmitted', () {
    final uri = _uri(
      address: 'Gent, Belgium',
      adults: 3,
      children: 2,
      languageCode: 'fr',
      currency: 'EUR',
      campaign: kStay22CampaignHotelsSearch,
      checkin: DateTime(2099, 8, 20),
      checkout: DateTime(2099, 8, 22),
    );
    expect(uri.queryParameters['adults'], '3');
    expect(uri.queryParameters['children'], '2');
    expect(uri.queryParameters['lang'], 'fr');
    expect(uri.queryParameters['currency'], 'EUR');
    expect(uri.queryParameters['campaign'], kStay22CampaignHotelsSearch);
    expect(
      stay22CampaignUsesUnderscores(uri.queryParameters['campaign']!),
      isTrue,
    );
    expect(uri.queryParameters['campaign']!.contains('-'), isFalse);
  });

  test('affiliate id stays in the request and is redacted from logs', () {
    final uri = _uri(address: 'Paris, France');
    expect(uri.queryParameters.containsKey('aid'), isTrue);
    expect(uri.queryParameters['aid'], isNotEmpty);
    final redacted = redactStay22Sensitive(uri.toString());
    expect(redacted.contains(_testAid), isFalse);
    expect(redacted.contains('aid='), isTrue);
    expect(redacted, contains('[REDACTED_AID]'));
  });

  test('undocumented rooms parameter is never emitted', () {
    final uri = _uri(address: 'Madrid, Spain');
    expect(uri.queryParameters.containsKey('rooms'), isFalse);
    expect(uri.query.contains('rooms='), isFalse);
  });

  test('past check-in, equal dates and reversed dates are rejected', () {
    final now = DateTime(2026, 8, 25);
    final past = validateStay22Search(
      address: 'Paris, France',
      adults: 2,
      children: 0,
      checkin: DateTime(2026, 8, 20),
      checkout: DateTime(2026, 8, 26),
      now: now,
    );
    expect(past.issues, contains(Stay22SearchIssue.pastCheckin));

    final sameDay = validateStay22Search(
      address: 'Paris, France',
      adults: 2,
      children: 0,
      checkin: DateTime(2026, 8, 26),
      checkout: DateTime(2026, 8, 26),
      now: now,
    );
    expect(sameDay.issues, contains(Stay22SearchIssue.checkoutNotAfterCheckin));

    final reversed = validateStay22Search(
      address: 'Paris, France',
      adults: 2,
      children: 0,
      checkin: DateTime(2026, 8, 28),
      checkout: DateTime(2026, 8, 26),
      now: now,
    );
    expect(
      reversed.issues,
      contains(Stay22SearchIssue.checkoutNotAfterCheckin),
    );
  });

  test('adults below 1 and negative children are rejected', () {
    final adults = validateStay22Search(
      address: 'Paris, France',
      adults: 0,
      children: 0,
      checkin: DateTime(2099, 8, 20),
      checkout: DateTime(2099, 8, 22),
    );
    expect(adults.issues, contains(Stay22SearchIssue.adultsBelowOne));

    final children = validateStay22Search(
      address: 'Paris, France',
      adults: 2,
      children: -1,
      checkin: DateTime(2099, 8, 20),
      checkout: DateTime(2099, 8, 22),
    );
    expect(children.issues, contains(Stay22SearchIssue.negativeChildren));
  });

  test('featured searches may omit dates without fabricating them', () {
    final validation = validateStay22Search(
      address: 'Warwick Brussels, Brussels, Belgium',
      adults: 2,
      children: 0,
      requireDates: false,
    );
    expect(validation.canLaunch, isTrue);
    final uri = _uri(address: 'Warwick Brussels, Brussels, Belgium');
    expect(uri.queryParameters.containsKey('checkin'), isFalse);
    expect(uri.queryParameters.containsKey('checkout'), isFalse);
  });

  test('country text is appended once without duplicating fragments', () {
    expect(
      composeStay22Address(freeText: 'Paris', country: 'France'),
      'Paris, France',
    );
    expect(
      composeStay22Address(freeText: 'Paris, France', country: 'France'),
      'Paris, France',
    );
    expect(
      composeStay22Address(city: 'Gent', country: 'Belgium'),
      'Gent, Belgium',
    );
    expect(
      composeStay22Address(
        freeText: 'Costa del Sol',
        region: 'Costa del Sol',
        country: 'Spain',
      ),
      'Costa del Sol, Spain',
    );
    expect(
      composeStay22Address(city: 'Vienna', country: 'Austria'),
      'Vienna, Austria',
    );
  });

  test('campaign names are distinct and use underscores', () {
    expect(
      stay22CampaignFor(Stay22SearchKind.general),
      kStay22CampaignHotelsSearch,
    );
    expect(
      stay22CampaignFor(Stay22SearchKind.featured),
      kStay22CampaignFeaturedStay,
    );
    expect(stay22CampaignFor(Stay22SearchKind.saved), kStay22CampaignSavedStay);
    for (final campaign in <String>[
      kStay22CampaignHotelsSearch,
      kStay22CampaignFeaturedStay,
      kStay22CampaignSavedStay,
    ]) {
      expect(stay22CampaignUsesUnderscores(campaign), isTrue);
    }
  });

  test('currency uses EUR for euro-area destinations and GBP for the UK', () {
    expect(stay22CurrencyForCountry('BE'), 'EUR');
    expect(stay22CurrencyForCountry('FR'), 'EUR');
    expect(stay22CurrencyForCountry('AT'), 'EUR');
    expect(stay22CurrencyForCountry('GB'), 'GBP');
    expect(stay22CurrencyForCountry(null), 'EUR');
    expect(stay22CurrencyForCountry('JP'), 'EUR');
  });

  test('language hints map the four app languages', () {
    expect(stay22LangHint('nl'), 'nl');
    expect(stay22LangHint('fr'), 'fr');
    expect(stay22LangHint('en'), 'en');
    expect(stay22LangHint('es'), 'es');
  });

  test('verified coordinates are added and unreliable ones are omitted', () {
    final withCoords = _uri(
      address: 'Warwick Brussels, Brussels, Belgium',
      latitude: 50.845,
      longitude: 4.3543,
    );
    expect(withCoords.queryParameters['lat'], '50.845000');
    expect(withCoords.queryParameters['lng'], '4.354300');

    final zero = _uri(
      address: 'Warwick Brussels, Brussels, Belgium',
      latitude: 0,
      longitude: 0,
    );
    expect(zero.queryParameters.containsKey('lat'), isFalse);
    expect(zero.queryParameters.containsKey('lng'), isFalse);
  });

  test('NL FR EN ES copy is complete and not mixed', () {
    const languages = <String>['nl', 'fr', 'en', 'es'];
    for (final language in languages) {
      final labels = <String>[
        stay22LiveSearchTitle(language),
        stay22LiveSearchCta(language),
        stay22LiveSearchSubtitle(language),
        stay22FeaturedCountLabel(19, language),
        stay22FeaturedFilterLabel(4, language),
        stay22FeaturedExplanation(language),
        stay22RoomsClarification(language),
        stay22LaunchFailureLabel(language),
        stay22ExternalActionSemantics(language),
        stay22SearchIssueLabel(Stay22SearchIssue.missingDestination, language),
        stay22SearchIssueLabel(Stay22SearchIssue.pastCheckin, language),
        stay22SearchIssueLabel(
          Stay22SearchIssue.checkoutNotAfterCheckin,
          language,
        ),
        stay22SearchIssueLabel(Stay22SearchIssue.adultsBelowOne, language),
        stay22SearchIssueLabel(Stay22SearchIssue.negativeChildren, language),
        stay22FeaturedBrowseTitle(language),
      ];
      for (final label in labels) {
        expect(label.trim(), isNotEmpty);
      }
      expect(stay22FeaturedCountLabel(19, language).contains('19'), isTrue);
      expect(
        stay22FeaturedCountLabel(19, language).toLowerCase(),
        isNot(contains('gevonden')),
      );
      expect(
        stay22FeaturedCountLabel(19, language).toLowerCase(),
        isNot(contains('found')),
      );
    }
    expect(
      stay22RoomsClarification('nl'),
      'Het aantal kamers bevestig je bij de aanbieder.',
    );
    expect(stay22FeaturedCountLabel(19, 'nl'), '19 uitgelichte verblijven');
    expect(stay22LiveSearchSubtitle('nl'), contains('Stay22'));
    expect(
      stay22LiveSearchSubtitle('fr'),
      isNot(stay22LiveSearchSubtitle('nl')),
    );
    expect(
      stay22LiveSearchSubtitle('en'),
      isNot(stay22LiveSearchSubtitle('es')),
    );
  });
}
