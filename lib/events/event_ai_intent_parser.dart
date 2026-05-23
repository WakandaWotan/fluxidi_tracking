import 'event_models.dart';

class EventAiIntent {
  const EventAiIntent({
    required this.marketKey,
    required this.categoryKey,
    required this.dateMode,
    required this.dateSignal,
    required this.searchQuery,
    required this.hasExplicitMarket,
    required this.hasExplicitCategory,
    required this.hasExplicitDate,
  });

  final String marketKey;
  final String categoryKey;
  final String dateMode;
  final String dateSignal;
  final String searchQuery;
  final bool hasExplicitMarket;
  final bool hasExplicitCategory;
  final bool hasExplicitDate;
}

EventAiIntent parseEventAiIntent({
  required String input,
  required String fallbackMarketKey,
  required String fallbackDateMode,
}) {
  final normalizedText = _normalizeForMatching(input);
  var remainingText = normalizedText;

  final marketMatch = _consumeBestAliasMatch(remainingText, _marketAliases);
  remainingText = marketMatch.updatedText;
  final categoryMatch = _consumeBestAliasMatch(remainingText, _categoryAliases);
  remainingText = categoryMatch.updatedText;
  final dateMatch = _consumeBestAliasMatch(remainingText, _dateAliases);
  remainingText = dateMatch.updatedText;

  final searchTokens = remainingText
      .split(' ')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .where((token) => !_searchStopWords.contains(token))
      .toList();
  final searchQuery = searchTokens.join(' ').trim();

  final dateSignal = dateMatch.key ?? fallbackDateMode;
  final dateMode = switch (dateSignal) {
    EventDateMode.today => EventDateMode.today,
    EventDateMode.weekend => EventDateMode.weekend,
    EventDateMode.month => EventDateMode.month,
    'year' => EventDateMode.all,
    _ => fallbackDateMode,
  };

  return EventAiIntent(
    marketKey: marketMatch.key ?? fallbackMarketKey,
    categoryKey: categoryMatch.key ?? 'all',
    dateMode: dateMode,
    dateSignal: dateSignal,
    searchQuery: searchQuery,
    hasExplicitMarket: marketMatch.key != null,
    hasExplicitCategory: categoryMatch.key != null,
    hasExplicitDate: dateMatch.key != null,
  );
}

class _AliasConsumeMatch {
  const _AliasConsumeMatch({
    required this.key,
    required this.alias,
    required this.updatedText,
  });

  final String? key;
  final String? alias;
  final String updatedText;
}

class _AliasCandidate {
  const _AliasCandidate({required this.key, required this.alias});

  final String key;
  final String alias;
}

_AliasConsumeMatch _consumeBestAliasMatch(
  String normalizedText,
  Map<String, List<String>> aliasesByKey,
) {
  final candidates = <_AliasCandidate>[];
  aliasesByKey.forEach((key, aliases) {
    for (final rawAlias in aliases) {
      final alias = _normalizeForMatching(rawAlias);
      if (alias.isEmpty) continue;
      candidates.add(_AliasCandidate(key: key, alias: alias));
    }
  });
  candidates.sort((a, b) {
    final tokenCountDiff =
        b.alias.split(' ').length - a.alias.split(' ').length;
    if (tokenCountDiff != 0) return tokenCountDiff;
    return b.alias.length - a.alias.length;
  });

  for (final candidate in candidates) {
    final consumed = _removeFirstWholePhrase(normalizedText, candidate.alias);
    if (consumed == null) continue;
    return _AliasConsumeMatch(
      key: candidate.key,
      alias: candidate.alias,
      updatedText: consumed,
    );
  }
  return _AliasConsumeMatch(
    key: null,
    alias: null,
    updatedText: normalizedText,
  );
}

String? _removeFirstWholePhrase(
  String normalizedText,
  String normalizedPhrase,
) {
  if (normalizedText.isEmpty || normalizedPhrase.isEmpty) return null;
  final paddedText = ' $normalizedText ';
  final paddedPhrase = ' $normalizedPhrase ';
  final start = paddedText.indexOf(paddedPhrase);
  if (start < 0) return null;
  final before = paddedText.substring(0, start);
  final after = paddedText.substring(start + paddedPhrase.length);
  return '$before $after'.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizeForMatching(String raw) {
  final source = raw.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in source.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentFoldMap[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r"\s+"), ' ')
      .trim();
}

const Map<String, String> _accentFoldMap = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

const Map<String, List<String>> _marketAliases = <String, List<String>>{
  'be': <String>['belgie', 'belgium', 'belgique', 'belgica'],
  'nl': <String>[
    'nederland',
    'netherlands',
    'pays bas',
    'pays-bas',
    'paises bajos',
  ],
  'fr': <String>['frankrijk', 'france', 'francia'],
  'uk': <String>[
    'uk',
    'united kingdom',
    'verenigd koninkrijk',
    'royaume uni',
    'reino unido',
    'engeland',
    'england',
  ],
  'es': <String>['spanje', 'spain', 'espagne', 'espana'],
};

const Map<String, List<String>> _categoryAliases = <String, List<String>>{
  EventCategoryKey.music: <String>[
    'muziek',
    'music',
    'musique',
    'musica',
    'concert',
    'concerten',
  ],
  EventCategoryKey.sport: <String>[
    'sport',
    'sports',
    'voetbal',
    'football',
    'sportevents',
  ],
  EventCategoryKey.theater: <String>['theater', 'theatre', 'théâtre', 'teatro'],
  EventCategoryKey.comedy: <String>['comedy', 'comedie', 'comédie', 'comedia'],
  EventCategoryKey.family: <String>[
    'familie',
    'family',
    'famille',
    'familia',
    'kinderen',
    'kids',
  ],
  EventCategoryKey.food: <String>[
    'food',
    'eten',
    'culinair',
    'gastronomie',
    'cuisine',
    'comida',
  ],
  EventCategoryKey.business: <String>[
    'business',
    'zakelijk',
    'congres',
    'conference',
    'negocios',
  ],
  EventCategoryKey.culture: <String>['cultuur', 'culture', 'cultura'],
};

const Map<String, List<String>> _dateAliases = <String, List<String>>{
  EventDateMode.today: <String>[
    'vandaag',
    'today',
    'aujourd hui',
    'aujourd\'hui',
    'hoy',
  ],
  EventDateMode.weekend: <String>['dit weekend', 'this weekend', 'weekend'],
  EventDateMode.month: <String>['deze maand', 'this month', 'maand', 'month'],
  'year': <String>['dit jaar', 'this year', 'jaar', 'year'],
};

const Set<String> _searchStopWords = <String>{
  'in',
  'op',
  'voor',
  'naar',
  'met',
  'de',
  'het',
  'een',
  'en',
  'van',
  'te',
  'for',
  'the',
  'and',
  'of',
  'a',
  'au',
  'avec',
  'et',
  'la',
  'le',
  'el',
  'los',
  'las',
  'con',
  'y',
  'del',
  'events',
  'event',
  'eventos',
  'evenementen',
  'evenements',
  'evenement',
};
