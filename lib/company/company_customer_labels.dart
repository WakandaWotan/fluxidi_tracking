// COMPANY-CUSTOMER-OPS-P0A

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

const LocalizedText kCompanyCustomersTitle = LocalizedText(
  nl: 'Klantenbeheer',
  en: 'Customer management',
  fr: 'Gestion des clients',
  es: 'Gestión de clientes',
);

const LocalizedText kCompanyCustomersSubtitle = LocalizedText(
  nl: 'Bedrijfsklanten',
  en: 'Company customers',
  fr: 'Clients de l’entreprise',
  es: 'Clientes de la empresa',
);

const LocalizedText kCompanyCustomersSearchHint = LocalizedText(
  nl: 'Zoek op naam, e-mail of telefoon',
  en: 'Search by name, email or phone',
  fr: 'Rechercher par nom, e-mail ou téléphone',
  es: 'Buscar por nombre, correo o teléfono',
);

const LocalizedText kCompanyCustomersAddLabel = LocalizedText(
  nl: 'Klant toevoegen',
  en: 'Add customer',
  fr: 'Ajouter un client',
  es: 'Añadir cliente',
);

const LocalizedText kCompanyCustomersActiveFilter = LocalizedText(
  nl: 'Actief',
  en: 'Active',
  fr: 'Actifs',
  es: 'Activos',
);

const LocalizedText kCompanyCustomersArchivedFilter = LocalizedText(
  nl: 'Gearchiveerd',
  en: 'Archived',
  fr: 'Archivés',
  es: 'Archivados',
);

const LocalizedText kCompanyCustomersEmptyActive = LocalizedText(
  nl: 'Nog geen actieve klanten voor dit bedrijf.',
  en: 'No active customers for this company yet.',
  fr: 'Aucun client actif pour cette entreprise.',
  es: 'Aún no hay clientes activos para esta empresa.',
);

const LocalizedText kCompanyCustomersEmptyArchived = LocalizedText(
  nl: 'Geen gearchiveerde klanten.',
  en: 'No archived customers.',
  fr: 'Aucun client archivé.',
  es: 'No hay clientes archivados.',
);

const LocalizedText kCompanyCustomersEmptySearch = LocalizedText(
  nl: 'Geen klanten gevonden voor deze zoekopdracht.',
  en: 'No customers match this search.',
  fr: 'Aucun client ne correspond à cette recherche.',
  es: 'Ningún cliente coincide con esta búsqueda.',
);

const LocalizedText kCompanyCustomersSearchStillOpen = LocalizedText(
  nl: 'Deze zoekopdracht is nog niet door alle pagina’s gegaan.',
  en: 'This search has not yet walked every remaining page.',
  fr: 'Cette recherche n’a pas encore parcouru toutes les pages.',
  es: 'Esta búsqueda aún no ha recorrido todas las páginas.',
);

const LocalizedText kCompanyCustomersContinueSearch = LocalizedText(
  nl: 'Verder zoeken in volgende pagina’s',
  en: 'Continue searching later pages',
  fr: 'Continuer la recherche sur les pages suivantes',
  es: 'Seguir buscando en páginas posteriores',
);

const LocalizedText kCompanyCustomersImportLabel = LocalizedText(
  nl: 'Klanten importeren',
  en: 'Import customers',
  fr: 'Importer des clients',
  es: 'Importar clientes',
);

const LocalizedText kCompanyCustomersLoading = LocalizedText(
  nl: 'Klanten laden…',
  en: 'Loading customers…',
  fr: 'Chargement des clients…',
  es: 'Cargando clientes…',
);

const LocalizedText kCompanyCustomersError = LocalizedText(
  nl: 'Klanten konden niet worden geladen.',
  en: 'Customers could not be loaded.',
  fr: 'Impossible de charger les clients.',
  es: 'No se pudieron cargar los clientes.',
);

