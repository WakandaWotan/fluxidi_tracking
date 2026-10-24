typedef DiscoveryLabelTranslator =
    String Function(String nl, String en, String fr, String es);

String discoveryStayTypeLabel(String typeKey, DiscoveryLabelTranslator t) {
  switch (typeKey.trim().toLowerCase()) {
    case 'hotel':
      return t('Hotel', 'Hotel', 'Hôtel', 'Hotel');
    case 'bnb':
    case 'b&b':
    case 'bed_and_breakfast':
      return t('B&B', 'B&B', 'B&B', 'B&B');
    case 'apartment':
    case 'appartement':
      return t('Appartement', 'Apartment', 'Appartement', 'Apartamento');
    case 'guesthouse':
      return t(
        'Gastenverblijf',
        'Guesthouse',
        'Maison d’hôtes',
        'Casa de huéspedes',
      );
    default:
      return t('Verblijf', 'Stay', 'Hébergement', 'Alojamiento');
  }
}

String formatDiscoveryPriceHint(String? raw, {required String fromLabel}) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';

  final normalized = value.toLowerCase();
  final alreadyPrefixed =
      normalized.startsWith('vanaf ') ||
      normalized.startsWith('from ') ||
      normalized.startsWith('desde ') ||
      normalized.startsWith('à partir ') ||
      normalized.startsWith('a partir ');

  if (alreadyPrefixed) return value;
  return '$fromLabel $value';
}
