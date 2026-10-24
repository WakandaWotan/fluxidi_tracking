import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company_driver_view_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme/driver_theme_selector.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

class BusinessThemePage extends StatefulWidget {
  const BusinessThemePage({super.key});

  @override
  State<BusinessThemePage> createState() => _BusinessThemePageState();
}

class _BusinessThemePageState extends State<BusinessThemePage> {
  late final Future<void> _loadPreferencesFuture;

  _BusinessThemePageVisuals _visualsForTheme(BusinessThemeVariant variant) {
    final palette = paletteForBusinessTheme(variant);
    final isClean = variant == BusinessThemeVariant.cleanProfessional;
    return _BusinessThemePageVisuals(
      palette: palette,
      pageBg: palette.background,
      sectionBg: palette.surface,
      sectionBorder: palette.border.withOpacity(isClean ? 0.92 : 0.58),
      titleColor: palette.textPrimary,
      subtitleColor: palette.textMuted.withOpacity(isClean ? 0.94 : 0.86),
      tileBg: isClean
          ? palette.surfaceAlt
          : palette.surfaceAlt.withOpacity(0.9),
      tileSelectedBg: palette.accent.withOpacity(isClean ? 0.11 : 0.16),
      tileBorder: palette.border.withOpacity(isClean ? 0.8 : 0.5),
      tileSelectedBorder: palette.accent.withOpacity(0.72),
      tileTitle: palette.textPrimary,
      tileSelectedTitle: isClean
          ? palette.textPrimary
          : palette.accent.withOpacity(0.98),
      tileSubtitle: palette.textMuted.withOpacity(isClean ? 0.9 : 0.82),
      selectedIcon: palette.accent,
      unselectedIcon: palette.textMuted.withOpacity(0.65),
      toneDotBorder: palette.border.withOpacity(isClean ? 0.74 : 0.58),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPreferencesFuture = _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    await Future.wait<void>([
      loadBusinessThemePreference(),
      loadBusinessHomeMobileLayoutPreference(),
      loadDriverHomeMobileLayoutPreference(),
      loadCompanyDriverViewThemePreference(),
    ]);
  }

  String _labelForBusiness(BusinessThemeVariant variant) {
    switch (variant) {
      case BusinessThemeVariant.executiveGold:
        return 'Executive Gold';
      case BusinessThemeVariant.corporateBlue:
        return 'Corporate Blue';
      case BusinessThemeVariant.cleanProfessional:
        return 'Clean Professional';
      case BusinessThemeVariant.emeraldIvory:
        return 'Emerald Ivory';
      case BusinessThemeVariant.fluxidiNeonRush:
        return 'Fluxidi Neon Rush';
      case BusinessThemeVariant.brandSignatureGold:
        return 'Brand Signature Gold';
    }
  }

  String _subtitleForBusiness(BusinessThemeVariant variant) {
    switch (variant) {
      case BusinessThemeVariant.emeraldIvory:
        return 'Luxury emerald, ivory and gold business look';
      case BusinessThemeVariant.fluxidiNeonRush:
        return 'Donker neon, premium taxi-energie';
      case BusinessThemeVariant.brandSignatureGold:
        return 'Brand Signature Gold';
      case BusinessThemeVariant.executiveGold:
      case BusinessThemeVariant.corporateBlue:
      case BusinessThemeVariant.cleanProfessional:
        return 'Business/admin weergave';
    }
  }

  String _labelForDriver(DriverThemeVariant variant) {
    switch (variant) {
      case DriverThemeVariant.nightGold:
        return 'Night Gold';
      case DriverThemeVariant.midnightBlue:
        return 'Midnight Blue';
      case DriverThemeVariant.highContrast:
        return 'Midday Gold';
      case DriverThemeVariant.lightEmerald:
        return 'Light Emerald';
      case DriverThemeVariant.customHuisstijl:
        return 'Brand Signature Gold';
    }
  }

  String _localized({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (appLanguageNotifier.value) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
        return nl;
      case AppLanguage.de:
        return en;
    }
  }

  String _labelForMobileLayout(BusinessHomeMobileLayout variant) {
    switch (variant) {
      case BusinessHomeMobileLayout.compact:
        return _localized(
          nl: 'Compact',
          en: 'Compact',
          fr: 'Compact',
          es: 'Compacto',
        );
      case BusinessHomeMobileLayout.visual:
        return _localized(
          nl: 'Visueel',
          en: 'Visual',
          fr: 'Visuel',
          es: 'Visual',
        );
    }
  }

  String _subtitleForMobileLayout(BusinessHomeMobileLayout variant) {
    switch (variant) {
      case BusinessHomeMobileLayout.compact:
        return _localized(
          nl: 'Standaard compacte tegels.',
          en: 'Standard compact tiles.',
          fr: 'Tuiles compactes standard.',
          es: 'Tarjetas compactas estándar.',
        );
      case BusinessHomeMobileLayout.visual:
        return _localized(
          nl: 'Brede actiekaarten met bedrijfsafbeeldingen.',
          en: 'Wide action cards with business images.',
          fr: 'Grandes cartes d’action avec images d’entreprise.',
          es: 'Tarjetas de acción amplias con imágenes de empresa.',
        );
    }
  }

  String _labelForDriverMobileLayout(DriverHomeMobileLayout variant) {
    switch (variant) {
      case DriverHomeMobileLayout.compact:
        return _localized(
          nl: 'Compact',
          en: 'Compact',
          fr: 'Compact',
          es: 'Compacto',
        );
      case DriverHomeMobileLayout.visual:
        return _localized(
          nl: 'Visueel',
          en: 'Visual',
          fr: 'Visuel',
          es: 'Visual',
        );
    }
  }

  String _subtitleForDriverMobileLayout(DriverHomeMobileLayout variant) {
    switch (variant) {
      case DriverHomeMobileLayout.compact:
        return _localized(
          nl: 'Standaard compacte chauffeur startpagina.',
          en: 'Standard compact driver home.',
          fr: 'Accueil chauffeur compact standard.',
          es: 'Inicio del conductor compacto estándar.',
        );
      case DriverHomeMobileLayout.visual:
        return _localized(
          nl: 'Brede actiekaarten met afbeeldingen voor de chauffeur.',
          en: 'Wide action cards with driver images.',
          fr: "Grandes cartes d'action avec images chauffeur.",
          es: 'Tarjetas de acción amplias con imágenes del conductor.',
        );
    }
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    required _BusinessThemePageVisuals visuals,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: visuals.sectionBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: visuals.sectionBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: visuals.titleColor,
              fontWeight: FontWeight.w800,
              fontSize: 14.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: visuals.subtitleColor, fontSize: 12.2),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  void _showSavedSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _toneDot(Color color) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: _activeVisuals.toneDotBorder),
      ),
    );
  }

  late _BusinessThemePageVisuals _activeVisuals;

  Widget _selectableThemeTile({
    Key? key,
    required String title,
    required String subtitle,
    required bool selected,
    required List<Color> swatches,
    required VoidCallback onTap,
    required _BusinessThemePageVisuals visuals,
  }) {
    final borderColor = selected
        ? visuals.tileSelectedBorder
        : visuals.tileBorder;
    final fill = selected ? visuals.tileSelectedBg : visuals.tileBg;
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.35 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected
                            ? visuals.tileSelectedTitle
                            : visuals.tileTitle,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visuals.tileSubtitle,
                        fontSize: 11.6,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        for (final color in swatches) ...[
                          _toneDot(color),
                          const SizedBox(width: 5),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_off,
                color: selected ? visuals.selectedIcon : visuals.unselectedIcon,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _businessSection() {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, current, _) {
        return Column(
          children: [
            for (final variant in BusinessThemeVariant.values) ...[
              _selectableThemeTile(
                title: _labelForBusiness(variant),
                subtitle: _subtitleForBusiness(variant),
                selected: variant == current,
                swatches: [
                  paletteForBusinessTheme(variant).background,
                  paletteForBusinessTheme(variant).surface,
                  paletteForBusinessTheme(variant).accent,
                ],
                onTap: () async {
                  await saveBusinessThemeAndAppearancePreset(variant);
                  _showSavedSnack(
                    'Bedrijfsthema opgeslagen: ${_labelForBusiness(variant)}',
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop(true);
                },
                visuals: _activeVisuals,
              ),
              if (variant != BusinessThemeVariant.values.last)
                const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _driverSection() {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: companyDriverViewThemeNotifier,
      builder: (context, current, _) {
        return Column(
          children: [
            for (final variant in kDriverThemeSelectorVariants) ...[
              _selectableThemeTile(
                key: driverThemeSelectorTileKey(variant),
                title: _labelForDriver(variant),
                subtitle: variant == DriverThemeVariant.customHuisstijl
                    ? 'Brand Signature Gold'
                    : 'Chauffeursweergave',
                selected: variant == current,
                swatches: [
                  paletteForDriverTheme(variant).background,
                  paletteForDriverTheme(variant).surface,
                  paletteForDriverTheme(variant).accent,
                ],
                onTap: () async {
                  await saveCompanyDriverViewThemePreference(variant);
                  if (!context.mounted) return;
                  _showSavedSnack(
                    'Chauffeursthema opgeslagen: ${_labelForDriver(variant)}',
                  );
                },
                visuals: _activeVisuals,
              ),
              if (variant != kDriverThemeSelectorVariants.last)
                const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _mobileLayoutSection() {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<BusinessHomeMobileLayout>(
          valueListenable: businessHomeMobileLayoutNotifier,
          builder: (context, current, ___) {
            final palette = _activeVisuals.palette;
            return Column(
              children: [
                for (final variant in BusinessHomeMobileLayout.values) ...[
                  _selectableThemeTile(
                    title: _labelForMobileLayout(variant),
                    subtitle: _subtitleForMobileLayout(variant),
                    selected: variant == current,
                    swatches: [
                      palette.background,
                      palette.surface,
                      palette.accent,
                    ],
                    onTap: () async {
                      await saveBusinessHomeMobileLayoutPreference(variant);
                      if (!context.mounted) return;
                      _showSavedSnack(
                        _localized(
                          nl: 'Mobiele dashboardweergave opgeslagen: ${_labelForMobileLayout(variant)}',
                          en: 'Mobile dashboard layout saved: ${_labelForMobileLayout(variant)}',
                          fr: 'Affichage mobile enregistré : ${_labelForMobileLayout(variant)}',
                          es: 'Vista móvil guardada: ${_labelForMobileLayout(variant)}',
                        ),
                      );
                    },
                    visuals: _activeVisuals,
                  ),
                  if (variant != BusinessHomeMobileLayout.values.last)
                    const SizedBox(height: 8),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _driverMobileLayoutSection() {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<DriverHomeMobileLayout>(
          valueListenable: driverHomeMobileLayoutNotifier,
          builder: (context, current, ___) {
            final palette = _activeVisuals.palette;
            return Column(
              children: [
                for (final variant in DriverHomeMobileLayout.values) ...[
                  _selectableThemeTile(
                    title: _labelForDriverMobileLayout(variant),
                    subtitle: _subtitleForDriverMobileLayout(variant),
                    selected: variant == current,
                    swatches: [
                      palette.background,
                      palette.surface,
                      palette.accent,
                    ],
                    onTap: () async {
                      await saveDriverHomeMobileLayoutPreference(variant);
                      if (!context.mounted) return;
                      _showSavedSnack(
                        _localized(
                          nl: 'Chauffeur startpagina opgeslagen: ${_labelForDriverMobileLayout(variant)}',
                          en: 'Driver home layout saved: ${_labelForDriverMobileLayout(variant)}',
                          fr: 'Accueil chauffeur enregistré : ${_labelForDriverMobileLayout(variant)}',
                          es: 'Inicio del conductor guardado: ${_labelForDriverMobileLayout(variant)}',
                        ),
                      );
                    },
                    visuals: _activeVisuals,
                  ),
                  if (variant != DriverHomeMobileLayout.values.last)
                    const SizedBox(height: 8),
                ],
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        _activeVisuals = _visualsForTheme(variant);
        return Scaffold(
          backgroundColor: _activeVisuals.pageBg,
          appBar: AppBar(
            backgroundColor: _activeVisuals.pageBg,
            foregroundColor: _activeVisuals.titleColor,
            title: const Text('Thema\'s & uitstraling'),
          ),
          body: FutureBuilder<void>(
            future: _loadPreferencesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _activeVisuals.selectedIcon,
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _sectionCard(
                    title: 'A. Bedrijfsweergave',
                    subtitle: 'Kies het thema voor business/admin schermen.',
                    child: _businessSection(),
                    visuals: _activeVisuals,
                  ),
                  _sectionCard(
                    title: 'B. Chauffeursweergave',
                    subtitle: 'Kies het thema voor chauffeur/driver schermen.',
                    child: _driverSection(),
                    visuals: _activeVisuals,
                  ),
                  ValueListenableBuilder<AppLanguage>(
                    valueListenable: appLanguageNotifier,
                    builder: (context, _, __) => _sectionCard(
                      title: _localized(
                        nl: 'C. Mobiele dashboardweergave',
                        en: 'C. Mobile dashboard layout',
                        fr: 'C. Affichage mobile du tableau de bord',
                        es: 'C. Vista móvil del panel',
                      ),
                      subtitle: _localized(
                        nl: 'Alleen telefoon staand. Tablet en telefoon liggend blijven ongewijzigd.',
                        en: 'Phone portrait only. Tablet and phone landscape stay unchanged.',
                        fr: 'Téléphone en mode portrait uniquement. Tablette et paysage inchangés.',
                        es: 'Solo teléfono en vertical. Tablet y horizontal sin cambios.',
                      ),
                      child: _mobileLayoutSection(),
                      visuals: _activeVisuals,
                    ),
                  ),
                  ValueListenableBuilder<AppLanguage>(
                    valueListenable: appLanguageNotifier,
                    builder: (context, _, __) => _sectionCard(
                      title: _localized(
                        nl: 'D. Chauffeur startpagina op gsm',
                        en: 'D. Driver home on phone',
                        fr: 'D. Accueil chauffeur sur mobile',
                        es: 'D. Inicio del conductor en móvil',
                      ),
                      subtitle: _localized(
                        nl: 'Alleen telefoon staand. Tablet en telefoon liggend blijven ongewijzigd.',
                        en: 'Phone portrait only. Tablet and phone landscape stay unchanged.',
                        fr: 'Téléphone en mode portrait uniquement. Tablette et paysage inchangés.',
                        es: 'Solo teléfono en vertical. Tablet y horizontal sin cambios.',
                      ),
                      child: _driverMobileLayoutSection(),
                      visuals: _activeVisuals,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _BusinessThemePageVisuals {
  const _BusinessThemePageVisuals({
    required this.palette,
    required this.pageBg,
    required this.sectionBg,
    required this.sectionBorder,
    required this.titleColor,
    required this.subtitleColor,
    required this.tileBg,
    required this.tileSelectedBg,
    required this.tileBorder,
    required this.tileSelectedBorder,
    required this.tileTitle,
    required this.tileSelectedTitle,
    required this.tileSubtitle,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.toneDotBorder,
  });

  final BusinessThemePalette palette;
  final Color pageBg;
  final Color sectionBg;
  final Color sectionBorder;
  final Color titleColor;
  final Color subtitleColor;
  final Color tileBg;
  final Color tileSelectedBg;
  final Color tileBorder;
  final Color tileSelectedBorder;
  final Color tileTitle;
  final Color tileSelectedTitle;
  final Color tileSubtitle;
  final Color selectedIcon;
  final Color unselectedIcon;
  final Color toneDotBorder;
}
