// FLUXIDI-PIP-METER-EXTERNAL-NAV-1
// PIP-COMPACT-KPI-READABILITY-P1
// GOOGLE-MAPS-PIP-LIVE-METER-P0
// PIP-TABLET-READABILITY-LOCALE-P1
// PIP-TABLET-KPI-DENSITY-P1
// PIP-TABLET-FORM-FACTOR-STABLE-P1
//
// Compact high-contrast PiP meter card. No map / menus.
// Tablet PiP uses a passenger-facing taxi-meter layout that fills the card.
// Phone PiP keeps the prior compact primary+secondary presentation.
//
// CRITICAL (field SM-X400): never classify tablet vs phone from the PiP
// *window* size. Entering PiP shrinks MediaQuery from sw~880dp to a small
// 16:9 surface (often shortestSide << 600). That falsely flipped the card
// onto the phone body after the first frame(s). Host form-factor must come
// from the device/display (or a latched pre-PiP flag).
//
// PiP MUST observe the same [DriverRideMetersSnapshot] stream as Tellers/HUD —
// never a one-shot model baked at PiP enter. There is no second fare engine.
//
// Overlay copy follows the signed-in driver's Fluxidi app language (nl/en/fr/es).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart'
    show DriverRideMetersSnapshot;

import 'external_navigation_session.dart';

enum PipMeterKind { fixedPrice, liveTariff, toCustomer }

/// Logical shortest-side threshold for tablet PiP chrome (device class).
const double kPipMeterTabletShortestSide = 600;

/// Device/display logical size — independent of the current PiP window bounds.
///
/// Field sequence on SM-X400:
/// 1) fullscreen MediaQuery ≈ sw880dp → tablet body
/// 2) PiP window MediaQuery ≈ 200–400dp shortestSide → would falsely select phone
/// Using [FlutterView.display] keeps the host form-factor stable across that
/// transition.
Size pipMeterDeviceLogicalSizeOf(BuildContext context) {
  final view = View.of(context);
  final dpr = view.devicePixelRatio;
  if (!dpr.isFinite || dpr <= 0) {
    return MediaQuery.sizeOf(context);
  }
  final physical = view.display.size;
  if (!physical.width.isFinite ||
      !physical.height.isFinite ||
      physical.width <= 0 ||
      physical.height <= 0) {
    return MediaQuery.sizeOf(context);
  }
  return Size(physical.width / dpr, physical.height / dpr);
}

