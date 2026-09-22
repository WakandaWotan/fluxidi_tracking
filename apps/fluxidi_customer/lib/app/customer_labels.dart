import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

/// One label in the languages the customer app offers.
class CustomerLabel {
  const CustomerLabel({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
    required this.de,
  });

  final String nl;
  final String en;
  final String fr;
  final String es;
  final String de;

  String of(AppLanguage language) => switch (language) {
        AppLanguage.nl => nl,
        AppLanguage.en => en,
        AppLanguage.fr => fr,
        AppLanguage.es => es,
        AppLanguage.de => de,
      };

  /// Resolves against the language the app is currently running in.
  String get current => of(appConfig.currentLanguage);
}

/// Rebuilds customer chrome when the shared app language changes.
///
/// MaterialApp already follows [appLanguageNotifier], but existing routes do
/// not rebuild unless they listen. Screens that bake labels into const
/// children or only watch the theme would otherwise keep the previous
/// language.
class CustomerLanguageBuilder extends StatelessWidget {
  const CustomerLanguageBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppLanguage language) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) => builder(context, language),
    );
  }
}

abstract final class CustomerText {
  static const whereTo = CustomerLabel(
    nl: 'Waar wil je naartoe?',
    en: 'Where do you want to go?',
    fr: 'Où voulez-vous aller ?',
    es: '¿A dónde quieres ir?',
    de: 'Wohin möchten Sie?',
  );

  static const destinationHint = CustomerLabel(
    nl: 'Bestemming',
    en: 'Destination',
    fr: 'Destination',
    es: 'Destino',
    de: 'Ziel',
  );

  static const bookTaxi = CustomerLabel(
    nl: 'Boek een taxi',
    en: 'Book a taxi',
    fr: 'Réserver un taxi',
    es: 'Reservar un taxi',
    de: 'Taxi buchen',
  );

  static const services = CustomerLabel(
    nl: 'Onze diensten',
    en: 'Our services',
    fr: 'Nos services',
    es: 'Nuestros servicios',
    de: 'Unsere Leistungen',
  );

  static const airportRides = CustomerLabel(
    nl: 'Luchthavenritten',
    en: 'Airport rides',
    fr: 'Trajets aéroport',
    es: 'Traslados al aeropuerto',
    de: 'Flughafenfahrten',
  );

  static const hotelsAndBnb = CustomerLabel(
    nl: 'Hotels & B&B',
    en: 'Hotels & B&B',
    fr: 'Hôtels & B&B',
    es: 'Hoteles y B&B',
    de: 'Hotels & B&B',
  );

  static const events = CustomerLabel(
    nl: 'Evenementen',
    en: 'Events',
    fr: 'Événements',
    es: 'Eventos',
    de: 'Veranstaltungen',
  );

  static const limousine = CustomerLabel(
    nl: 'Limousine',
    en: 'Limousine',
    fr: 'Limousine',
    es: 'Limusina',
    de: 'Limousine',
  );

  static const regionRadar = CustomerLabel(
    nl: 'Regio Radar',
    en: 'Region Radar',
    fr: 'Radar régional',
    es: 'Radar de región',
    de: 'Regionsradar',
  );

  static const regionRadarSubtitle = CustomerLabel(
    nl: 'Laat weten waar je vervoer nodig hebt',
    en: 'Tell us where you need a ride',
    fr: 'Dites-nous où vous avez besoin d’un trajet',
    es: 'Dinos dónde necesitas un viaje',
    de: 'Sagen Sie uns, wo Sie eine Fahrt brauchen',
  );

  static const home = CustomerLabel(
    nl: 'Home',
    en: 'Home',
    fr: 'Accueil',
    es: 'Inicio',
    de: 'Start',
  );

  static const bookings = CustomerLabel(
    nl: 'Boekingen',
    en: 'Bookings',
    fr: 'Réservations',
    es: 'Reservas',
    de: 'Buchungen',
  );

  static const profile = CustomerLabel(
    nl: 'Profiel',
    en: 'Profile',
    fr: 'Profil',
    es: 'Perfil',
    de: 'Profil',
  );

  static const myDetails = CustomerLabel(
    nl: 'Mijn gegevens',
    en: 'My details',
    fr: 'Mes données',
    es: 'Mis datos',
    de: 'Meine Daten',
  );

  static const myBookings = CustomerLabel(
    nl: 'Mijn boekingen',
    en: 'My bookings',
    fr: 'Mes réservations',
    es: 'Mis reservas',
    de: 'Meine Buchungen',
  );

  static const language = CustomerLabel(
    nl: 'Taal',
    en: 'Language',
    fr: 'Langue',
    es: 'Idioma',
    de: 'Sprache',
  );

