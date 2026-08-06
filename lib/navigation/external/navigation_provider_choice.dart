// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
//
// Explicit NAV provider choice. No persisted preference unless a dedicated
// settings contract already exists (it does not today).

import 'package:flutter/material.dart';

enum NavigationProviderChoice { fluxidi, googleMapsWithMeter }

Future<NavigationProviderChoice?> showNavigationProviderChoiceDialog(
  BuildContext context, {
  required String Function({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) tr,
}) {
  return showDialog<NavigationProviderChoice>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: Text(
          tr(
            nl: 'Navigatie kiezen',
            en: 'Choose navigation',
            fr: 'Choisir la navigation',
            es: 'Elegir navegación',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.navigation, color: Color(0xFF1E88E5)),
              title: Text(
                tr(
                  nl: 'Fluxidi-navigatie',
                  en: 'Fluxidi navigation',
                  fr: 'Navigation Fluxidi',
                  es: 'Navegación Fluxidi',
                ),
              ),
              subtitle: Text(
                tr(
                  nl: 'Ingebouwde begeleiding op de kaart',
                  en: 'Built-in guidance on the map',
                  fr: 'Guidage intégré sur la carte',
                  es: 'Guía integrada en el mapa',
                ),
              ),
              onTap: () =>
                  Navigator.of(ctx).pop(NavigationProviderChoice.fluxidi),
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.map, color: Color(0xFF34A853)),
              title: Text(
                tr(
                  nl: 'Google Maps + Fluxidi-teller',
                  en: 'Google Maps + Fluxidi meter',
                  fr: 'Google Maps + compteur Fluxidi',
                  es: 'Google Maps + contador Fluxidi',
                ),
              ),
              subtitle: Text(
                tr(
                  nl: 'Google Maps fullscreen met Fluxidi in beeld-in-beeld',
                  en: 'Google Maps fullscreen with Fluxidi picture-in-picture',
                  fr: 'Google Maps plein écran avec Fluxidi en PiP',
                  es: 'Google Maps a pantalla completa con Fluxidi en PiP',
                ),
              ),
              onTap: () => Navigator.of(ctx)
                  .pop(NavigationProviderChoice.googleMapsWithMeter),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              tr(
                nl: 'Annuleren',
                en: 'Cancel',
                fr: 'Annuler',
                es: 'Cancelar',
              ),
            ),
          ),
        ],
      );
    },
  );
}