/// Resolve whether the PiP host device is a tablet.
///
/// Precedence:
/// 1. explicit latched pre-PiP flag (session / launch-time)
/// 2. device/display shortestSide
/// 3. never the transient PiP window size alone
bool resolvePipMeterHostIsTablet({
  bool? latchedHostIsTablet,
  Size? deviceSize,
  Size? windowSize,
}) {
  if (latchedHostIsTablet != null) return latchedHostIsTablet;
  if (deviceSize != null) {
    return deviceSize.shortestSide >= kPipMeterTabletShortestSide;
  }
  // Last-resort fallback for pure unit tests without a view/display.
  if (windowSize != null) {
    return windowSize.shortestSide >= kPipMeterTabletShortestSide;
  }
  return false;
}

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
    this.primaryMetrics = const <PipMeterMetric>[],
    this.secondaryMetrics = const <PipMeterMetric>[],
    this.language = AppLanguage.en,
  });

  final PipMeterKind kind;
  final String title;
  final String primaryValue;
  final String primaryLabel;
  final String? kmText;
  final String? durationText;
  final String? waitText;

  /// Legacy flat metrics list (phone / older tests). Prefer [primaryMetrics] /
  /// [secondaryMetrics] for the tablet taxi-meter layout.
  final List<PipMeterMetric> metrics;

  /// Tablet primary row: Distance | Time (label above large value).
  final List<PipMeterMetric> primaryMetrics;

  /// Tablet secondary row: Current | Fare | Ride duration.
  final List<PipMeterMetric> secondaryMetrics;
  final AppLanguage language;

  /// Backward-compatible unlabeled secondary values (tests / legacy callers).
  List<String> get secondaryLines {
    final source = secondaryMetrics.isNotEmpty
        ? secondaryMetrics
        : (metrics.isNotEmpty ? metrics : const <PipMeterMetric>[]);
    if (source.isNotEmpty) {
      return source
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

/// Format authoritative GPS speed for the PiP secondary "Current" KPI.
/// Does not invent speed — unknown / non-finite values become an em dash.
String formatPipMeterSpeedKmh(double? speedKmh, AppLanguage language) {
  if (speedKmh == null || !speedKmh.isFinite || speedKmh < 0) {
    return pipMeterUnknownValue();
  }
  final n = speedKmh.round();
  final unit = language == AppLanguage.nl ? 'km/u' : 'km/h';
  return '$n $unit';
}

String pipMeterToPickupTitle(AppLanguage language) {
  return const LocalizedText(
    nl: 'Naar ophaalpunt',
    en: 'To pickup point',
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
    en: 'Fare',
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

String pipMeterRideDurationLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Ritduur',
    en: 'Ride time',
    fr: 'Durée',
    es: 'Duración',
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
  String? speedText,
}) {
  final lang = resolvePipMeterLanguage(
    appLanguage: language,
    deviceLocaleCode: languageCode,
  );
  final distanceLabel = pipMeterDistanceLabel(lang);
  final timeLabel = pipMeterTimeLabel(lang);
  final fareLabel = pipMeterPriceLabel(lang);
  final currentLabel = pipMeterLiveLabel(lang);
  final rideDurationLabel = pipMeterRideDurationLabel(lang);

  final remaining = (remainingDistanceText ?? '').trim();
  final travelled = (kmText ?? '').trim();
  final eta = (etaText ?? '').trim();
  final duration = (durationText ?? '').trim();
  final fare = isFixedPrice && !isStreetRide
      ? (fixedPriceText ?? '').trim()
      : (liveFareText ?? '').trim();
  final speed = (speedText ?? '').trim();

  // Primary Distance = remaining when known, else travelled (never a time).
  final distanceValue = remaining.isNotEmpty ? remaining : travelled;
  // Primary Time = ETA/time-to-point only (never ride duration / distance).
  final timeValue = eta;

  final primaryMetrics = <PipMeterMetric>[
    _metric(label: distanceLabel, value: distanceValue),
    _metric(label: timeLabel, value: timeValue),
  ];

  final secondaryMetrics = <PipMeterMetric>[
    _metric(label: currentLabel, value: speed),
    _metric(label: fareLabel, value: fare),
    _metric(label: rideDurationLabel, value: duration),
  ];

  if (phase == ExternalNavPhase.toPickup) {
    final useEta = eta.isNotEmpty;
    final phonePrimary = useEta
        ? eta
        : (remaining.isNotEmpty ? remaining : pipMeterUnknownValue());
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.toCustomer,
      title: pipMeterToPickupTitle(lang),
      // Phone compact primary: ETA or remaining distance.
      primaryValue: phonePrimary,
      primaryLabel: useEta ? pipMeterEtaLabel(lang) : distanceLabel,
      kmText: remaining.isEmpty ? null : remaining,
      durationText: durationText,
      metrics: secondaryMetrics,
      primaryMetrics: primaryMetrics,
      secondaryMetrics: secondaryMetrics,
      language: lang,
    );
  }

  // Active passenger / return leg.
  if (isFixedPrice && !isStreetRide) {
    return ExternalNavPipMeterModel(
      kind: PipMeterKind.fixedPrice,
      title: pipMeterToDestinationTitle(lang),
      primaryValue: pipMeterDisplayValue(fixedPriceText),
      primaryLabel: fareLabel,
      kmText: remaining.isNotEmpty ? remaining : kmText,
      durationText: durationText,
      waitText: waitText,
      metrics: secondaryMetrics,
      primaryMetrics: primaryMetrics,
      secondaryMetrics: secondaryMetrics,
      language: lang,
    );
  }
  return ExternalNavPipMeterModel(
    kind: PipMeterKind.liveTariff,
    title: pipMeterToDestinationTitle(lang),
    primaryValue: pipMeterDisplayValue(liveFareText),
    primaryLabel: fareLabel,
    kmText: remaining.isNotEmpty ? remaining : kmText,
    durationText: durationText,
    waitText: waitText,
    metrics: secondaryMetrics,
    primaryMetrics: primaryMetrics,
    secondaryMetrics: secondaryMetrics,
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
  String? speedText,
}) {
  final remaining = snapshot.remainingDistanceText.trim();
  final eta = snapshot.etaText.trim();
  final snapSpeed = snapshot.speedText.trim();
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
    speedText: (speedText ?? '').trim().isNotEmpty
        ? speedText
        : (snapSpeed.isEmpty ? null : snapSpeed),
  );
}

