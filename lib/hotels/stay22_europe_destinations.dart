part of 'stay22_europe_countries.dart';

/// City-states / microstates where a separate region selector would be artificial.
const Set<String> kStay22CityStateCountryCodes = <String>{
  'AD',
  'LI',
  'MC',
  'SM',
  'VA',
};

class _DestCity {
  const _DestCity(
    this.key,
    this.en, {
    this.nl,
    this.fr,
    this.es,
    this.aliases = const <String>[],
    this.capital = false,
    this.queryName,
  });

  final String key;
  final String en;
  final String? nl;
  final String? fr;
  final String? es;
  final List<String> aliases;
  final bool capital;
  final String? queryName;

  HotelGeoSettlement toSettlement() {
    return HotelGeoSettlement(
      key: key,
      labels: HotelGeoLabel(
        nl: nl ?? en,
        en: en,
        fr: fr ?? en,
        es: es ?? en,
      ),
      kind: HotelGeoSettlementKind.city,
      aliases: aliases,
      queryName: queryName ?? en,
      isCapital: capital,
    );
  }
}

class _DestRegion {
  const _DestRegion(
    this.key,
    this.en,
    this.cities, {
    this.nl,
    this.fr,
    this.es,
  });

  final String key;
  final String en;
  final String? nl;
  final String? fr;
  final String? es;
  final List<_DestCity> cities;

  HotelGeoRegion toRegion() {
    return HotelGeoRegion(
      key: key,
      labels: HotelGeoLabel(
        nl: nl ?? en,
        en: en,
        fr: fr ?? en,
        es: es ?? en,
      ),
      settlements: cities.map((city) => city.toSettlement()).toList(),
    );
  }
}

class _DestCountry {
  const _DestCountry(
    this.regions, {
    this.hideRegion = false,
    this.capitalKey,
  });

  final List<_DestRegion> regions;
  final bool hideRegion;
  final String? capitalKey;
}

