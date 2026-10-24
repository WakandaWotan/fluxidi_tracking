// COMPANY-CUSTOMER-OPS-P0B

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';

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
  nl: 'Land voor telefoonnummers zonder landcode',
  en: 'Country for phone numbers without a country code',
  fr: 'Pays pour les numéros sans indicatif',
  es: 'País para números sin código de país',
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

const LocalizedText kCompanyCustomerImportSkippedColumns = LocalizedText(
  nl: 'Deze kolommen worden niet geïmporteerd. Koppel ze of laat ze bewust overgeslagen.',
  en: 'These columns will not be imported. Map them or leave them skipped on purpose.',
  fr: 'Ces colonnes ne seront pas importées. Associez-les ou laissez-les ignorées.',
  es: 'Estas columnas no se importarán. Asócialas o déjalas omitidas a propósito.',
);

const LocalizedText kCompanyCustomerImportSkipColumn = LocalizedText(
  nl: 'Overslaan',
  en: 'Skip',
  fr: 'Ignorer',
  es: 'Omitir',
);

const LocalizedText kCompanyCustomerImportExpired = LocalizedText(
  nl: 'Deze import is verlopen. De al bevestigde klanten blijven bewaard. Start een nieuwe import voor de rest.',
  en: 'This import has expired. Confirmed customers are kept. Start a new import for the rest.',
  fr: 'Cette import a expiré. Les clients confirmés sont conservés. Recommencez pour le reste.',
  es: 'Esta importación caducó. Los clientes confirmados se conservan. Empieza una nueva para el resto.',
);

const LocalizedText kCompanyCustomerImportUnknown = LocalizedText(
  nl: 'Deze import is niet meer bekend op de server. Start een nieuwe import. Al bevestigde klanten blijven staan.',
  en: 'The server no longer knows this import. Start a new import. Confirmed customers remain.',
  fr: 'Le serveur ne connaît plus cette import. Recommencez. Les clients confirmés restent.',
  es: 'El servidor ya no conoce esta importación. Empieza una nueva. Los confirmados permanecen.',
);

const LocalizedText kCompanyCustomerImportRepick = LocalizedText(
  nl: 'Kies hetzelfde bestand opnieuw. Alleen de lokale voortgang is bewaard, niet het bestand.',
  en: 'Choose the same file again. Only local progress was kept, not the file.',
  fr: 'Choisissez le même fichier. Seule la progression locale a été conservée.',
  es: 'Elige de nuevo el mismo archivo. Solo se guardó el progreso local.',
);

const LocalizedText kCompanyCustomerImportFileMismatch = LocalizedText(
  nl: 'Dit bestand of de kolommen komen niet overeen met de onderbroken import.',
  en: 'This file or its columns do not match the unfinished import.',
  fr: 'Ce fichier ou ses colonnes ne correspondent pas à l’import interrompue.',
  es: 'Este archivo o sus columnas no coinciden con la importación interrumpida.',
);

const LocalizedText kCompanyCustomerImportMappingMismatch = LocalizedText(
  nl: 'De veldkoppeling komt niet overeen. Controleer de kolommen vóór hervatten.',
  en: 'The column mapping does not match. Check the columns before resuming.',
  fr: 'L’association des colonnes ne correspond pas. Vérifiez-la avant de reprendre.',
  es: 'La asignación de columnas no coincide. Revísala antes de reanudar.',
);

const LocalizedText kCompanyCustomerImportLookupFailed = LocalizedText(
  nl: 'Het bestand is gelezen, maar de servercontrole op bestaande klanten is mislukt.',
  en: 'The file was read, but the server check for existing customers failed.',
  fr: 'Le fichier a été lu, mais le contrôle serveur des clients existants a échoué.',
  es: 'El archivo se leyó, pero falló la comprobación de clientes existentes en el servidor.',
);

const LocalizedText kCompanyCustomerImportCountFound = LocalizedText(
  nl: 'Gevonden rijen',
  en: 'Rows found',
  fr: 'Lignes trouvées',
  es: 'Filas encontradas',
);

const LocalizedText kCompanyCustomerImportCountValid = LocalizedText(
  nl: 'Geldig',
  en: 'Valid',
  fr: 'Valides',
  es: 'Válidas',
);

const LocalizedText kCompanyCustomerImportCountInvalid = LocalizedText(
  nl: 'Ongeldig',
  en: 'Invalid',
  fr: 'Invalides',
  es: 'No válidas',
);

const LocalizedText kCompanyCustomerImportCountMissing = LocalizedText(
  nl: 'Naam of contact ontbreekt',
  en: 'Missing name or contact',
  fr: 'Nom ou contact manquant',
  es: 'Falta nombre o contacto',
);

const LocalizedText kCompanyCustomerImportCountInFileDup = LocalizedText(
  nl: 'Dubbel in dit bestand',
  en: 'Duplicate in this file',
  fr: 'Doublon dans ce fichier',
  es: 'Duplicado en este archivo',
);

const LocalizedText kCompanyCustomerImportCountCompanyMatch = LocalizedText(
  nl: 'Al bekend bij dit bedrijf',
  en: 'Already at this company',
  fr: 'Déjà connu de cette entreprise',
  es: 'Ya conocido en esta empresa',
);

const LocalizedText kCompanyCustomerImportCountSelected = LocalizedText(
  nl: 'Geselecteerd om te importeren',
  en: 'Selected to import',
  fr: 'Sélectionnées pour import',
  es: 'Seleccionadas para importar',
);

