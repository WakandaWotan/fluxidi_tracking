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
  @override
  void initState() {
    super.initState();
    unawaited(loadBusinessThemePreference());
    unawaited(loadDriverThemePreference());
    unawaited(loadBusinessPublishedCustomerThemePreference());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        title: const Text('Thema\'s & uitstraling'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: 'A. Bedrijfsweergave',
            subtitle: 'Kies het thema voor business/admin schermen.',
            child: ValueListenableBuilder<BusinessThemeVariant>(
              valueListenable: businessThemeNotifier,
              builder: (context, current, _) {
                return DropdownButtonFormField<BusinessThemeVariant>(
                  value: current,
                  dropdownColor: const Color(0xFF111111),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF0B0B0B),
                  ),
                  items: BusinessThemeVariant.values
                      .map(
                        (variant) => DropdownMenuItem<BusinessThemeVariant>(
                          value: variant,
                          child: Text(_labelForBusiness(variant)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (next) {
                    if (next == null) return;
                    unawaited(saveBusinessThemePreference(next));
                  },
                );
              },
            ),
          ),
          _sectionCard(
            title: 'B. Chauffeursweergave',
            subtitle: 'Kies het thema voor chauffeur/driver schermen.',
            child: ValueListenableBuilder<DriverThemeVariant>(
              valueListenable: driverThemeNotifier,
              builder: (context, current, _) {
                return DropdownButtonFormField<DriverThemeVariant>(
                  value: current,
                  dropdownColor: const Color(0xFF111111),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF0B0B0B),
                  ),
                  items: DriverThemeVariant.values
                      .map(
                        (variant) => DropdownMenuItem<DriverThemeVariant>(
                          value: variant,
                          child: Text(_labelForDriver(variant)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (next) {
                    if (next == null) return;
                    unawaited(saveDriverThemePreference(next));
                  },
                );
              },
            ),
          ),
          _sectionCard(
            title: 'C. Klantweergave publiceren',
            subtitle:
                'Voorbereiding op publieke klantstijl. In deze fase alleen lokaal opgeslagen.',
            child: ValueListenableBuilder<CustomerThemeVariant>(
              valueListenable: businessPublishedCustomerThemeNotifier,
              builder: (context, current, _) {
                return DropdownButtonFormField<CustomerThemeVariant>(
                  value: current,
                  dropdownColor: const Color(0xFF111111),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF0B0B0B),
                  ),
                  items: CustomerThemeVariant.values
                      .map(
                        (variant) => DropdownMenuItem<CustomerThemeVariant>(
                          value: variant,
                          child: Text(_labelForCustomer(variant)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (next) {
                    if (next == null) return;
                    unawaited(
                      saveBusinessPublishedCustomerThemePreference(next),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Bedrijfsthema\'s komen hier.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