  static const chooseTheme = CustomerLabel(
    nl: 'Thema kiezen',
    en: 'Choose theme',
    fr: 'Choisir un thème',
    es: 'Elegir tema',
    de: 'Design wählen',
  );

  static const dataAndAccount = CustomerLabel(
    nl: 'Mijn gegevens & account verwijderen',
    en: 'My data & delete account',
    fr: 'Mes données et suppression du compte',
    es: 'Mis datos y eliminar cuenta',
    de: 'Meine Daten & Konto löschen',
  );

  static const signIn = CustomerLabel(
    nl: 'Aanmelden',
    en: 'Sign in',
    fr: 'Se connecter',
    es: 'Iniciar sesión',
    de: 'Anmelden',
  );

  static const signOut = CustomerLabel(
    nl: 'Afmelden',
    en: 'Sign out',
    fr: 'Se déconnecter',
    es: 'Cerrar sesión',
    de: 'Abmelden',
  );

  static const signedOutHint = CustomerLabel(
    nl: 'Meld je aan om je boekingen en gegevens te zien.',
    en: 'Sign in to see your bookings and details.',
    fr: 'Connectez-vous pour voir vos réservations et vos données.',
    es: 'Inicia sesión para ver tus reservas y datos.',
    de: 'Melden Sie sich an, um Buchungen und Daten zu sehen.',
  );

  static const unlockSwitchTitle = CustomerLabel(
    nl: 'Ontgrendel met dit toestel',
    en: 'Unlock with this device',
    fr: 'Déverrouiller avec cet appareil',
    es: 'Desbloquear con este dispositivo',
    de: 'Mit diesem Gerät entsperren',
  );

  static const unlockSwitchSubtitle = CustomerLabel(
    nl: 'Vingerafdruk, gezicht of de toestelcode',
    en: 'Fingerprint, face or the device code',
    fr: 'Empreinte, visage ou code de l’appareil',
    es: 'Huella, rostro o código del dispositivo',
    de: 'Fingerabdruck, Gesicht oder Gerätecode',
  );

  static const unlockOfferTitle = CustomerLabel(
    nl: 'Dit toestel gebruiken om te ontgrendelen?',
    en: 'Use this device to unlock?',
    fr: 'Utiliser cet appareil pour déverrouiller ?',
    es: '¿Usar este dispositivo para desbloquear?',
    de: 'Dieses Gerät zum Entsperren nutzen?',
  );

  static const unlockOfferBody = CustomerLabel(
    nl: 'Na het sluiten van de app vraag Fluxidi Klanten om je vingerafdruk, gezicht of toestelcode. Een verlopen of ingetrokken aanmelding wordt daarmee niet opnieuw geldig.',
    en: 'After you leave the app, Fluxidi Klanten will ask for your fingerprint, face or device code. That cannot make an expired or revoked sign-in valid again.',
    fr: 'Après avoir quitté l’app, Fluxidi Klanten demandera votre empreinte, votre visage ou le code de l’appareil. Cela ne rend pas une connexion expirée ou révoquée à nouveau valide.',
    es: 'Al salir de la app, Fluxidi Klanten pedirá tu huella, rostro o código del dispositivo. Eso no vuelve a validar un inicio de sesión caducado o revocado.',
    de: 'Nach dem Verlassen der App fragt Fluxidi Klanten nach Fingerabdruck, Gesicht oder Gerätecode. Eine abgelaufene oder widerrufene Anmeldung wird dadurch nicht wieder gültig.',
  );

  static const unlockOfferEnable = CustomerLabel(
    nl: 'Inschakelen',
    en: 'Turn on',
    fr: 'Activer',
    es: 'Activar',
    de: 'Aktivieren',
  );

  static const unlockOfferLater = CustomerLabel(
    nl: 'Nu niet',
    en: 'Not now',
    fr: 'Pas maintenant',
    es: 'Ahora no',
    de: 'Jetzt nicht',
  );

  static const unlockGateTitle = CustomerLabel(
    nl: 'Fluxidi Klanten is vergrendeld',
    en: 'Fluxidi Klanten is locked',
    fr: 'Fluxidi Klanten est verrouillé',
    es: 'Fluxidi Klanten está bloqueado',
    de: 'Fluxidi Klanten ist gesperrt',
  );

  static const unlockGateBody = CustomerLabel(
    nl: 'Gebruik de beveiliging van dit toestel om verder te gaan.',
    en: 'Use this device’s security to continue.',
    fr: 'Utilisez la sécurité de cet appareil pour continuer.',
    es: 'Usa la seguridad de este dispositivo para continuar.',
    de: 'Nutzen Sie die Gerätesicherheit, um fortzufahren.',
  );

  static const unlockRetry = CustomerLabel(
    nl: 'Ontgrendelen',
    en: 'Unlock',
    fr: 'Déverrouiller',
    es: 'Desbloquear',
    de: 'Entsperren',
  );

