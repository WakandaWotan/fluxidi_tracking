// COMPANY-CUSTOMER-OPS-P0 — existing Business Home tiles and web fit.

import 'package:fluxidi_tracking/app_strings.dart';

enum CompanyDashboardTileWebFit { available, blocked }

class CompanyDashboardTileSpec {
  const CompanyDashboardTileSpec({
    required this.actionKey,
    required this.title,
    required this.subtitle,
    required this.webFit,
    this.blocker,
  });

  final String actionKey;
  final LocalizedText title;
  final LocalizedText subtitle;
  final CompanyDashboardTileWebFit webFit;
  final LocalizedText? blocker;
}

const LocalizedText kCompanyDashboardTitle = LocalizedText(
  nl: 'Bedrijfsdashboard',
  en: 'Company dashboard',
  fr: 'Tableau de bord entreprise',
  es: 'Panel de empresa',
);

const LocalizedText kCompanyDashboardSwitchCompany = LocalizedText(
  nl: 'Ander bedrijf',
  en: 'Switch company',
  fr: 'Changer d’entreprise',
  es: 'Cambiar de empresa',
);

const LocalizedText kCompanyDashboardSignOut = LocalizedText(
  nl: 'Uitloggen',
  en: 'Sign out',
  fr: 'Déconnexion',
  es: 'Cerrar sesión',
);

const LocalizedText kCompanyDashboardPickCompany = LocalizedText(
  nl: 'Kies een bedrijf',
  en: 'Choose a company',
  fr: 'Choisir une entreprise',
  es: 'Elige una empresa',
);

