// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
// PIP-COMPACT-KPI-READABILITY-P1
//
// Compact high-contrast PiP meter card. Max four core values. No map / menus.
// Tablet PiP uses denser padding and larger primary/metrics for SM-X400.

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
      // NAVIGATION-SINGLE-ACTIVE-TARGET-TRUTH-P0-5
      title: 'Naar ophaalpunt',
      primaryValue: primary.isEmpty ? '—' : primary,
      primaryLabel: etaText != null ? 'ETA' : 'Afstand',
      kmText: remainingDistanceText,
      durationText: durationText,
    );
  }
  // Active passenger / return leg: label tracks destination B (or return).
  // Fare/fixed-price values stay authoritative — never swap in pickup KPIs.
  final remainingOrEta = (etaText ?? remainingDistanceText ?? '').trim();
  if (isFixedPrice && !isStreetRide) {
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.fixedPrice,
      title: 'Naar bestemming',
      primaryValue: (fixedPriceText ?? '—').trim(),
      primaryLabel: 'Prijs',
      kmText: remainingDistanceText ?? kmText,
      durationText: remainingOrEta.isNotEmpty ? remainingOrEta : durationText,
      waitText: waitText,
    );
  }
  return ExternalNavPipMeterModel(
    kind: PipMeterKind.liveTariff,
    title: 'Naar bestemming',
    primaryValue: (liveFareText ?? '—').trim(),
    primaryLabel: 'Actueel',
    kmText: remainingDistanceText ?? kmText,
    durationText: remainingOrEta.isNotEmpty ? remainingOrEta : durationText,
    waitText: waitText,
  );
}

/// PIP-COMPACT-KPI-READABILITY-P1: tablet denser layout; phone unchanged.
@immutable
class PipMeterTypography {
  const PipMeterTypography({
    required this.titleSize,
    required this.primarySize,
    required this.metricSize,
    required this.labelSize,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.titleGap,
    required this.metricsGap,
  });

  final double titleSize;
  final double primarySize;
  final double metricSize;
  final double labelSize;
  final double horizontalPadding;
  final double verticalPadding;
  final double titleGap;
  final double metricsGap;

  static PipMeterTypography forSize(Size size, {required bool compact}) {
    final isPhone = size.shortestSide < 600;
    if (isPhone) {
      return PipMeterTypography(
        titleSize: 14,
        primarySize: 34,
        metricSize: 16,
        labelSize: 13.6,
        horizontalPadding: compact ? 12 : 20,
        verticalPadding: compact ? 8 : 16,
        titleGap: 6,
        metricsGap: 10,
      );
    }
    // Tablet SM-X400 PiP: fill surface, larger KPI, thinner frame feel.
    return PipMeterTypography(
      titleSize: 20,
      primarySize: 44,
      metricSize: 24,
      labelSize: 16,
      horizontalPadding: compact ? 16 : 20,
      verticalPadding: compact ? 14 : 18,
      titleGap: 4,
      metricsGap: 8,
    );
  }
}

class ExternalNavPipMeterCard extends StatelessWidget {
  const ExternalNavPipMeterCard({
    super.key,
    required this.model,
    this.compact = true,
  });

  final ExternalNavPipMeterModel model;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final typo = PipMeterTypography.forSize(size, compact: compact);

    return Material(
      color: const Color(0xFF0B0F14),
      child: SafeArea(
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: typo.horizontalPadding,
            vertical: typo.verticalPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                model.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFE8EEF5),
                  fontSize: typo.titleSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: typo.titleGap),
              Text(
                model.primaryValue,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFFFC107),
                  fontSize: typo.primarySize,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              Text(
                model.primaryLabel,
                style: TextStyle(
                  color: const Color(0xFF9AA7B5),
                  fontSize: typo.labelSize,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              SizedBox(height: typo.metricsGap),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: model.secondaryLines
                    .map(
                      (line) => Text(
                        line,
                        style: TextStyle(
                          color: const Color(0xFFE8EEF5),
                          fontSize: typo.metricSize,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              // NAV-PIP-PLANNED-COMPLETION-EVIDENCE-FIX-P0:
              // Do not render a Flutter "Terug naar Fluxidi" button inside PiP.
              // Field evidence: the yellow TextButton never delivers taps /
              // MethodChannel events on Samsung PiP. Return is owned by the
              // Android system PiP RemoteAction / PendingIntent.
            ],
          ),
        ),
      ),
    );
  }
}
