part of '../main.dart';

class _BookingsHubThemeTokens {
  const _BookingsHubThemeTokens({
    required this.background,
    required this.pageGradient,
    required this.surfaceGradient,
    required this.panelGradient,
    required this.surfaceBorder,
    required this.panelBorder,
    required this.primaryText,
    required this.mutedText,
    required this.accent,
  });

  final Color background;
  final Gradient pageGradient;
  final Gradient surfaceGradient;
  final Gradient panelGradient;
  final Color surfaceBorder;
  final Color panelBorder;
  final Color primaryText;
  final Color mutedText;
  final Color accent;
}

_BookingsHubThemeTokens _bookingsHubThemeForVariant(
  DriverThemeVariant variant,
) {
  if (variant == DriverThemeVariant.midnightBlue) {
    return const _BookingsHubThemeTokens(
      background: Color(0xFF060C17),
      pageGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF020711), Color(0xFF07111F), Color(0xFF0B1B33)],
      ),
      surfaceGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF102036), Color(0xFF0A1628)],
      ),
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F1D32), Color(0xFF091426)],
      ),
      surfaceBorder: Color(0x665A9DD9),
      panelBorder: Color(0x805AA7E8),
      primaryText: Color(0xFFEAF6FF),
      mutedText: Color(0xFFAFCBEA),
      accent: Color(0xFF4DA3FF),
    );
  }
  if (variant == DriverThemeVariant.highContrast) {
    return const _BookingsHubThemeTokens(
      background: Color(0xFF171108),
      pageGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF100B06), Color(0xFF17110A), Color(0xFF2C2113)],
      ),
      surfaceGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3B2B17), Color(0xFF22170C)],
      ),
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF402D16), Color(0xFF27190B)],
      ),
      surfaceBorder: Color(0x99E8C57E),
      panelBorder: Color(0x80FFDFA3),
      primaryText: Color(0xFFFFF0D0),
      mutedText: Color(0xFFE1CCA0),
      accent: Color(0xFFFFDFA3),
    );
  }
  return _BookingsHubThemeTokens(
    background: const Color(0xFF07080C),
    pageGradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF07080C), Color(0xFF0E0F12)],
    ),
    surfaceGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF141517), Color(0xFF0E0F12)],
    ),
    panelGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF121315), Color(0xFF0D0E11)],
    ),
    surfaceBorder: kFluxidiYellow.withOpacity(0.30),
    panelBorder: kFluxidiYellow.withOpacity(0.30),
    primaryText: Colors.white,
    mutedText: Colors.white.withOpacity(0.70),
    accent: kFluxidiYellow.withOpacity(0.95),
  );
}

class _BookingsHubPage extends StatelessWidget {
  final String title;
  final Widget Function(double screenH) buildList;
  final VoidCallback onRefresh;
  final ValueListenable<int> repaintListenable;

  const _BookingsHubPage({
    required this.title,
    required this.buildList,
    required this.onRefresh,
    required this.repaintListenable,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    String tr({
      required String nl,
      required String en,
      required String fr,
      required String es,
    }) {
      switch (appConfig.currentLanguage) {
        case AppLanguage.nl:
          return nl;
        case AppLanguage.en:
          return en;
        case AppLanguage.fr:
          return fr;
        case AppLanguage.es:
          return es;
      }
    }

    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: driverThemeNotifier,
      builder: (context, variant, _) {
        final theme = _bookingsHubThemeForVariant(variant);
        return Scaffold(
          backgroundColor: theme.background,
          appBar: AppBar(
            backgroundColor: theme.background,
            elevation: 0,
            foregroundColor: theme.primaryText,
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.primaryText,
              ),
            ),
            actions: [
              IconButton(
                tooltip: tr(
                  nl: 'Vernieuwen',
                  en: 'Refresh',
                  fr: 'Actualiser',
                  es: 'Actualizar',
                ),
                onPressed: onRefresh,
                icon: Icon(Icons.refresh, color: theme.accent),
              ),
            ],
          ),
          body: SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: theme.pageGradient),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: theme.surfaceGradient,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.surfaceBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(
                                    nl: 'Beschikbare ritten',
                                    en: 'Available rides',
                                    fr: 'Courses disponibles',
                                    es: 'Viajes disponibles',
                                  ),
                                  style: TextStyle(
                                    color: theme.primaryText,
                                    fontSize: 14.6,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr(
                                    nl: 'Overzicht van jouw beschikbare en recente ritten.',
                                    en: 'Overview of your available and recent rides.',
                                    fr: 'Aperçu de vos courses disponibles et récentes.',
                                    es: 'Resumen de tus viajes disponibles y recientes.',
                                  ),
                                  style: TextStyle(
                                    color: theme.mutedText,
                                    fontSize: 11.6,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.accent,
                              side: BorderSide(color: theme.panelBorder),
                              backgroundColor:
                                  (theme.panelGradient as LinearGradient)
                                      .colors
                                      .first,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh, size: 15),
                            label: Text(
                              tr(
                                nl: 'Vernieuw',
                                en: 'Refresh',
                                fr: 'Actualiser',
                                es: 'Actualizar',
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: theme.panelGradient,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: theme.panelBorder),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: ValueListenableBuilder<int>(
                            valueListenable: repaintListenable,
                            builder: (_, __, ___) => buildList(h),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
