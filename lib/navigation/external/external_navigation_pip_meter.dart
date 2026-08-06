// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
//
// Compact high-contrast PiP meter card. Max four core values. No map / menus.

import 'package:flutter/material.dart';

import 'external_navigation_session.dart';

enum PipMeterKind { fixedPrice, liveTariff, toCustomer }

class ExternalNavPipMeterModel {
  const ExternalNavPipMeterModel({
    required this.kind,
    required this.title,
    required this.primaryValue,
    required this.primaryLabel,
    this.kmText,
    this.durationText,
    this.waitText,
  });

  final PipMeterKind kind;
  final String title;
  final String primaryValue;
  final String primaryLabel;
  final String? kmText;
  final String? durationText;
  final String? waitText;

  List<String> get secondaryLines {
    return <String>[
      if ((kmText ?? '').trim().isNotEmpty) kmText!.trim(),
      if ((durationText ?? '').trim().isNotEmpty) durationText!.trim(),
      if ((waitText ?? '').trim().isNotEmpty) waitText!.trim(),
    ].take(3).toList(growable: false);
  }
}

/// Pure builder for PiP meter values.
ExternalNavPipMeterModel buildExternalNavPipMeterModel({
  required ExternalNavPhase phase,
  required bool isStreetRide,
  required bool isFixedPrice,
  String? fixedPriceText,
  String? liveFareText,
  String? kmText,
  String? durationText,
  String? waitText,
  String? etaText,
  String? remainingDistanceText,
}) {
  if (phase == ExternalNavPhase.toPickup) {
    final primary = (etaText ?? remainingDistanceText ?? '—').trim();
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.toCustomer,
      title: 'Naar klant',
      primaryValue: primary.isEmpty ? '—' : primary,
      primaryLabel: etaText != null ? 'ETA' : 'Afstand',
      kmText: remainingDistanceText,
      durationText: durationText,
    );
  }
  if (isFixedPrice && !isStreetRide) {
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.fixedPrice,
      title: 'Vaste prijs',
      primaryValue: (fixedPriceText ?? '—').trim(),
      primaryLabel: 'Prijs',
      kmText: kmText,
      durationText: durationText,
      waitText: waitText,
    );
  }
  return ExternalNavPipMeterModel(
    kind: PipMeterKind.liveTariff,
    title: 'Tarief',
    primaryValue: (liveFareText ?? '—').trim(),
    primaryLabel: 'Actueel',
    kmText: kmText,
    durationText: durationText,
    waitText: waitText,
  );
}

class ExternalNavPipMeterCard extends StatelessWidget {
  const ExternalNavPipMeterCard({
    super.key,
    required this.model,
    this.onReturnToFluxidi,
    this.compact = true,
  });

  final ExternalNavPipMeterModel model;
  final VoidCallback? onReturnToFluxidi;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < 600;
    final titleSize = isPhone ? 14.0 : 16.0;
    final primarySize = isPhone ? 34.0 : 42.0;
    final secondarySize = isPhone ? 16.0 : 18.0;

    return Material(
      color: const Color(0xFF0B0F14),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 20,
            vertical: compact ? 8 : 16,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                model.title,
                style: TextStyle(
                  color: const Color(0xFFE8EEF5),
                  fontSize: titleSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                model.primaryValue,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFC107),
                  fontSize: primarySize,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              Text(
                model.primaryLabel,
                style: TextStyle(
                  color: const Color(0xFF9AA7B5),
                  fontSize: secondarySize * 0.85,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: model.secondaryLines
                    .map(
                      (line) => Text(
                        line,
                        style: TextStyle(
                          color: const Color(0xFFE8EEF5),
                          fontSize: secondarySize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              if (onReturnToFluxidi != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onReturnToFluxidi,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0B0F14),
                    backgroundColor: const Color(0xFFFFC107),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Terug naar Fluxidi'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
