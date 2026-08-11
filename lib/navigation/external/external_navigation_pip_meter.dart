// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
// PIP-COMPACT-KPI-READABILITY-P1
// GOOGLE-MAPS-PIP-LIVE-METER-P0
// PIP-TABLET-READABILITY-LOCALE-P1
//
// Compact high-contrast PiP meter card. Max four core values. No map / menus.
// Tablet PiP uses denser padding and larger primary/metrics for SM-X400.
//
// PiP MUST observe the same [DriverRideMetersSnapshot] stream as Tellers/HUD —
// never a one-shot model baked at PiP enter. There is no second fare engine.
//
// Overlay copy follows the signed-in driver's Fluxidi app language (nl/en/fr/es).

import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart'
    show DriverRideMetersSnapshot;

import 'external_navigation_session.dart';

enum PipMeterKind { fixedPrice, liveTariff, toCustomer }

/// One labeled KPI cell. Value is always paired with [label] — never orphaned.
@immutable
class PipMeterMetric {
  const PipMeterMetric({
    required this.label,
    required this.value,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final String? semanticLabel;

  String get resolvedSemantics =>
      (semanticLabel ?? '$label $value').trim();
}

class ExternalNavPipMeterModel {
  const ExternalNavPipMeterModel({
    required this.kind,
    required this.title,
    required this.primaryValue,
    required this.primaryLabel,
    this.kmText,
    this.durationText,
    this.waitText,
    this.metrics = const <PipMeterMetric>[],
    this.language = AppLanguage.en,
  });

  final PipMeterKind kind;
  final String title;
  final String primaryValue;
  final String primaryLabel;
  final String? kmText;
  final String? durationText;
  final String? waitText;
  final List<PipMeterMetric> metrics;
  final AppLanguage language;

  /// Backward-compatible unlabeled secondary values (tests / legacy callers).
  List<String> get secondaryLines {
    if (metrics.isNotEmpty) {
      return metrics
          .map((m) => m.value.trim())
          .where((v) => v.isNotEmpty && v != '—')
          .take(3)
          .toList(growable: false);
    }
    return <String>[
      if ((kmText ?? '').trim().isNotEmpty) kmText!.trim(),
      if ((durationText ?? '').trim().isNotEmpty) durationText!.trim(),
      if ((waitText ?? '').trim().isNotEmpty) waitText!.trim(),
    ].take(3).toList(growable: false);
  }
}

/// Normalize a locale/language code for the driver-facing PiP overlay.
///
/// Precedence for callers: pass the explicit Fluxidi app language first.
/// Unsupported / empty codes fall back to English (never silent Dutch).
AppLanguage normalizePipMeterLanguageCode(String? code) {
  final raw = (code ?? '').trim().toLowerCase();
  if (raw.isEmpty) return AppLanguage.en;
  final primary = raw.split(RegExp(r'[_-]')).first;
  switch (primary) {
    case 'nl':
      return AppLanguage.nl;
    case 'en':
      return AppLanguage.en;
    case 'fr':
      return AppLanguage.fr;
    case 'es':
      return AppLanguage.es;
    default:
      return AppLanguage.en;
  }
}

/// Resolve PiP language: explicit app language → optional device code → EN.
AppLanguage resolvePipMeterLanguage({
  AppLanguage? appLanguage,
  String? deviceLocaleCode,
}) {
  if (appLanguage != null) {
    // de (and any future non-overlay language) → English for PiP chrome.
    if (appLanguage == AppLanguage.de) return AppLanguage.en;
    return appLanguage;
  }
  return normalizePipMeterLanguageCode(deviceLocaleCode);
}

String pipMeterUnknownValue() => '—';

String pipMeterDisplayValue(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return pipMeterUnknownValue();
  return t;
}

String pipMeterToPickupTitle(AppLanguage language) {
  return const LocalizedText(
    nl: 'Naar ophaalpunt',
    en: 'To pickup',
    fr: 'Vers le lieu de prise en charge',
    es: 'Hacia el punto de recogida',
  ).of(language);
}

String pipMeterToDestinationTitle(AppLanguage language) {
  return const LocalizedText(
    nl: 'Naar bestemming',
    en: 'To destination',
    fr: 'Vers la destination',
    es: 'Hacia el destino',
  ).of(language);
}

String pipMeterDistanceLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Afstand',
    en: 'Distance',
    fr: 'Distance',
    es: 'Distancia',
  ).of(language);
}

String pipMeterTimeLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Tijd',
    en: 'Time',
    fr: 'Temps',
    es: 'Tiempo',
  ).of(language);
}

String pipMeterEtaLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'ETA',
    en: 'ETA',
    fr: 'ETA',
    es: 'ETA',
  ).of(language);
}

String pipMeterPriceLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Prijs',
    en: 'Price',
    fr: 'Prix',
    es: 'Precio',
  ).of(language);
}

String pipMeterLiveLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Actueel',
    en: 'Current',
    fr: 'Actuel',
    es: 'Actual',
  ).of(language);
}

String pipMeterWaitingLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Wachttijd',
    en: 'Waiting',
    fr: 'Attente',
    es: 'Espera',
  ).of(language);
}

PipMeterMetric _metric({
  required String label,
  required String? value,
}) {
  final display = pipMeterDisplayValue(value);
  return PipMeterMetric(
    label: label,
    value: display,
    semanticLabel: '$label $display',
  );
}

/// Pure builder for PiP meter values.
ExternalNavPipMeterModel buildExternalNavPipMeterModel({
  required ExternalNavPhase phase,
  required bool isStreetRide,
  required bool isFixedPrice,
  AppLanguage? language,
  String? languageCode,
  String? fixedPriceText,
  String? liveFareText,
  String? kmText,
  String? durationText,
  String? waitText,
  String? etaText,
  String? remainingDistanceText,
}) {
  final lang = resolvePipMeterLanguage(
    appLanguage: language,
    deviceLocaleCode: languageCode,
  );
  final distanceLabel = pipMeterDistanceLabel(lang);
  final timeLabel = pipMeterTimeLabel(lang);
  final etaLabel = pipMeterEtaLabel(lang);
  final waitingLabel = pipMeterWaitingLabel(lang);

  if (phase == ExternalNavPhase.toPickup) {
    final eta = (etaText ?? '').trim();
    final remaining = (remainingDistanceText ?? '').trim();
    final useEta = eta.isNotEmpty;
    final primary = useEta
        ? eta
        : (remaining.isNotEmpty ? remaining : pipMeterUnknownValue());
    final metrics = <PipMeterMetric>[
      if (useEta && remaining.isNotEmpty)
        _metric(label: distanceLabel, value: remaining),
      if ((durationText ?? '').trim().isNotEmpty)
        _metric(label: timeLabel, value: durationText),
    ];
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.toCustomer,
      title: pipMeterToPickupTitle(lang),
      primaryValue: primary,
      primaryLabel: useEta ? etaLabel : distanceLabel,
      kmText: remaining.isEmpty ? null : remaining,
      durationText: durationText,
      metrics: metrics,
      language: lang,
    );
  }

  // Active passenger / return leg: label tracks destination B (or return).
  // Fare/fixed-price values stay authoritative — never swap in pickup KPIs.
  // Do NOT stuff ETA/remaining into the duration field (pairing bug).
  final remaining = (remainingDistanceText ?? '').trim();
  final distanceValue =
      remaining.isNotEmpty ? remaining : (kmText ?? '').trim();
  final metrics = <PipMeterMetric>[
    if (distanceValue.isNotEmpty)
      _metric(label: distanceLabel, value: distanceValue),
    if ((durationText ?? '').trim().isNotEmpty)
      _metric(label: timeLabel, value: durationText),
    if ((waitText ?? '').trim().isNotEmpty)
      _metric(label: waitingLabel, value: waitText),
  ];

  if (isFixedPrice && !isStreetRide) {
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.fixedPrice,
      title: pipMeterToDestinationTitle(lang),
      primaryValue: pipMeterDisplayValue(fixedPriceText),
      primaryLabel: pipMeterPriceLabel(lang),
      kmText: remaining.isNotEmpty ? remaining : kmText,
      durationText: durationText,
      waitText: waitText,
      metrics: metrics,
      language: lang,
    );
  }
  return ExternalNavPipMeterModel(
    kind: PipMeterKind.liveTariff,
    title: pipMeterToDestinationTitle(lang),
    primaryValue: pipMeterDisplayValue(liveFareText),
    primaryLabel: pipMeterLiveLabel(lang),
    kmText: remaining.isNotEmpty ? remaining : kmText,
    durationText: durationText,
    waitText: waitText,
    metrics: metrics,
    language: lang,
  );
}

