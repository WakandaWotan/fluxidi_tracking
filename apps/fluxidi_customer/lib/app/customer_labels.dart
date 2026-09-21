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
    es: 'Viajes al aeropuerto',
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
}