  static const unlockCanceled = CustomerLabel(
    nl: 'Ontgrendelen geannuleerd.',
    en: 'Unlock cancelled.',
    fr: 'Déverrouillage annulé.',
    es: 'Desbloqueo cancelado.',
    de: 'Entsperren abgebrochen.',
  );

  static const unlockFailed = CustomerLabel(
    nl: 'Ontgrendelen mislukt. Probeer opnieuw.',
    en: 'Unlock failed. Try again.',
    fr: 'Échec du déverrouillage. Réessayez.',
    es: 'Error al desbloquear. Inténtalo de nuevo.',
    de: 'Entsperren fehlgeschlagen. Erneut versuchen.',
  );

  static const unlockUnavailable = CustomerLabel(
    nl: 'Ontgrendelen is op dit toestel niet beschikbaar.',
    en: 'Unlock is not available on this device.',
    fr: 'Le déverrouillage n’est pas disponible sur cet appareil.',
    es: 'El desbloqueo no está disponible en este dispositivo.',
    de: 'Entsperren ist auf diesem Gerät nicht verfügbar.',
  );

  static const unlockReasonOpen = CustomerLabel(
    nl: 'Ontgrendel Fluxidi Klanten',
    en: 'Unlock Fluxidi Klanten',
    fr: 'Déverrouiller Fluxidi Klanten',
    es: 'Desbloquear Fluxidi Klanten',
    de: 'Fluxidi Klanten entsperren',
  );

  static const unlockReasonEnable = CustomerLabel(
    nl: 'Bevestig om ontgrendelen in te schakelen',
    en: 'Confirm to turn on unlock',
    fr: 'Confirmez pour activer le déverrouillage',
    es: 'Confirma para activar el desbloqueo',
    de: 'Bestätigen, um das Entsperren zu aktivieren',
  );

  static const unlockReasonDisable = CustomerLabel(
    nl: 'Bevestig om ontgrendelen uit te schakelen',
    en: 'Confirm to turn off unlock',
    fr: 'Confirmez pour désactiver le déverrouillage',
    es: 'Confirma para desactivar el desbloqueo',
    de: 'Bestätigen, um das Entsperren zu deaktivieren',
  );

  static const noDestinationYet = CustomerLabel(
    nl: 'Vul eerst een bestemming in.',
    en: 'Enter a destination first.',
    fr: 'Saisissez d’abord une destination.',
    es: 'Introduce primero un destino.',
    de: 'Geben Sie zuerst ein Ziel ein.',
  );

  static const searchingAddress = CustomerLabel(
    nl: 'Adressen zoeken…',
    en: 'Searching addresses…',
    fr: 'Recherche d’adresses…',
    es: 'Buscando direcciones…',
    de: 'Adressen werden gesucht…',
  );

  static const noAddressFound = CustomerLabel(
    nl: 'Geen adres gevonden. Vul straat, nummer en gemeente in.',
    en: 'No address found. Enter street, number and town.',
    fr: 'Aucune adresse trouvée. Indiquez rue, numéro et commune.',
    es: 'No se encontró la dirección. Indica calle, número y localidad.',
    de: 'Keine Adresse gefunden. Straße, Hausnummer und Ort angeben.',
  );

  static const noMapboxToken = CustomerLabel(
    nl: 'Adressuggesties zijn uit: deze build heeft geen MAPBOX_TOKEN.',
    en: 'Address suggestions are off: this build has no MAPBOX_TOKEN.',
    fr: 'Suggestions d’adresses désactivées : pas de MAPBOX_TOKEN.',
    es: 'Sugerencias de direcciones desactivadas: falta MAPBOX_TOKEN.',
    de: 'Adressvorschläge aus: dieser Build hat kein MAPBOX_TOKEN.',
  );

  static const companies = CustomerLabel(
    nl: 'Taxibedrijven',
    en: 'Taxi companies',
    fr: 'Sociétés de taxi',
    es: 'Empresas de taxi',
    de: 'Taxiunternehmen',
  );

  static const radarKicker = CustomerLabel(
    nl: 'REGIO RADAR',
    en: 'REGION RADAR',
    fr: 'RADAR RÉGIONAL',
    es: 'RADAR REGIONAL',
    de: 'REGION RADAR',
  );

  static const radarHeadline = CustomerLabel(
    nl: 'Help lokale taxi’s hun eigen omzet terug te winnen.',
    en: 'Help local taxis win back their own revenue.',
    fr: 'Aidez les taxis locaux à récupérer leur propre chiffre d’affaires.',
    es: 'Ayuda a los taxis locales a recuperar su propia facturación.',
    de: 'Helfen Sie lokalen Taxis, den eigenen Umsatz zurückzugewinnen.',
  );

