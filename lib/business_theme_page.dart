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
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 12.2),
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
        border: Border.all(color: Colors.black.withOpacity(0.16)),
      ),
    );
  }

  Widget _selectableThemeTile({
    required String title,
    required String subtitle,
    required bool selected,
    required List<Color> swatches,
    required VoidCallback onTap,
  }) {
    final borderColor = selected
        ? const Color(0xFFE5B641)
        : const Color(0x33FFFFFF);
    final fill = selected ? const Color(0xFF1A1408) : const Color(0xFF121418);
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
                            ? const Color(0xFFFFE2A0)
                            : Colors.white.withOpacity(0.96),
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
                        color: Colors.white.withOpacity(0.66),
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
                color: selected ? const Color(0xFFE5B641) : Colors.white38,
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
                onTap: () {
                  unawaited(saveBusinessThemePreference(variant));
                  _showSavedSnack(
                    'Bedrijfsthema opgeslagen: ${_labelForBusiness(variant)}',
                  );
                },
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
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        title: const Text('Thema\'s & uitstraling'),
      ),
      body: FutureBuilder<void>(
        future: _loadPreferencesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _sectionCard(
                title: 'A. Bedrijfsweergave',
                subtitle: 'Kies het thema voor business/admin schermen.',
                child: _businessSection(),
              ),
              _sectionCard(
                title: 'B. Chauffeursweergave',
                subtitle: 'Kies het thema voor chauffeur/driver schermen.',
                child: _driverSection(),
              ),
              _sectionCard(
                title: 'C. Klantweergave publiceren',
                subtitle:
                    'Voorbereiding op publieke klantstijl. In deze fase alleen lokaal opgeslagen.',
                child: _publishedCustomerSection(),
              ),
            ],
          );
        },
      ),
    );
  }
}