const Map<String, _DestCountry> kStay22EuropeDestinationSeeds =
    <String, _DestCountry>{
  'AL': _DestCountry(
    <_DestRegion>[
      _DestRegion('tirana', 'Tirana County', <_DestCity>[
        _DestCity('tirana', 'Tirana', nl: 'Tirana', fr: 'Tirana', es: 'Tirana', capital: true),
      ], nl: 'District Tirana', fr: 'Comté de Tirana', es: 'Condado de Tirana'),
      _DestRegion('durres', 'Durrës County', <_DestCity>[
        _DestCity('durres', 'Durrës', nl: 'Durrës', fr: 'Durrës', es: 'Durrës', aliases: <String>['Durres']),
      ], nl: 'District Durrës', fr: 'Comté de Durrës', es: 'Condado de Durrës'),
      _DestRegion('vlore', 'Vlorë County', <_DestCity>[
        _DestCity('vlore', 'Vlorë', nl: 'Vlorë', fr: 'Vlorë', es: 'Vlorë', aliases: <String>['Vlore']),
        _DestCity('sarande', 'Sarandë', nl: 'Sarandë', fr: 'Saranda', es: 'Saranda', aliases: <String>['Sarande']),
      ], nl: 'District Vlorë', fr: 'Comté de Vlorë', es: 'Condado de Vlorë'),
      _DestRegion('shkoder', 'Shkodër County', <_DestCity>[
        _DestCity('shkoder', 'Shkodër', nl: 'Shkodër', fr: 'Shkodër', es: 'Shkodër', aliases: <String>['Shkoder']),
      ], nl: 'District Shkodër', fr: 'Comté de Shkodër', es: 'Condado de Shkodër'),
      _DestRegion('berat', 'Berat County', <_DestCity>[
        _DestCity('berat', 'Berat'),
      ], nl: 'District Berat', fr: 'Comté de Berat', es: 'Condado de Berat'),
      _DestRegion('gjirokaster', 'Gjirokastër County', <_DestCity>[
        _DestCity('gjirokaster', 'Gjirokastër', aliases: <String>['Gjirokaster']),
      ], nl: 'District Gjirokastër', fr: 'Comté de Gjirokastër', es: 'Condado de Gjirokastër'),
    ],
    capitalKey: 'tirana',
  ),
  'AD': _DestCountry(
    <_DestRegion>[
      _DestRegion('andorra', 'Andorra', <_DestCity>[
        _DestCity('andorra-la-vella', 'Andorra la Vella', nl: 'Andorra la Vella', fr: 'Andorre-la-Vieille', es: 'Andorra la Vieja', capital: true),
        _DestCity('escaldes-engordany', 'Escaldes-Engordany'),
        _DestCity('encamp', 'Encamp'),
        _DestCity('la-massana', 'La Massana'),
        _DestCity('pas-de-la-casa', 'Pas de la Casa'),
      ]),
    ],
    hideRegion: true,
    capitalKey: 'andorra-la-vella',
  ),
  'AT': _DestCountry(
    <_DestRegion>[
      _DestRegion('vienna', 'Vienna', <_DestCity>[
        _DestCity('vienna', 'Vienna', nl: 'Wenen', fr: 'Vienne', es: 'Viena', aliases: <String>['Wien'], capital: true),
      ], nl: 'Wenen', fr: 'Vienne', es: 'Viena'),
      _DestRegion('salzburg', 'Salzburg', <_DestCity>[
        _DestCity('salzburg', 'Salzburg', nl: 'Salzburg', fr: 'Salzbourg', es: 'Salzburgo'),
      ], nl: 'Salzburg', fr: 'Salzbourg', es: 'Salzburgo'),
      _DestRegion('tyrol', 'Tyrol', <_DestCity>[
        _DestCity('innsbruck', 'Innsbruck'),
        _DestCity('st-anton', 'St. Anton am Arlberg', aliases: <String>['Sankt Anton', 'St Anton']),
      ], nl: 'Tirol', fr: 'Tyrol', es: 'Tirol'),
      _DestRegion('styria', 'Styria', <_DestCity>[
        _DestCity('graz', 'Graz'),
      ], nl: 'Stiermarken', fr: 'Styrie', es: 'Estiria'),
      _DestRegion('upper-austria', 'Upper Austria', <_DestCity>[
        _DestCity('linz', 'Linz'),
      ], nl: 'Opper-Oostenrijk', fr: 'Haute-Autriche', es: 'Alta Austria'),
      _DestRegion('carinthia', 'Carinthia', <_DestCity>[
        _DestCity('klagenfurt', 'Klagenfurt'),
        _DestCity('villach', 'Villach'),
      ], nl: 'Karinthië', fr: 'Carinthie', es: 'Carintia'),
      _DestRegion('vorarlberg', 'Vorarlberg', <_DestCity>[
        _DestCity('bregenz', 'Bregenz'),
      ]),
      _DestRegion('upper-salzkammergut', 'Salzkammergut', <_DestCity>[
        _DestCity('hallstatt', 'Hallstatt'),
      ]),
    ],
    capitalKey: 'vienna',
  ),
  'BA': _DestCountry(
    <_DestRegion>[
      _DestRegion('sarajevo', 'Sarajevo Canton', <_DestCity>[
        _DestCity('sarajevo', 'Sarajevo', capital: true),
      ], nl: 'Kanton Sarajevo', fr: 'Canton de Sarajevo', es: 'Cantón de Sarajevo'),
      _DestRegion('herzegovina-neretva', 'Herzegovina-Neretva', <_DestCity>[
        _DestCity('mostar', 'Mostar'),
      ]),
      _DestRegion('banja-luka', 'Banja Luka Region', <_DestCity>[
        _DestCity('banja-luka', 'Banja Luka'),
      ], nl: 'Regio Banja Luka', fr: 'Région de Banja Luka', es: 'Región de Banja Luka'),
      _DestRegion('tuzla', 'Tuzla Canton', <_DestCity>[
        _DestCity('tuzla', 'Tuzla'),
      ], nl: 'Kanton Tuzla', fr: 'Canton de Tuzla', es: 'Cantón de Tuzla'),
      _DestRegion('trebinje', 'Trebinje Region', <_DestCity>[
        _DestCity('trebinje', 'Trebinje'),
      ], nl: 'Regio Trebinje', fr: 'Région de Trebinje', es: 'Región de Trebinje'),
    ],
    capitalKey: 'sarajevo',
  ),
  'BG': _DestCountry(
    <_DestRegion>[
      _DestRegion('sofia', 'Sofia City', <_DestCity>[
        _DestCity('sofia', 'Sofia', nl: 'Sofia', fr: 'Sofia', es: 'Sofía', capital: true),
      ], nl: 'Sofia', fr: 'Sofia', es: 'Sofía'),
      _DestRegion('plovdiv', 'Plovdiv Province', <_DestCity>[
        _DestCity('plovdiv', 'Plovdiv'),
      ], nl: 'Oblast Plovdiv', fr: 'Province de Plovdiv', es: 'Provincia de Plovdiv'),
      _DestRegion('varna', 'Varna Province', <_DestCity>[
        _DestCity('varna', 'Varna'),
      ]),
      _DestRegion('burgas', 'Burgas Province', <_DestCity>[
        _DestCity('burgas', 'Burgas'),
        _DestCity('nessebar', 'Nessebar', aliases: <String>['Nesebar']),
      ]),
      _DestRegion('veliko-tarnovo', 'Veliko Tarnovo Province', <_DestCity>[
        _DestCity('veliko-tarnovo', 'Veliko Tarnovo'),
      ]),
      _DestRegion('blagoevgrad', 'Blagoevgrad Province', <_DestCity>[
        _DestCity('bansko', 'Bansko'),
      ]),
      _DestRegion('ruse', 'Ruse Province', <_DestCity>[
        _DestCity('ruse', 'Ruse', aliases: <String>['Rousse']),
      ]),
    ],
    capitalKey: 'sofia',
  ),
  'CH': _DestCountry(
    <_DestRegion>[
      _DestRegion('zurich', 'Canton of Zurich', <_DestCity>[
        _DestCity('zurich', 'Zurich', nl: 'Zürich', fr: 'Zurich', es: 'Zúrich', aliases: <String>['Zürich', 'Zurich'], capital: false),
      ], nl: 'Kanton Zürich', fr: 'Canton de Zurich', es: 'Cantón de Zúrich'),
      _DestRegion('geneva', 'Canton of Geneva', <_DestCity>[
        _DestCity('geneva', 'Geneva', nl: 'Genève', fr: 'Genève', es: 'Ginebra', aliases: <String>['Genève', 'Genf']),
      ], nl: 'Kanton Genève', fr: 'Canton de Genève', es: 'Cantón de Ginebra'),
      _DestRegion('basel-stadt', 'Basel-Stadt', <_DestCity>[
        _DestCity('basel', 'Basel', nl: 'Bazel', fr: 'Bâle', es: 'Basilea', aliases: <String>['Bâle']),
      ]),
      _DestRegion('bern', 'Canton of Bern', <_DestCity>[
        _DestCity('bern', 'Bern', nl: 'Bern', fr: 'Berne', es: 'Berna', aliases: <String>['Berne'], capital: true),
        _DestCity('interlaken', 'Interlaken'),
      ], nl: 'Kanton Bern', fr: 'Canton de Berne', es: 'Cantón de Berna'),
      _DestRegion('vaud', 'Vaud', <_DestCity>[
        _DestCity('lausanne', 'Lausanne'),
      ]),
      _DestRegion('lucerne', 'Canton of Lucerne', <_DestCity>[
        _DestCity('lucerne', 'Lucerne', nl: 'Luzern', fr: 'Lucerne', es: 'Lucerna', aliases: <String>['Luzern']),
      ], nl: 'Kanton Luzern', fr: 'Canton de Lucerne', es: 'Cantón de Lucerna'),
      _DestRegion('ticino', 'Ticino', <_DestCity>[
        _DestCity('lugano', 'Lugano'),
      ]),
      _DestRegion('valais', 'Valais', <_DestCity>[
        _DestCity('zermatt', 'Zermatt'),
      ]),
      _DestRegion('graubunden', 'Graubünden', <_DestCity>[
        _DestCity('st-moritz', 'St. Moritz', aliases: <String>['Saint Moritz', 'Sankt Moritz']),
      ], nl: 'Graubünden', fr: 'Grisons', es: 'Grisones'),
    ],
    capitalKey: 'bern',
  ),
  'CY': _DestCountry(
    <_DestRegion>[
      _DestRegion('nicosia', 'Nicosia District', <_DestCity>[
        _DestCity('nicosia', 'Nicosia', nl: 'Nicosia', fr: 'Nicosie', es: 'Nicosia', aliases: <String>['Lefkosia'], capital: true),
      ], nl: 'District Nicosia', fr: 'District de Nicosie', es: 'Distrito de Nicosia'),
      _DestRegion('limassol', 'Limassol District', <_DestCity>[
        _DestCity('limassol', 'Limassol', aliases: <String>['Lemesos']),
      ]),
      _DestRegion('larnaca', 'Larnaca District', <_DestCity>[
        _DestCity('larnaca', 'Larnaca'),
      ]),
      _DestRegion('paphos', 'Paphos District', <_DestCity>[
        _DestCity('paphos', 'Paphos', aliases: <String>['Pafos']),
      ]),
      _DestRegion('famagusta', 'Famagusta District', <_DestCity>[
        _DestCity('ayia-napa', 'Ayia Napa', aliases: <String>['Agia Napa']),
      ]),
    ],
    capitalKey: 'nicosia',
  ),
  'CZ': _DestCountry(
    <_DestRegion>[
      _DestRegion('prague', 'Prague', <_DestCity>[
        _DestCity('prague', 'Prague', nl: 'Praag', fr: 'Prague', es: 'Praga', aliases: <String>['Praha'], capital: true),
      ], nl: 'Praag', fr: 'Prague', es: 'Praga'),
      _DestRegion('south-moravia', 'South Moravia', <_DestCity>[
        _DestCity('brno', 'Brno'),
      ], nl: 'Zuid-Moravië', fr: 'Moravie-du-Sud', es: 'Moravia Meridional'),
      _DestRegion('moravian-silesia', 'Moravian-Silesian Region', <_DestCity>[
        _DestCity('ostrava', 'Ostrava'),
      ], nl: 'Moravië-Silezië', fr: 'Moravie-Silésie', es: 'Moravia-Silesia'),
      _DestRegion('plzen', 'Plzeň Region', <_DestCity>[
        _DestCity('plzen', 'Plzeň', aliases: <String>['Pilsen', 'Plzen']),
      ], nl: 'Regio Pilsen', fr: 'Région de Pilsen', es: 'Región de Pilsen'),
      _DestRegion('karlovy-vary', 'Karlovy Vary Region', <_DestCity>[
        _DestCity('karlovy-vary', 'Karlovy Vary', aliases: <String>['Carlsbad']),
      ]),
      _DestRegion('south-bohemia', 'South Bohemia', <_DestCity>[
        _DestCity('cesky-krumlov', 'Český Krumlov', aliases: <String>['Cesky Krumlov']),
      ], nl: 'Zuid-Bohemen', fr: 'Bohême-du-Sud', es: 'Bohemia Meridional'),
      _DestRegion('olomouc', 'Olomouc Region', <_DestCity>[
        _DestCity('olomouc', 'Olomouc'),
      ]),
      _DestRegion('liberec', 'Liberec Region', <_DestCity>[
        _DestCity('liberec', 'Liberec'),
      ]),
    ],
    capitalKey: 'prague',
  ),
  'DK': _DestCountry(
    <_DestRegion>[
      _DestRegion('capital-region', 'Capital Region of Denmark', <_DestCity>[
        _DestCity('copenhagen', 'Copenhagen', nl: 'Kopenhagen', fr: 'Copenhague', es: 'Copenhague', aliases: <String>['København', 'Kobenhavn'], capital: true),
        _DestCity('helsingor', 'Helsingør', aliases: <String>['Elsinore', 'Helsingor']),
      ], nl: 'Hoofdstedelijk gebied', fr: 'Région de la capitale', es: 'Región Capital'),
      _DestRegion('central-denmark', 'Central Denmark Region', <_DestCity>[
        _DestCity('aarhus', 'Aarhus', aliases: <String>['Århus']),
        _DestCity('billund', 'Billund'),
      ], nl: 'Midden-Jutland', fr: 'Jutland-Central', es: 'Jutlandia Central'),
      _DestRegion('southern-denmark', 'Region of Southern Denmark', <_DestCity>[
        _DestCity('odense', 'Odense'),
      ], nl: 'Zuid-Denemarken', fr: 'Danemark du Sud', es: 'Dinamarca Meridional'),
      _DestRegion('north-denmark', 'North Denmark Region', <_DestCity>[
        _DestCity('aalborg', 'Aalborg', aliases: <String>['Ålborg']),
      ], nl: 'Noord-Jutland', fr: 'Jutland-du-Nord', es: 'Jutlandia Septentrional'),
      _DestRegion('zealand', 'Region Zealand', <_DestCity>[
        _DestCity('roskilde', 'Roskilde'),
      ], nl: 'Seeland', fr: 'Zélande', es: 'Selandia'),
    ],
    capitalKey: 'copenhagen',
  ),
  'EE': _DestCountry(
    <_DestRegion>[
      _DestRegion('harju', 'Harju County', <_DestCity>[
        _DestCity('tallinn', 'Tallinn', capital: true),
      ], nl: 'Harjumaa', fr: 'Comté de Harju', es: 'Condado de Harju'),
      _DestRegion('tartu', 'Tartu County', <_DestCity>[
        _DestCity('tartu', 'Tartu'),
      ]),
      _DestRegion('parnu', 'Pärnu County', <_DestCity>[
        _DestCity('parnu', 'Pärnu', aliases: <String>['Parnu']),
      ]),
      _DestRegion('ida-viru', 'Ida-Viru County', <_DestCity>[
        _DestCity('narva', 'Narva'),
      ]),
      _DestRegion('saare', 'Saare County', <_DestCity>[
        _DestCity('kuressaare', 'Kuressaare'),
      ]),
    ],
    capitalKey: 'tallinn',
  ),
  'FI': _DestCountry(
    <_DestRegion>[
      _DestRegion('uusimaa', 'Uusimaa', <_DestCity>[
        _DestCity('helsinki', 'Helsinki', capital: true),
        _DestCity('espoo', 'Espoo'),
      ]),
      _DestRegion('southwest-finland', 'Southwest Finland', <_DestCity>[
        _DestCity('turku', 'Turku', aliases: <String>['Åbo']),
      ], nl: 'Zuidwest-Finland', fr: 'Finlande du Sud-Ouest', es: 'Finlandia del Sudoeste'),
      _DestRegion('pirkanmaa', 'Pirkanmaa', <_DestCity>[
        _DestCity('tampere', 'Tampere'),
      ]),
      _DestRegion('north-ostrobothnia', 'North Ostrobothnia', <_DestCity>[
        _DestCity('oulu', 'Oulu'),
      ], nl: 'Noord-Pohjanmaa', fr: 'Ostrobotnie du Nord', es: 'Ostrobotnia del Norte'),
      _DestRegion('lapland', 'Lapland', <_DestCity>[
        _DestCity('rovaniemi', 'Rovaniemi'),
        _DestCity('levi', 'Levi'),
      ], nl: 'Lapland', fr: 'Laponie', es: 'Laponia'),
      _DestRegion('central-finland', 'Central Finland', <_DestCity>[
        _DestCity('jyvaskyla', 'Jyväskylä', aliases: <String>['Jyvaskyla']),
      ], nl: 'Midden-Finland', fr: 'Finlande-Centrale', es: 'Finlandia Central'),
    ],
    capitalKey: 'helsinki',
  ),
  'GR': _DestCountry(
    <_DestRegion>[
      _DestRegion('attica', 'Attica', <_DestCity>[
        _DestCity('athens', 'Athens', nl: 'Athene', fr: 'Athènes', es: 'Atenas', aliases: <String>['Athina'], capital: true),
      ], nl: 'Attica', fr: 'Attique', es: 'Ática'),
      _DestRegion('central-macedonia', 'Central Macedonia', <_DestCity>[
        _DestCity('thessaloniki', 'Thessaloniki', aliases: <String>['Saloniki', 'Salonica']),
      ], nl: 'Centraal-Macedonië', fr: 'Macédoine-Centrale', es: 'Macedonia Central'),
      _DestRegion('crete', 'Crete', <_DestCity>[
        _DestCity('heraklion', 'Heraklion', aliases: <String>['Iraklion', 'Heraklio']),
        _DestCity('chania', 'Chania', aliases: <String>['Hania']),
      ], nl: 'Kreta', fr: 'Crète', es: 'Creta'),
      _DestRegion('south-aegean', 'South Aegean', <_DestCity>[
        _DestCity('rhodes', 'Rhodes', nl: 'Rodos', fr: 'Rhodes', es: 'Rodas', aliases: <String>['Rodos']),
        _DestCity('mykonos', 'Mykonos'),
        _DestCity('santorini', 'Santorini', aliases: <String>['Thira']),
        _DestCity('kos', 'Kos'),
      ], nl: 'Zuid-Egeïsche Eilanden', fr: 'Égée-Méridionale', es: 'Egeo Meridional'),
      _DestRegion('ionian-islands', 'Ionian Islands', <_DestCity>[
        _DestCity('corfu', 'Corfu', nl: 'Korfoe', fr: 'Corfou', es: 'Corfú', aliases: <String>['Kerkyra']),
        _DestCity('zakynthos', 'Zakynthos', aliases: <String>['Zante']),
      ], nl: 'Ionische Eilanden', fr: 'Îles Ioniennes', es: 'Islas Jónicas'),
      _DestRegion('western-greece', 'Western Greece', <_DestCity>[
        _DestCity('patras', 'Patras'),
      ], nl: 'West-Griekenland', fr: 'Grèce-Occidentale', es: 'Grecia Occidental'),
      _DestRegion('epirus', 'Epirus', <_DestCity>[
        _DestCity('ioannina', 'Ioannina'),
      ], nl: 'Epirus', fr: 'Épire', es: 'Epiro'),
    ],
    capitalKey: 'athens',
  ),
  'HR': _DestCountry(
    <_DestRegion>[
      _DestRegion('zagreb', 'City of Zagreb', <_DestCity>[
        _DestCity('zagreb', 'Zagreb', capital: true),
      ], nl: 'Zagreb', fr: 'Zagreb', es: 'Zagreb'),
      _DestRegion('split-dalmatia', 'Split-Dalmatia', <_DestCity>[
        _DestCity('split', 'Split'),
        _DestCity('hvar', 'Hvar'),
      ], nl: 'Split-Dalmatië', fr: 'Split-Dalmatie', es: 'Split-Dalmacia'),
      _DestRegion('dubrovnik-neretva', 'Dubrovnik-Neretva', <_DestCity>[
        _DestCity('dubrovnik', 'Dubrovnik'),
      ]),
      _DestRegion('zadar', 'Zadar County', <_DestCity>[
        _DestCity('zadar', 'Zadar'),
      ]),
      _DestRegion('primorje-gorski', 'Primorje-Gorski Kotar', <_DestCity>[
        _DestCity('rijeka', 'Rijeka'),
      ]),
      _DestRegion('istria', 'Istria', <_DestCity>[
        _DestCity('pula', 'Pula'),
        _DestCity('rovinj', 'Rovinj'),
      ], nl: 'Istrië', fr: 'Istrie', es: 'Istria'),
      _DestRegion('sibenik-knin', 'Šibenik-Knin', <_DestCity>[
        _DestCity('sibenik', 'Šibenik', aliases: <String>['Sibenik']),
      ]),
    ],
    capitalKey: 'zagreb',
  ),
  'HU': _DestCountry(
    <_DestRegion>[
      _DestRegion('budapest', 'Budapest', <_DestCity>[
        _DestCity('budapest', 'Budapest', capital: true),
      ]),
      _DestRegion('hajdu-bihar', 'Hajdú-Bihar', <_DestCity>[
        _DestCity('debrecen', 'Debrecen'),
      ]),
      _DestRegion('csongrad', 'Csongrád-Csanád', <_DestCity>[
        _DestCity('szeged', 'Szeged'),
      ]),
      _DestRegion('baranya', 'Baranya', <_DestCity>[
        _DestCity('pecs', 'Pécs', aliases: <String>['Pecs']),
      ]),
      _DestRegion('gyor-moson-sopron', 'Győr-Moson-Sopron', <_DestCity>[
        _DestCity('gyor', 'Győr', aliases: <String>['Gyor']),
        _DestCity('sopron', 'Sopron'),
      ]),
      _DestRegion('heves', 'Heves', <_DestCity>[
        _DestCity('eger', 'Eger'),
      ]),
      _DestRegion('zala', 'Zala', <_DestCity>[
        _DestCity('heviz', 'Hévíz', aliases: <String>['Heviz']),
      ]),
    ],
    capitalKey: 'budapest',
  ),
  'IE': _DestCountry(
    <_DestRegion>[
      _DestRegion('leinster', 'Leinster', <_DestCity>[
        _DestCity('dublin', 'Dublin', capital: true),
        _DestCity('kilkenny', 'Kilkenny'),
      ], nl: 'Leinster', fr: 'Leinster', es: 'Leinster'),
      _DestRegion('munster', 'Munster', <_DestCity>[
        _DestCity('cork', 'Cork'),
        _DestCity('limerick', 'Limerick'),
        _DestCity('killarney', 'Killarney'),
        _DestCity('waterford', 'Waterford'),
        _DestCity('dingle', 'Dingle'),
      ]),
      _DestRegion('connacht', 'Connacht', <_DestCity>[
        _DestCity('galway', 'Galway'),
        _DestCity('westport', 'Westport'),
        _DestCity('sligo', 'Sligo'),
      ]),
    ],
    capitalKey: 'dublin',
  ),
  'IS': _DestCountry(
    <_DestRegion>[
      _DestRegion('capital-region', 'Capital Region', <_DestCity>[
        _DestCity('reykjavik', 'Reykjavík', aliases: <String>['Reykjavik'], capital: true),
      ], nl: 'Hoofdstedelijke regio', fr: 'Région de la capitale', es: 'Región Capital'),
      _DestRegion('southern-peninsula', 'Southern Peninsula', <_DestCity>[
        _DestCity('keflavik', 'Keflavík', aliases: <String>['Keflavik']),
      ], nl: 'Reykjanes', fr: 'Péninsule sud', es: 'Península Sur'),
      _DestRegion('northeastern', 'Northeastern Region', <_DestCity>[
        _DestCity('akureyri', 'Akureyri'),
      ], nl: 'Noordoost-IJsland', fr: 'Nord-Est', es: 'Noreste'),
      _DestRegion('southern', 'Southern Region', <_DestCity>[
        _DestCity('vik', 'Vík í Mýrdal', aliases: <String>['Vik', 'Vík']),
        _DestCity('hofn', 'Höfn', aliases: <String>['Hofn']),
      ], nl: 'Zuid-IJsland', fr: 'Sud', es: 'Sur'),
      _DestRegion('westfjords', 'Westfjords', <_DestCity>[
        _DestCity('isafjordur', 'Ísafjörður', aliases: <String>['Isafjordur']),
      ], nl: 'Westfjorden', fr: 'Fjords de l’Ouest', es: 'Fiordos Occidentales'),
    ],
    capitalKey: 'reykjavik',
  ),
  'IT': _DestCountry(
    <_DestRegion>[
      _DestRegion('lazio', 'Lazio', <_DestCity>[
        _DestCity('rome', 'Rome', nl: 'Rome', fr: 'Rome', es: 'Roma', aliases: <String>['Roma'], capital: true),
      ]),
      _DestRegion('lombardy', 'Lombardy', <_DestCity>[
        _DestCity('milan', 'Milan', nl: 'Milaan', fr: 'Milan', es: 'Milán', aliases: <String>['Milano']),
        _DestCity('como', 'Como'),
      ], nl: 'Lombardije', fr: 'Lombardie', es: 'Lombardía'),
      _DestRegion('veneto', 'Veneto', <_DestCity>[
        _DestCity('venice', 'Venice', nl: 'Venetië', fr: 'Venise', es: 'Venecia', aliases: <String>['Venezia']),
        _DestCity('verona', 'Verona'),
      ], nl: 'Veneto', fr: 'Vénétie', es: 'Véneto'),
      _DestRegion('tuscany', 'Tuscany', <_DestCity>[
        _DestCity('florence', 'Florence', nl: 'Florence', fr: 'Florence', es: 'Florencia', aliases: <String>['Firenze']),
        _DestCity('pisa', 'Pisa'),
        _DestCity('siena', 'Siena'),
      ], nl: 'Toscane', fr: 'Toscane', es: 'Toscana'),
      _DestRegion('campania', 'Campania', <_DestCity>[
        _DestCity('naples', 'Naples', nl: 'Napels', fr: 'Naples', es: 'Nápoles', aliases: <String>['Napoli']),
        _DestCity('amalfi', 'Amalfi'),
      ]),
      _DestRegion('emilia-romagna', 'Emilia-Romagna', <_DestCity>[
        _DestCity('bologna', 'Bologna', nl: 'Bologna', fr: 'Bologne', es: 'Bolonia'),
      ]),
      _DestRegion('piedmont', 'Piedmont', <_DestCity>[
        _DestCity('turin', 'Turin', nl: 'Turijn', fr: 'Turin', es: 'Turín', aliases: <String>['Torino']),
      ], nl: 'Piëmont', fr: 'Piémont', es: 'Piamonte'),
      _DestRegion('sicily', 'Sicily', <_DestCity>[
        _DestCity('palermo', 'Palermo'),
        _DestCity('catania', 'Catania'),
      ], nl: 'Sicilië', fr: 'Sicile', es: 'Sicilia'),
      _DestRegion('liguria', 'Liguria', <_DestCity>[
        _DestCity('genoa', 'Genoa', nl: 'Genua', fr: 'Gênes', es: 'Génova', aliases: <String>['Genova', 'Genova']),
      ]),
      _DestRegion('apulia', 'Apulia', <_DestCity>[
        _DestCity('bari', 'Bari'),
      ], nl: 'Apulië', fr: 'Pouilles', es: 'Apulia'),
      _DestRegion('sardinia', 'Sardinia', <_DestCity>[
        _DestCity('cagliari', 'Cagliari'),
      ], nl: 'Sardinië', fr: 'Sardaigne', es: 'Cerdeña'),
      _DestRegion('umbria', 'Umbria', <_DestCity>[
        _DestCity('perugia', 'Perugia'),
      ], nl: 'Umbrië', fr: 'Ombrie', es: 'Umbría'),
    ],
    capitalKey: 'rome',
  ),
  'LI': _DestCountry(
    <_DestRegion>[
      _DestRegion('liechtenstein', 'Liechtenstein', <_DestCity>[
        _DestCity('vaduz', 'Vaduz', capital: true),
        _DestCity('schaan', 'Schaan'),
      ]),
    ],
    hideRegion: true,
    capitalKey: 'vaduz',
  ),
  'LT': _DestCountry(
    <_DestRegion>[
      _DestRegion('vilnius', 'Vilnius County', <_DestCity>[
        _DestCity('vilnius', 'Vilnius', capital: true),
        _DestCity('trakai', 'Trakai'),
      ], nl: 'District Vilnius', fr: 'Comté de Vilnius', es: 'Condado de Vilna'),
      _DestRegion('kaunas', 'Kaunas County', <_DestCity>[
        _DestCity('kaunas', 'Kaunas'),
      ]),
      _DestRegion('klaipeda', 'Klaipėda County', <_DestCity>[
        _DestCity('klaipeda', 'Klaipėda', aliases: <String>['Klaipeda']),
        _DestCity('palanga', 'Palanga'),
      ]),
    ],
    capitalKey: 'vilnius',
  ),
  'LV': _DestCountry(
    <_DestRegion>[
      _DestRegion('riga', 'Riga Region', <_DestCity>[
        _DestCity('riga', 'Riga', nl: 'Riga', fr: 'Riga', es: 'Riga', capital: true),
        _DestCity('jurmala', 'Jūrmala', aliases: <String>['Jurmala']),
      ], nl: 'Regio Riga', fr: 'Région de Riga', es: 'Región de Riga'),
      _DestRegion('kurzeme', 'Kurzeme', <_DestCity>[
        _DestCity('liepaja', 'Liepāja', aliases: <String>['Liepaja']),
      ]),
      _DestRegion('latgale', 'Latgale', <_DestCity>[
        _DestCity('daugavpils', 'Daugavpils'),
      ]),
      _DestRegion('vidzeme', 'Vidzeme', <_DestCity>[
        _DestCity('sigulda', 'Sigulda'),
      ]),
    ],
    capitalKey: 'riga',
  ),
  'MC': _DestCountry(
    <_DestRegion>[
      _DestRegion('monaco', 'Monaco', <_DestCity>[
        _DestCity('monaco', 'Monaco', nl: 'Monaco', fr: 'Monaco', es: 'Mónaco', aliases: <String>['Monte Carlo', 'Monte-Carlo'], capital: true),
      ]),
    ],
    hideRegion: true,
    capitalKey: 'monaco',
  ),
  'MD': _DestCountry(
    <_DestRegion>[
      _DestRegion('chisinau', 'Chișinău', <_DestCity>[
        _DestCity('chisinau', 'Chișinău', aliases: <String>['Chisinau', 'Kishinev'], capital: true),
      ]),
      _DestRegion('balti', 'Bălți', <_DestCity>[
        _DestCity('balti', 'Bălți', aliases: <String>['Balti']),
      ]),
      _DestRegion('tiraspol', 'Tiraspol', <_DestCity>[
        _DestCity('tiraspol', 'Tiraspol'),
      ]),
      _DestRegion('cahul', 'Cahul', <_DestCity>[
        _DestCity('cahul', 'Cahul'),
      ]),
      _DestRegion('orhei', 'Orhei', <_DestCity>[
        _DestCity('orhei', 'Orhei'),
      ]),
    ],
    capitalKey: 'chisinau',
  ),
  'ME': _DestCountry(
    <_DestRegion>[
      _DestRegion('podgorica', 'Podgorica', <_DestCity>[
        _DestCity('podgorica', 'Podgorica', capital: true),
      ]),
      _DestRegion('kotor', 'Kotor Municipality', <_DestCity>[
        _DestCity('kotor', 'Kotor'),
      ]),
      _DestRegion('budva', 'Budva Municipality', <_DestCity>[
        _DestCity('budva', 'Budva'),
      ]),
      _DestRegion('tivat', 'Tivat Municipality', <_DestCity>[
        _DestCity('tivat', 'Tivat'),
      ]),
      _DestRegion('cetinje', 'Cetinje', <_DestCity>[
        _DestCity('cetinje', 'Cetinje'),
      ]),
      _DestRegion('herceg-novi', 'Herceg Novi', <_DestCity>[
        _DestCity('herceg-novi', 'Herceg Novi'),
      ]),
    ],
    capitalKey: 'podgorica',
  ),
  'MK': _DestCountry(
    <_DestRegion>[
      _DestRegion('skopje', 'Skopje Region', <_DestCity>[
        _DestCity('skopje', 'Skopje', capital: true),
      ], nl: 'Regio Skopje', fr: 'Région de Skopje', es: 'Región de Skopie'),
      _DestRegion('southwestern', 'Southwestern Region', <_DestCity>[
        _DestCity('ohrid', 'Ohrid'),
      ], nl: 'Zuidwest', fr: 'Sud-Ouest', es: 'Suroeste'),
      _DestRegion('pelagonia', 'Pelagonia', <_DestCity>[
        _DestCity('bitola', 'Bitola'),
        _DestCity('prilep', 'Prilep'),
      ]),
      _DestRegion('polog', 'Polog', <_DestCity>[
        _DestCity('tetovo', 'Tetovo'),
      ]),
    ],
    capitalKey: 'skopje',
  ),
  'MT': _DestCountry(
    <_DestRegion>[
      _DestRegion('malta-island', 'Malta', <_DestCity>[
        _DestCity('valletta', 'Valletta', nl: 'Valletta', fr: 'La Valette', es: 'La Valeta', capital: true),
        _DestCity('sliema', 'Sliema'),
        _DestCity('st-julians', 'St. Julian\'s', aliases: <String>["St Julian's", 'San Giljan']),
        _DestCity('mdina', 'Mdina'),
        _DestCity('mellieha', 'Mellieħa', aliases: <String>['Mellieha']),
      ]),
      _DestRegion('gozo', 'Gozo', <_DestCity>[
        _DestCity('victoria-gozo', 'Victoria', aliases: <String>['Rabat Gozo', 'Ir-Rabat']),
      ], nl: 'Gozo', fr: 'Gozo', es: 'Gozo'),
    ],
    capitalKey: 'valletta',
  ),
  'NO': _DestCountry(
    <_DestRegion>[
      _DestRegion('oslo', 'Oslo', <_DestCity>[
        _DestCity('oslo', 'Oslo', capital: true),
      ]),
      _DestRegion('vestland', 'Vestland', <_DestCity>[
        _DestCity('bergen', 'Bergen'),
        _DestCity('flam', 'Flåm', aliases: <String>['Flam']),
      ]),
      _DestRegion('trondelag', 'Trøndelag', <_DestCity>[
        _DestCity('trondheim', 'Trondheim'),
      ]),
      _DestRegion('rogaland', 'Rogaland', <_DestCity>[
        _DestCity('stavanger', 'Stavanger'),
      ]),
      _DestRegion('troms', 'Troms', <_DestCity>[
        _DestCity('tromso', 'Tromsø', aliases: <String>['Tromso']),
      ]),
      _DestRegion('more-og-romsdal', 'Møre og Romsdal', <_DestCity>[
        _DestCity('alesund', 'Ålesund', aliases: <String>['Alesund']),
        _DestCity('geiranger', 'Geiranger'),
      ]),
      _DestRegion('agder', 'Agder', <_DestCity>[
        _DestCity('kristiansand', 'Kristiansand'),
      ]),
      _DestRegion('nordland', 'Nordland', <_DestCity>[
        _DestCity('bodo', 'Bodø', aliases: <String>['Bodo']),
      ]),
    ],
    capitalKey: 'oslo',
  ),
  'PL': _DestCountry(
    <_DestRegion>[
      _DestRegion('masovia', 'Masovian Voivodeship', <_DestCity>[
        _DestCity('warsaw', 'Warsaw', nl: 'Warschau', fr: 'Varsovie', es: 'Varsovia', aliases: <String>['Warszawa'], capital: true),
      ], nl: 'Mazovië', fr: 'Mazovie', es: 'Mazovia'),
      _DestRegion('lesser-poland', 'Lesser Poland', <_DestCity>[
        _DestCity('krakow', 'Kraków', nl: 'Krakau', fr: 'Cracovie', es: 'Cracovia', aliases: <String>['Krakow', 'Cracow']),
        _DestCity('zakopane', 'Zakopane'),
      ], nl: 'Klein-Polen', fr: 'Petite-Pologne', es: 'Pequeña Polonia'),
      _DestRegion('pomerania', 'Pomeranian Voivodeship', <_DestCity>[
        _DestCity('gdansk', 'Gdańsk', aliases: <String>['Gdansk', 'Danzig']),
      ], nl: 'Pommeren', fr: 'Poméranie', es: 'Pomerania'),
      _DestRegion('lower-silesia', 'Lower Silesia', <_DestCity>[
        _DestCity('wroclaw', 'Wrocław', aliases: <String>['Wroclaw', 'Breslau']),
      ], nl: 'Neder-Silezië', fr: 'Basse-Silésie', es: 'Baja Silesia'),
      _DestRegion('greater-poland', 'Greater Poland', <_DestCity>[
        _DestCity('poznan', 'Poznań', aliases: <String>['Poznan']),
      ], nl: 'Groot-Polen', fr: 'Grande-Pologne', es: 'Gran Polonia'),
      _DestRegion('lodz', 'Łódź Voivodeship', <_DestCity>[
        _DestCity('lodz', 'Łódź', aliases: <String>['Lodz']),
      ]),
      _DestRegion('lublin', 'Lublin Voivodeship', <_DestCity>[
        _DestCity('lublin', 'Lublin'),
      ]),
      _DestRegion('west-pomerania', 'West Pomerania', <_DestCity>[
        _DestCity('szczecin', 'Szczecin'),
      ], nl: 'West-Pommeren', fr: 'Poméranie occidentale', es: 'Pomerania Occidental'),
      _DestRegion('kuyavia', 'Kuyavian-Pomeranian', <_DestCity>[
        _DestCity('torun', 'Toruń', aliases: <String>['Torun']),
      ]),
    ],
    capitalKey: 'warsaw',
  ),
  'PT': _DestCountry(
    <_DestRegion>[
      _DestRegion('lisboa', 'Lisbon District', <_DestCity>[
        _DestCity('lisbon', 'Lisbon', nl: 'Lissabon', fr: 'Lisbonne', es: 'Lisboa', aliases: <String>['Lisboa'], capital: true),
        _DestCity('sintra', 'Sintra'),
      ], nl: 'District Lissabon', fr: 'District de Lisbonne', es: 'Distrito de Lisboa'),
      _DestRegion('porto', 'Porto District', <_DestCity>[
        _DestCity('porto', 'Porto', aliases: <String>['Oporto']),
      ]),
      _DestRegion('faro', 'Faro District', <_DestCity>[
        _DestCity('faro', 'Faro'),
        _DestCity('lagos', 'Lagos'),
        _DestCity('portimao', 'Portimão', aliases: <String>['Portimao']),
      ], nl: 'District Faro', fr: 'District de Faro', es: 'Distrito de Faro'),
      _DestRegion('braga', 'Braga District', <_DestCity>[
        _DestCity('braga', 'Braga'),
      ]),
      _DestRegion('coimbra', 'Coimbra District', <_DestCity>[
        _DestCity('coimbra', 'Coimbra'),
      ]),
      _DestRegion('madeira', 'Madeira', <_DestCity>[
        _DestCity('funchal', 'Funchal'),
      ]),
      _DestRegion('evora', 'Évora District', <_DestCity>[
        _DestCity('evora', 'Évora', aliases: <String>['Evora']),
      ]),
      _DestRegion('aveiro', 'Aveiro District', <_DestCity>[
        _DestCity('aveiro', 'Aveiro'),
      ]),
    ],
    capitalKey: 'lisbon',
  ),
  'RO': _DestCountry(
    <_DestRegion>[
      _DestRegion('bucharest', 'Bucharest', <_DestCity>[
        _DestCity('bucharest', 'Bucharest', nl: 'Boekarest', fr: 'Bucarest', es: 'Bucarest', aliases: <String>['Bucuresti', 'București'], capital: true),
      ], nl: 'Boekarest', fr: 'Bucarest', es: 'Bucarest'),
      _DestRegion('brasov', 'Brașov County', <_DestCity>[
        _DestCity('brasov', 'Brașov', aliases: <String>['Brasov']),
      ]),
      _DestRegion('cluj', 'Cluj County', <_DestCity>[
        _DestCity('cluj-napoca', 'Cluj-Napoca'),
      ]),
      _DestRegion('timis', 'Timiș County', <_DestCity>[
        _DestCity('timisoara', 'Timișoara', aliases: <String>['Timisoara']),
      ]),
      _DestRegion('iasi', 'Iași County', <_DestCity>[
        _DestCity('iasi', 'Iași', aliases: <String>['Iasi']),
      ]),
      _DestRegion('sibiu', 'Sibiu County', <_DestCity>[
        _DestCity('sibiu', 'Sibiu'),
        _DestCity('sighisoara', 'Sighișoara', aliases: <String>['Sighisoara']),
      ]),
      _DestRegion('constanta', 'Constanța County', <_DestCity>[
        _DestCity('constanta', 'Constanța', aliases: <String>['Constanta']),
      ]),
      _DestRegion('bihor', 'Bihor County', <_DestCity>[
        _DestCity('oradea', 'Oradea'),
      ]),
    ],
    capitalKey: 'bucharest',
  ),
  'RS': _DestCountry(
    <_DestRegion>[
      _DestRegion('belgrade', 'Belgrade', <_DestCity>[
        _DestCity('belgrade', 'Belgrade', nl: 'Belgrado', fr: 'Belgrade', es: 'Belgrado', aliases: <String>['Beograd'], capital: true),
      ], nl: 'Belgrado', fr: 'Belgrade', es: 'Belgrado'),
      _DestRegion('vojvodina', 'Vojvodina', <_DestCity>[
        _DestCity('novi-sad', 'Novi Sad'),
        _DestCity('subotica', 'Subotica'),
      ]),
      _DestRegion('nisava', 'Nišava', <_DestCity>[
        _DestCity('nis', 'Niš', aliases: <String>['Nis']),
      ]),
      _DestRegion('sumadija', 'Šumadija', <_DestCity>[
        _DestCity('kragujevac', 'Kragujevac'),
      ]),
    ],
    capitalKey: 'belgrade',
  ),
  'SE': _DestCountry(
    <_DestRegion>[
      _DestRegion('stockholm', 'Stockholm County', <_DestCity>[
        _DestCity('stockholm', 'Stockholm', capital: true),
      ], nl: 'Stockholm', fr: 'Stockholm', es: 'Estocolmo'),
      _DestRegion('vastra-gotaland', 'Västra Götaland', <_DestCity>[
        _DestCity('gothenburg', 'Gothenburg', nl: 'Göteborg', fr: 'Göteborg', es: 'Gotemburgo', aliases: <String>['Göteborg', 'Goteborg']),
      ]),
      _DestRegion('skane', 'Skåne', <_DestCity>[
        _DestCity('malmo', 'Malmö', aliases: <String>['Malmo']),
        _DestCity('lund', 'Lund'),
      ]),
      _DestRegion('uppsala', 'Uppsala County', <_DestCity>[
        _DestCity('uppsala', 'Uppsala'),
      ]),
      _DestRegion('gotland', 'Gotland', <_DestCity>[
        _DestCity('visby', 'Visby'),
      ]),
      _DestRegion('norrbotten', 'Norrbotten', <_DestCity>[
        _DestCity('kiruna', 'Kiruna'),
      ]),
      _DestRegion('orebro', 'Örebro County', <_DestCity>[
        _DestCity('orebro', 'Örebro', aliases: <String>['Orebro']),
      ]),
    ],
    capitalKey: 'stockholm',
  ),
  'SI': _DestCountry(
    <_DestRegion>[
      _DestRegion('central-slovenia', 'Central Slovenia', <_DestCity>[
        _DestCity('ljubljana', 'Ljubljana', capital: true),
      ], nl: 'Centraal-Slovenië', fr: 'Slovénie-Centrale', es: 'Eslovenia Central'),
      _DestRegion('upper-carniola', 'Upper Carniola', <_DestCity>[
        _DestCity('bled', 'Bled'),
      ], nl: 'Opper-Krain', fr: 'Haute-Carniole', es: 'Alta Carniola'),
      _DestRegion('drava', 'Drava', <_DestCity>[
        _DestCity('maribor', 'Maribor'),
      ]),
      _DestRegion('coastal-karst', 'Coastal–Karst', <_DestCity>[
        _DestCity('piran', 'Piran'),
        _DestCity('koper', 'Koper'),
      ], nl: 'Kust-Karst', fr: 'Littoral-Karst', es: 'Litoral-Karst'),
      _DestRegion('inner-carniola', 'Inner Carniola', <_DestCity>[
        _DestCity('postojna', 'Postojna'),
      ]),
    ],
    capitalKey: 'ljubljana',
  ),
  'SK': _DestCountry(
    <_DestRegion>[
      _DestRegion('bratislava', 'Bratislava Region', <_DestCity>[
        _DestCity('bratislava', 'Bratislava', capital: true),
      ], nl: 'Regio Bratislava', fr: 'Région de Bratislava', es: 'Región de Bratislava'),
      _DestRegion('kosice', 'Košice Region', <_DestCity>[
        _DestCity('kosice', 'Košice', aliases: <String>['Kosice']),
      ]),
      _DestRegion('zilina', 'Žilina Region', <_DestCity>[
        _DestCity('zilina', 'Žilina', aliases: <String>['Zilina']),
      ]),
      _DestRegion('presov', 'Prešov Region', <_DestCity>[
        _DestCity('poprad', 'Poprad'),
        _DestCity('high-tatras', 'High Tatras', nl: 'Hoge Tatra', fr: 'Hautes Tatras', es: 'Altos Tatras', aliases: <String>['Vysoke Tatry', 'Tatra']),
      ]),
      _DestRegion('banska-bystrica', 'Banská Bystrica Region', <_DestCity>[
        _DestCity('banska-bystrica', 'Banská Bystrica', aliases: <String>['Banska Bystrica']),
      ]),
    ],
    capitalKey: 'bratislava',
  ),
  'SM': _DestCountry(
    <_DestRegion>[
      _DestRegion('san-marino', 'San Marino', <_DestCity>[
        _DestCity('san-marino', 'San Marino', capital: true),
        _DestCity('serravalle', 'Serravalle'),
      ]),
    ],
    hideRegion: true,
    capitalKey: 'san-marino',
  ),
  'UA': _DestCountry(
    <_DestRegion>[
      _DestRegion('kyiv', 'Kyiv', <_DestCity>[
        _DestCity('kyiv', 'Kyiv', nl: 'Kyiv', fr: 'Kyiv', es: 'Kyiv', aliases: <String>['Kiev'], capital: true),
      ]),
      _DestRegion('lviv', 'Lviv Oblast', <_DestCity>[
        _DestCity('lviv', 'Lviv', aliases: <String>['Lwow', 'Lviv']),
      ]),
      _DestRegion('odesa', 'Odesa Oblast', <_DestCity>[
        _DestCity('odesa', 'Odesa', aliases: <String>['Odessa']),
      ]),
      _DestRegion('kharkiv', 'Kharkiv Oblast', <_DestCity>[
        _DestCity('kharkiv', 'Kharkiv', aliases: <String>['Kharkov']),
      ]),
      _DestRegion('dnipro', 'Dnipropetrovsk Oblast', <_DestCity>[
        _DestCity('dnipro', 'Dnipro', aliases: <String>['Dnipropetrovsk']),
      ]),
      _DestRegion('zakarpattia', 'Zakarpattia Oblast', <_DestCity>[
        _DestCity('uzhhorod', 'Uzhhorod'),
      ]),
      _DestRegion('chernivtsi', 'Chernivtsi Oblast', <_DestCity>[
        _DestCity('chernivtsi', 'Chernivtsi'),
      ]),
      _DestRegion('ivano-frankivsk', 'Ivano-Frankivsk Oblast', <_DestCity>[
        _DestCity('ivano-frankivsk', 'Ivano-Frankivsk'),
      ]),
    ],
    capitalKey: 'kyiv',
  ),
  'VA': _DestCountry(
    <_DestRegion>[
      _DestRegion('vatican', 'Vatican City', <_DestCity>[
        _DestCity('vatican-city', 'Vatican City', nl: 'Vaticaanstad', fr: 'Cité du Vatican', es: 'Ciudad del Vaticano', aliases: <String>['Vatican'], capital: true),
      ]),
    ],
    hideRegion: true,
    capitalKey: 'vatican-city',
  ),
  'XK': _DestCountry(
    <_DestRegion>[
      _DestRegion('pristina', 'Pristina District', <_DestCity>[
        _DestCity('pristina', 'Pristina', aliases: <String>['Prishtina', 'Priština'], capital: true),
      ], nl: 'District Pristina', fr: 'District de Pristina', es: 'Distrito de Pristina'),
      _DestRegion('prizren', 'Prizren District', <_DestCity>[
        _DestCity('prizren', 'Prizren'),
      ]),
      _DestRegion('peja', 'Peja District', <_DestCity>[
        _DestCity('peja', 'Peja', aliases: <String>['Pec', 'Peć']),
      ]),
      _DestRegion('gjakova', 'Gjakova District', <_DestCity>[
        _DestCity('gjakova', 'Gjakova', aliases: <String>['Djakovica']),
      ]),
      _DestRegion('mitrovica', 'Mitrovica District', <_DestCity>[
        _DestCity('mitrovica', 'Mitrovica'),
      ]),
    ],
    capitalKey: 'pristina',
  ),
};