const LocalizedText kCompanyCustomersWrongEnvironment = LocalizedText(
  nl: 'Klantenbeheer bestaat niet op deze aanmeldserver. Gebruik de lokale Worker (127.0.0.1:8788), niet productie.',
  en: 'Customer management is not on this sign-in server. Use the local Worker (127.0.0.1:8788), not production.',
  fr: 'La gestion des clients n’existe pas sur ce serveur. Utilisez le Worker local (127.0.0.1:8788), pas la production.',
  es: 'La gestión de clientes no está en este servidor. Usa el Worker local (127.0.0.1:8788), no producción.',
);

const LocalizedText kCompanyCustomersRouteMissing = LocalizedText(
  nl: 'Deze lokale Worker kent de klantenroute niet. Start de juiste debug-Worker en probeer opnieuw.',
  en: 'This local Worker does not expose the customers route. Start the correct debug Worker and try again.',
  fr: 'Ce Worker local n’expose pas la route clients. Démarrez le bon Worker de debug et réessayez.',
  es: 'Este Worker local no tiene la ruta de clientes. Arranca el Worker correcto e inténtalo de nuevo.',
);

const LocalizedText kCompanyCustomersUnauthorized = LocalizedText(
  nl: 'Geen geldige bedrijfssessie voor klanten. Meld het bedrijf opnieuw aan en probeer opnieuw.',
  en: 'No valid company session for customers. Sign the company in again and retry.',
  fr: 'Aucune session entreprise valide pour les clients. Reconnectez l’entreprise et réessayez.',
  es: 'No hay una sesión de empresa válida para clientes. Vuelve a entrar y reintenta.',
);

const LocalizedText kCompanyCustomersOffline = LocalizedText(
  nl: 'Geen verbinding. Controleer het netwerk en probeer opnieuw.',
  en: 'You are offline. Check the network and try again.',
  fr: 'Hors connexion. Vérifiez le réseau et réessayez.',
  es: 'Sin conexión. Comprueba la red e inténtalo de nuevo.',
);

const LocalizedText kCompanyCustomersRetry = LocalizedText(
  nl: 'Opnieuw proberen',
  en: 'Try again',
  fr: 'Réessayer',
  es: 'Intentar de nuevo',
);

const LocalizedText kCompanyCustomersLoadMore = LocalizedText(
  nl: 'Meer laden',
  en: 'Load more',
  fr: 'Charger plus',
  es: 'Cargar más',
);

const LocalizedText kCompanyCustomersSave = LocalizedText(
  nl: 'Opslaan',
  en: 'Save',
  fr: 'Enregistrer',
  es: 'Guardar',
);

const LocalizedText kCompanyCustomersEdit = LocalizedText(
  nl: 'Bewerken',
  en: 'Edit',
  fr: 'Modifier',
  es: 'Editar',
);

const LocalizedText kCompanyCustomersArchive = LocalizedText(
  nl: 'Archiveren',
  en: 'Archive',
  fr: 'Archiver',
  es: 'Archivar',
);

const LocalizedText kCompanyCustomersRestore = LocalizedText(
  nl: 'Herstellen',
  en: 'Restore',
  fr: 'Restaurer',
  es: 'Restaurar',
);

const LocalizedText kCompanyCustomersDisplayName = LocalizedText(
  nl: 'Weergavenaam',
  en: 'Display name',
  fr: 'Nom affiché',
  es: 'Nombre visible',
);

const LocalizedText kCompanyCustomersFirstName = LocalizedText(
  nl: 'Voornaam',
  en: 'First name',
  fr: 'Prénom',
  es: 'Nombre',
);

const LocalizedText kCompanyCustomersLastName = LocalizedText(
  nl: 'Achternaam',
  en: 'Last name',
  fr: 'Nom de famille',
  es: 'Apellidos',
);

const LocalizedText kCompanyCustomersEmail = LocalizedText(
  nl: 'E-mail',
  en: 'Email',
  fr: 'E-mail',
  es: 'Correo',
);

