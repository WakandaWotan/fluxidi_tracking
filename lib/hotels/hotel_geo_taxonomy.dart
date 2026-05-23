class HotelGeoSettlementKind {
  static const String city = 'city';
  static const String town = 'town';
  static const String village = 'village';
}

class HotelGeoLabel {
  const HotelGeoLabel({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
  });

  final String nl;
  final String en;
  final String fr;
  final String es;

  String of(String languageCode) {
    switch (languageCode.trim().toLowerCase()) {
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      case 'es':
        return es;
      case 'en':
      default:
        return en;
    }
  }

  Set<String> allValuesNormalized() {
    return <String>{nl, en, fr, es}
        .where((value) => value.trim().isNotEmpty)
        .map((value) => value.trim().toLowerCase())
        .toSet();
  }
}

class HotelGeoSettlement {
  const HotelGeoSettlement({
    required this.key,
    required this.labels,
    required this.kind,
  });

  final String key;
  final HotelGeoLabel labels;
  final String kind;
}

class HotelGeoRegion {
  const HotelGeoRegion({
    required this.key,
    required this.labels,
    this.settlements = const <HotelGeoSettlement>[],
  });

  final String key;
  final HotelGeoLabel labels;
  final List<HotelGeoSettlement> settlements;
}

class HotelGeoCountry {
  const HotelGeoCountry({
    required this.code,
    required this.labels,
    this.regions = const <HotelGeoRegion>[],
  });

  final String code;
  final HotelGeoLabel labels;
  final List<HotelGeoRegion> regions;
}

class HotelGeoOption {
  const HotelGeoOption({required this.value, required this.label});

  final String value;
  final String label;
}