List<HotelGeoCountry>? _stay22EuropeanCountriesExpanded;

List<HotelGeoCountry> stay22EuropeanCountriesWithDestinations() {
  return _stay22EuropeanCountriesExpanded ??= kStay22EuropeanCountryIdentities
      .map(stay22AttachDestinationCatalogue)
      .toList(growable: false);
}

HotelGeoCountry stay22AttachDestinationCatalogue(HotelGeoCountry identity) {
  final seed = kStay22EuropeDestinationSeeds[identity.code.toUpperCase()];
  if (seed == null) return identity;
  final regions = seed.regions
      .where((region) => region.cities.isNotEmpty)
      .map((region) => region.toRegion())
      .toList(growable: false);
  return HotelGeoCountry(
    code: identity.code,
    labels: identity.labels,
    regions: regions,
    hideRegionSelector:
        seed.hideRegion ||
        kStay22CityStateCountryCodes.contains(identity.code.toUpperCase()),
    capitalKey: seed.capitalKey,
  );
}

HotelGeoCountry? stay22CatalogueCountryByCode(String countryCode) {
  final normalized = countryCode.trim().toUpperCase();
  if (normalized.isEmpty) return null;
  final seeded = hotelGeoCountryByCode(normalized);
  if (seeded != null) return seeded;
  for (final country in stay22EuropeanCountriesWithDestinations()) {
    if (country.code.toUpperCase() == normalized) return country;
  }
  return null;
}