const LocalizedText kCompanyCustomersPhone = LocalizedText(
  nl: 'Telefoon',
  en: 'Phone',
  fr: 'Téléphone',
  es: 'Teléfono',
);

const LocalizedText kCompanyCustomersCallingCode = LocalizedText(
  nl: 'Landnummer',
  en: 'Country calling code',
  fr: 'Indicatif pays',
  es: 'Prefijo internacional',
);

const LocalizedText kCompanyCustomersLocale = LocalizedText(
  nl: 'Taal',
  en: 'Language',
  fr: 'Langue',
  es: 'Idioma',
);

const LocalizedText kCompanyCustomersCompanyName = LocalizedText(
  nl: 'Bedrijfsnaam',
  en: 'Company name',
  fr: 'Nom de l’entreprise',
  es: 'Nombre de empresa',
);

const LocalizedText kCompanyCustomersVat = LocalizedText(
  nl: 'Ondernemings-/btw-nummer',
  en: 'Company / VAT number',
  fr: 'N° d’entreprise / TVA',
  es: 'NIF / IVA',
);

const LocalizedText kCompanyCustomersInternalNotes = LocalizedText(
  nl: 'Interne notities (niet zichtbaar voor de klant)',
  en: 'Internal notes (not visible to the customer)',
  fr: 'Notes internes (non visibles pour le client)',
  es: 'Notas internas (no visibles para el cliente)',
);

const LocalizedText kCompanyCustomersAddresses = LocalizedText(
  nl: 'Adressen',
  en: 'Addresses',
  fr: 'Adresses',
  es: 'Direcciones',
);

const LocalizedText kCompanyCustomersAddAddress = LocalizedText(
  nl: 'Adres toevoegen',
  en: 'Add address',
  fr: 'Ajouter une adresse',
  es: 'Añadir dirección',
);

const LocalizedText kCompanyCustomersRequiredMark = LocalizedText(
  nl: 'Verplicht',
  en: 'Required',
  fr: 'Obligatoire',
  es: 'Obligatorio',
);

const LocalizedText kCompanyCustomersIdentityGroup = LocalizedText(
  nl: 'Naam',
  en: 'Name',
  fr: 'Nom',
  es: 'Nombre',
);

const LocalizedText kCompanyCustomersContactGroup = LocalizedText(
  nl: 'Contact',
  en: 'Contact',
  fr: 'Contact',
  es: 'Contacto',
);

const LocalizedText kCompanyCustomersCompanyGroup = LocalizedText(
  nl: 'Bedrijf',
  en: 'Company',
  fr: 'Entreprise',
  es: 'Empresa',
);

const LocalizedText kCompanyCustomersContactRequired = LocalizedText(
  nl: 'Vul een naam in en minstens e-mail of telefoon.',
  en: 'Enter a name and at least an email or phone number.',
  fr: 'Saisissez un nom et au moins un e-mail ou un téléphone.',
  es: 'Introduce un nombre y al menos un correo o teléfono.',
);

const LocalizedText kCompanyCustomersEmailOrPhoneHint = LocalizedText(
  nl: 'E-mail of telefoon is verplicht.',
  en: 'Email or phone is required.',
  fr: 'E-mail ou téléphone obligatoire.',
  es: 'Correo o teléfono obligatorio.',
);

const LocalizedText kCompanyCustomersInvalidEmail = LocalizedText(
  nl: 'Dit e-mailadres is ongeldig.',
  en: 'This email address is invalid.',
  fr: 'Cette adresse e-mail n’est pas valide.',
  es: 'Esta dirección de correo no es válida.',
);

const LocalizedText kCompanyCustomersInvalidPhone = LocalizedText(
  nl: 'Dit telefoonnummer is ongeldig.',
  en: 'This phone number is invalid.',
  fr: 'Ce numéro de téléphone n’est pas valide.',
  es: 'Este número de teléfono no es válido.',
);