  static const radarLead = CustomerLabel(
    nl: 'Laat weten dat je interesse hebt. Zo zien taxibedrijven waar er vraag is naar vervoer in hun werkgebied.',
    en: 'Show that you are interested. Taxi companies can then see where there is demand in their area.',
    fr: 'Montrez votre intérêt. Les taxis voient ainsi où il y a une demande de transport dans leur zone.',
    es: 'Muestra tu interés. Así las empresas de taxi ven dónde hay demanda de transporte en su zona.',
    de: 'Zeigen Sie Ihr Interesse. So sehen Taxibetriebe, wo in ihrem Gebiet Nachfrage besteht.',
  );

  static const radarTrustLocal = CustomerLabel(
    nl: 'Lokale bedrijven',
    en: 'Local companies',
    fr: 'Entreprises locales',
    es: 'Empresas locales',
    de: 'Lokale Betriebe',
  );

  static const radarTrustPrices = CustomerLabel(
    nl: 'Eigen prijzen',
    en: 'Their own prices',
    fr: 'Leurs propres tarifs',
    es: 'Sus propios precios',
    de: 'Eigene Preise',
  );

  static const radarTrustNoFee = CustomerLabel(
    nl: 'Geen ritcommissie',
    en: 'No ride commission',
    fr: 'Sans commission sur la course',
    es: 'Sin comisión por viaje',
    de: 'Keine Fahrtprovision',
  );

  static const radarSearchTitle = CustomerLabel(
    nl: 'Waar wil je een taxi kunnen boeken?',
    en: 'Where do you want to be able to book a taxi?',
    fr: 'Où voulez-vous pouvoir réserver un taxi ?',
    es: '¿Dónde quieres poder reservar un taxi?',
    de: 'Wo möchten Sie ein Taxi buchen können?',
  );

  static const radarSearchHint = CustomerLabel(
    nl: 'Kies je regio en laat je interesse zien.',
    en: 'Choose your region and show your interest.',
    fr: 'Choisissez votre région et montrez votre intérêt.',
    es: 'Elige tu región y muestra tu interés.',
    de: 'Wählen Sie Ihre Region und zeigen Sie Ihr Interesse.',
  );

  static const radarViewRegion = CustomerLabel(
    nl: 'Bekijk mijn regio',
    en: 'View my region',
    fr: 'Voir ma région',
    es: 'Ver mi región',
    de: 'Meine Region ansehen',
  );

  static const radarFormTitle = CustomerLabel(
    nl: 'Laat jouw regio meetellen',
    en: 'Let your region count',
    fr: 'Faites compter votre région',
    es: 'Haz que tu región cuente',
    de: 'Lassen Sie Ihre Region zählen',
  );

  static const radarFormHint = CustomerLabel(
    nl: 'Toon lokale taxibedrijven dat er ook in jouw buurt interesse is.',
    en: 'Show local taxi companies that there is interest near you too.',
    fr: 'Montrez aux taxis locaux qu’il y a aussi de l’intérêt près de chez vous.',
    es: 'Muestra a los taxis locales que también hay interés cerca de ti.',
    de: 'Zeigen Sie lokalen Taxibetrieben, dass es auch in Ihrer Nähe Interesse gibt.',
  );

  static const radarFirstName = CustomerLabel(
    nl: 'Voornaam',
    en: 'First name',
    fr: 'Prénom',
    es: 'Nombre',
    de: 'Vorname',
  );

  static const radarLastName = CustomerLabel(
    nl: 'Achternaam',
    en: 'Last name',
    fr: 'Nom',
    es: 'Apellidos',
    de: 'Nachname',
  );

  static const radarNameLabel = CustomerLabel(
    nl: 'Voornaam en achternaam',
    en: 'First and last name',
    fr: 'Prénom et nom',
    es: 'Nombre y apellidos',
    de: 'Vor- und Nachname',
  );

  static const radarEmailLabel = CustomerLabel(
    nl: 'E-mailadres',
    en: 'Email address',
    fr: 'Adresse e-mail',
    es: 'Correo electrónico',
    de: 'E-Mail-Adresse',
  );

  static const radarPhoneLabel = CustomerLabel(
    nl: 'Telefoon (optioneel)',
    en: 'Phone (optional)',
    fr: 'Téléphone (facultatif)',
    es: 'Teléfono (opcional)',
    de: 'Telefon (optional)',
  );

  static const radarCtaInterest = CustomerLabel(
    nl: 'Ja, ik heb interesse',
    en: 'Yes, I am interested',
    fr: 'Oui, cela m’intéresse',
    es: 'Sí, tengo interés',
    de: 'Ja, ich habe Interesse',
  );

  static const radarNoRide = CustomerLabel(
    nl: 'Je toont interesse. Je boekt nog geen rit.',
    en: 'You are showing interest. You are not booking a ride yet.',
    fr: 'Vous montrez votre intérêt. Vous ne réservez pas encore de course.',
    es: 'Muestras interés. Aún no reservas un viaje.',
    de: 'Sie zeigen Interesse. Sie buchen noch keine Fahrt.',
  );