/// PIP-TABLET-KPI-DENSITY-P1: tablet taxi-meter typography; phone unchanged.
@immutable
class PipMeterTypography {
  const PipMeterTypography({
    required this.titleSize,
    required this.primarySize,
    required this.metricSize,
    required this.labelSize,
    required this.primaryValueSize,
    required this.primaryLabelSize,
    required this.secondaryValueSize,
    required this.secondaryLabelSize,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.titleGap,
    required this.metricsGap,
    required this.sectionGap,
    required this.frameWidth,
    required this.isTablet,
  });

  final double titleSize;
  final double primarySize;
  final double metricSize;
  final double labelSize;
  final double primaryValueSize;
  final double primaryLabelSize;
  final double secondaryValueSize;
  final double secondaryLabelSize;
  final double horizontalPadding;
  final double verticalPadding;
  final double titleGap;
  final double metricsGap;
  final double sectionGap;
  final double frameWidth;
  final bool isTablet;

  /// [size] is the *window* (may be the tiny PiP surface).
  /// [hostIsTablet] must reflect the *device* form-factor, not the window.
  static PipMeterTypography forSize(
    Size size, {
    required bool compact,
    bool? hostIsTablet,
  }) {
    final useTablet = resolvePipMeterHostIsTablet(
      latchedHostIsTablet: hostIsTablet,
      windowSize: size,
    );
    if (!useTablet) {
      return PipMeterTypography(
        titleSize: 14,
        primarySize: 34,
        metricSize: 16,
        labelSize: 13.6,
        primaryValueSize: 34,
        primaryLabelSize: 13.6,
        secondaryValueSize: 16,
        secondaryLabelSize: 13.6,
        horizontalPadding: compact ? 12 : 20,
        verticalPadding: compact ? 8 : 16,
        titleGap: 6,
        metricsGap: 10,
        sectionGap: 8,
        frameWidth: 0,
        isTablet: false,
      );
    }
    // Tablet device: keep taxi-meter hierarchy even inside a small PiP window.
    // Scale fonts to the window shortest side so content still fits, but never
    // fall back to the phone branch (field flash → small steady-state bug).
    final landscape = size.width > size.height;
    final scale = (size.shortestSide / 420.0).clamp(0.70, 1.0);
    double s(double v) => v * scale;
    return PipMeterTypography(
      titleSize: s(landscape ? 28 : 30),
      primarySize: s(landscape ? 44 : 50),
      metricSize: s(landscape ? 32 : 36),
      labelSize: s(landscape ? 18 : 20),
      primaryValueSize: s(landscape ? 44 : 50),
      primaryLabelSize: s(landscape ? 20 : 22),
      secondaryValueSize: s(landscape ? 32 : 36),
      secondaryLabelSize: s(landscape ? 18 : 20),
      horizontalPadding: math.max(12.0, s(24)),
      verticalPadding: math.max(8.0, s(landscape ? 12 : 16)),
      titleGap: s(8),
      metricsGap: s(6),
      sectionGap: s(10),
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
    this.hostIsTablet,
  });

  final ExternalNavPipMeterModel model;
  final bool compact;

  /// Latched pre-PiP / session device class. When null, resolved from display.
  final bool? hostIsTablet;

  @override
  Widget build(BuildContext context) {
    final windowSize = MediaQuery.sizeOf(context);
    final deviceSize = pipMeterDeviceLogicalSizeOf(context);
    final useTablet = resolvePipMeterHostIsTablet(
      latchedHostIsTablet: hostIsTablet,
      deviceSize: deviceSize,
      windowSize: windowSize,
    );
    final typo = PipMeterTypography.forSize(
      windowSize,
      compact: compact,
      hostIsTablet: useTablet,
    );

    // PIP-TABLET-FORM-FACTOR-STABLE-P1: one-line proof for field logcat.
    assert(() {
      debugPrint(
        '[PIP_METER] form_factor '
        'window=${windowSize.width.toStringAsFixed(0)}x'
        '${windowSize.height.toStringAsFixed(0)} '
        'device=${deviceSize.width.toStringAsFixed(0)}x'
        '${deviceSize.height.toStringAsFixed(0)} '
        'latched=$hostIsTablet useTablet=$useTablet '
        'branch=${useTablet ? "tablet_taxi" : "phone_compact"}',
      );
      return true;
    }());

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: typo.horizontalPadding,
        vertical: typo.verticalPadding,
      ),
      child: typo.isTablet
          ? _TabletTaxiMeterBody(model: model, typo: typo)
          : _PhonePipMeterBody(model: model, typo: typo),
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

/// Phone: preserve field-green compact primary + secondary presentation.
class _PhonePipMeterBody extends StatelessWidget {
  const _PhonePipMeterBody({
    required this.model,
    required this.typo,
  });