const List<HotelGeoCountry> kHotelGeoTaxonomy = <HotelGeoCountry>[
  HotelGeoCountry(
    code: 'BE',
    labels: HotelGeoLabel(
      nl: 'België',
      en: 'Belgium',
      fr: 'Belgique',
      es: 'Bélgica',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'west-vlaanderen',
        labels: HotelGeoLabel(
          nl: 'West-Vlaanderen',
          en: 'West Flanders',
          fr: 'Flandre-Occidentale',
          es: 'Flandes Occidental',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'brugge',
            labels: HotelGeoLabel(
              nl: 'Brugge',
              en: 'Brugge',
              fr: 'Bruges',
              es: 'Brujas',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'knokke-heist',
            labels: HotelGeoLabel(
              nl: 'Knokke-Heist',
              en: 'Knokke-Heist',
              fr: 'Knokke-Heist',
              es: 'Knokke-Heist',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'oostende',
            labels: HotelGeoLabel(
              nl: 'Oostende',
              en: 'Oostende',
              fr: 'Ostende',
              es: 'Ostende',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'de-panne',
            labels: HotelGeoLabel(
              nl: 'De Panne',
              en: 'De Panne',
              fr: 'La Panne',
              es: 'De Panne',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'antwerpen',
        labels: HotelGeoLabel(
          nl: 'Antwerpen',
          en: 'Antwerp',
          fr: 'Anvers',
          es: 'Amberes',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'antwerpen',
            labels: HotelGeoLabel(
              nl: 'Antwerpen',
              en: 'Antwerp',
              fr: 'Anvers',
              es: 'Amberes',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'mechelen',
            labels: HotelGeoLabel(
              nl: 'Mechelen',
              en: 'Mechelen',
              fr: 'Malines',
              es: 'Malinas',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'turnhout',
            labels: HotelGeoLabel(
              nl: 'Turnhout',
              en: 'Turnhout',
              fr: 'Turnhout',
              es: 'Turnhout',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'oost-vlaanderen',
        labels: HotelGeoLabel(
          nl: 'Oost-Vlaanderen',
          en: 'East Flanders',
          fr: 'Flandre-Orientale',
          es: 'Flandes Oriental',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'gent',
            labels: HotelGeoLabel(
              nl: 'Gent',
              en: 'Ghent',
              fr: 'Gand',
              es: 'Gante',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'aalst',
            labels: HotelGeoLabel(
              nl: 'Aalst',
              en: 'Aalst',
              fr: 'Alost',
              es: 'Aalst',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'oudenaarde',
            labels: HotelGeoLabel(
              nl: 'Oudenaarde',
              en: 'Oudenaarde',
              fr: 'Audenarde',
              es: 'Oudenaarde',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'ronse',
            labels: HotelGeoLabel(
              nl: 'Ronse',
              en: 'Ronse',
              fr: 'Renaix',
              es: 'Ronse',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'brakel',
            labels: HotelGeoLabel(
              nl: 'Brakel',
              en: 'Brakel',
              fr: 'Brakel',
              es: 'Brakel',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
          HotelGeoSettlement(
            key: 'kluisbergen',
            labels: HotelGeoLabel(
              nl: 'Kluisbergen',
              en: 'Kluisbergen',
              fr: 'Kluisbergen',
              es: 'Kluisbergen',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
          HotelGeoSettlement(
            key: 'maarkedal',
            labels: HotelGeoLabel(
              nl: 'Maarkedal',
              en: 'Maarkedal',
              fr: 'Maarkedal',
              es: 'Maarkedal',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
          HotelGeoSettlement(
            key: 'horebeke',
            labels: HotelGeoLabel(
              nl: 'Horebeke',
              en: 'Horebeke',
              fr: 'Horebeke',
              es: 'Horebeke',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
          HotelGeoSettlement(
            key: 'zwalm',
            labels: HotelGeoLabel(
              nl: 'Zwalm',
              en: 'Zwalm',
              fr: 'Zwalm',
              es: 'Zwalm',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
          HotelGeoSettlement(
            key: 'zottegem',
            labels: HotelGeoLabel(
              nl: 'Zottegem',
              en: 'Zottegem',
              fr: 'Zottegem',
              es: 'Zottegem',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'geraardsbergen',
            labels: HotelGeoLabel(
              nl: 'Geraardsbergen',
              en: 'Geraardsbergen',
              fr: 'Grammont',
              es: 'Geraardsbergen',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'limburg-be',
        labels: HotelGeoLabel(
          nl: 'Limburg',
          en: 'Limburg',
          fr: 'Limbourg',
          es: 'Limburgo',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'hasselt',
            labels: HotelGeoLabel(
              nl: 'Hasselt',
              en: 'Hasselt',
              fr: 'Hasselt',
              es: 'Hasselt',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'genk',
            labels: HotelGeoLabel(
              nl: 'Genk',
              en: 'Genk',
              fr: 'Genk',
              es: 'Genk',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'tongeren',
            labels: HotelGeoLabel(
              nl: 'Tongeren',
              en: 'Tongeren',
              fr: 'Tongres',
              es: 'Tongeren',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'vlaams-brabant',
        labels: HotelGeoLabel(
          nl: 'Vlaams-Brabant',
          en: 'Flemish Brabant',
          fr: 'Brabant flamand',
          es: 'Brabante Flamenco',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'leuven',
            labels: HotelGeoLabel(
              nl: 'Leuven',
              en: 'Leuven',
              fr: 'Louvain',
              es: 'Lovaina',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'tienen',
            labels: HotelGeoLabel(
              nl: 'Tienen',
              en: 'Tienen',
              fr: 'Tirlemont',
              es: 'Tirlemont',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'diest',
            labels: HotelGeoLabel(
              nl: 'Diest',
              en: 'Diest',
              fr: 'Diest',
              es: 'Diest',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'waals-brabant',
        labels: HotelGeoLabel(
          nl: 'Waals-Brabant',
          en: 'Walloon Brabant',
          fr: 'Brabant wallon',
          es: 'Brabante Valón',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'waver',
            labels: HotelGeoLabel(
              nl: 'Waver',
              en: 'Wavre',
              fr: 'Wavre',
              es: 'Wavre',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'louvain-la-neuve',
            labels: HotelGeoLabel(
              nl: 'Louvain-la-Neuve',
              en: 'Louvain-la-Neuve',
              fr: 'Louvain-la-Neuve',
              es: 'Louvain-la-Neuve',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'waterloo',
            labels: HotelGeoLabel(
              nl: 'Waterloo',
              en: 'Waterloo',
              fr: 'Waterloo',
              es: 'Waterloo',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'nijvel',
            labels: HotelGeoLabel(
              nl: 'Nijvel',
              en: 'Nivelles',
              fr: 'Nivelles',
              es: 'Nivelles',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'henegouwen',
        labels: HotelGeoLabel(
          nl: 'Henegouwen',
          en: 'Hainaut',
          fr: 'Hainaut',
          es: 'Henao',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'bergen',
            labels: HotelGeoLabel(
              nl: 'Bergen',
              en: 'Mons',
              fr: 'Mons',
              es: 'Mons',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'charleroi',
            labels: HotelGeoLabel(
              nl: 'Charleroi',
              en: 'Charleroi',
              fr: 'Charleroi',
              es: 'Charleroi',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'doornik',
            labels: HotelGeoLabel(
              nl: 'Doornik',
              en: 'Tournai',
              fr: 'Tournai',
              es: 'Tournai',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'lessines',
            labels: HotelGeoLabel(
              nl: 'Lessines',
              en: 'Lessines',
              fr: 'Lessines',
              es: 'Lessines',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'ellezelles',
            labels: HotelGeoLabel(
              nl: 'Ellezelles',
              en: 'Ellezelles',
              fr: 'Ellezelles',
              es: 'Ellezelles',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'luik',
        labels: HotelGeoLabel(
          nl: 'Luik',
          en: 'Liège',
          fr: 'Liège',
          es: 'Lieja',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'luik',
            labels: HotelGeoLabel(
              nl: 'Luik',
              en: 'Liège',
              fr: 'Liège',
              es: 'Lieja',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'verviers',
            labels: HotelGeoLabel(
              nl: 'Verviers',
              en: 'Verviers',
              fr: 'Verviers',
              es: 'Verviers',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'spa',
            labels: HotelGeoLabel(nl: 'Spa', en: 'Spa', fr: 'Spa', es: 'Spa'),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'malmedy',
            labels: HotelGeoLabel(
              nl: 'Malmedy',
              en: 'Malmedy',
              fr: 'Malmedy',
              es: 'Malmedy',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'namen',
        labels: HotelGeoLabel(
          nl: 'Namen',
          en: 'Namur',
          fr: 'Namur',
          es: 'Namur',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'namen',
            labels: HotelGeoLabel(
              nl: 'Namen',
              en: 'Namur',
              fr: 'Namur',
              es: 'Namur',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'dinant',
            labels: HotelGeoLabel(
              nl: 'Dinant',
              en: 'Dinant',
              fr: 'Dinant',
              es: 'Dinant',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'luxemburg-be',
        labels: HotelGeoLabel(
          nl: 'Luxemburg',
          en: 'Luxembourg',
          fr: 'Luxembourg',
          es: 'Luxemburgo',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'aarlen',
            labels: HotelGeoLabel(
              nl: 'Aarlen',
              en: 'Arlon',
              fr: 'Arlon',
              es: 'Arlon',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'durbuy',
            labels: HotelGeoLabel(
              nl: 'Durbuy',
              en: 'Durbuy',
              fr: 'Durbuy',
              es: 'Durbuy',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'bastogne',
            labels: HotelGeoLabel(
              nl: 'Bastogne',
              en: 'Bastogne',
              fr: 'Bastogne',
              es: 'Bastogne',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'bouillon',
            labels: HotelGeoLabel(
              nl: 'Bouillon',
              en: 'Bouillon',
              fr: 'Bouillon',
              es: 'Bouillon',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'brussels-hoofdstedelijk-gewest',
        labels: HotelGeoLabel(
          nl: 'Brussels Hoofdstedelijk Gewest',
          en: 'Brussels Capital Region',
          fr: 'Région de Bruxelles-Capitale',
          es: 'Región de Bruselas-Capital',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'brussel',
            labels: HotelGeoLabel(
              nl: 'Brussel',
              en: 'Brussels',
              fr: 'Bruxelles',
              es: 'Bruselas',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'schaarbeek',
            labels: HotelGeoLabel(
              nl: 'Schaarbeek',
              en: 'Schaerbeek',
              fr: 'Schaerbeek',
              es: 'Schaerbeek',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'elsene',
            labels: HotelGeoLabel(
              nl: 'Elsene',
              en: 'Ixelles',
              fr: 'Ixelles',
              es: 'Ixelles',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'anderlecht',
            labels: HotelGeoLabel(
              nl: 'Anderlecht',
              en: 'Anderlecht',
              fr: 'Anderlecht',
              es: 'Anderlecht',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
    ],
  ),
  HotelGeoCountry(
    code: 'NL',
    labels: HotelGeoLabel(
      nl: 'Nederland',
      en: 'Netherlands',
      fr: 'Pays-Bas',
      es: 'Países Bajos',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'noord-holland',
        labels: HotelGeoLabel(
          nl: 'Noord-Holland',
          en: 'North Holland',
          fr: 'Hollande-Septentrionale',
          es: 'Holanda Septentrional',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'amsterdam',
            labels: HotelGeoLabel(
              nl: 'Amsterdam',
              en: 'Amsterdam',
              fr: 'Amsterdam',
              es: 'Ámsterdam',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'zandvoort',
            labels: HotelGeoLabel(
              nl: 'Zandvoort',
              en: 'Zandvoort',
              fr: 'Zandvoort',
              es: 'Zandvoort',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'haarlem',
            labels: HotelGeoLabel(
              nl: 'Haarlem',
              en: 'Haarlem',
              fr: 'Haarlem',
              es: 'Haarlem',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'de-koog',
            labels: HotelGeoLabel(
              nl: 'De Koog',
              en: 'De Koog',
              fr: 'De Koog',
              es: 'De Koog',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'zeeland',
        labels: HotelGeoLabel(
          nl: 'Zeeland',
          en: 'Zealand',
          fr: 'Zélande',
          es: 'Zelanda',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'domburg',
            labels: HotelGeoLabel(
              nl: 'Domburg',
              en: 'Domburg',
              fr: 'Dombourg',
              es: 'Domburg',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'renesse',
            labels: HotelGeoLabel(
              nl: 'Renesse',
              en: 'Renesse',
              fr: 'Renesse',
              es: 'Renesse',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'middelburg',
            labels: HotelGeoLabel(
              nl: 'Middelburg',
              en: 'Middelburg',
              fr: 'Middelbourg',
              es: 'Middelburgo',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'limburg-nl',
        labels: HotelGeoLabel(
          nl: 'Limburg',
          en: 'Limburg',
          fr: 'Limbourg',
          es: 'Limburgo',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'valkenburg-aan-de-geul',
            labels: HotelGeoLabel(
              nl: 'Valkenburg aan de Geul',
              en: 'Valkenburg aan de Geul',
              fr: 'Valkenburg aan de Geul',
              es: 'Valkenburg aan de Geul',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'maastricht',
            labels: HotelGeoLabel(
              nl: 'Maastricht',
              en: 'Maastricht',
              fr: 'Maastricht',
              es: 'Maastricht',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'gulpen',
            labels: HotelGeoLabel(
              nl: 'Gulpen',
              en: 'Gulpen',
              fr: 'Gulpen',
              es: 'Gulpen',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'gelderland',
        labels: HotelGeoLabel(
          nl: 'Gelderland',
          en: 'Gelderland',
          fr: 'Gueldre',
          es: 'Güeldres',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'apeldoorn',
            labels: HotelGeoLabel(
              nl: 'Apeldoorn',
              en: 'Apeldoorn',
              fr: 'Apeldoorn',
              es: 'Apeldoorn',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'otterlo',
            labels: HotelGeoLabel(
              nl: 'Otterlo',
              en: 'Otterlo',
              fr: 'Otterlo',
              es: 'Otterlo',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'zuid-holland',
        labels: HotelGeoLabel(
          nl: 'Zuid-Holland',
          en: 'South Holland',
          fr: 'Hollande-Méridionale',
          es: 'Holanda Meridional',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'rotterdam',
            labels: HotelGeoLabel(
              nl: 'Rotterdam',
              en: 'Rotterdam',
              fr: 'Rotterdam',
              es: 'Rotterdam',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'den-haag',
            labels: HotelGeoLabel(
              nl: 'Den Haag',
              en: 'The Hague',
              fr: 'La Haye',
              es: 'La Haya',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'leiden',
            labels: HotelGeoLabel(
              nl: 'Leiden',
              en: 'Leiden',
              fr: 'Leyde',
              es: 'Leiden',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'utrecht',
        labels: HotelGeoLabel(
          nl: 'Utrecht',
          en: 'Utrecht',
          fr: 'Utrecht',
          es: 'Utrecht',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'utrecht-city',
            labels: HotelGeoLabel(
              nl: 'Utrecht',
              en: 'Utrecht',
              fr: 'Utrecht',
              es: 'Utrecht',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'amersfoort',
            labels: HotelGeoLabel(
              nl: 'Amersfoort',
              en: 'Amersfoort',
              fr: 'Amersfoort',
              es: 'Amersfoort',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
    ],
  ),
  HotelGeoCountry(
    code: 'FR',
    labels: HotelGeoLabel(
      nl: 'Frankrijk',
      en: 'France',
      fr: 'France',
      es: 'Francia',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'provence-alpes-cote-d-azur',
        labels: HotelGeoLabel(
          nl: 'Provence-Alpes-Côte d\'Azur',
          en: 'Provence-Alpes-Côte d\'Azur',
          fr: 'Provence-Alpes-Côte d\'Azur',
          es: 'Provenza-Alpes-Costa Azul',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'nice',
            labels: HotelGeoLabel(
              nl: 'Nice',
              en: 'Nice',
              fr: 'Nice',
              es: 'Niza',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'cannes',
            labels: HotelGeoLabel(
              nl: 'Cannes',
              en: 'Cannes',
              fr: 'Cannes',
              es: 'Cannes',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'saint-tropez',
            labels: HotelGeoLabel(
              nl: 'Saint-Tropez',
              en: 'Saint-Tropez',
              fr: 'Saint-Tropez',
              es: 'Saint-Tropez',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'gordes',
            labels: HotelGeoLabel(
              nl: 'Gordes',
              en: 'Gordes',
              fr: 'Gordes',
              es: 'Gordes',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'ile-de-france',
        labels: HotelGeoLabel(
          nl: 'Île-de-France',
          en: 'Île-de-France',
          fr: 'Île-de-France',
          es: 'Isla de Francia',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'paris',
            labels: HotelGeoLabel(
              nl: 'Parijs',
              en: 'Paris',
              fr: 'Paris',
              es: 'París',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'versailles',
            labels: HotelGeoLabel(
              nl: 'Versailles',
              en: 'Versailles',
              fr: 'Versailles',
              es: 'Versalles',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'normandie',
        labels: HotelGeoLabel(
          nl: 'Normandië',
          en: 'Normandy',
          fr: 'Normandie',
          es: 'Normandía',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'honfleur',
            labels: HotelGeoLabel(
              nl: 'Honfleur',
              en: 'Honfleur',
              fr: 'Honfleur',
              es: 'Honfleur',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'deauville',
            labels: HotelGeoLabel(
              nl: 'Deauville',
              en: 'Deauville',
              fr: 'Deauville',
              es: 'Deauville',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'etretat',
            labels: HotelGeoLabel(
              nl: 'Étretat',
              en: 'Étretat',
              fr: 'Étretat',
              es: 'Étretat',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'hauts-de-france',
        labels: HotelGeoLabel(
          nl: 'Hauts-de-France',
          en: 'Hauts-de-France',
          fr: 'Hauts-de-France',
          es: 'Altos de Francia',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'lille',
            labels: HotelGeoLabel(
              nl: 'Lille',
              en: 'Lille',
              fr: 'Lille',
              es: 'Lille',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'calais',
            labels: HotelGeoLabel(
              nl: 'Calais',
              en: 'Calais',
              fr: 'Calais',
              es: 'Calais',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'dunkerque',
            labels: HotelGeoLabel(
              nl: 'Dunkerque',
              en: 'Dunkirk',
              fr: 'Dunkerque',
              es: 'Dunkerque',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'auvergne-rhone-alpes',
        labels: HotelGeoLabel(
          nl: 'Auvergne-Rhône-Alpes',
          en: 'Auvergne-Rhône-Alpes',
          fr: 'Auvergne-Rhône-Alpes',
          es: 'Auvernia-Ródano-Alpes',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'lyon',
            labels: HotelGeoLabel(
              nl: 'Lyon',
              en: 'Lyon',
              fr: 'Lyon',
              es: 'Lyon',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'annecy',
            labels: HotelGeoLabel(
              nl: 'Annecy',
              en: 'Annecy',
              fr: 'Annecy',
              es: 'Annecy',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'chamonix',
            labels: HotelGeoLabel(
              nl: 'Chamonix',
              en: 'Chamonix',
              fr: 'Chamonix',
              es: 'Chamonix',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
    ],
  ),
  HotelGeoCountry(
    code: 'DE',
    labels: HotelGeoLabel(
      nl: 'Duitsland',
      en: 'Germany',
      fr: 'Allemagne',
      es: 'Alemania',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'berlin',
        labels: HotelGeoLabel(
          nl: 'Berlijn',
          en: 'Berlin',
          fr: 'Berlin',
          es: 'Berlín',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'berlin-city',
            labels: HotelGeoLabel(
              nl: 'Berlijn',
              en: 'Berlin',
              fr: 'Berlin',
              es: 'Berlín',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'north-rhine-westphalia',
        labels: HotelGeoLabel(
          nl: 'Noordrijn-Westfalen',
          en: 'North Rhine-Westphalia',
          fr: 'Rhénanie-du-Nord-Westphalie',
          es: 'Renania del Norte-Westfalia',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'cologne',
            labels: HotelGeoLabel(
              nl: 'Keulen',
              en: 'Cologne',
              fr: 'Cologne',
              es: 'Colonia',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'dusseldorf',
            labels: HotelGeoLabel(
              nl: 'Düsseldorf',
              en: 'Düsseldorf',
              fr: 'Düsseldorf',
              es: 'Düsseldorf',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'aachen',
            labels: HotelGeoLabel(
              nl: 'Aken',
              en: 'Aachen',
              fr: 'Aix-la-Chapelle',
              es: 'Aquisgrán',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'bavaria',
        labels: HotelGeoLabel(
          nl: 'Beieren',
          en: 'Bavaria',
          fr: 'Bavière',
          es: 'Baviera',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'munich',
            labels: HotelGeoLabel(
              nl: 'München',
              en: 'Munich',
              fr: 'Munich',
              es: 'Múnich',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'nuremberg',
            labels: HotelGeoLabel(
              nl: 'Neurenberg',
              en: 'Nuremberg',
              fr: 'Nuremberg',
              es: 'Núremberg',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'fussen',
            labels: HotelGeoLabel(
              nl: 'Füssen',
              en: 'Füssen',
              fr: 'Füssen',
              es: 'Füssen',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'baden-wurttemberg',
        labels: HotelGeoLabel(
          nl: 'Baden-Württemberg',
          en: 'Baden-Württemberg',
          fr: 'Bade-Wurtemberg',
          es: 'Baden-Wurtemberg',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'stuttgart',
            labels: HotelGeoLabel(
              nl: 'Stuttgart',
              en: 'Stuttgart',
              fr: 'Stuttgart',
              es: 'Stuttgart',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'heidelberg',
            labels: HotelGeoLabel(
              nl: 'Heidelberg',
              en: 'Heidelberg',
              fr: 'Heidelberg',
              es: 'Heidelberg',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'freiburg-im-breisgau',
            labels: HotelGeoLabel(
              nl: 'Freiburg im Breisgau',
              en: 'Freiburg im Breisgau',
              fr: 'Fribourg-en-Brisgau',
              es: 'Friburgo de Brisgovia',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'rhineland-palatinate',
        labels: HotelGeoLabel(
          nl: 'Rijnland-Palts',
          en: 'Rhineland-Palatinate',
          fr: 'Rhénanie-Palatinat',
          es: 'Renania-Palatinado',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'trier',
            labels: HotelGeoLabel(
              nl: 'Trier',
              en: 'Trier',
              fr: 'Trèves',
              es: 'Tréveris',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'koblenz',
            labels: HotelGeoLabel(
              nl: 'Koblenz',
              en: 'Koblenz',
              fr: 'Coblence',
              es: 'Coblenza',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
    ],
  ),
  HotelGeoCountry(
    code: 'LU',
    labels: HotelGeoLabel(
      nl: 'Luxemburg',
      en: 'Luxembourg',
      fr: 'Luxembourg',
      es: 'Luxemburgo',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'luxembourg',
        labels: HotelGeoLabel(
          nl: 'Luxembourg',
          en: 'Luxembourg',
          fr: 'Luxembourg',
          es: 'Luxemburgo',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'luxembourg-city',
            labels: HotelGeoLabel(
              nl: 'Luxembourg City',
              en: 'Luxembourg City',
              fr: 'Luxembourg-Ville',
              es: 'Ciudad de Luxemburgo',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'echternach',
            labels: HotelGeoLabel(
              nl: 'Echternach',
              en: 'Echternach',
              fr: 'Echternach',
              es: 'Echternach',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'vianden',
            labels: HotelGeoLabel(
              nl: 'Vianden',
              en: 'Vianden',
              fr: 'Vianden',
              es: 'Vianden',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'clervaux',
            labels: HotelGeoLabel(
              nl: 'Clervaux',
              en: 'Clervaux',
              fr: 'Clervaux',
              es: 'Clervaux',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
    ],
  ),
  HotelGeoCountry(
    code: 'GB',
    labels: HotelGeoLabel(
      nl: 'Verenigd Koninkrijk',
      en: 'United Kingdom',
      fr: 'Royaume-Uni',
      es: 'Reino Unido',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'greater-london',
        labels: HotelGeoLabel(
          nl: 'Greater London',
          en: 'Greater London',
          fr: 'Grand Londres',
          es: 'Gran Londres',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'london',
            labels: HotelGeoLabel(
              nl: 'London',
              en: 'London',
              fr: 'Londres',
              es: 'Londres',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'cumbria',
        labels: HotelGeoLabel(
          nl: 'Cumbria',
          en: 'Cumbria',
          fr: 'Cumbria',
          es: 'Cumbria',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'windermere',
            labels: HotelGeoLabel(
              nl: 'Windermere',
              en: 'Windermere',
              fr: 'Windermere',
              es: 'Windermere',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'ambleside',
            labels: HotelGeoLabel(
              nl: 'Ambleside',
              en: 'Ambleside',
              fr: 'Ambleside',
              es: 'Ambleside',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'keswick',
            labels: HotelGeoLabel(
              nl: 'Keswick',
              en: 'Keswick',
              fr: 'Keswick',
              es: 'Keswick',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'gloucestershire',
        labels: HotelGeoLabel(
          nl: 'Gloucestershire',
          en: 'Gloucestershire',
          fr: 'Gloucestershire',
          es: 'Gloucestershire',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'bourton-on-the-water',
            labels: HotelGeoLabel(
              nl: 'Bourton-on-the-Water',
              en: 'Bourton-on-the-Water',
              fr: 'Bourton-on-the-Water',
              es: 'Bourton-on-the-Water',
            ),
            kind: HotelGeoSettlementKind.village,
          ),
          HotelGeoSettlement(
            key: 'chipping-campden',
            labels: HotelGeoLabel(
              nl: 'Chipping Campden',
              en: 'Chipping Campden',
              fr: 'Chipping Campden',
              es: 'Chipping Campden',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'scotland',
        labels: HotelGeoLabel(
          nl: 'Schotland',
          en: 'Scotland',
          fr: 'Écosse',
          es: 'Escocia',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'edinburgh',
            labels: HotelGeoLabel(
              nl: 'Edinburgh',
              en: 'Edinburgh',
              fr: 'Édimbourg',
              es: 'Edimburgo',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'inverness',
            labels: HotelGeoLabel(
              nl: 'Inverness',
              en: 'Inverness',
              fr: 'Inverness',
              es: 'Inverness',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'greater-manchester',
        labels: HotelGeoLabel(
          nl: 'Greater Manchester',
          en: 'Greater Manchester',
          fr: 'Grand Manchester',
          es: 'Gran Mánchester',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'manchester',
            labels: HotelGeoLabel(
              nl: 'Manchester',
              en: 'Manchester',
              fr: 'Manchester',
              es: 'Mánchester',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'north-yorkshire',
        labels: HotelGeoLabel(
          nl: 'North Yorkshire',
          en: 'North Yorkshire',
          fr: 'North Yorkshire',
          es: 'Yorkshire del Norte',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'york',
            labels: HotelGeoLabel(
              nl: 'York',
              en: 'York',
              fr: 'York',
              es: 'York',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'harrogate',
            labels: HotelGeoLabel(
              nl: 'Harrogate',
              en: 'Harrogate',
              fr: 'Harrogate',
              es: 'Harrogate',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
    ],
  ),
  HotelGeoCountry(
    code: 'ES',
    labels: HotelGeoLabel(
      nl: 'Spanje',
      en: 'Spain',
      fr: 'Espagne',
      es: 'España',
    ),
    regions: <HotelGeoRegion>[
      HotelGeoRegion(
        key: 'catalonia',
        labels: HotelGeoLabel(
          nl: 'Catalonië',
          en: 'Catalonia',
          fr: 'Catalogne',
          es: 'Cataluña',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'barcelona',
            labels: HotelGeoLabel(
              nl: 'Barcelona',
              en: 'Barcelona',
              fr: 'Barcelone',
              es: 'Barcelona',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'lloret-de-mar',
            labels: HotelGeoLabel(
              nl: 'Lloret de Mar',
              en: 'Lloret de Mar',
              fr: 'Lloret de Mar',
              es: 'Lloret de Mar',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'tossa-de-mar',
            labels: HotelGeoLabel(
              nl: 'Tossa de Mar',
              en: 'Tossa de Mar',
              fr: 'Tossa de Mar',
              es: 'Tossa de Mar',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'andalusia',
        labels: HotelGeoLabel(
          nl: 'Andalusië',
          en: 'Andalusia',
          fr: 'Andalousie',
          es: 'Andalucía',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'sevilla',
            labels: HotelGeoLabel(
              nl: 'Sevilla',
              en: 'Seville',
              fr: 'Séville',
              es: 'Sevilla',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'marbella',
            labels: HotelGeoLabel(
              nl: 'Marbella',
              en: 'Marbella',
              fr: 'Marbella',
              es: 'Marbella',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'ronda',
            labels: HotelGeoLabel(
              nl: 'Ronda',
              en: 'Ronda',
              fr: 'Ronda',
              es: 'Ronda',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'malaga',
            labels: HotelGeoLabel(
              nl: 'Málaga',
              en: 'Málaga',
              fr: 'Málaga',
              es: 'Málaga',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'granada',
            labels: HotelGeoLabel(
              nl: 'Granada',
              en: 'Granada',
              fr: 'Grenade',
              es: 'Granada',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'balearic-islands',
        labels: HotelGeoLabel(
          nl: 'Balearic Islands',
          en: 'Balearic Islands',
          fr: 'Îles Baléares',
          es: 'Islas Baleares',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'palma-de-mallorca',
            labels: HotelGeoLabel(
              nl: 'Palma de Mallorca',
              en: 'Palma de Mallorca',
              fr: 'Palma de Majorque',
              es: 'Palma de Mallorca',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'alcudia',
            labels: HotelGeoLabel(
              nl: 'Alcúdia',
              en: 'Alcúdia',
              fr: 'Alcúdia',
              es: 'Alcúdia',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
          HotelGeoSettlement(
            key: 'soller',
            labels: HotelGeoLabel(
              nl: 'Sóller',
              en: 'Sóller',
              fr: 'Sóller',
              es: 'Sóller',
            ),
            kind: HotelGeoSettlementKind.town,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'community-of-madrid',
        labels: HotelGeoLabel(
          nl: 'Community of Madrid',
          en: 'Community of Madrid',
          fr: 'Communauté de Madrid',
          es: 'Comunidad de Madrid',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'madrid',
            labels: HotelGeoLabel(
              nl: 'Madrid',
              en: 'Madrid',
              fr: 'Madrid',
              es: 'Madrid',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
      HotelGeoRegion(
        key: 'valencian-community',
        labels: HotelGeoLabel(
          nl: 'Valencian Community',
          en: 'Valencian Community',
          fr: 'Communauté valencienne',
          es: 'Comunidad Valenciana',
        ),
        settlements: <HotelGeoSettlement>[
          HotelGeoSettlement(
            key: 'valencia',
            labels: HotelGeoLabel(
              nl: 'Valencia',
              en: 'Valencia',
              fr: 'Valence',
              es: 'Valencia',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'alicante',
            labels: HotelGeoLabel(
              nl: 'Alicante',
              en: 'Alicante',
              fr: 'Alicante',
              es: 'Alicante',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
          HotelGeoSettlement(
            key: 'benidorm',
            labels: HotelGeoLabel(
              nl: 'Benidorm',
              en: 'Benidorm',
              fr: 'Benidorm',
              es: 'Benidorm',
            ),
            kind: HotelGeoSettlementKind.city,
          ),
        ],
      ),
    ],
  ),
];

List<HotelGeoOption> hotelGeoCountryOptions(String languageCode) {
  final options =
      kHotelGeoTaxonomy
          .map(
            (country) => HotelGeoOption(
              value: country.code,
              label: country.labels.of(languageCode),
            ),
          )
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
  return options;
}

List<HotelGeoOption> hotelGeoRegionOptions({
  required String countryCode,
  required String languageCode,
}) {
  final country = hotelGeoCountryByCode(countryCode);
  if (country == null) return const <HotelGeoOption>[];
  final options =
      country.regions
          .map(
            (region) => HotelGeoOption(
              value: region.key,
              label: region.labels.of(languageCode),
            ),
          )
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
  return options;
}

List<HotelGeoOption> hotelGeoSettlementOptions({
  required String countryCode,
  required String regionKey,
  required String languageCode,
}) {
  final region = hotelGeoRegionByKey(
    countryCode: countryCode,
    regionKey: regionKey,
  );
  if (region == null) return const <HotelGeoOption>[];
  final options =
      region.settlements
          .map(
            (settlement) => HotelGeoOption(
              value: settlement.key,
              label: settlement.labels.of(languageCode),
            ),
          )
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
  return options;
}

HotelGeoCountry? hotelGeoCountryByCode(String countryCode) {
  final normalized = countryCode.trim().toUpperCase();
  if (normalized.isEmpty) return null;
  for (final country in kHotelGeoTaxonomy) {
    if (country.code.toUpperCase() == normalized) return country;
  }
  return null;
}

HotelGeoRegion? hotelGeoRegionByKey({
  required String countryCode,
  required String regionKey,
}) {
  final country = hotelGeoCountryByCode(countryCode);
  if (country == null) return null;
  final normalized = regionKey.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final region in country.regions) {
    if (region.key.trim().toLowerCase() == normalized) return region;
  }
  return null;
}

HotelGeoSettlement? hotelGeoSettlementByKey({
  required String countryCode,
  required String regionKey,
  required String settlementKey,
}) {
  final region = hotelGeoRegionByKey(
    countryCode: countryCode,
    regionKey: regionKey,
  );
  if (region == null) return null;
  final normalized = settlementKey.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final settlement in region.settlements) {
    if (settlement.key.trim().toLowerCase() == normalized) return settlement;
  }
  return null;
}

Set<String> hotelGeoCountryMatchValues(String countryCode) {
  final country = hotelGeoCountryByCode(countryCode);
  if (country == null) return const <String>{};
  return <String>{
    country.code.toLowerCase(),
    ...country.labels.allValuesNormalized(),
  };
}

Set<String> hotelGeoRegionMatchValues({
  required String countryCode,
  required String regionKey,
}) {
  final region = hotelGeoRegionByKey(
    countryCode: countryCode,
    regionKey: regionKey,
  );
  if (region == null) return const <String>{};
  return <String>{
    region.key.toLowerCase(),
    ...region.labels.allValuesNormalized(),
  };
}

Set<String> hotelGeoSettlementMatchValues({
  required String countryCode,
  required String regionKey,
  required String settlementKey,
}) {
  final settlement = hotelGeoSettlementByKey(
    countryCode: countryCode,
    regionKey: regionKey,
    settlementKey: settlementKey,
  );
  if (settlement == null) return const <String>{};
  return <String>{
    settlement.key.toLowerCase(),
    ...settlement.labels.allValuesNormalized(),
  };
}