  static const radarMapIdle = CustomerLabel(
    nl: 'Vul je postcode in om de interesse in jouw regio te bekijken.',
    en: 'Enter your postcode to see interest in your region.',
    fr: 'Saisissez votre code postal pour voir l’intérêt dans votre région.',
    es: 'Introduce tu código postal para ver el interés en tu región.',
    de: 'Geben Sie Ihre Postleitzahl ein, um das Interesse in Ihrer Region zu sehen.',
  );

  static const radarEmpty = CustomerLabel(
    nl: 'Nog geen regiogegevens voor deze postcode.',
    en: 'No region data for this postcode yet.',
    fr: 'Pas encore de données régionales pour ce code postal.',
    es: 'Todavía no hay datos regionales para este código postal.',
    de: 'Noch keine Regionsdaten für diese Postleitzahl.',
  );

  static const radarEmptyHint = CustomerLabel(
    nl: 'Schrijf je in zodat je interesse zichtbaar wordt.',
    en: 'Sign up so your interest becomes visible.',
    fr: 'Inscrivez-vous pour rendre votre intérêt visible.',
    es: 'Regístrate para que tu interés sea visible.',
    de: 'Melden Sie sich an, damit Ihr Interesse sichtbar wird.',
  );

  static const radarPostcodeNotFound = CustomerLabel(
    nl: 'Deze postcode werd niet gevonden in het gekozen land. De kaart toont geen andere regio.',
    en: 'This postcode was not found in the chosen country. The map does not show another region.',
    fr: 'Ce code postal n’a pas été trouvé dans le pays choisi. La carte n’affiche pas une autre région.',
    es: 'Este código postal no se encontró en el país elegido. El mapa no muestra otra región.',
    de: 'Diese Postleitzahl wurde im gewählten Land nicht gefunden. Die Karte zeigt keine andere Region.',
  );

  static const radarFail = CustomerLabel(
    nl: 'Radar ophalen mislukt.',
    en: 'Could not load the radar.',
    fr: 'Impossible de charger le radar.',
    es: 'No se pudo cargar el radar.',
    de: 'Radar konnte nicht geladen werden.',
  );

  static const radarSearching = CustomerLabel(
    nl: 'Regio opzoeken…',
    en: 'Looking up the region…',
    fr: 'Recherche de la région…',
    es: 'Buscando la región…',
    de: 'Region wird gesucht…',
  );

  static const radarCountLabel = CustomerLabel(
    nl: 'interesse in deze regio',
    en: 'interest in this region',
    fr: 'd’intérêt dans cette région',
    es: 'interés en esta región',
    de: 'Interesse in dieser Region',
  );

  static const radarRegionWord = CustomerLabel(
    nl: 'Regio',
    en: 'Region',
    fr: 'Région',
    es: 'Región',
    de: 'Region',
  );

  static const radarPartnersWanted = CustomerLabel(
    nl: 'taxibedrijven gezocht',
    en: 'partners wanted',
    fr: 'taxis recherchés',
    es: 'se buscan taxis',
    de: 'Partner gesucht',
  );

  static const radarNeedPostcode = CustomerLabel(
    nl: 'Vul een postcode in voor Regio Radar.',
    en: 'Enter a postcode for Region Radar.',
    fr: 'Saisissez un code postal pour le Radar régional.',
    es: 'Introduce un código postal para el Radar regional.',
    de: 'Geben Sie eine Postleitzahl für Region Radar ein.',
  );

  static const radarNeedFields = CustomerLabel(
    nl: 'Voornaam, achternaam, e-mail en postcode zijn verplicht.',
    en: 'First name, last name, email and postcode are required.',
    fr: 'Le prénom, le nom, l’e-mail et le code postal sont obligatoires.',
    es: 'Nombre, apellidos, correo y código postal son obligatorios.',
    de: 'Vorname, Nachname, E-Mail und Postleitzahl sind Pflicht.',
  );

  static const radarSaved = CustomerLabel(
    nl: 'Je regio-inschrijving is bewaard.',
    en: 'Your region signup is saved.',
    fr: 'Votre inscription régionale est enregistrée.',
    es: 'Tu registro regional está guardado.',
    de: 'Ihre Regionsanmeldung ist gespeichert.',
  );

  static const radarAlreadyRegistered = CustomerLabel(
    nl: 'Deze interesse stond al geregistreerd. Je hoeft niets opnieuw te versturen.',
    en: 'This interest was already registered. You do not need to send it again.',
    fr: 'Cet intérêt était déjà enregistré. Vous n’avez pas besoin de le renvoyer.',
    es: 'Este interés ya estaba registrado. No hace falta enviarlo de nuevo.',
    de: 'Dieses Interesse war bereits registriert. Sie müssen es nicht erneut senden.',
  );

