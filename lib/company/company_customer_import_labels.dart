// COMPANY-CUSTOMER-OPS-P0B

import 'package:fluxidi_tracking/app_strings.dart';

const LocalizedText kCompanyCustomerImportTitle = LocalizedText(
  nl: 'Klanten importeren',
  en: 'Import customers',
  fr: 'Importer des clients',
  es: 'Importar clientes',
);

const LocalizedText kCompanyCustomerImportPick = LocalizedText(
  nl: 'Kies een CSV-, Excel- of vCard-bestand',
  en: 'Choose a CSV, Excel or vCard file',
  fr: 'Choisissez un fichier CSV, Excel ou vCard',
  es: 'Elige un archivo CSV, Excel o vCard',
);

const LocalizedText kCompanyCustomerImportChooseFile = LocalizedText(
  nl: 'Bestand kiezen',
  en: 'Choose file',
  fr: 'Choisir un fichier',
  es: 'Elegir archivo',
);

const LocalizedText kCompanyCustomerImportNext = LocalizedText(
  nl: 'Volgende',
  en: 'Next',
  fr: 'Suivant',
  es: 'Siguiente',
);

const LocalizedText kCompanyCustomerImportBack = LocalizedText(
  nl: 'Terug',
  en: 'Back',
  fr: 'Retour',
  es: 'Atrás',
);

const LocalizedText kCompanyCustomerImportMap = LocalizedText(
  nl: 'Koppel de kolommen aan klantvelden. Niet-herkende kolommen mag je overslaan.',
  en: 'Map columns to customer fields. Unrecognized columns may be skipped.',
  fr: 'Associez les colonnes aux champs client. Les colonnes non reconnues peuvent être ignorées.',
  es: 'Asocia las columnas a los campos del cliente. Puedes omitir las no reconocidas.',
);

const LocalizedText kCompanyCustomerImportSheet = LocalizedText(
  nl: 'Werkblad',
  en: 'Sheet',
  fr: 'Feuille',
  es: 'Hoja',
);

const LocalizedText kCompanyCustomerImportHeaderRow = LocalizedText(
  nl: 'Kopregel',
  en: 'Header row',
  fr: 'Ligne d’en-tête',
  es: 'Fila de encabezado',
);

const LocalizedText kCompanyCustomerImportDefaultCountry = LocalizedText(
  nl: 'Standaardland voor lokale nummers (niet automatisch België)',
  en: 'Default country for local numbers (not assumed to be Belgium)',
  fr: 'Pays par défaut pour les numéros locaux (la Belgique n’est pas présumée)',
  es: 'País predeterminado para números locales (no se asume Bélgica)',
);

const LocalizedText kCompanyCustomerImportNoDefaultCountry = LocalizedText(
  nl: 'Geen standaardland',
  en: 'No default country',
  fr: 'Aucun pays par défaut',
  es: 'Sin país predeterminado',
);

const LocalizedText kCompanyCustomerImportReview = LocalizedText(
  nl: 'Controleer de selectie vóór het importeren.',
  en: 'Review the selection before importing.',
  fr: 'Vérifiez la sélection avant d’importer.',
  es: 'Revisa la selección antes de importar.',
);

const LocalizedText kCompanyCustomerImportPartialConfirm = LocalizedText(
  nl: 'Alleen de geselecteerde geldige rijen importeren. Ongeldige rijen blijven buiten.',
  en: 'Import only the selected valid rows. Invalid rows will be left out.',
  fr: 'Importer uniquement les lignes valides sélectionnées. Les lignes invalides restent exclues.',
  es: 'Importar solo las filas válidas seleccionadas. Las inválidas quedarán fuera.',
);

const LocalizedText kCompanyCustomerImportStart = LocalizedText(
  nl: 'Importeren',
  en: 'Import',
  fr: 'Importer',
  es: 'Importar',
);

const LocalizedText kCompanyCustomerImportStop = LocalizedText(
  nl: 'Stoppen',
  en: 'Stop',
  fr: 'Arrêter',
  es: 'Detener',
);

const LocalizedText kCompanyCustomerImportStopHint = LocalizedText(
  nl: 'Stoppen bewaart de klanten die de server al heeft bevestigd.',
  en: 'Stopping keeps customers the server already confirmed.',
  fr: 'Arrêter conserve les clients déjà confirmés par le serveur.',
  es: 'Detener conserva los clientes que el servidor ya confirmó.',
);

