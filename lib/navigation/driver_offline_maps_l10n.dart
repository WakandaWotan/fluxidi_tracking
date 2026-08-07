// RELEASE-LANGUAGE-CONSISTENCY-NL-EN-FR-ES-P0
//
// Offline maps UI chrome must follow Fluxidi appLanguage for NL/EN/FR/ES.
// Never silently fall back to English when FR/ES is active for known chrome.

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';

/// Resolve an offline-maps UI string for the active Fluxidi language.
///
/// Prefer passing all four languages. When [fr]/[es] are omitted, a curated
/// English-key table is used so nl/en call sites stay fully localized.
String resolveOfflineMapsUiText({
  required String nl,
  required String en,
  String? fr,
  String? es,
}) {
  final lang = appConfig.currentLanguage;
  final lookedUp = _lookupFrEs(en);
  final resolvedFr = fr ?? lookedUp?.$1;
  final resolvedEs = es ?? lookedUp?.$2;
  if (resolvedFr != null && resolvedEs != null) {
    return LocalizedText(
      nl: nl,
      en: en,
      fr: resolvedFr,
      es: resolvedEs,
    ).of(lang);
  }

  switch (lang) {
    case AppLanguage.nl:
      return nl;
    case AppLanguage.en:
      return en;
    case AppLanguage.fr:
      return resolvedFr ?? en;
    case AppLanguage.es:
      return resolvedEs ?? en;
    case AppLanguage.de:
      return en;
  }
}

(String, String)? _lookupFrEs(String en) {
  final direct = _offlineMapsFrEsByEn[en];
  if (direct != null) return direct;
  final compact = en.replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final entry in _offlineMapsFrEsByEn.entries) {
    if (entry.key.replaceAll(RegExp(r'\s+'), ' ').trim() == compact) {
      return entry.value;
    }
  }
  return null;
}

/// Localized offline-region completion status for UI chrome.
String offlineMapsRegionStatusText(DriverOfflineMapCompletionStatus status) {
  switch (status) {
    case DriverOfflineMapCompletionStatus.complete:
      return resolveOfflineMapsUiText(
        nl: 'Volledig',
        en: 'Complete',
        fr: 'Complet',
        es: 'Completo',
      );
    case DriverOfflineMapCompletionStatus.completedWithErrors:
      return resolveOfflineMapsUiText(
        nl: 'Ontladen met fouten (niet volledig)',
        en: 'Downloaded with errors (not complete)',
        fr: 'Téléchargé avec erreurs (incomplet)',
        es: 'Descargado con errores (incompleto)',
      );
    case DriverOfflineMapCompletionStatus.incomplete:
      return resolveOfflineMapsUiText(
        nl: 'Bezig / onvolledig',
        en: 'In progress / incomplete',
        fr: 'En cours / incomplet',
        es: 'En curso / incompleto',
      );
    case DriverOfflineMapCompletionStatus.expiredOrStale:
      return resolveOfflineMapsUiText(
        nl: 'Verlopen — vernieuwen aanbevolen',
        en: 'Expired — refresh recommended',
        fr: 'Expiré — actualisation recommandée',
        es: 'Caducado — se recomienda actualizar',
      );
    case DriverOfflineMapCompletionStatus.unknown:
      return resolveOfflineMapsUiText(
        nl: 'Status onbekend',
        en: 'Status unknown',
        fr: 'Statut inconnu',
        es: 'Estado desconocido',
      );
  }
}

String offlineMapsNoneLabel() => resolveOfflineMapsUiText(
      nl: 'geen',
      en: 'none',
      fr: 'aucun',
      es: 'ninguno',
    );

String offlineMapsVerifiedSuffix({required bool? verified}) {
  if (verified == true) {
    return resolveOfflineMapsUiText(
      nl: ' (geverifieerd)',
      en: ' (verified)',
      fr: ' (vérifié)',
      es: ' (verificado)',
    );
  }
  if (verified == false) {
    return resolveOfflineMapsUiText(
      nl: ' (niet volledig)',
      en: ' (not complete)',
      fr: ' (incomplet)',
      es: ' (incompleto)',
    );
  }
  return resolveOfflineMapsUiText(
    nl: ' (niet geverifieerd)',
    en: ' (not verified)',
    fr: ' (non vérifié)',
    es: ' (no verificado)',
  );
}

