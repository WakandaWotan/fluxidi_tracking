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