bool stay22CountryHasMajorCities(HotelGeoCountry country) {
  for (final region in country.regions) {
    if (region.settlements.isNotEmpty) return true;
  }
  return false;
}

HotelGeoRegion? stay22CatalogueRegionByKey({
  required String countryCode,
  required String regionKey,
}) {
  final country = stay22CatalogueCountryByCode(countryCode);
  if (country == null) return null;
  final normalized = regionKey.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final region in country.regions) {
    if (region.key.trim().toLowerCase() == normalized) return region;
  }
  return null;
}

HotelGeoSettlement? stay22CatalogueCityByKey({
  required String countryCode,
  required String cityKey,
}) {
  final country = stay22CatalogueCountryByCode(countryCode);
  if (country == null) return null;
  final normalized = cityKey.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final region in country.regions) {
    for (final city in region.settlements) {
      if (city.key.trim().toLowerCase() == normalized) return city;
    }
  }
  return null;
}

HotelGeoRegion? stay22RegionForCity({
  required String countryCode,
  required String cityKey,
}) {
  final country = stay22CatalogueCountryByCode(countryCode);
  if (country == null) return null;
  final normalized = cityKey.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final region in country.regions) {
    for (final city in region.settlements) {
      if (city.key.trim().toLowerCase() == normalized) return region;
    }
  }
  return null;
}

