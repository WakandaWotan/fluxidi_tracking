// Official place, province and country names for address display.
// Street names and house tokens are never rewritten.

class LimousineOfficialAddressName {
  const LimousineOfficialAddressName({
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

String limousineFoldOfficialAddressName(String raw) {
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

String limousineNormalizeAddressLanguage(String raw) {
  final language = raw.trim().toLowerCase();
  if (language.isEmpty) return 'nl';
  return language.split(RegExp(r'[,_]')).first.trim();
}

const List<LimousineOfficialAddressName> kLimousineOfficialAddressNames =
    <LimousineOfficialAddressName>[
      LimousineOfficialAddressName(
        nl: 'België',
        en: 'Belgium',
        fr: 'Belgique',
        de: 'Belgien',
        es: 'Bélgica',
      ),
      LimousineOfficialAddressName(
        nl: 'Nederland',
        en: 'Netherlands',
        fr: 'Pays-Bas',
        de: 'Niederlande',
        es: 'Países Bajos',
      ),
      LimousineOfficialAddressName(
        nl: 'Frankrijk',
        en: 'France',
        fr: 'France',
        de: 'Frankreich',
        es: 'Francia',
      ),
      LimousineOfficialAddressName(
        nl: 'Duitsland',
        en: 'Germany',
        fr: 'Allemagne',
        de: 'Deutschland',
        es: 'Alemania',
      ),
      LimousineOfficialAddressName(
        nl: 'Luxemburg',
        en: 'Luxembourg',
        fr: 'Luxembourg',
        de: 'Luxemburg',
        es: 'Luxemburgo',
      ),
      LimousineOfficialAddressName(
        nl: 'Spanje',
        en: 'Spain',
        fr: 'Espagne',
        de: 'Spanien',
        es: 'España',
      ),
      LimousineOfficialAddressName(
        nl: 'Oost-Vlaanderen',
        en: 'East Flanders',
        fr: 'Flandre-Orientale',
        de: 'Ostflandern',
        es: 'Flandes Oriental',
      ),
      LimousineOfficialAddressName(
        nl: 'West-Vlaanderen',
        en: 'West Flanders',
        fr: 'Flandre-Occidentale',
        de: 'Westflandern',
        es: 'Flandes Occidental',
      ),
      LimousineOfficialAddressName(
        nl: 'Vlaams-Brabant',
        en: 'Flemish Brabant',
        fr: 'Brabant flamand',
        de: 'Flämisch-Brabant',
        es: 'Brabante Flamenco',
      ),
      LimousineOfficialAddressName(
        nl: 'Waals-Brabant',
        en: 'Walloon Brabant',
        fr: 'Brabant wallon',
        de: 'Wallonisch-Brabant',
        es: 'Brabante Valón',
      ),
      LimousineOfficialAddressName(
        nl: 'Antwerpen',
        en: 'Antwerp',
        fr: 'Anvers',
        de: 'Antwerpen',
        es: 'Amberes',
      ),
      LimousineOfficialAddressName(
        nl: 'Limburg',
        en: 'Limburg',
        fr: 'Limbourg',
        de: 'Limburg',
        es: 'Limburgo',
      ),
      LimousineOfficialAddressName(
        nl: 'Henegouwen',
        en: 'Hainaut',
        fr: 'Hainaut',
        de: 'Hennegau',
        es: 'Henao',
      ),
      LimousineOfficialAddressName(
        nl: 'Luik',
        en: 'Liège',
        fr: 'Liège',
        de: 'Lüttich',
        es: 'Lieja',
      ),
      LimousineOfficialAddressName(
        nl: 'Namen',
        en: 'Namur',
        fr: 'Namur',
        de: 'Namur',
        es: 'Namur',
      ),
      LimousineOfficialAddressName(
        nl: 'Luxemburg',
        en: 'Luxembourg',
        fr: 'Luxembourg',
        de: 'Luxemburg',
        es: 'Luxemburgo',
      ),
      LimousineOfficialAddressName(
        nl: 'Brussel',
        en: 'Brussels',
        fr: 'Bruxelles',
        de: 'Brüssel',
        es: 'Bruselas',
      ),
      LimousineOfficialAddressName(
        nl: 'Gent',
        en: 'Ghent',
        fr: 'Gand',
        de: 'Gent',
        es: 'Gante',
      ),
      LimousineOfficialAddressName(
        nl: 'Brugge',
        en: 'Bruges',
        fr: 'Bruges',
        de: 'Brügge',
        es: 'Brujas',
      ),
      LimousineOfficialAddressName(
        nl: 'Oostende',
        en: 'Ostend',
        fr: 'Ostende',
        de: 'Ostende',
        es: 'Ostende',
      ),
      LimousineOfficialAddressName(
        nl: 'Kortrijk',
        en: 'Kortrijk',
        fr: 'Courtrai',
        de: 'Kortrijk',
        es: 'Courtrai',
      ),
      LimousineOfficialAddressName(
        nl: 'Ronse',
        en: 'Ronse',
        fr: 'Renaix',
        de: 'Ronse',
        es: 'Ronse',
      ),
      LimousineOfficialAddressName(
        nl: 'Oudenaarde',
        en: 'Oudenaarde',
        fr: 'Audenarde',
        de: 'Oudenaarde',
        es: 'Oudenaarde',
      ),
      LimousineOfficialAddressName(
        nl: 'Mechelen',
        en: 'Mechelen',
        fr: 'Malines',
        de: 'Mechelen',
        es: 'Malinas',
      ),
      LimousineOfficialAddressName(
        nl: 'Leuven',
        en: 'Leuven',
        fr: 'Louvain',
        de: 'Löwen',
        es: 'Lovaina',
      ),
    ];

const Map<String, String> kLimousineOfficialCountryCodes = <String, String>{
  'be': 'België',
  'nl': 'Nederland',
  'fr': 'Frankrijk',
  'de': 'Duitsland',
  'lu': 'Luxemburg',
  'es': 'Spanje',
};

final Map<String, LimousineOfficialAddressName> kLimousineOfficialAddressIndex =
    _buildOfficialAddressIndex();

Map<String, LimousineOfficialAddressName> _buildOfficialAddressIndex() {
  final out = <String, LimousineOfficialAddressName>{};
  void add(String raw, LimousineOfficialAddressName name) {
    final key = limousineFoldOfficialAddressName(raw);
    if (key.isEmpty) return;
    out.putIfAbsent(key, () => name);
  }

  for (final name in kLimousineOfficialAddressNames) {
    add(name.nl, name);
    add(name.en, name);
    add(name.fr, name);
    add(name.de, name);
    add(name.es, name);
  }
  const netherlands = LimousineOfficialAddressName(
    nl: 'Nederland',
    en: 'Netherlands',
    fr: 'Pays-Bas',
    de: 'Niederlande',
    es: 'Países Bajos',
  );
  const brussels = LimousineOfficialAddressName(
    nl: 'Brussel',
    en: 'Brussels',
    fr: 'Bruxelles',
    de: 'Brüssel',
    es: 'Bruselas',
  );
  add('the netherlands', netherlands);
  add('holland', netherlands);
  add('brussels capital', brussels);
  add('brussels hoofdstedelijk gewest', brussels);
  add('region de bruxelles capitale', brussels);
  return Map<String, LimousineOfficialAddressName>.unmodifiable(out);
}

LimousineOfficialAddressName? limousineOfficialAddressNameFor(String raw) {
  final folded = limousineFoldOfficialAddressName(raw);
  if (folded.isEmpty) return null;
  return kLimousineOfficialAddressIndex[folded];
}

String? limousineOfficialAddressPart(String raw, String language) {
  final part = raw.trim();
  if (part.isEmpty) return null;
  final lang = limousineNormalizeAddressLanguage(language);
  final named = limousineOfficialAddressNameFor(part);
  if (named != null) return named.of(lang);
  if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) {
    final dutch = kLimousineOfficialCountryCodes[part.toLowerCase()];
    if (dutch != null) {
      return limousineOfficialAddressNameFor(dutch)?.of(lang) ?? dutch;
    }
  }
  return null;
}

/// Rewrites only official place, province and country tokens. Streets stay as-is.
String limousineLocalizeAddressLabel(String label, String language) {
  final raw = label.trim();
  if (raw.isEmpty) return '';
  final lang = limousineNormalizeAddressLanguage(language);
  final joiner = raw.contains(' / ') && !raw.contains(',') ? ' / ' : ', ';
  return raw
      .split(RegExp(r'\s*(?:,|/)\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .map((part) => limousineOfficialAddressPart(part, lang) ?? part)
      .join(joiner);
}

String limousineMapboxLocalizedField(
  Map<Object?, Object?> feature,
  String key,
  String language,
) {
  final lang = limousineNormalizeAddressLanguage(language);
  final localized = (feature['${key}_$lang'] ?? '').toString().trim();
  if (localized.isNotEmpty) return localized;
  return (feature[key] ?? '').toString().trim();
}

String limousineMapboxFeatureIdentityLabel(Map<Object?, Object?> feature) {
  return (feature['place_name'] ?? feature['text'] ?? '').toString().trim();
}

String limousineMapboxReconstructLabel(
  Map<Object?, Object?> feature,
  String language,
) {
  final lang = limousineNormalizeAddressLanguage(language);
  final parts = <String>[];
  final head = limousineMapboxLocalizedField(feature, 'text', lang);
  if (head.isNotEmpty) parts.add(head);
  final context = feature['context'];
  if (context is List) {
    for (final item in context) {
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final text = limousineMapboxLocalizedField(map, 'text', lang);
      if (text.isEmpty) continue;
      if (parts.any(
        (part) =>
            limousineFoldOfficialAddressName(part) ==
            limousineFoldOfficialAddressName(text),
      )) {
        continue;
      }
      parts.add(text);
    }
  }
  return parts.join(', ');
}

/// Display label from a Mapbox feature, using the endpoint language and
/// official translations. The raw [place_name] stays the identity label.
String limousineMapboxFeatureDisplayLabel(
  Map<Object?, Object?> feature,
  String language,
) {
  final lang = limousineNormalizeAddressLanguage(language);
  final localizedPlaceName = limousineMapboxLocalizedField(
    feature,
    'place_name',
    lang,
  );
  if (localizedPlaceName.isNotEmpty) {
    return limousineLocalizeAddressLabel(localizedPlaceName, lang);
  }
  final reconstructed = limousineMapboxReconstructLabel(feature, lang);
  if (reconstructed.isNotEmpty) {
    return limousineLocalizeAddressLabel(reconstructed, lang);
  }
  return limousineLocalizeAddressLabel(
    limousineMapboxFeatureIdentityLabel(feature),
    lang,
  );
}
