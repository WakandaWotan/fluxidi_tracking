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
    case 'white':
      return brandSignatureGoldL10n(
        nl: 'Wit',
        en: 'White',
        fr: 'Blanc',
        es: 'Blanco',
      );
    case 'warmWhite':
      return brandSignatureGoldL10n(
        nl: 'Warm wit',
        en: 'Warm white',
        fr: 'Blanc chaud',
        es: 'Blanco cálido',
      );
    case 'lightGray':
      return brandSignatureGoldL10n(
        nl: 'Lichtgrijs',
        en: 'Light gray',
        fr: 'Gris clair',
        es: 'Gris claro',
      );
    case 'midGray':
      return brandSignatureGoldL10n(
        nl: 'Middengrijs',
        en: 'Mid gray',
        fr: 'Gris moyen',
        es: 'Gris medio',
      );
    case 'anthracite':
      return brandSignatureGoldL10n(
        nl: 'Antraciet',
        en: 'Anthracite',
        fr: 'Anthracite',
        es: 'Antracita',
      );
    case 'black':
      return brandSignatureGoldL10n(
        nl: 'Zwart',
        en: 'Black',
        fr: 'Noir',
        es: 'Negro',
      );
    case 'red':
      return brandSignatureGoldL10n(
        nl: 'Rood',
        en: 'Red',
        fr: 'Rouge',
        es: 'Rojo',
      );
    case 'orange':
      return brandSignatureGoldL10n(
        nl: 'Oranje',
        en: 'Orange',
        fr: 'Orange',
        es: 'Naranja',
      );
    case 'yellow':
      return brandSignatureGoldL10n(
        nl: 'Geel',
        en: 'Yellow',
        fr: 'Jaune',
        es: 'Amarillo',
      );
    case 'lime':
      return brandSignatureGoldL10n(
        nl: 'Lime',
        en: 'Lime',
        fr: 'Citron vert',
        es: 'Lima',
      );
    case 'green':
      return brandSignatureGoldL10n(
        nl: 'Groen',
        en: 'Green',
        fr: 'Vert',
        es: 'Verde',
      );
    case 'turquoise':
      return brandSignatureGoldL10n(
        nl: 'Turquoise',
        en: 'Turquoise',
        fr: 'Turquoise',
        es: 'Turquesa',
      );
    case 'cyan':
      return brandSignatureGoldL10n(
        nl: 'Cyaan',
        en: 'Cyan',
        fr: 'Cyan',
        es: 'Cian',
      );
    case 'blue':
      return brandSignatureGoldL10n(
        nl: 'Blauw',
        en: 'Blue',
        fr: 'Bleu',
        es: 'Azul',
      );
    case 'indigo':
      return brandSignatureGoldL10n(
        nl: 'Indigo',
        en: 'Indigo',
        fr: 'Indigo',
        es: 'Índigo',
      );
    case 'violet':
      return brandSignatureGoldL10n(
        nl: 'Violet',
        en: 'Violet',
        fr: 'Violet',
        es: 'Violeta',
      );
    case 'purple':
      return brandSignatureGoldL10n(
        nl: 'Paars',
        en: 'Purple',
        fr: 'Violet',
        es: 'Morado',
      );
    case 'magenta':
      return brandSignatureGoldL10n(
        nl: 'Magenta',
        en: 'Magenta',
        fr: 'Magenta',
        es: 'Magenta',
      );
    default:
      return brandSignatureGoldL10n(
        nl: 'Achtergrondkleur',
        en: 'Background color',
        fr: 'Couleur de fond',
        es: 'Color de fondo',
      );
  }
}