List<HotelGeoOption> stay22RegionPickerOptions({
  required String countryCode,
  required String languageCode,
}) {
  final country = stay22CatalogueCountryByCode(countryCode);
  if (country == null || country.hideRegionSelector) {
    return const <HotelGeoOption>[];
  }
  final options = country.regions
      .where((region) => region.settlements.isNotEmpty)
      .map(
        (region) => HotelGeoOption(
          value: region.key,
          label: region.labels.of(languageCode),
          searchAliases: <String>[
            region.labels.en,
            region.labels.nl,
            region.labels.fr,
            region.labels.es,
            region.key,
          ],
        ),
      )
      .toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  return options;
}

List<HotelGeoOption> stay22CityPickerOptions({
  required String countryCode,
  required String languageCode,
  String regionKey = '',
}) {
  final country = stay22CatalogueCountryByCode(countryCode);
  if (country == null) return const <HotelGeoOption>[];
  final wantedRegion = regionKey.trim().toLowerCase();
  final options = <HotelGeoOption>[];
  final seen = <String>{};
  for (final region in country.regions) {
    if (wantedRegion.isNotEmpty &&
        region.key.trim().toLowerCase() != wantedRegion) {
      continue;
    }
    for (final city in region.settlements) {
      final key = city.key.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      options.add(
        HotelGeoOption(
          value: city.key,
          label: city.labels.of(languageCode),
          groupLabel: country.hideRegionSelector
              ? null
              : region.labels.of(languageCode),
          searchAliases: <String>[
            city.labels.en,
            city.labels.nl,
            city.labels.fr,
            city.labels.es,
            city.canonicalQueryName,
            city.key,
            ...city.aliases,
          ],
        ),
      );
    }
  }
  options.sort((a, b) {
    final group = (a.groupLabel ?? '').compareTo(b.groupLabel ?? '');
    if (group != 0) return group;
    return a.label.compareTo(b.label);
  });
  return options;
}