const LocalizedText kCompanyCustomersSaveFailed = LocalizedText(
  nl: 'Opslaan is mislukt. Er is niets lokaal bewaard.',
  en: 'Save failed. Nothing was stored locally.',
  fr: 'Échec de l’enregistrement. Rien n’a été stocké localement.',
  es: 'Error al guardar. No se ha guardado nada en local.',
);

const LocalizedText kCompanyCustomersDuplicateWarning = LocalizedText(
  nl: 'Mogelijke dubbele klant in dit bedrijf. De nieuwe klant is toch bewaard.',
  en: 'Possible duplicate in this company. The new customer was still saved.',
  fr: 'Doublon possible dans cette entreprise. Le nouveau client a tout de même été enregistré.',
  es: 'Posible duplicado en esta empresa. El cliente nuevo se ha guardado igualmente.',
);

const LocalizedText kCompanyCustomersMissingScope = LocalizedText(
  nl: 'Geen geldige bedrijfscontext. Meld opnieuw aan.',
  en: 'No valid company context. Sign in again.',
  fr: 'Aucun contexte entreprise valide. Reconnectez-vous.',
  es: 'No hay un contexto de empresa válido. Vuelve a iniciar sesión.',
);

const LocalizedText kCompanyCustomersSelectHint = LocalizedText(
  nl: 'Selecteer een klant om de details te zien.',
  en: 'Select a customer to see the details.',
  fr: 'Sélectionnez un client pour voir les détails.',
  es: 'Selecciona un cliente para ver los detalles.',
);

String companyCustomersExceptionText(
  CompanyCustomerException error,
  AppLanguage language,
) {
  switch (error.code) {
    case 'missing_tenant_scope':
      return kCompanyCustomersMissingScope.of(language);
    case 'wrong_environment':
      return kCompanyCustomersWrongEnvironment.of(language);
    case 'route_missing':
      return kCompanyCustomersRouteMissing.of(language);
    case 'unauthorized':
      return kCompanyCustomersUnauthorized.of(language);
    default:
      return error.offline
          ? kCompanyCustomersOffline.of(language)
          : kCompanyCustomersError.of(language);
  }
}

const LocalizedText kCompanyCustomersNotFilled = LocalizedText(
  nl: 'Niet ingevuld',
  en: 'Not filled in',
  fr: 'Non renseigné',
  es: 'Sin rellenar',
);

const LocalizedText kCompanyCustomersNotesGroup = LocalizedText(
  nl: 'Notities',
  en: 'Notes',
  fr: 'Notes',
  es: 'Notas',
);

const LocalizedText kCompanyCustomersBookingsGroup = LocalizedText(
  nl: 'Boekingen',
  en: 'Bookings',
  fr: 'Réservations',
  es: 'Reservas',
);

const LocalizedText kCompanyCustomersNoQuotes = LocalizedText(
  nl: 'Nog geen offertes voor deze klant.',
  en: 'No quotes for this customer yet.',
  fr: 'Aucun devis pour ce client.',
  es: 'Aún no hay presupuestos para este cliente.',
);

const LocalizedText kCompanyCustomersQuotesError = LocalizedText(
  nl: 'Offertes konden niet worden geladen.',
  en: 'Quotes could not be loaded.',
  fr: 'Impossible de charger les devis.',
  es: 'No se pudieron cargar los presupuestos.',
);

const LocalizedText kCompanyCustomersNoBookings = LocalizedText(
  nl: 'Nog geen gekoppelde boeking via offerte of agenda.',
  en: 'No linked booking via quote or agenda yet.',
  fr: 'Aucune réservation liée via devis ou agenda.',
  es: 'Aún no hay reserva vinculada por presupuesto o agenda.',
);

const LocalizedText kCompanyCustomersContactPerson = LocalizedText(
  nl: 'Contactpersoon',
  en: 'Contact person',
  fr: 'Personne de contact',
  es: 'Persona de contacto',
);