/// Curated FR/ES for exact English offline-maps chrome strings.
const Map<String, (String, String)> _offlineMapsFrEsByEn =
    <String, (String, String)>{
  'Offline map tiles': (
    'Tuiles de carte hors ligne',
    'Teselas de mapa sin conexión',
  ),
  'Downloaded maps': ('Cartes téléchargées', 'Mapas descargados'),
  'Map display can be available offline. Route calculation, search, traffic information and rerouting currently require internet.':
      (
        'L’affichage de la carte peut être disponible hors ligne. Le calcul d’itinéraire, la recherche, le trafic et le recalcul nécessitent encore Internet.',
        'La visualización del mapa puede estar disponible sin conexión. El cálculo de rutas, la búsqueda, el tráfico y el recálculo siguen necesitando internet.',
      ),
  'Download map areas for weak mobile signal.': (
    'Téléchargez des zones de carte pour un signal mobile faible.',
    'Descarga zonas de mapa para señal móvil débil.',
  ),
  'Downloaded maps keep the street map visible when signal is weak. New routes and recalculation still need internet.':
      (
        'Les cartes téléchargées gardent la carte visible lorsque le signal est faible. Les nouveaux itinéraires et le recalcul nécessitent encore Internet.',
        'Los mapas descargados mantienen el mapa visible cuando la señal es débil. Las rutas nuevas y el recálculo siguen necesitando internet.',
      ),
  'Wi‑Fi recommended for large downloads.': (
    'Wi‑Fi recommandé pour les gros téléchargements.',
    'Se recomienda Wi‑Fi para descargas grandes.',
  ),
  'Wi‑Fi only': ('Wi‑Fi uniquement', 'Solo Wi‑Fi'),
  'Europe — search your operating area': (
    'Europe — recherchez votre zone d’activité',
    'Europa — busca tu zona de operación',
  ),
  'Search a city, municipality or postcode in Europe. Download uses a bounded radius (not a whole country).':
      (
        'Recherchez une ville, une commune ou un code postal en Europe. Le téléchargement utilise un rayon limité (pas un pays entier).',
        'Busca una ciudad, municipio o código postal en Europa. La descarga usa un radio limitado (no un país entero).',
      ),
  'e.g. Lille, Eindhoven, Köln, Madrid…': (
    'p. ex. Lille, Eindhoven, Köln, Madrid…',
    'p. ej. Lille, Eindhoven, Köln, Madrid…',
  ),
  'Download radius': ('Rayon de téléchargement', 'Radio de descarga'),
  'Preview & download': ('Aperçu et télécharger', 'Vista previa y descargar'),
  'Select a place first.': (
    'Sélectionnez d’abord un lieu.',
    'Selecciona primero un lugar.',
  ),
  'Preparing preview…': (
    'Préparation de l’aperçu…',
    'Preparando vista previa…',
  ),
  'Estimating the map area size.': (
    'Estimation de la taille de la zone.',
    'Estimando el tamaño del área del mapa.',
  ),
  'Shortcuts (existing)': (
    'Raccourcis (existants)',
    'Accesos directos (existentes)',
  ),
  'Existing Belgium / Maarkedal regions remain available.': (
    'Les régions Belgique / Maarkedal existantes restent disponibles.',
    'Las regiones existentes de Bélgica / Maarkedal siguen disponibles.',
  ),
  'Refresh': ('Actualiser', 'Actualizar'),
  'Downloaded regions': ('Régions téléchargées', 'Regiones descargadas'),
  'No map tiles downloaded yet.': (
    'Aucune tuile de carte téléchargée pour le moment.',
    'Aún no hay teselas de mapa descargadas.',
  ),
  'Download map area?': (
    'Télécharger la zone de carte ?',
    '¿Descargar el área del mapa?',
  ),
  'Map area too large': (
    'Zone de carte trop grande',
    'Área de mapa demasiado grande',
  ),
  'Cancel': ('Annuler', 'Cancelar'),
  'Download': ('Télécharger', 'Descargar'),
  'Delete region?': ('Supprimer la région ?', '¿Eliminar la región?'),
  'Delete': ('Supprimer', 'Eliminar'),
  'Map tiles removed.': (
    'Tuiles de carte supprimées.',
    'Teselas de mapa eliminadas.',
  ),
  'Could not delete region.': (
    'Impossible de supprimer la région.',
    'No se pudo eliminar la región.',
  ),
  'Estimating size…': ('Estimation de la taille…', 'Estimando tamaño…'),
  'Map area downloaded. Status: Complete.': (
    'Zone de carte téléchargée. Statut : Complet.',
    'Área de mapa descargada. Estado: Completo.',
  ),
  'Download finished. Status is being verified — not yet marked complete.': (
    'Téléchargement terminé. Statut en cours de vérification — pas encore marqué comme complet.',
    'Descarga finalizada. El estado se está verificando — aún no marcada como completa.',
  ),
  'Could not load downloaded map tiles.': (
    'Impossible de charger les tuiles téléchargées.',
    'No se pudieron cargar las teselas descargadas.',
  ),
  'No European place found. Try a city, municipality or postcode.': (
    'Aucun lieu européen trouvé. Essayez une ville, une commune ou un code postal.',
    'No se encontró un lugar europeo. Prueba ciudad, municipio o código postal.',
  ),
  'Offline map': ('Carte hors ligne', 'Mapa sin conexión'),
  'Back': ('Retour', 'Atrás'),
  'Night': ('Nuit', 'Noche'),
  'Day': ('Jour', 'Día'),
  'Offline region · Complete': (
    'Région hors ligne · Complet',
    'Región sin conexión · Completa',
  ),
  'Outside the downloaded map area': (
    'Hors de la zone de carte téléchargée',
    'Fuera del área de mapa descargada',
  ),
  'This region has no usable geometry for a preview.': (
    'Cette région n’a pas de géométrie utilisable pour un aperçu.',
    'Esta región no tiene geometría usable para una vista previa.',
  ),
  'View map': ('Voir la carte', 'Ver mapa'),
  'suggested': ('suggestion', 'sugerido'),
  'Style pack': ('Style de carte', 'Estilo de mapa'),
  'Map tiles': ('Tuiles de carte', 'Teselas de mapa'),
  'Estimate': ('Estimation', 'Estimación'),
  'Belgium base map': ('Carte de base Belgique', 'Mapa base de Bélgica'),
  'Overview map for Belgium. Limited detail, lower storage use.': (
    'Carte d’ensemble pour la Belgique. Détail limité, moins de stockage.',
    'Mapa general de Bélgica. Detalle limitado, menos almacenamiento.',
  ),
  'Maarkedal / Flemish Ardennes detail': (
    'Maarkedal / Ardennes flamandes — détail',
    'Maarkedal / Ardenas flamencas — detalle',
  ),
  'Street detail for Maarkedal, Oudenaarde, Ronse and nearby area.': (
    'Détail des rues pour Maarkedal, Oudenaarde, Ronse et environs.',
    'Detalle de calles para Maarkedal, Oudenaarde, Ronse y alrededores.',
  ),
  'Brussels (test)': ('Bruxelles (test)', 'Bruselas (prueba)'),
  'Internal test region.': (
    'Région de test interne.',
    'Región de prueba interna.',
  ),
  'Selected place': ('Lieu sélectionné', 'Lugar seleccionado'),
  'Downloading…': ('Téléchargement…', 'Descargando…'),
  'Downloading map area…': (
    'Téléchargement de la zone…',
    'Descargando área del mapa…',
  ),
  'Active route corridor (preparation)': (
    'Corridor d’itinéraire actif (préparation)',
    'Corredor de ruta activa (preparación)',
  ),
  'Wi‑Fi is recommended. This uses storage and mobile data.\n\nThis only keeps the street map visible when signal is weak. New routes and recalculation still need internet.':
      (
        'Préférez le Wi‑Fi. Cela utilise du stockage et des données mobiles.\n\nCela ne garde que la carte visible avec un signal faible. Les nouveaux itinéraires et le recalcul nécessitent encore Internet.',
        'Prefiere Wi‑Fi. Esto usa almacenamiento y datos móviles.\n\nSolo mantiene el mapa visible con señal débil. Las rutas nuevas y el recálculo siguen necesitando internet.',
      ),
};
