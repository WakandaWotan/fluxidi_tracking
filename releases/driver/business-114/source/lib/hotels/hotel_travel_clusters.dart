class HotelTravelClusterLabel {
  const HotelTravelClusterLabel({
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
}

class HotelTravelCluster {
  const HotelTravelCluster({
    required this.key,
    required this.labels,
    this.tags = const <String>[],
    this.relatedCountryCodes = const <String>[],
    this.relatedRegionKeys = const <String>[],
    this.relatedSettlementKeys = const <String>[],
  });

  /// Stable machine-readable identifier for AI/recommendation pipelines.
  final String key;
  final HotelTravelClusterLabel labels;

  /// Optional semantic tags for clustering/retrieval.
  final List<String> tags;

  /// Stable country codes, aligned with geo taxonomy (BE/NL/FR/DE/GB/ES/LU...).
  final List<String> relatedCountryCodes;

  /// Stable region keys, aligned with `hotel_geo_taxonomy.dart`.
  final List<String> relatedRegionKeys;

  /// Stable settlement keys, aligned with `hotel_geo_taxonomy.dart`.
  final List<String> relatedSettlementKeys;
}

const List<HotelTravelCluster> kHotelTravelClusters = <HotelTravelCluster>[
  HotelTravelCluster(
    key: 'vlaamse_ardennen',
    labels: HotelTravelClusterLabel(
      nl: 'Vlaamse Ardennen',
      en: 'Flemish Ardennes',
      fr: 'Ardennes flamandes',
      es: 'Ardenas flamencas',
    ),
    tags: <String>[
      'cycling',
      'rolling-hills',
      'rural-boutique',
      'slow-travel',
      'popularFor:hiking',
      'popularFor:weekend-getaway',
    ],
    relatedCountryCodes: <String>['BE'],
    relatedRegionKeys: <String>['oost-vlaanderen'],
    relatedSettlementKeys: <String>[
      'oudenaarde',
      'ronse',
      'brakel',
      'kluisbergen',
      'maarkedal',
      'horebeke',
      'zwalm',
      'zottegem',
      'geraardsbergen',
    ],
  ),
  HotelTravelCluster(
    key: 'ardennes',
    labels: HotelTravelClusterLabel(
      nl: 'Ardennen',
      en: 'Ardennes',
      fr: 'Ardennes',
      es: 'Ardenas',
    ),
    tags: <String>[
      'forest',
      'nature',
      'wellness',
      'active-outdoors',
      'popularFor:retreat',
      'popularFor:family-nature',
    ],
    relatedCountryCodes: <String>['BE'],
    relatedRegionKeys: <String>['luxemburg-be', 'luik', 'namen'],
    relatedSettlementKeys: <String>['durbuy', 'bastogne', 'spa', 'dinant'],
  ),
  HotelTravelCluster(
    key: 'belgian_coast',
    labels: HotelTravelClusterLabel(
      nl: 'Belgische kust',
      en: 'Belgian coast',
      fr: 'Côte belge',
      es: 'Costa belga',
    ),
    tags: <String>[
      'coastal',
      'beach',
      'family',
      'seafood',
      'popularFor:summer',
      'popularFor:weekend-seaside',
    ],
    relatedCountryCodes: <String>['BE'],
    relatedRegionKeys: <String>['west-vlaanderen'],
    relatedSettlementKeys: <String>[
      'knokke-heist',
      'oostende',
      'de-panne',
      'brugge',
    ],
  ),
  HotelTravelCluster(
    key: 'historic_cities',
    labels: HotelTravelClusterLabel(
      nl: 'Historische steden',
      en: 'Historic cities',
      fr: 'Villes historiques',
      es: 'Ciudades históricas',
    ),
    tags: <String>[
      'culture',
      'architecture',
      'museums',
      'city-break',
      'popularFor:heritage',
    ],
    relatedCountryCodes: <String>['BE'],
    relatedRegionKeys: <String>[
      'brussels-hoofdstedelijk-gewest',
      'oost-vlaanderen',
      'west-vlaanderen',
      'antwerpen',
    ],
    relatedSettlementKeys: <String>['brussel', 'gent', 'brugge', 'antwerpen'],
  ),
  HotelTravelCluster(
    key: 'zeeland_coast',
    labels: HotelTravelClusterLabel(
      nl: 'Zeeuwse kust',
      en: 'Zeeland coast',
      fr: 'Côte de Zélande',
      es: 'Costa de Zelanda',
    ),
    tags: <String>[
      'coastal',
      'beach',
      'dunes',
      'family',
      'popularFor:summer-escape',
    ],
    relatedCountryCodes: <String>['NL'],
    relatedRegionKeys: <String>['zeeland'],
    relatedSettlementKeys: <String>['domburg', 'renesse', 'middelburg'],
  ),
  HotelTravelCluster(
    key: 'limburg_hills',
    labels: HotelTravelClusterLabel(
      nl: 'Limburgse heuvels',
      en: 'Limburg hills',
      fr: 'Collines du Limbourg',
      es: 'Colinas de Limburgo',
    ),
    tags: <String>[
      'hills',
      'cycling',
      'wellness',
      'gastronomy',
      'popularFor:active-weekend',
    ],
    relatedCountryCodes: <String>['NL'],
    relatedRegionKeys: <String>['limburg-nl'],
    relatedSettlementKeys: <String>[
      'valkenburg-aan-de-geul',
      'maastricht',
      'gulpen',
    ],
  ),
  HotelTravelCluster(
    key: 'veluwe',
    labels: HotelTravelClusterLabel(
      nl: 'Veluwe',
      en: 'Veluwe',
      fr: 'Veluwe',
      es: 'Veluwe',
    ),
    tags: <String>[
      'nature',
      'national-park',
      'forest',
      'wildlife',
      'popularFor:nature-retreat',
    ],
    relatedCountryCodes: <String>['NL'],
    relatedRegionKeys: <String>['gelderland'],
    relatedSettlementKeys: <String>['apeldoorn', 'otterlo'],
  ),
  HotelTravelCluster(
    key: 'randstad',
    labels: HotelTravelClusterLabel(
      nl: 'Randstad',
      en: 'Randstad',
      fr: 'Randstad',
      es: 'Randstad',
    ),
    tags: <String>[
      'urban',
      'business',
      'culture',
      'city-hop',
      'popularFor:city-break',
    ],
    relatedCountryCodes: <String>['NL'],
    relatedRegionKeys: <String>['noord-holland', 'zuid-holland', 'utrecht'],
    relatedSettlementKeys: <String>[
      'amsterdam',
      'rotterdam',
      'den-haag',
      'utrecht-city',
    ],
  ),
  HotelTravelCluster(
    key: 'provence',
    labels: HotelTravelClusterLabel(
      nl: 'Provence',
      en: 'Provence',
      fr: 'Provence',
      es: 'Provenza',
    ),
    tags: <String>[
      'lavender',
      'villages',
      'slow-travel',
      'gastronomy',
      'popularFor:romantic',
    ],
    relatedCountryCodes: <String>['FR'],
    relatedRegionKeys: <String>['provence-alpes-cote-d-azur'],
    relatedSettlementKeys: <String>['gordes', 'cannes', 'nice'],
  ),
  HotelTravelCluster(
    key: 'cote_dazur',
    labels: HotelTravelClusterLabel(
      nl: 'Côte d\'Azur',
      en: 'Côte d\'Azur',
      fr: 'Côte d\'Azur',
      es: 'Costa Azul',
    ),
    tags: <String>[
      'riviera',
      'coastal',
      'luxury',
      'beach',
      'popularFor:summer-luxury',
    ],
    relatedCountryCodes: <String>['FR'],
    relatedRegionKeys: <String>['provence-alpes-cote-d-azur'],
    relatedSettlementKeys: <String>['nice', 'cannes', 'saint-tropez'],
  ),
  HotelTravelCluster(
    key: 'normandy',
    labels: HotelTravelClusterLabel(
      nl: 'Normandië',
      en: 'Normandy',
      fr: 'Normandie',
      es: 'Normandía',
    ),
    tags: <String>[
      'coastal',
      'historic',
      'roadtrip',
      'seafood',
      'popularFor:weekend-coast',
    ],
    relatedCountryCodes: <String>['FR'],
    relatedRegionKeys: <String>['normandie'],
    relatedSettlementKeys: <String>['honfleur', 'deauville', 'etretat'],
  ),
  HotelTravelCluster(
    key: 'french_alps',
    labels: HotelTravelClusterLabel(
      nl: 'Franse Alpen',
      en: 'French Alps',
      fr: 'Alpes françaises',
      es: 'Alpes franceses',
    ),
    tags: <String>[
      'mountains',
      'ski',
      'hiking',
      'wellness',
      'popularFor:winter-sports',
      'popularFor:summer-hikes',
    ],
    relatedCountryCodes: <String>['FR'],
    relatedRegionKeys: <String>['auvergne-rhone-alpes'],
    relatedSettlementKeys: <String>['annecy', 'chamonix', 'lyon'],
  ),
  HotelTravelCluster(
    key: 'bavarian_alps',
    labels: HotelTravelClusterLabel(
      nl: 'Beierse Alpen',
      en: 'Bavarian Alps',
      fr: 'Alpes bavaroises',
      es: 'Alpes bávaros',
    ),
    tags: <String>[
      'mountains',
      'lakes',
      'wellness',
      'alpine',
      'popularFor:outdoor',
    ],
    relatedCountryCodes: <String>['DE'],
    relatedRegionKeys: <String>['bavaria'],
    relatedSettlementKeys: <String>['munich', 'fussen', 'nuremberg'],
  ),
  HotelTravelCluster(
    key: 'romantic_rhine',
    labels: HotelTravelClusterLabel(
      nl: 'Romantische Rijn',
      en: 'Romantic Rhine',
      fr: 'Rhin romantique',
      es: 'Rin romántico',
    ),
    tags: <String>[
      'river',
      'castles',
      'wine',
      'culture',
      'popularFor:roadtrip',
      'popularFor:couples',
    ],
    relatedCountryCodes: <String>['DE'],
    relatedRegionKeys: <String>['rhineland-palatinate'],
    relatedSettlementKeys: <String>['koblenz', 'trier'],
  ),
  HotelTravelCluster(
    key: 'lake_district',
    labels: HotelTravelClusterLabel(
      nl: 'Lake District',
      en: 'Lake District',
      fr: 'Lake District',
      es: 'Lake District',
    ),
    tags: <String>[
      'lakes',
      'hiking',
      'nature',
      'cottage',
      'popularFor:outdoor-weekend',
    ],
    relatedCountryCodes: <String>['GB'],
    relatedRegionKeys: <String>['cumbria'],
    relatedSettlementKeys: <String>['windermere', 'ambleside', 'keswick'],
  ),
  HotelTravelCluster(
    key: 'cotswolds',
    labels: HotelTravelClusterLabel(
      nl: 'Cotswolds',
      en: 'Cotswolds',
      fr: 'Cotswolds',
      es: 'Cotswolds',
    ),
    tags: <String>[
      'villages',
      'countryside',
      'boutique',
      'slow-travel',
      'popularFor:romantic-villages',
    ],
    relatedCountryCodes: <String>['GB'],
    relatedRegionKeys: <String>['gloucestershire'],
    relatedSettlementKeys: <String>['bourton-on-the-water', 'chipping-campden'],
  ),
  HotelTravelCluster(
    key: 'scottish_highlands',
    labels: HotelTravelClusterLabel(
      nl: 'Schotse Hooglanden',
      en: 'Scottish Highlands',
      fr: 'Highlands écossais',
      es: 'Tierras Altas de Escocia',
    ),
    tags: <String>[
      'highlands',
      'nature',
      'roadtrip',
      'adventure',
      'popularFor:wild-landscapes',
    ],
    relatedCountryCodes: <String>['GB'],
    relatedRegionKeys: <String>['scotland'],
    relatedSettlementKeys: <String>['inverness', 'edinburgh'],
  ),
  HotelTravelCluster(
    key: 'costa_brava',
    labels: HotelTravelClusterLabel(
      nl: 'Costa Brava',
      en: 'Costa Brava',
      fr: 'Costa Brava',
      es: 'Costa Brava',
    ),
    tags: <String>[
      'coastal',
      'beach',
      'mediterranean',
      'family',
      'popularFor:summer-coast',
    ],
    relatedCountryCodes: <String>['ES'],
    relatedRegionKeys: <String>['catalonia'],
    relatedSettlementKeys: <String>[
      'lloret-de-mar',
      'tossa-de-mar',
      'barcelona',
    ],
  ),
  HotelTravelCluster(
    key: 'andalusia',
    labels: HotelTravelClusterLabel(
      nl: 'Andalusië',
      en: 'Andalusia',
      fr: 'Andalousie',
      es: 'Andalucía',
    ),
    tags: <String>[
      'sun',
      'culture',
      'beach',
      'mountains',
      'popularFor:multi-stop-roadtrip',
    ],
    relatedCountryCodes: <String>['ES'],
    relatedRegionKeys: <String>['andalusia'],
    relatedSettlementKeys: <String>[
      'sevilla',
      'marbella',
      'ronda',
      'malaga',
      'granada',
    ],
  ),
  HotelTravelCluster(
    key: 'mallorca',
    labels: HotelTravelClusterLabel(
      nl: 'Mallorca',
      en: 'Mallorca',
      fr: 'Majorque',
      es: 'Mallorca',
    ),
    tags: <String>[
      'island',
      'coastal',
      'wellness',
      'family',
      'popularFor:island-holidays',
    ],
    relatedCountryCodes: <String>['ES'],
    relatedRegionKeys: <String>['balearic-islands'],
    relatedSettlementKeys: <String>['palma-de-mallorca', 'alcudia', 'soller'],
  ),
];

HotelTravelCluster? hotelTravelClusterByKey(String key) {
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final cluster in kHotelTravelClusters) {
    if (cluster.key == normalized) return cluster;
  }
  return null;
}

List<HotelTravelCluster> hotelTravelClustersForCountryCode(String countryCode) {
  final normalized = countryCode.trim().toUpperCase();
  if (normalized.isEmpty) return const <HotelTravelCluster>[];
  return kHotelTravelClusters
      .where((cluster) => cluster.relatedCountryCodes.contains(normalized))
      .toList(growable: false);
}

List<HotelTravelCluster> hotelTravelClustersForRegionKey(String regionKey) {
  final normalized = regionKey.trim().toLowerCase();
  if (normalized.isEmpty) return const <HotelTravelCluster>[];
  return kHotelTravelClusters
      .where((cluster) => cluster.relatedRegionKeys.contains(normalized))
      .toList(growable: false);
}

List<HotelTravelCluster> hotelTravelClustersForSettlementKey(
  String settlementKey,
) {
  final normalized = settlementKey.trim().toLowerCase();
  if (normalized.isEmpty) return const <HotelTravelCluster>[];
  return kHotelTravelClusters
      .where((cluster) => cluster.relatedSettlementKeys.contains(normalized))
      .toList(growable: false);
}