Set<String> stay22CatalogueRegionMatchValues({
  required String countryCode,
  required String regionKey,
}) {
  final region = stay22CatalogueRegionByKey(
    countryCode: countryCode,
    regionKey: regionKey,
  );
  if (region == null) return const <String>{};
  return <String>{
    region.key.toLowerCase(),
    ...region.labels.allValuesNormalized(),
  };
}

Set<String> stay22CatalogueCityMatchValues({
  required String countryCode,
  required String cityKey,
}) {
  final city = stay22CatalogueCityByKey(
    countryCode: countryCode,
    cityKey: cityKey,
  );
  if (city == null) return const <String>{};
  return <String>{
    city.key.toLowerCase(),
    ...city.labels.allValuesNormalized(),
    ...city.aliases
        .map((alias) => alias.trim().toLowerCase())
        .where((alias) => alias.isNotEmpty),
    city.canonicalQueryName.toLowerCase(),
  };
}

class Stay22LocationSelection {
  const Stay22LocationSelection({
    this.countryCode = '',
    this.regionKey = '',
    this.cityKey = '',
    this.freeText = '',
  });

  final String countryCode;
  final String regionKey;
  final String cityKey;
  final String freeText;

  Stay22LocationSelection copyWith({
    String? countryCode,
    String? regionKey,
    String? cityKey,
    String? freeText,
  }) {
    return Stay22LocationSelection(
      countryCode: countryCode ?? this.countryCode,
      regionKey: regionKey ?? this.regionKey,
      cityKey: cityKey ?? this.cityKey,
      freeText: freeText ?? this.freeText,
    );
  }
}

