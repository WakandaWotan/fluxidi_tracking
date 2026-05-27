part of '../main.dart';

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

    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07080C),
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: tr(
              nl: 'Vernieuwen',
              en: 'Refresh',
              fr: 'Actualiser',
              es: 'Actualizar',
            ),
            onPressed: onRefresh,
            icon: Icon(Icons.refresh, color: kFluxidiYellow.withOpacity(0.95)),
          ),
        ],
      ),
      body: SafeArea(
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
                  color: const Color(0xFF101113),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
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
                            style: const TextStyle(
                              color: Colors.white,
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
                              color: Colors.white.withOpacity(0.70),
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
                        foregroundColor: kFluxidiYellow.withOpacity(0.95),
                        side: BorderSide(
                          color: kFluxidiYellow.withOpacity(0.40),
                        ),
                        backgroundColor: const Color(0xFF15120A),
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
                      color: const Color(0xFF101113).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: kFluxidiYellow.withOpacity(0.30),
                      ),
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
    );
  }
}
