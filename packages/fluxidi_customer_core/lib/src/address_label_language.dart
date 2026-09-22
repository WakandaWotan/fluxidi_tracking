/// Official place, province and country names for address display.
/// Street names and house tokens are never rewritten.
library;

class FluxidiOfficialAddressName {
  const FluxidiOfficialAddressName({
    required this.nl,
    required this.en,
    required this.fr,
    required this.de,
    required this.es,
  });

  final String nl;
  final String en;
  final String fr;
  final String de;
  final String es;

  String of(String language) {
    switch (language.trim().toLowerCase().split(',').first) {
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      case 'de':
        return de;
      case 'es':
        return es;
      default:
        return en;
    }
  }
}

String fluxidiFoldOfficialAddressName(String raw) {
  const from = 'àáâäãåæçèéêëìíîïñòóôöõøùúûüýÿ';
  const to = 'aaaaaaeceeeeiiiinoooooouuuuyy';
  final buffer = StringBuffer();
  for (final rune in raw.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

String fluxidiNormalizeAddressLanguage(String raw) {
  final language = raw.trim().toLowerCase();
  if (language.isEmpty) return 'nl';
  return language.split(RegExp(r'[,_]')).first.trim();
}

const List<FluxidiOfficialAddressName> kFluxidiOfficialAddressNames =
    <FluxidiOfficialAddressName>[
      FluxidiOfficialAddressName(
        nl: 'België',
        en: 'Belgium',
        fr: 'Belgique',
        de: 'Belgien',
        es: 'Bélgica',
      ),
      FluxidiOfficialAddressName(
        nl: 'Nederland',
        en: 'Netherlands',
        fr: 'Pays-Bas',
        de: 'Niederlande',
        es: 'Países Bajos',
      ),
      FluxidiOfficialAddressName(
        nl: 'Frankrijk',
        en: 'France',
        fr: 'France',
        de: 'Frankreich',
        es: 'Francia',
      ),
      FluxidiOfficialAddressName(
        nl: 'Duitsland',
        en: 'Germany',
        fr: 'Allemagne',
        de: 'Deutschland',
        es: 'Alemania',
      ),
      FluxidiOfficialAddressName(
        nl: 'Luxemburg',
        en: 'Luxembourg',
        fr: 'Luxembourg',
        de: 'Luxemburg',
        es: 'Luxemburgo',
      ),
      FluxidiOfficialAddressName(
        nl: 'Oost-Vlaanderen',
        en: 'East Flanders',
        fr: 'Flandre-Orientale',
        de: 'Ostflandern',
        es: 'Flandes Oriental',
      ),
      FluxidiOfficialAddressName(
        nl: 'West-Vlaanderen',
        en: 'West Flanders',
        fr: 'Flandre-Occidentale',
        de: 'Westflandern',
        es: 'Flandes Occidental',
      ),
      FluxidiOfficialAddressName(
        nl: 'Vlaams-Brabant',
        en: 'Flemish Brabant',
        fr: 'Brabant flamand',
        de: 'Flämisch-Brabant',
        es: 'Brabante Flamenco',
      ),
      FluxidiOfficialAddressName(
        nl: 'Waals-Brabant',
        en: 'Walloon Brabant',
        fr: 'Brabant wallon',
        de: 'Wallonisch-Brabant',
        es: 'Brabante Valón',
      ),
      FluxidiOfficialAddressName(
        nl: 'Antwerpen',
        en: 'Antwerp',
        fr: 'Anvers',
        de: 'Antwerpen',
        es: 'Amberes',
      ),
      FluxidiOfficialAddressName(
        nl: 'Limburg',
        en: 'Limburg',
        fr: 'Limbourg',
        de: 'Limburg',
        es: 'Limburgo',
      ),
      FluxidiOfficialAddressName(
        nl: 'Henegouwen',
        en: 'Hainaut',
        fr: 'Hainaut',
        de: 'Hennegau',
        es: 'Henao',
      ),
      FluxidiOfficialAddressName(
        nl: 'Luik',
        en: 'Liège',
        fr: 'Liège',
        de: 'Lüttich',
        es: 'Lieja',
      ),
      FluxidiOfficialAddressName(
        nl: 'Namen',
        en: 'Namur',
        fr: 'Namur',
        de: 'Namur',
        es: 'Namur',
      ),
      FluxidiOfficialAddressName(
        nl: 'Brussel',
        en: 'Brussels',
        fr: 'Bruxelles',
        de: 'Brüssel',
        es: 'Bruselas',
      ),
      FluxidiOfficialAddressName(
        nl: 'Gent',
        en: 'Ghent',
        fr: 'Gand',
        de: 'Gent',
        es: 'Gante',
      ),
      FluxidiOfficialAddressName(
        nl: 'Brugge',
        en: 'Bruges',
        fr: 'Bruges',
        de: 'Brügge',
        es: 'Brujas',
      ),
      FluxidiOfficialAddressName(
        nl: 'Oostende',
        en: 'Ostend',
        fr: 'Ostende',
        de: 'Ostende',
        es: 'Ostende',
      ),
      FluxidiOfficialAddressName(
        nl: 'Kortrijk',
        en: 'Kortrijk',
        fr: 'Courtrai',
        de: 'Kortrijk',
        es: 'Courtrai',
      ),
      FluxidiOfficialAddressName(
        nl: 'Ronse',
        en: 'Ronse',
        fr: 'Renaix',
        de: 'Ronse',
        es: 'Ronse',
      ),
      FluxidiOfficialAddressName(
        nl: 'Oudenaarde',
        en: 'Oudenaarde',
        fr: 'Audenarde',
        de: 'Oudenaarde',
        es: 'Oudenaarde',
      ),
    ];

const Map<String, String> kFluxidiOfficialCountryCodes = <String, String>{
  'be': 'België',
  'nl': 'Nederland',
  'fr': 'Frankrijk',
  'de': 'Duitsland',
  'lu': 'Luxemburg',
};

final Map<String, FluxidiOfficialAddressName> kFluxidiOfficialAddressIndex =
    _buildOfficialAddressIndex();

Map<String, FluxidiOfficialAddressName> _buildOfficialAddressIndex() {
  final out = <String, FluxidiOfficialAddressName>{};
  void add(String raw, FluxidiOfficialAddressName name) {
    final key = fluxidiFoldOfficialAddressName(raw);
    if (key.isEmpty) return;
    out.putIfAbsent(key, () => name);
  }

  for (final name in kFluxidiOfficialAddressNames) {
    add(name.nl, name);
    add(name.en, name);
    add(name.fr, name);
    add(name.de, name);
    add(name.es, name);
  }
  const netherlands = FluxidiOfficialAddressName(
    nl: 'Nederland',
    en: 'Netherlands',
    fr: 'Pays-Bas',
    de: 'Niederlande',
    es: 'Países Bajos',
  );
  add('the netherlands', netherlands);
  add('holland', netherlands);
  return Map<String, FluxidiOfficialAddressName>.unmodifiable(out);
}

FluxidiOfficialAddressName? fluxidiOfficialAddressNameFor(String raw) {
  final folded = fluxidiFoldOfficialAddressName(raw);
  if (folded.isEmpty) return null;
  return kFluxidiOfficialAddressIndex[folded];
}

String? fluxidiOfficialAddressPart(String raw, String language) {
  final part = raw.trim();
  if (part.isEmpty) return null;
  final lang = fluxidiNormalizeAddressLanguage(language);
  final named = fluxidiOfficialAddressNameFor(part);
  if (named != null) return named.of(lang);
  if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) {
    final dutch = kFluxidiOfficialCountryCodes[part.toLowerCase()];
    if (dutch != null) {
      return fluxidiOfficialAddressNameFor(dutch)?.of(lang) ?? dutch;
    }
  }
  return null;
}

/// Rewrites only official place, province and country tokens. Streets stay as-is.
String fluxidiLocalizeAddressLabel(String label, String language) {
  final raw = label.trim();
  if (raw.isEmpty) return '';
  final lang = fluxidiNormalizeAddressLanguage(language);
  final joiner = raw.contains(' / ') && !raw.contains(',') ? ' / ' : ', ';
  return raw
      .split(RegExp(r'\s*(?:,|/)\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .map((part) => fluxidiOfficialAddressPart(part, lang) ?? part)
      .join(joiner);
}

String fluxidiMapboxLocalizedField(
  Map<Object?, Object?> feature,
  String key,
  String language,
) {
  final lang = fluxidiNormalizeAddressLanguage(language);
  final localized = (feature['${key}_$lang'] ?? '').toString().trim();
  if (localized.isNotEmpty) return localized;
  return (feature[key] ?? '').toString().trim();
}

String fluxidiMapboxFeatureIdentityLabel(Map<Object?, Object?> feature) {
  return (feature['place_name'] ?? feature['text'] ?? '').toString().trim();
}

String fluxidiMapboxReconstructLabel(
  Map<Object?, Object?> feature,
  String language,
) {
  final lang = fluxidiNormalizeAddressLanguage(language);
  final parts = <String>[];
  final head = fluxidiMapboxLocalizedField(feature, 'text', lang);
  if (head.isNotEmpty) parts.add(head);
  final context = feature['context'];
  if (context is List) {
    for (final item in context) {
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final text = fluxidiMapboxLocalizedField(map, 'text', lang);
      if (text.isEmpty) continue;
      if (parts.any(
        (part) =>
            fluxidiFoldOfficialAddressName(part) ==
            fluxidiFoldOfficialAddressName(text),
      )) {
        continue;
      }
      parts.add(text);
    }
  }
  return parts.join(', ');
}

String fluxidiMapboxFeatureDisplayLabel(
  Map<Object?, Object?> feature,
  String language,
) {
  final lang = fluxidiNormalizeAddressLanguage(language);
  final localizedPlaceName = fluxidiMapboxLocalizedField(
    feature,
    'place_name',
    lang,
  );
  if (localizedPlaceName.isNotEmpty) {
    return fluxidiLocalizeAddressLabel(localizedPlaceName, lang);
  }
  final reconstructed = fluxidiMapboxReconstructLabel(feature, lang);
  if (reconstructed.isNotEmpty) {
    return fluxidiLocalizeAddressLabel(reconstructed, lang);
  }
  return fluxidiLocalizeAddressLabel(
    fluxidiMapboxFeatureIdentityLabel(feature),
    lang,
  );
}