/// Project the authoritative ride-meter snapshot into the compact PiP model.
///
/// GOOGLE-MAPS-PIP-LIVE-METER-P0: same numeric/text source as Tellers — no
/// duplicate GPS/fare calculation. Phase/street/fixed flags only choose which
/// snapshot fields are emphasised in the compact layout.
ExternalNavPipMeterModel buildExternalNavPipMeterModelFromRideMeters({
  required DriverRideMetersSnapshot snapshot,
  required ExternalNavPhase phase,
  required bool isStreetRide,
  required bool isFixedPrice,
  AppLanguage? language,
  String? languageCode,
  String? fixedPriceText,
}) {
  final remaining = snapshot.remainingDistanceText.trim();
  final eta = snapshot.etaText.trim();
  return buildExternalNavPipMeterModel(
    phase: phase,
    isStreetRide: isStreetRide,
    isFixedPrice: isFixedPrice,
    language: language,
    languageCode: languageCode,
    fixedPriceText: fixedPriceText,
    liveFareText: snapshot.fareText,
    kmText: snapshot.distanceTravelledText,
    durationText: snapshot.rideDurationText,
    waitText: snapshot.waitingTimeText,
    etaText: eta.isEmpty ? null : eta,
    remainingDistanceText: remaining.isEmpty ? null : remaining,
  );
}

/// PIP-COMPACT-KPI-READABILITY-P1 / PIP-TABLET-READABILITY-LOCALE-P1:
/// tablet denser layout + larger KPI; phone unchanged.
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
    required this.frameWidth,
    required this.isTablet,
  });

  final double titleSize;
  final double primarySize;
  final double metricSize;
  final double labelSize;
  final double horizontalPadding;
  final double verticalPadding;
  final double titleGap;
  final double metricsGap;
  final double frameWidth;
  final bool isTablet;

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
        frameWidth: 0,
        isTablet: false,
      );
    }
    // Tablet SM-X400 PiP: fill interior, larger KPI, thin accent frame.
    // Targets: title 24–30, labels 16–20, values 32–42; compact padding.
    return PipMeterTypography(
      titleSize: 26,
      primarySize: 40,
      metricSize: 36,
      labelSize: 18,
      horizontalPadding: compact ? 10 : 14,
      verticalPadding: compact ? 8 : 12,
      titleGap: 4,
      metricsGap: 6,
      frameWidth: 1.5,
      isTablet: true,
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
    final metrics = model.metrics;

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: typo.horizontalPadding,
        vertical: typo.verticalPadding,
      ),
      child: Column(
        mainAxisAlignment: typo.isTablet
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            model.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF9AA7B5),
              fontSize: typo.labelSize,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          SizedBox(height: typo.metricsGap),
          if (metrics.isNotEmpty)
            _PipMeterMetricsRow(
              metrics: metrics,
              typo: typo,
            )
          else
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
    );

    return Material(
      color: const Color(0xFF0B0F14),
      child: SafeArea(
        minimum: EdgeInsets.zero,
        child: typo.frameWidth > 0
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F14),
                  border: Border.all(
                    color: const Color(0xFF1E88E5),
                    width: typo.frameWidth,
                  ),
                ),
                child: content,
              )
            : content,
      ),
    );
  }
}

class _PipMeterMetricsRow extends StatelessWidget {
  const _PipMeterMetricsRow({
    required this.metrics,
    required this.typo,
  });

  final List<PipMeterMetric> metrics;
  final PipMeterTypography typo;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) SizedBox(width: typo.isTablet ? 8 : 12),
          Expanded(
            child: Semantics(
              label: metrics[i].resolvedSemantics,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    metrics[i].value,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFE8EEF5),
                      fontSize: typo.metricSize,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metrics[i].label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF9AA7B5),
                      fontSize: typo.labelSize,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
