import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

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
      loadDriverThemePreference(),
      loadBusinessPublishedCustomerThemePreference(),
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
    }
  }

  String _labelForDriver(DriverThemeVariant variant) {
    switch (variant) {
      case DriverThemeVariant.nightGold:
        return 'Night Gold';
      case DriverThemeVariant.midnightBlue:
        return 'Midnight Blue';
      case DriverThemeVariant.highContrast:
        return 'High Contrast';
    }
  }

  String _labelForCustomer(CustomerThemeVariant variant) {
    switch (variant) {
      case CustomerThemeVariant.premiumLight:
        return 'Premium Light';
      case CustomerThemeVariant.nightGold:
        return 'Night Gold';
      case CustomerThemeVariant.ivoryGold:
        return 'Ivory Gold';
      case CustomerThemeVariant.champagneSand:
        return 'Champagne Sand';
      case CustomerThemeVariant.urbanSlate:
        return 'Urban Slate';
      case CustomerThemeVariant.midnightPlatinum:
        return 'Midnight Platinum';
      case CustomerThemeVariant.royalBlueGold:
        return 'Royal Blue Gold';
      case CustomerThemeVariant.emeraldGarden:
        return 'Emerald Garden';
      case CustomerThemeVariant.roseQuartz:
        return 'Rose Quartz';
      case CustomerThemeVariant.lavenderMist:
        return 'Lavender Mist';
      case CustomerThemeVariant.emeraldNoir:
        return 'Emerald Noir';
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
                subtitle: 'Business/admin weergave',
                selected: variant == current,
                swatches: [
                  paletteForBusinessTheme(variant).background,
                  paletteForBusinessTheme(variant).surface,
                  paletteForBusinessTheme(variant).accent,
                ],
                onTap: () async {
                  await saveBusinessThemePreference(variant);
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
      valueListenable: driverThemeNotifier,
      builder: (context, current, _) {
        return Column(
          children: [
            for (final variant in DriverThemeVariant.values) ...[
              _selectableThemeTile(
                title: _labelForDriver(variant),
                subtitle: 'Chauffeursweergave',
                selected: variant == current,
                swatches: [
                  paletteForDriverTheme(variant).background,
                  paletteForDriverTheme(variant).surface,
                  paletteForDriverTheme(variant).accent,
                ],
                onTap: () {
                  unawaited(saveDriverThemePreference(variant));
                  _showSavedSnack(
                    'Chauffeursthema opgeslagen: ${_labelForDriver(variant)}',
                  );
                },
                visuals: _activeVisuals,
              ),
              if (variant != DriverThemeVariant.values.last)
                const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _publishedCustomerSection() {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: businessPublishedCustomerThemeNotifier,
      builder: (context, current, _) {
        return Column(
          children: [
            for (final variant in CustomerThemeVariant.values) ...[
              _selectableThemeTile(
                title: _labelForCustomer(variant),
                subtitle:
                    'Lokale publiceer-voorkeur (backend nog uitgeschakeld)',
                selected: variant == current,
                swatches: [
                  paletteForCustomerTheme(variant).background,
                  paletteForCustomerTheme(variant).surface,
                  paletteForCustomerTheme(variant).gold,
                ],
                onTap: () {
                  unawaited(
                    saveBusinessPublishedCustomerThemePreference(variant),
                  );
                  _showSavedSnack(
                    'Klantthema-voorkeur opgeslagen: ${_labelForCustomer(variant)}',
                  );
                },
                visuals: _activeVisuals,
              ),
              if (variant != CustomerThemeVariant.values.last)
                const SizedBox(height: 8),
            ],
          ],
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
                  _sectionCard(
                    title: 'C. Klantweergave publiceren',
                    subtitle:
                        'Voorbereiding op publieke klantstijl. In deze fase alleen lokaal opgeslagen.',
                    child: _publishedCustomerSection(),
                    visuals: _activeVisuals,
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