Stay22LocationSelection stay22ApplyCountrySelection(
  Stay22LocationSelection current,
  String countryCode,
) {
  return Stay22LocationSelection(
    countryCode: countryCode.trim().toUpperCase(),
    freeText: '',
  );
}

Stay22LocationSelection stay22ApplyRegionSelection(
  Stay22LocationSelection current,
  String regionKey,
) {
  final country = current.countryCode;
  final nextRegion = regionKey.trim();
  var nextCity = current.cityKey;
  if (nextCity.isNotEmpty) {
    final home = stay22RegionForCity(countryCode: country, cityKey: nextCity);
    if (nextRegion.isEmpty ||
        home == null ||
        home.key.toLowerCase() != nextRegion.toLowerCase()) {
      nextCity = '';
    }
  }
  return current.copyWith(regionKey: nextRegion, cityKey: nextCity);
}

Stay22LocationSelection stay22ApplyCitySelection(
  Stay22LocationSelection current,
  String cityKey,
) {
  final country = current.countryCode;
  final nextCity = cityKey.trim();
  if (nextCity.isEmpty) {
    return current.copyWith(cityKey: '');
  }
  final home = stay22RegionForCity(countryCode: country, cityKey: nextCity);
  return current.copyWith(
    cityKey: nextCity,
    regionKey: home?.key ?? current.regionKey,
  );
}