  final ExternalNavPipMeterModel model;
  final PipMeterTypography typo;

  @override
  Widget build(BuildContext context) {
    // Keep phone primary (fare/ETA) unique — do not repeat it in the compact
    // secondary row (tablet owns the full taxi-meter secondary set).
    final metrics = (model.secondaryMetrics.isNotEmpty
            ? model.secondaryMetrics
            : model.metrics)
        .where(
          (m) =>
              m.value != model.primaryValue &&
              m.label != model.primaryLabel,
        )
        .toList(growable: false);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
            valueSize: typo.metricSize,
            labelSize: typo.labelSize,
            labelAboveValue: false,
            showDividers: false,
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
      ],
    );
  }
}

/// Tablet: full-width taxi-meter density matching visual acceptance target.
class _TabletTaxiMeterBody extends StatelessWidget {
  const _TabletTaxiMeterBody({
    required this.model,
    required this.typo,
  });

  final ExternalNavPipMeterModel model;
  final PipMeterTypography typo;

  @override
  Widget build(BuildContext context) {
    final primary = model.primaryMetrics;
    final secondary = model.secondaryMetrics;
    return Column(
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
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
        SizedBox(height: typo.titleGap * 0.5),
        Center(
          child: Container(
            width: 56,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(height: typo.sectionGap),
        if (primary.isNotEmpty)
          Expanded(
            flex: 5,
            child: _PipMeterMetricsRow(
              metrics: primary,
              valueSize: typo.primaryValueSize,
              labelSize: typo.primaryLabelSize,
              labelAboveValue: true,
              showDividers: false,
              valueColor: const Color(0xFFFFFFFF),
              expandVertically: true,
            ),
          ),
        SizedBox(height: typo.sectionGap),
        const Divider(
          height: 1,
          thickness: 1,
          color: Color(0xFF3A4654),
        ),
        SizedBox(height: typo.sectionGap),
        if (secondary.isNotEmpty)
          Expanded(
            flex: 4,
            child: _PipMeterMetricsRow(
              metrics: secondary,
              valueSize: typo.secondaryValueSize,
              labelSize: typo.secondaryLabelSize,
              labelAboveValue: true,
              showDividers: true,
              valueColor: const Color(0xFFE8EEF5),
              expandVertically: true,
            ),
          ),
      ],
    );
  }
}

class _PipMeterMetricsRow extends StatelessWidget {
  const _PipMeterMetricsRow({
    required this.metrics,
    required this.valueSize,
    required this.labelSize,
    required this.labelAboveValue,
    required this.showDividers,
    this.valueColor = const Color(0xFFE8EEF5),
    this.expandVertically = false,
  });

  final List<PipMeterMetric> metrics;
  final double valueSize;
  final double labelSize;
  final bool labelAboveValue;
  final bool showDividers;
  final Color valueColor;
  final bool expandVertically;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: expandVertically
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0 && showDividers)
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFF3A4654),
            )
          else if (i > 0)
            const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              label: metrics[i].resolvedSemantics,
              child: _PipMeterMetricCell(
                metric: metrics[i],
                valueSize: valueSize,
                labelSize: labelSize,
                labelAboveValue: labelAboveValue,
                valueColor: valueColor,
                expandVertically: expandVertically,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PipMeterMetricCell extends StatelessWidget {
  const _PipMeterMetricCell({
    required this.metric,
    required this.valueSize,
    required this.labelSize,
    required this.labelAboveValue,
    required this.valueColor,
    required this.expandVertically,
  });

  final PipMeterMetric metric;
  final double valueSize;
  final double labelSize;
  final bool labelAboveValue;
  final Color valueColor;
  final bool expandVertically;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      metric.label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF9AA7B5),
        fontSize: labelSize,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    );
    final value = Text(
      metric.value,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: valueColor,
        fontSize: valueSize,
        fontWeight: FontWeight.w800,
        height: 1.05,
      ),
    );

    final column = Column(
      mainAxisAlignment: expandVertically
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      mainAxisSize: expandVertically ? MainAxisSize.max : MainAxisSize.min,
      children: labelAboveValue
          ? <Widget>[label, const SizedBox(height: 4), value]
          : <Widget>[value, const SizedBox(height: 2), label],
    );

    if (!expandVertically) return column;
    return column;
  }
}