  static const radarSubmitFailed = CustomerLabel(
    nl: 'Je interesse kon niet worden verstuurd. Probeer het later opnieuw.',
    en: 'Your interest could not be sent. Try again later.',
    fr: 'Votre intérêt n’a pas pu être envoyé. Réessayez plus tard.',
    es: 'No se pudo enviar tu interés. Inténtalo más tarde.',
    de: 'Ihr Interesse konnte nicht gesendet werden. Versuchen Sie es später erneut.',
  );

  static const radarSending = CustomerLabel(
    nl: 'Bezig…',
    en: 'Sending…',
    fr: 'Envoi…',
    es: 'Enviando…',
    de: 'Wird gesendet…',
  );

  static const radarCountryLabel = CustomerLabel(
    nl: 'Land',
    en: 'Country',
    fr: 'Pays',
    es: 'País',
    de: 'Land',
  );

  static const radarPostcodeLabel = CustomerLabel(
    nl: 'Postcode',
    en: 'Postcode',
    fr: 'Code postal',
    es: 'Código postal',
    de: 'Postleitzahl',
  );

  static const radarStep1Title = CustomerLabel(
    nl: 'Kies je regio',
    en: 'Choose your region',
    fr: 'Choisissez votre région',
    es: 'Elige tu región',
    de: 'Region wählen',
  );

  static const radarStep1Text = CustomerLabel(
    nl: 'Vul je postcode in en bekijk jouw regio.',
    en: 'Enter your postcode and view your region.',
    fr: 'Saisissez votre code postal et consultez votre région.',
    es: 'Introduce tu código postal y mira tu región.',
    de: 'Geben Sie Ihre Postleitzahl ein und sehen Sie Ihre Region.',
  );

  static const radarStep2Title = CustomerLabel(
    nl: 'Laat je interesse zien',
    en: 'Show your interest',
    fr: 'Montrez votre intérêt',
    es: 'Muestra tu interés',
    de: 'Interesse zeigen',
  );

  static const radarStep2Text = CustomerLabel(
    nl: 'Toon lokale bedrijven dat er vraag is.',
    en: 'Show local companies that there is demand.',
    fr: 'Montrez aux entreprises locales qu’il y a une demande.',
    es: 'Muestra a las empresas locales que hay demanda.',
    de: 'Zeigen Sie lokalen Betrieben, dass Nachfrage besteht.',
  );

  static const radarStep3Title = CustomerLabel(
    nl: 'Maak de vraag zichtbaar',
    en: 'Make the demand visible',
    fr: 'Rendez la demande visible',
    es: 'Haz visible la demanda',
    de: 'Die Nachfrage sichtbar machen',
  );

  static const radarStep3Text = CustomerLabel(
    nl: 'Zo wordt interesse in jouw regio zichtbaar.',
    en: 'This is how interest in your region becomes visible.',
    fr: 'Ainsi, l’intérêt pour votre région devient visible.',
    es: 'Así el interés en tu región se hace visible.',
    de: 'So wird Interesse in Ihrer Region sichtbar.',
  );

  static const radarMapMissing = CustomerLabel(
    nl: 'De kaart ontbreekt op dit toestel. De regio-inschrijving blijft beschikbaar.',
    en: 'The map is missing on this device. Region signup stays available.',
    fr: 'La carte est absente sur cet appareil. L’inscription régionale reste disponible.',
    es: 'El mapa no está disponible en este dispositivo. El registro regional sigue disponible.',
    de: 'Die Karte fehlt auf diesem Gerät. Die Regionsanmeldung bleibt verfügbar.',
  );

  static const radarMapCaption = CustomerLabel(
    nl: 'Interesse per regio · locaties bij benadering',
    en: 'Interest by region · approximate locations',
    fr: 'Intérêt par région · emplacements approximatifs',
    es: 'Interés por región · ubicaciones aproximadas',
    de: 'Interesse je Region · ungefähre Standorte',
  );

  static const radarYourInterest = CustomerLabel(
    nl: 'Jouw interesse',
    en: 'Your interest',
    fr: 'Votre intérêt',
    es: 'Tu interés',
    de: 'Ihr Interesse',
  );

  static const radarGroupInterest = CustomerLabel(
    nl: 'Geregistreerde interesse in deze regio',
    en: 'Registered interest in this region',
    fr: 'Intérêt enregistré dans cette région',
    es: 'Interés registrado en esta región',
    de: 'Registriertes Interesse in dieser Region',
  );

  static const radarSelectedRegion = CustomerLabel(
    nl: 'Geselecteerde regio',
    en: 'Selected region',
    fr: 'Région sélectionnée',
    es: 'Región seleccionada',
    de: 'Ausgewählte Region',
  );