Stay22LocationSelection stay22ApplyFreeText(
  Stay22LocationSelection current,
  String freeText,
) {
  return current.copyWith(freeText: freeText);
}

class Stay22ResolvedDestination {
  const Stay22ResolvedDestination({
    required this.countryCode,
    required this.countryEnglish,
    this.city,
    this.region,
    this.destination,
  });

  final String countryCode;
  final String countryEnglish;
  final String? city;
  final String? region;
  final String? destination;
}

Stay22ResolvedDestination stay22ResolveDestinationQuery({
  required String countryCode,
  String regionKey = '',
  String cityKey = '',
  String freeText = '',
  String defaultCountryCode = 'BE',
}) {
  final selected = countryCode.trim().toUpperCase();
  final iso = selected.isEmpty || selected == 'ALL'
      ? defaultCountryCode
      : selected;
  final country = stay22CatalogueCountryByCode(iso);
  final countryEnglish =
      country?.labels.en ?? stay22EnglishCountryName(iso) ?? 'Belgium';
  final city = stay22CatalogueCityByKey(countryCode: iso, cityKey: cityKey);
  final region = stay22CatalogueRegionByKey(
    countryCode: iso,
    regionKey: regionKey,
  );
  final destination = freeText.trim();
  return Stay22ResolvedDestination(
    countryCode: iso,
    countryEnglish: countryEnglish,
    city: city?.canonicalQueryName,
    region: region?.labels.en,
    destination: destination.isEmpty ? null : destination,
  );
}

String stay22EffectiveStay22Address({
  required Stay22ResolvedDestination resolved,
  String extraFreeText = '',
}) {
  final preferred = extraFreeText.trim().isNotEmpty
      ? extraFreeText.trim()
      : (resolved.destination ?? '');
  return composeStay22AddressFromParts(
    freeText: preferred,
    city: resolved.city ?? '',
    region: resolved.region ?? '',
    country: resolved.countryEnglish,
  );
}

String composeStay22AddressFromParts({
  String freeText = '',
  String city = '',
  String region = '',
  String country = '',
}) {
  final parts = <String>[];
  void add(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;
    final lower = value.toLowerCase();
    if (parts.any((part) => part.toLowerCase() == lower)) return;
    if (parts.any((part) => part.toLowerCase().contains(lower))) return;
    if (parts.any((part) => lower.contains(part.toLowerCase()))) {
      final index = parts.indexWhere(
        (part) => lower.contains(part.toLowerCase()),
      );
      if (index >= 0 && value.length > parts[index].length) {
        parts[index] = value;
      }
      return;
    }
    parts.add(value);
  }

  add(freeText);
  if (freeText.trim().isEmpty) {
    add(city);
    add(region);
  }
  add(country);
  return parts.join(', ');
}