const List<CompanyDashboardTileSpec> kCompanyDashboardTiles =
    <CompanyDashboardTileSpec>[
      CompanyDashboardTileSpec(
        actionKey: 'settings',
        title: LocalizedText(
          nl: 'Instellingen',
          en: 'Settings',
          fr: 'Réglages',
          es: 'Ajustes',
        ),
        subtitle: LocalizedText(
          nl: 'Profiel & branding',
          en: 'Profile & branding',
          fr: 'Profil & branding',
          es: 'Perfil y marca',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Instellingen opent BusinessSettingsPage. Die pagina importeert dart:io, path_provider en lokale bestandskiezers en zit niet in de Flutter-webcompilatie. Er is geen lokale vervangingspagina.',
          en:
              'Settings opens BusinessSettingsPage. That page imports dart:io, path_provider and local file pickers and is not in the Flutter web compilation unit. There is no stand-in page.',
          fr:
              'Réglages ouvre BusinessSettingsPage. Cette page importe dart:io, path_provider et des sélecteurs de fichiers locaux et n’est pas compilée pour Flutter web. Il n’y a pas de page de remplacement.',
          es:
              'Ajustes abre BusinessSettingsPage. Esa página importa dart:io, path_provider y selectores de archivos locales y no entra en la compilación web de Flutter. No hay página sustituta.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'payments',
        title: LocalizedText(
          nl: 'Abonnement',
          en: 'Plan',
          fr: 'Abonnement',
          es: 'Plan',
        ),
        subtitle: LocalizedText(
          nl: 'Facturatie',
          en: 'Billing',
          fr: 'Facturation',
          es: 'Facturación',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Abonnement opent CompanySubscriptionBillingPage, een part of lib/main.dart met native facturatie- en sessieketens. Die bestemming compileert niet voor Flutter web. Er is geen lege facturatiepagina.',
          en:
              'Plan opens CompanySubscriptionBillingPage, a part of lib/main.dart with native billing and session chains. That destination does not compile for Flutter web. There is no empty billing page.',
          fr:
              'Abonnement ouvre CompanySubscriptionBillingPage, un part de lib/main.dart avec facturation et session natives. Cette destination ne compile pas pour Flutter web. Il n’y a pas de page de facturation vide.',
          es:
              'Plan abre CompanySubscriptionBillingPage, un part de lib/main.dart con facturación y sesión nativas. Ese destino no compila en Flutter web. No hay una página de facturación vacía.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'vehicles',
        title: LocalizedText(
          nl: 'Voertuigen',
          en: 'Vehicles',
          fr: 'Véhicules',
          es: 'Vehículos',
        ),
        subtitle: LocalizedText(
          nl: 'Wagenpark',
          en: 'Fleet',
          fr: 'Flotte',
          es: 'Flota',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Voertuigen opent VehicleManagementPage (dart:io, lokale fleetbestanden, native camera/bestanden). Die pagina zit niet in de webcompilatie.',
          en:
              'Vehicles opens VehicleManagementPage (dart:io, local fleet files, native camera/files). That page is not in the web compilation unit.',
          fr:
              'Véhicules ouvre VehicleManagementPage (dart:io, fichiers de flotte locaux, caméra/fichiers natifs). Cette page n’est pas compilée pour le web.',
          es:
              'Vehículos abre VehicleManagementPage (dart:io, archivos de flota locales, cámara/archivos nativos). Esa página no entra en la compilación web.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'chiron',
        title: LocalizedText(
          nl: 'Chiron',
          en: 'Chiron',
          fr: 'Chiron',
          es: 'Chiron',
        ),
        subtitle: LocalizedText(
          nl: 'Compliance',
          en: 'Compliance',
          fr: 'Conformité',
          es: 'Cumplimiento',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Chiron opent ChironComplianceDashboardPage met native bestanden, sessieherstel en compliance-ketens uit de volledige app. Niet webcompatibel in deze aansluiting.',
          en:
              'Chiron opens ChironComplianceDashboardPage with native files, session recovery and compliance chains from the full app. Not web-compatible in this integration.',
          fr:
              'Chiron ouvre ChironComplianceDashboardPage avec fichiers natifs, reprise de session et chaînes de conformité de l’application complète. Pas compatible web dans cette intégration.',
          es:
              'Chiron abre ChironComplianceDashboardPage con archivos nativos, recuperación de sesión y cadenas de cumplimiento de la app completa. No es compatible con web en esta integración.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'customers',
        title: LocalizedText(
          nl: 'Chauffeurs',
          en: 'Drivers',
          fr: 'Chauffeurs',
          es: 'Conductores',
        ),
        subtitle: LocalizedText(
          nl: 'Team',
          en: 'Team',
          fr: 'Équipe',
          es: 'Equipo',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Chauffeurs opent CompanyDriverManagementPage na een backend-bedrijfssessiecontrole. Die pagina en de hersteldialogen zitten in de native app-shell (main.dart / dart:io) en ontbreken in Flutter web.',
          en:
              'Drivers opens CompanyDriverManagementPage after a backend company-session check. That page and the recovery dialogs live in the native app shell (main.dart / dart:io) and are absent from Flutter web.',
          fr:
              'Chauffeurs ouvre CompanyDriverManagementPage après un contrôle de session entreprise. Cette page et les dialogues de reprise sont dans le shell natif (main.dart / dart:io) et absents de Flutter web.',
          es:
              'Conductores abre CompanyDriverManagementPage tras una comprobación de sesión de empresa. Esa página y los diálogos de recuperación están en el shell nativo (main.dart / dart:io) y no existen en Flutter web.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'drivers',
        title: LocalizedText(
          nl: 'Chauffeur weergave',
          en: 'Driver view',
          fr: 'Vue chauffeur',
          es: 'Vista de conductor',
        ),
        subtitle: LocalizedText(
          nl: 'Ga naar de bestaande chauffeurcockpit zonder uit te loggen.',
          en: 'Open the existing driver cockpit without signing out.',
          fr: 'Ouvrir le cockpit chauffeur existant sans se déconnecter.',
          es: 'Abre la cabina de conductor existente sin cerrar sesión.',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Chauffeur weergave opent de bestaande chauffeurcockpit (Mapbox, geolocator, dart:io). Die cockpit compileert niet voor Flutter web. Er is geen tweede cockpit.',
          en:
              'Driver view opens the existing driver cockpit (Mapbox, geolocator, dart:io). That cockpit does not compile for Flutter web. There is no second cockpit.',
          fr:
              'Vue chauffeur ouvre le cockpit chauffeur existant (Mapbox, geolocator, dart:io). Ce cockpit ne compile pas pour Flutter web. Il n’y a pas de second cockpit.',
          es:
              'Vista de conductor abre la cabina existente (Mapbox, geolocator, dart:io). Esa cabina no compila en Flutter web. No hay una segunda cabina.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'demand_radar',
        title: LocalizedText(
          nl: 'Vraagradar',
          en: 'Demand radar',
          fr: 'Radar demande',
          es: 'Radar demanda',
        ),
        subtitle: LocalizedText(
          nl: 'Klantvraag',
          en: 'Customer demand',
          fr: 'Demande clients',
          es: 'Demanda clientes',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Vraagradar opent BusinessRegionalDemandPage (kaart/native vraagdata, part of de app-shell). Niet beschikbaar in deze webcompilatie.',
          en:
              'Demand radar opens BusinessRegionalDemandPage (map/native demand data, part of the app shell). Not available in this web compilation unit.',
          fr:
              'Radar demande ouvre BusinessRegionalDemandPage (carte/données natives, part du shell). Indisponible dans cette compilation web.',
          es:
              'Radar de demanda abre BusinessRegionalDemandPage (mapa/datos nativos, part del shell). No está disponible en esta compilación web.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'booking_link',
        title: LocalizedText(
          nl: 'Deel boekingslink',
          en: 'Share booking link',
          fr: 'Partager le lien de réservation',
          es: 'Compartir enlace de reserva',
        ),
        subtitle: LocalizedText(
          nl: 'Link + QR',
          en: 'Link + QR',
          fr: 'Lien + QR',
          es: 'Enlace + QR',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Deel boekingslink gebruikt de native share-sheet, QR-weergave en de gepaarde publieke boekings-URL uit de volledige bedrijfssessie. Die keten is hier niet aangesloten; er is geen nep-QR.',
          en:
              'Share booking link uses the native share sheet, QR rendering and the paired public booking URL from the full company session. That chain is not wired here; there is no fake QR.',
          fr:
              'Partager le lien utilise la feuille de partage native, le QR et l’URL publique appariée de la session entreprise. Cette chaîne n’est pas branchée ici ; il n’y a pas de faux QR.',
          es:
              'Compartir enlace usa la hoja nativa, el QR y la URL pública emparejada de la sesión de empresa. Esa cadena no está cableada aquí; no hay un QR falso.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'planning',
        title: LocalizedText(
          nl: 'Boekingen',
          en: 'Bookings',
          fr: 'Réservations',
          es: 'Reservas',
        ),
        subtitle: LocalizedText(
          nl: 'Planning & opvolging',
          en: 'Planning & follow-up',
          fr: 'Planification & suivi',
          es: 'Planificación y seguimiento',
        ),
        webFit: CompanyDashboardTileWebFit.blocked,
        blocker: LocalizedText(
          nl:
              'Boekingen opent CompanyBookingsOverviewPage (part of lib/main.dart): planning, toewijzing, annuleren, credit en archief. Die pagina compileert niet voor Flutter web. Geaccepteerde offertes blijven zichtbaar via Klantenbeheer → Boeking bekijken (GET /bookings/:id). Dit is geen tweede planner.',
          en:
              'Bookings opens CompanyBookingsOverviewPage (part of lib/main.dart): planning, assignment, cancel, credit and archive. That page does not compile for Flutter web. Accepted quotes remain visible via Customer management → View booking (GET /bookings/:id). This is not a second planner.',
          fr:
              'Réservations ouvre CompanyBookingsOverviewPage (part de lib/main.dart) : planning, affectation, annulation, avoir et archive. Cette page ne compile pas pour Flutter web. Les devis acceptés restent visibles via Gestion des clients → Voir la réservation. Ce n’est pas un second planner.',
          es:
              'Reservas abre CompanyBookingsOverviewPage (part de lib/main.dart): planificación, asignación, cancelación, abono y archivo. Esa página no compila en Flutter web. Los presupuestos aceptados siguen visibles en Gestión de clientes → Ver reserva. No es una segunda agenda.',
        ),
      ),
      CompanyDashboardTileSpec(
        actionKey: 'ai_dispatch',
        title: LocalizedText(
          nl: 'Klantenbeheer',
          en: 'Customer management',
          fr: 'Gestion des clients',
          es: 'Gestión de clientes',
        ),
        subtitle: LocalizedText(
          nl: 'Bedrijfsklanten',
          en: 'Company customers',
          fr: 'Clients de l’entreprise',
          es: 'Clientes de la empresa',
        ),
        webFit: CompanyDashboardTileWebFit.available,
      ),
    ];