  static const radarInterested = CustomerLabel(
    nl: 'geïnteresseerden',
    en: 'interested',
    fr: 'intéressés',
    es: 'interesados',
    de: 'Interessenten',
  );

  static const paymentReturnTitle = CustomerLabel(
    nl: 'Terug in de app',
    en: 'Back in the app',
    fr: 'De retour dans l’application',
    es: 'De vuelta en la app',
    de: 'Zurück in der App',
  );

  static const paymentReturnHeadline = CustomerLabel(
    nl: 'Je bent terug in de app',
    en: 'You are back in the app',
    fr: 'Vous êtes de retour dans l’application',
    es: 'Has vuelto a la aplicación',
    de: 'Sie sind wieder in der App',
  );

  static const paymentReturnBody = CustomerLabel(
    nl: 'Deze app heeft een terugkeerlink ontvangen op het eigen developmentscheme. Er is in deze fase geen betaling, boeking of status aan verbonden.',
    en: 'This app received a return link on its own development scheme. No payment, booking or status is attached at this stage.',
    fr: 'Cette application a reçu un lien de retour sur son propre schéma de développement. Aucun paiement, réservation ou statut n’y est lié à ce stade.',
    es: 'Esta aplicación ha recibido un enlace de retorno en su propio esquema de desarrollo. En esta fase no hay ningún pago, reserva ni estado asociado.',
    de: 'Diese App hat einen Rückkehrlink über das eigene Entwicklungsschema empfangen. In dieser Phase ist keine Zahlung, Buchung oder Status damit verbunden.',
  );

  static const paymentReturnWhyTitle = CustomerLabel(
    nl: 'Waarom hier geen status staat',
    en: 'Why no status is shown here',
    fr: 'Pourquoi aucun statut n’apparaît ici',
    es: 'Por qué no hay un estado aquí',
    de: 'Warum hier kein Status steht',
  );

  static const paymentReturnWhyBody = CustomerLabel(
    nl: 'Een terugkeerlink is geen betaalbewijs. Een betaalstatus mag later alleen van de server komen, nooit uit de link zelf.',
    en: 'A return link is not proof of payment. A payment status may later come only from the server, never from the link itself.',
    fr: 'Un lien de retour n’est pas une preuve de paiement. Un statut de paiement ne pourra plus tard venir que du serveur, jamais du lien lui-même.',
    es: 'Un enlace de retorno no es un comprobante de pago. El estado de un pago solo podrá venir más adelante del servidor, nunca del propio enlace.',
    de: 'Ein Rückkehrlink ist kein Zahlungsbeleg. Ein Zahlungsstatus darf später nur vom Server kommen, niemals aus dem Link selbst.',
  );

  static const paymentReturnClose = CustomerLabel(
    nl: 'Naar het startscherm',
    en: 'To the start screen',
    fr: 'Vers l’écran d’accueil',
    es: 'Ir a la pantalla de inicio',
    de: 'Zum Startbildschirm',
  );

  /// Every customer-chrome label. Used to assert no empty values per language.
  static const List<CustomerLabel> all = <CustomerLabel>[
    whereTo,
    destinationHint,
    bookTaxi,
    services,
    airportRides,
    hotelsAndBnb,
    events,
    limousine,
    regionRadar,
    regionRadarSubtitle,
    home,
    bookings,
    profile,
    myDetails,
    myBookings,
    language,
    chooseTheme,
    dataAndAccount,
    signIn,
    signOut,
    signedOutHint,
    unlockSwitchTitle,
    unlockSwitchSubtitle,
    unlockOfferTitle,
    unlockOfferBody,
    unlockOfferEnable,
    unlockOfferLater,
    unlockGateTitle,
    unlockGateBody,
    unlockRetry,
    unlockCanceled,
    unlockFailed,
    unlockUnavailable,
    unlockReasonOpen,
    unlockReasonEnable,
    unlockReasonDisable,
    noDestinationYet,
    searchingAddress,
    noAddressFound,
    noMapboxToken,
    companies,
    radarKicker,
    radarHeadline,
    radarLead,
    radarTrustLocal,
    radarTrustPrices,
    radarTrustNoFee,
    radarSearchTitle,
    radarSearchHint,
    radarViewRegion,
    radarFormTitle,
    radarFormHint,
    radarFirstName,
    radarLastName,
    radarNameLabel,
    radarEmailLabel,
    radarPhoneLabel,
    radarCtaInterest,
    radarNoRide,
    radarMapIdle,
    radarEmpty,
    radarEmptyHint,
    radarPostcodeNotFound,
    radarFail,
    radarSearching,
    radarCountLabel,
    radarRegionWord,
    radarPartnersWanted,
    radarNeedPostcode,
    radarNeedFields,
    radarSaved,
    radarAlreadyRegistered,
    radarSubmitFailed,
    radarSending,
    radarCountryLabel,
    radarPostcodeLabel,
    radarStep1Title,
    radarStep1Text,
    radarStep2Title,
    radarStep2Text,
    radarStep3Title,
    radarStep3Text,
    radarMapMissing,
    radarMapCaption,
    radarYourInterest,
    radarGroupInterest,
    radarSelectedRegion,
    radarInterested,
    paymentReturnTitle,
    paymentReturnHeadline,
    paymentReturnBody,
    paymentReturnWhyTitle,
    paymentReturnWhyBody,
    paymentReturnClose,
  ];
}