const LocalizedText kCompanyCustomerImportSkipDup = LocalizedText(
  nl: 'Overslaan',
  en: 'Skip',
  fr: 'Ignorer',
  es: 'Omitir',
);

const LocalizedText kCompanyCustomerImportKeepSeparate = LocalizedText(
  nl: 'Toch als aparte klant toevoegen',
  en: 'Add as a separate customer',
  fr: 'Ajouter quand même comme client distinct',
  es: 'Añadir igualmente como cliente distinto',
);

const LocalizedText kCompanyCustomerImportDupHint = LocalizedText(
  nl: 'Gedeelde e-mail of telefoon betekent niet automatisch dezelfde persoon. Dossiers worden niet samengevoegd.',
  en: 'A shared email or phone does not mean the same person. Records are not merged.',
  fr: 'Un e-mail ou un téléphone partagé ne signifie pas la même personne. Les dossiers ne sont pas fusionnés.',
  es: 'Un correo o teléfono compartido no implica la misma persona. No se fusionan expedientes.',
);

const LocalizedText kCompanyCustomerImportResume = LocalizedText(
  nl: 'Hervatten',
  en: 'Resume',
  fr: 'Reprendre',
  es: 'Reanudar',
);

const LocalizedText kCompanyCustomerImportResumeHint = LocalizedText(
  nl: 'Er staat een onvolledige import klaar. Hervatten gebruikt dezelfde rijen zonder een tweede klant te maken.',
  en: 'An unfinished import is waiting. Resume uses the same rows and will not create a second customer.',
  fr: 'Une import inachevée est en attente. La reprise utilise les mêmes lignes et ne crée pas de second client.',
  es: 'Hay una importación incompleta. Reanudar usa las mismas filas y no crea un segundo cliente.',
);

const LocalizedText kCompanyCustomerImportFileUnreadable = LocalizedText(
  nl: 'Dit bestand kon niet worden gelezen.',
  en: 'This file could not be read.',
  fr: 'Impossible de lire ce fichier.',
  es: 'No se pudo leer este archivo.',
);

const LocalizedText kCompanyCustomerImportLimitFile = LocalizedText(
  nl: 'Het bestand is groter dan 2 MB.',
  en: 'The file is larger than 2 MB.',
  fr: 'Le fichier dépasse 2 Mo.',
  es: 'El archivo supera 2 MB.',
);

const LocalizedText kCompanyCustomerImportLimitRows = LocalizedText(
  nl: 'Meer dan 2000 contacten. Het bestand is niet ingekort.',
  en: 'More than 2000 contacts. The file was not truncated.',
  fr: 'Plus de 2000 contacts. Le fichier n’a pas été tronqué.',
  es: 'Más de 2000 contactos. El archivo no se ha recortado.',
);

const LocalizedText kCompanyCustomerImportLimitXlsx = LocalizedText(
  nl: 'De uitgepakte Excel-inhoud is groter dan 8 MB.',
  en: 'Unpacked Excel content is larger than 8 MB.',
  fr: 'Le contenu Excel décompressé dépasse 8 Mo.',
  es: 'El contenido Excel descomprimido supera 8 MB.',
);

const LocalizedText kCompanyCustomerImportFormula = LocalizedText(
  nl: 'Een formulecel kon niet veilig worden gelezen. Formules worden niet uitgevoerd.',
  en: 'A formula cell could not be read safely. Formulas are not executed.',
  fr: 'Une cellule formule n’a pas pu être lue en toute sécurité. Les formules ne sont pas exécutées.',
  es: 'No se pudo leer una celda de fórmula de forma segura. No se ejecutan fórmulas.',
);

const LocalizedText kCompanyCustomerImportUnsupported = LocalizedText(
  nl: 'Dit bestandsformaat of deze vCard-versie wordt niet ondersteund.',
  en: 'This file format or vCard version is not supported.',
  fr: 'Ce format ou cette version vCard n’est pas pris en charge.',
  es: 'Este formato o versión vCard no es compatible.',
);

const LocalizedText kCompanyCustomerImportSkipColumn = LocalizedText(
  nl: 'Overslaan',
  en: 'Skip',
  fr: 'Ignorer',
  es: 'Omitir',
);
