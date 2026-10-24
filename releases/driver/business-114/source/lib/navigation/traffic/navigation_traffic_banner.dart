import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../driver_theme_palette.dart';
import 'navigation_traffic_controller.dart';
import 'navigation_traffic_model.dart';

String navigationTrafficAlertText(
  NavigationTrafficAlert alert,
  String languageCode,
) {
  final language = languageCode.split(RegExp('[-_]')).first.toLowerCase();
  String localized(
    String nl,
    String en,
    String fr,
    String es,
    String de,
    String pt,
  ) => switch (language) {
    'nl' => nl,
    'fr' => fr,
    'es' => es,
    'de' => de,
    'pt' => pt,
    _ => en,
  };
  final title = switch (alert.event) {
    NavigationTrafficEvent.closure => localized(
      'Weg afgesloten',
      'Road closed',
      'Route fermée',
      'Carretera cerrada',
      'Straße gesperrt',
      'Estrada fechada',
    ),
    NavigationTrafficEvent.incident => localized(
      'Incident',
      'Incident',
      'Incident',
      'Incidente',
      'Vorfall',
      'Incidente',
    ),
    NavigationTrafficEvent.roadworks => localized(
      'Werken',
      'Roadworks',
      'Travaux',
      'Obras',
      'Baustelle',
      'Obras',
    ),
    NavigationTrafficEvent.congestion =>
      alert.traffic == NavigationTrafficClass.heavy ||
              alert.traffic == NavigationTrafficClass.severe
          ? localized(
              'File',
              'Traffic jam',
              'Bouchon',
              'Atasco',
              'Stau',
              'Trânsito lento',
            )
          : localized(
              'Druk verkeer',
              'Busy traffic',
              'Trafic dense',
              'Tráfico denso',
              'Dichter Verkehr',
              'Trânsito intenso',
            ),
  };
  final distance = alert.distanceMeters >= 1000
      ? '${(alert.distanceMeters / 1000).toStringAsFixed(1)} km'
      : '${(alert.distanceMeters / 100).round() * 100} m';
  final localizedDistance = language == 'en'
      ? distance
      : distance.replaceAll('.', ',');
  final parts = <String>[title];
  if (alert.distanceMeters >= 100) parts.add(localizedDistance);
  final delay = alert.delaySeconds;
  if (delay != null && delay >= 30) {
    final minutes = (delay / 60).round();
    parts.add('+$minutes min');
  }
  return parts.join(' · ');
}

class NavigationTrafficBannerHost extends StatelessWidget {
  const NavigationTrafficBannerHost({
    super.key,
    required this.alertListenable,
    required this.themeListenable,
    required this.languageCode,
    required this.child,
  });
  final ValueListenable<NavigationTrafficAlert?> alertListenable;
  final ValueListenable<DriverThemeVariant> themeListenable;
  final String languageCode;
  final Widget child;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<NavigationTrafficAlert?>(
    valueListenable: alertListenable,
    child: child,
    builder: (context, alert, child) {
      // Identical maneuver widget/layout when no current trustworthy traffic.
      if (alert == null) return child!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child!,
          const SizedBox(height: 3),
          NavigationTrafficBanner(
            alert: alert,
            themeListenable: themeListenable,
            languageCode: languageCode,
          ),
        ],
      );
    },
  );
}

class NavigationTrafficBanner extends StatelessWidget {
  const NavigationTrafficBanner({
    super.key,
    required this.alert,
    required this.themeListenable,
    required this.languageCode,
  });
  final NavigationTrafficAlert alert;
  final ValueListenable<DriverThemeVariant> themeListenable;
  final String languageCode;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DriverThemeVariant>(
        valueListenable: themeListenable,
        builder: (context, variant, _) {
          final palette = paletteForDriverTheme(variant);
          final text = navigationTrafficAlertText(alert, languageCode);
          final icon = switch (alert.event) {
            NavigationTrafficEvent.closure => Icons.block,
            NavigationTrafficEvent.roadworks => Icons.construction,
            NavigationTrafficEvent.incident => Icons.warning_amber_rounded,
            NavigationTrafficEvent.congestion => Icons.traffic_outlined,
          };
          return Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: IntrinsicWidth(
                child: Semantics(
                  label: text,
                  container: true,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      key: const Key('navigation-traffic-pill'),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              color: Color(
                                navigationTrafficColor(alert.traffic),
                              ),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                text,
                                softWrap: true,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
