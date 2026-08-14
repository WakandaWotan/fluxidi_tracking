import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

String brandSignatureGoldL10n({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (appLanguageNotifier.value) {
    case AppLanguage.en:
      return en;
    case AppLanguage.fr:
      return fr;
    case AppLanguage.es:
      return es;
    case AppLanguage.nl:
      return nl;
    case AppLanguage.de:
      return en;
  }
}

String businessThemeSelectorTitle() => brandSignatureGoldL10n(
  nl: 'Kies je uitstraling',
  en: 'Choose your appearance',
  fr: 'Choisissez votre apparence',
  es: 'Elige tu estilo',
);

String businessThemeSelectorApplyLabel() => brandSignatureGoldL10n(
  nl: 'Toepassen',
  en: 'Apply',
  fr: 'Appliquer',
  es: 'Aplicar',
);

String businessThemeSelectorCancelLabel() => brandSignatureGoldL10n(
  nl: 'Annuleren',
  en: 'Cancel',
  fr: 'Annuler',
  es: 'Cancelar',
);

String brandSignatureCustomizeStyleLabel() => brandSignatureGoldL10n(
  nl: 'Huisstijl aanpassen',
  en: 'Customize brand style',
  fr: 'Personnaliser le style',
  es: 'Personalizar estilo',
);

String brandSignatureRailTitle() => brandSignatureGoldL10n(
  nl: 'Kies je achtergrondkleur',
  en: 'Choose your background color',
  fr: 'Choisissez votre couleur de fond',
  es: 'Elige el color de fondo',
);

String brandSignatureResetDefaultLabel() => brandSignatureGoldL10n(
  nl: 'Standaard herstellen',
  en: 'Restore default',
  fr: 'Restaurer le défaut',
  es: 'Restaurar predeterminado',
);

String brandSignatureFamilyLabel(String familyId) {
  switch (familyId) {
    case 'bronze':
      return brandSignatureGoldL10n(
        nl: 'Warm brons',
        en: 'Warm bronze',
        fr: 'Bronze chaud',
        es: 'Bronce cálido',
      );
    case 'bordeaux':
      return brandSignatureGoldL10n(
        nl: 'Diep bordeaux',
        en: 'Deep burgundy',
        fr: 'Bordeaux profond',
        es: 'Burdeos profundo',
      );
    case 'aubergine':
      return brandSignatureGoldL10n(
        nl: 'Aubergine',
        en: 'Aubergine',
        fr: 'Aubergine',
        es: 'Berenjena',
      );
    case 'midnight':
      return brandSignatureGoldL10n(
        nl: 'Nachtblauw',
        en: 'Midnight blue',
        fr: 'Bleu nuit',
        es: 'Azul noche',
      );
    case 'petroleum':
      return brandSignatureGoldL10n(
        nl: 'Petroleum',
        en: 'Petroleum',
        fr: 'Pétrole',
        es: 'Petróleo',
      );
    case 'emerald':
      return brandSignatureGoldL10n(
        nl: 'Smaragd',
        en: 'Emerald',
        fr: 'Émeraude',
        es: 'Esmeralda',
      );
    case 'anthracite':
      return brandSignatureGoldL10n(
        nl: 'Antraciet',
        en: 'Anthracite',
        fr: 'Anthracite',
        es: 'Antracita',
      );
    case 'goldBrown':
    default:
      return brandSignatureGoldL10n(
        nl: 'Warm goudbruin',
        en: 'Warm gold-brown',
        fr: 'Brun doré chaud',
        es: 'Marrón dorado',
      );
  }
}