const LocalizedText kCompanyCustomerImportCountAdded = LocalizedText(
  nl: 'Toegevoegd',
  en: 'Added',
  fr: 'Ajoutés',
  es: 'Añadidos',
);

const LocalizedText kCompanyCustomerImportCountSkipped = LocalizedText(
  nl: 'Overgeslagen',
  en: 'Skipped',
  fr: 'Ignorés',
  es: 'Omitidos',
);

const LocalizedText kCompanyCustomerImportCountFailed = LocalizedText(
  nl: 'Mislukt',
  en: 'Failed',
  fr: 'Échoués',
  es: 'Fallidos',
);

const LocalizedText kCompanyCustomerImportSourceRow = LocalizedText(
  nl: 'Bestandsrij',
  en: 'File row',
  fr: 'Ligne du fichier',
  es: 'Fila del archivo',
);

const LocalizedText kCompanyCustomerImportContactRequired = LocalizedText(
  nl: 'E-mail of telefoon is verplicht.',
  en: 'Email or phone is required.',
  fr: 'L’e-mail ou le téléphone est obligatoire.',
  es: 'El correo o el teléfono es obligatorio.',
);

const LocalizedText kCompanyCustomerImportNameRequired = LocalizedText(
  nl: 'Naam is verplicht.',
  en: 'A name is required.',
  fr: 'Le nom est obligatoire.',
  es: 'El nombre es obligatorio.',
);

const LocalizedText kCompanyCustomerImportEmailInvalid = LocalizedText(
  nl: 'E-mailadres is ongeldig.',
  en: 'The email address is invalid.',
  fr: 'L’adresse e-mail n’est pas valable.',
  es: 'El correo no es válido.',
);

const LocalizedText kCompanyCustomerImportPhoneInvalid = LocalizedText(
  nl: 'Telefoonnummer is ongeldig.',
  en: 'The phone number is invalid.',
  fr: 'Le numéro de téléphone n’est pas valable.',
  es: 'El teléfono no es válido.',
);

String companyCustomerImportFieldErrorText(
  String field,
  String code,
  AppLanguage language,
) {
  switch ('$field:$code') {
    case 'contact:required':
      return kCompanyCustomerImportContactRequired.of(language);
    case 'display_name:required':
      return kCompanyCustomerImportNameRequired.of(language);
    case 'email:invalid':
      return kCompanyCustomerImportEmailInvalid.of(language);
    case 'phone:invalid':
      return kCompanyCustomerImportPhoneInvalid.of(language);
    case 'vat_number:invalid':
      return kCompanyCustomersInvalidVat.of(language);
    default:
      return '$field: $code';
  }
}

String companyCustomerImportFieldLabel(String field, AppLanguage language) {
  switch (field) {
    case 'skip':
      return kCompanyCustomerImportSkipColumn.of(language);
    case 'display_name':
      return kCompanyCustomersDisplayName.of(language);
    case 'first_name':
      return kCompanyCustomersFirstName.of(language);
    case 'last_name':
      return kCompanyCustomersLastName.of(language);
    case 'email':
      return kCompanyCustomersEmail.of(language);
    case 'phone':
      return kCompanyCustomersPhone.of(language);
    case 'country_calling_code':
      return kCompanyCustomersCallingCode.of(language);
    case 'company_name':
      return kCompanyCustomersCompanyName.of(language);
    case 'vat_number':
      return kCompanyCustomersVat.of(language);
    case 'locale':
      return kCompanyCustomersLocale.of(language);
    case 'internal_notes':
      return kCompanyCustomersInternalNotes.of(language);
    case 'address_line1':
      return kCompanyCustomersAddressStreet.of(language);
    case 'address_house_number':
      return kCompanyCustomersAddressNumber.of(language);
    case 'address_line2':
      return kCompanyCustomersAddressLine2.of(language);
    case 'address_city':
      return kCompanyCustomersAddressCity.of(language);
    case 'address_postal_code':
      return kCompanyCustomersAddressPostal.of(language);
    case 'address_country':
      return kCompanyCustomersAddressCountry.of(language);
    case 'address_type':
      return kCompanyCustomersAddressType.of(language);
    case 'address_label':
      return kCompanyCustomersAddressLabel.of(language);
    case 'address_notes':
      return kCompanyCustomersAddressNotes.of(language);
    case 'address2_line1':
      return '${kCompanyCustomersAddressStreet.of(language)} 2';
    case 'address2_house_number':
      return '${kCompanyCustomersAddressNumber.of(language)} 2';
    case 'address2_line2':
      return '${kCompanyCustomersAddressLine2.of(language)} 2';
    case 'address2_city':
      return '${kCompanyCustomersAddressCity.of(language)} 2';
    case 'address2_postal_code':
      return '${kCompanyCustomersAddressPostal.of(language)} 2';
    case 'address2_country':
      return '${kCompanyCustomersAddressCountry.of(language)} 2';
    case 'address2_type':
      return '${kCompanyCustomersAddressType.of(language)} 2';
    case 'address2_label':
      return '${kCompanyCustomersAddressLabel.of(language)} 2';
    case 'address2_notes':
      return '${kCompanyCustomersAddressNotes.of(language)} 2';
    default:
      return field;
  }
}

String companyCustomerImportSourceRowLabel(int sourceIndex, AppLanguage language) {
  return '${kCompanyCustomerImportSourceRow.of(language)} $sourceIndex';
}