/// Website country list for Region Radar, with the same ISO2 codes the API uses.
String regionRadarCountryName(String code, AppLanguage language) {
  const names = <String, CustomerLabel>{
    'BE': CustomerLabel(
      nl: 'België',
      en: 'Belgium',
      fr: 'Belgique',
      es: 'Bélgica',
      de: 'Belgien',
    ),
    'NL': CustomerLabel(
      nl: 'Nederland',
      en: 'Netherlands',
      fr: 'Pays-Bas',
      es: 'Países Bajos',
      de: 'Niederlande',
    ),
    'FR': CustomerLabel(
      nl: 'Frankrijk',
      en: 'France',
      fr: 'France',
      es: 'Francia',
      de: 'Frankreich',
    ),
    'DE': CustomerLabel(
      nl: 'Duitsland',
      en: 'Germany',
      fr: 'Allemagne',
      es: 'Alemania',
      de: 'Deutschland',
    ),
    'LU': CustomerLabel(
      nl: 'Luxemburg',
      en: 'Luxembourg',
      fr: 'Luxembourg',
      es: 'Luxemburgo',
      de: 'Luxemburg',
    ),
    'GB': CustomerLabel(
      nl: 'Verenigd Koninkrijk',
      en: 'United Kingdom',
      fr: 'Royaume-Uni',
      es: 'Reino Unido',
      de: 'Vereinigtes Königreich',
    ),
    'ES': CustomerLabel(
      nl: 'Spanje',
      en: 'Spain',
      fr: 'Espagne',
      es: 'España',
      de: 'Spanien',
    ),
    'PT': CustomerLabel(
      nl: 'Portugal',
      en: 'Portugal',
      fr: 'Portugal',
      es: 'Portugal',
      de: 'Portugal',
    ),
    'IT': CustomerLabel(
      nl: 'Italië',
      en: 'Italy',
      fr: 'Italie',
      es: 'Italia',
      de: 'Italien',
    ),
    'AT': CustomerLabel(
      nl: 'Oostenrijk',
      en: 'Austria',
      fr: 'Autriche',
      es: 'Austria',
      de: 'Österreich',
    ),
    'IE': CustomerLabel(
      nl: 'Ierland',
      en: 'Ireland',
      fr: 'Irlande',
      es: 'Irlanda',
      de: 'Irland',
    ),
    'CH': CustomerLabel(
      nl: 'Zwitserland',
      en: 'Switzerland',
      fr: 'Suisse',
      es: 'Suiza',
      de: 'Schweiz',
    ),
    'DK': CustomerLabel(
      nl: 'Denemarken',
      en: 'Denmark',
      fr: 'Danemark',
      es: 'Dinamarca',
      de: 'Dänemark',
    ),
    'SE': CustomerLabel(
      nl: 'Zweden',
      en: 'Sweden',
      fr: 'Suède',
      es: 'Suecia',
      de: 'Schweden',
    ),
    'NO': CustomerLabel(
      nl: 'Noorwegen',
      en: 'Norway',
      fr: 'Norvège',
      es: 'Noruega',
      de: 'Norwegen',
    ),
    'FI': CustomerLabel(
      nl: 'Finland',
      en: 'Finland',
      fr: 'Finlande',
      es: 'Finlandia',
      de: 'Finnland',
    ),
    'PL': CustomerLabel(
      nl: 'Polen',
      en: 'Poland',
      fr: 'Pologne',
      es: 'Polonia',
      de: 'Polen',
    ),
    'CZ': CustomerLabel(
      nl: 'Tsjechië',
      en: 'Czechia',
      fr: 'Tchéquie',
      es: 'Chequia',
      de: 'Tschechien',
    ),
  };
  return names[code.toUpperCase()]?.of(language) ?? code.toUpperCase();
}

const List<String> kRegionRadarCountryCodes = <String>[
  'BE',
  'NL',
  'FR',
  'DE',
  'LU',
  'GB',
  'ES',
  'PT',
  'IT',
  'AT',
  'IE',
  'CH',
  'DK',
  'SE',
  'NO',
  'FI',
  'PL',
  'CZ',
];