const LocalizedText kCompanyCustomersAddressLine1 = LocalizedText(
  nl: 'Straat en nummer',
  en: 'Street and number',
  fr: 'Rue et numéro',
  es: 'Calle y número',
);

const LocalizedText kCompanyCustomersAddressStreet = LocalizedText(
  nl: 'Straat',
  en: 'Street',
  fr: 'Rue',
  es: 'Calle',
);

const LocalizedText kCompanyCustomersAddressNumber = LocalizedText(
  nl: 'Huisnummer',
  en: 'House number',
  fr: 'Numéro',
  es: 'Número',
);

const LocalizedText kCompanyCustomersAddressLine2 = LocalizedText(
  nl: 'Adresregel 2',
  en: 'Address line 2',
  fr: 'Complément d’adresse',
  es: 'Línea 2',
);

const LocalizedText kCompanyCustomersAddressCity = LocalizedText(
  nl: 'Plaats',
  en: 'City',
  fr: 'Ville',
  es: 'Ciudad',
);

const LocalizedText kCompanyCustomersAddressPostal = LocalizedText(
  nl: 'Postcode',
  en: 'Postal code',
  fr: 'Code postal',
  es: 'Código postal',
);

const LocalizedText kCompanyCustomersAddressCountry = LocalizedText(
  nl: 'Land',
  en: 'Country',
  fr: 'Pays',
  es: 'País',
);

const LocalizedText kCompanyCustomersAddressLabel = LocalizedText(
  nl: 'Adreslabel',
  en: 'Address label',
  fr: 'Libellé d’adresse',
  es: 'Etiqueta de dirección',
);

const LocalizedText kCompanyCustomersAddressNotes = LocalizedText(
  nl: 'Adresnotitie',
  en: 'Address note',
  fr: 'Note d’adresse',
  es: 'Nota de dirección',
);

const LocalizedText kCompanyCustomersAddressType = LocalizedText(
  nl: 'Adrestype',
  en: 'Address type',
  fr: 'Type d’adresse',
  es: 'Tipo de dirección',
);

String companyCustomerAddressTypeLabel(String type, AppLanguage language) {
  switch (type.trim().toLowerCase()) {
    case 'home':
      return LocalizedText(
        nl: 'Thuis',
        en: 'Home',
        fr: 'Domicile',
        es: 'Casa',
      ).of(language);
    case 'work':
      return LocalizedText(
        nl: 'Werk',
        en: 'Work',
        fr: 'Travail',
        es: 'Trabajo',
      ).of(language);
    case 'pickup':
      return LocalizedText(
        nl: 'Ophaaladres',
        en: 'Pickup',
        fr: 'Prise en charge',
        es: 'Recogida',
      ).of(language);
    case 'billing':
      return LocalizedText(
        nl: 'Facturatie',
        en: 'Billing',
        fr: 'Facturation',
        es: 'Facturación',
      ).of(language);
    default:
      return LocalizedText(
        nl: 'Overig',
        en: 'Other',
        fr: 'Autre',
        es: 'Otro',
      ).of(language);
  }
}

const LocalizedText kCompanyCustomersInvalidVat = LocalizedText(
  nl: 'Ondernemings- of btw-nummer is ongeldig.',
  en: 'The company or VAT number is invalid.',
  fr: 'Le numéro d’entreprise ou de TVA n’est pas valable.',
  es: 'El NIF o IVA no es válido.',
);

const LocalizedText kCompanyCustomersConflict = LocalizedText(
  nl: 'Deze klant is intussen gewijzigd. Herlaad en probeer opnieuw.',
  en: 'This customer changed in the meantime. Reload and try again.',
  fr: 'Ce client a été modifié entre-temps. Rechargez et réessayez.',
  es: 'Este cliente ha cambiado. Recarga e inténtalo de nuevo.',
);
