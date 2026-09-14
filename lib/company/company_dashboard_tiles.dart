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
        webFit: CompanyDashboardTileWebFit.available,
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
        webFit: CompanyDashboardTileWebFit.available,
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
        webFit: CompanyDashboardTileWebFit.available,
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
              'Chiron is ChironComplianceDashboardPage in de volledige app-shell. Een browser kan die pagina niet compileren (native bestanden, sessieherstel). Op Flutter Windows-desktop hoort dezelfde pagina via main.dart te openen, niet een vervangend scherm.',
          en:
              'Chiron is ChironComplianceDashboardPage in the full app shell. A browser cannot compile that page (native files, session recovery). Flutter Windows desktop should open the same page through main.dart, not a replacement screen.',
          fr:
              'Chiron est ChironComplianceDashboardPage dans le shell complet. Un navigateur ne peut pas compiler cette page. Flutter Windows desktop doit ouvrir la même page via main.dart.',
          es:
              'Chiron es ChironComplianceDashboardPage en el shell completo. Un navegador no puede compilar esa página. Flutter Windows desktop debe abrir la misma página vía main.dart.',
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
        webFit: CompanyDashboardTileWebFit.available,
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
              'Chauffeur weergave is de bestaande rijcockpit (Mapbox, gps, dart:io). De browser kan die cockpit niet compileren. mapbox_maps_flutter heeft geen Windows-plugin; op Flutter Windows-desktop is de app-shell wel de route, maar de kaart zelf vereist nog een platformadapter.',
          en:
              'Driver view is the existing driving cockpit (Mapbox, GPS, dart:io). The browser cannot compile that cockpit. mapbox_maps_flutter has no Windows plugin; Flutter Windows desktop is still the app-shell route, but the map itself still needs a platform adapter.',
          fr:
              'Vue chauffeur est le cockpit existant (Mapbox, GPS, dart:io). Le navigateur ne le compile pas. mapbox_maps_flutter n’a pas de plugin Windows.',
          es:
              'Vista de conductor es la cabina existente (Mapbox, GPS, dart:io). El navegador no la compila. mapbox_maps_flutter no tiene plugin de Windows.',
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
              'Vraagradar is BusinessRegionalDemandPage in de app-shell (part of main.dart). Dat is een te onderzoeken compile-afhankelijkheid, geen productuitsluiting. De browser kan die unit niet laden; Flutter Windows-desktop via main.dart is de volledige route.',
          en:
              'Demand radar is BusinessRegionalDemandPage in the app shell (part of main.dart). That is a compile dependency to investigate, not a product exclusion. The browser cannot load that unit; Flutter Windows desktop through main.dart is the full route.',
          fr:
              'Radar demande est BusinessRegionalDemandPage (part de main.dart). Dépendance de compilation, pas une exclusion produit. Le navigateur ne charge pas cette unité.',
          es:
              'Radar de demanda es BusinessRegionalDemandPage (part de main.dart). Dependencia de compilación, no exclusión de producto. El navegador no carga esa unidad.',
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
        webFit: CompanyDashboardTileWebFit.available,
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
        webFit: CompanyDashboardTileWebFit.available,
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
