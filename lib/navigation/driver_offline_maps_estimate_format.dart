// FLUXIDI-OFFLINE-MAP-NONFINITE-ESTIMATE-DIALOG-P0-2
//
// Field crash: Europe confirmation dialog called `.round()` on an SDK
// `errorMargin` that was NaN/Infinity ("Unsupported operation: Infinity or NaN
// toInt"). All estimate-derived arithmetic/integer conversion must go through
// these guards before the dialog is built.

import 'package:fluxidi_tracking/app_strings.dart';

/// Classification of one estimate-derived numeric for PII-safe diagnostics.
enum OfflineMapEstimateFiniteClass {
  missing,
  finite,
  nan,
  infinity,
  negative,
}

OfflineMapEstimateFiniteClass classifyOfflineMapEstimateNumber(num? value) {
  if (value == null) return OfflineMapEstimateFiniteClass.missing;
  final d = value.toDouble();
  if (d.isNaN) return OfflineMapEstimateFiniteClass.nan;
  if (d.isInfinite) return OfflineMapEstimateFiniteClass.infinity;
  if (d < 0) return OfflineMapEstimateFiniteClass.negative;
  if (!d.isFinite) return OfflineMapEstimateFiniteClass.infinity;
  return OfflineMapEstimateFiniteClass.finite;
}

String offlineMapEstimateFiniteClassToken(OfflineMapEstimateFiniteClass c) {
  switch (c) {
    case OfflineMapEstimateFiniteClass.missing:
      return 'missing';
    case OfflineMapEstimateFiniteClass.finite:
      return 'finite';
    case OfflineMapEstimateFiniteClass.nan:
      return 'nan';
    case OfflineMapEstimateFiniteClass.infinity:
      return 'infinity';
    case OfflineMapEstimateFiniteClass.negative:
      return 'negative';
  }
}

/// Safe non-negative int from an untrusted numeric. Null when unusable.
int? safeOfflineMapNonNegativeInt(num? value, {int maxBytes = 1 << 50}) {
  final cls = classifyOfflineMapEstimateNumber(value);
  if (cls != OfflineMapEstimateFiniteClass.finite) return null;
  final d = value!.toDouble();
  if (d > maxBytes) return null;
  // Finite and in range — `.round()` / `.toInt()` cannot throw.
  return d.round();
}

/// Safe error-margin fraction in `[0, 10]`. Null when unusable.
double? safeOfflineMapErrorMargin(num? value) {
  final cls = classifyOfflineMapEstimateNumber(value);
  if (cls != OfflineMapEstimateFiniteClass.finite) return null;
  final d = value!.toDouble();
  if (d > 10) return null;
  return d;
}

/// Safe percentage 0–100 for progress UI. Null when fraction is unusable.
int? safeOfflineMapPercent(num? fraction) {
  final cls = classifyOfflineMapEstimateNumber(fraction);
  if (cls != OfflineMapEstimateFiniteClass.finite) return null;
  final d = fraction!.toDouble().clamp(0.0, 1.0);
  return (d * 100).round();
}

/// Whether byte sizes are usable for the confirmation dialog.
bool offlineMapEstimateSizesUsable({
  required int? transferSizeBytes,
  required int? storageSizeBytes,
}) {
  final transfer = safeOfflineMapNonNegativeInt(transferSizeBytes);
  final storage = safeOfflineMapNonNegativeInt(storageSizeBytes);
  if (transfer == null && storage == null) return false;
  return (transfer ?? 0) > 0 || (storage ?? 0) > 0;
}

String formatOfflineMapByteCount(int? bytes) {
  final safe = safeOfflineMapNonNegativeInt(bytes);
  if (safe == null || safe <= 0) return '—';
  final mb = safe / (1024 * 1024);
  if (mb < 1) {
    return '${(safe / 1024).toStringAsFixed(0)} KB';
  }
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
  return '${mb.toStringAsFixed(1)} MB';
}

/// Localized "estimate unavailable" copy (NL/EN/FR/ES).
String offlineMapEstimateUnavailableLabel(AppLanguage language) {
  switch (language) {
    case AppLanguage.nl:
      return 'Geschatte downloadgrootte niet beschikbaar';
    case AppLanguage.fr:
      return 'Taille de téléchargement estimée indisponible';
    case AppLanguage.es:
      return 'Tamaño de descarga estimado no disponible';
    case AppLanguage.de:
      return 'Geschätzte Downloadgröße nicht verfügbar';
    case AppLanguage.en:
      return 'Estimated download size unavailable';
  }
}

/// Builds the confirmation dialog estimate line. Never throws on NaN/Infinity.
///
/// Returns unavailable text when sizes are missing/invalid. Omits the margin
/// percentage when the margin is non-finite so `.round()` can never run on it.
String formatOfflineMapEstimateConfirmLine({
  required AppLanguage language,
  int? transferSizeBytes,
  int? storageSizeBytes,
  num? errorMargin,
}) {
  final transfer = safeOfflineMapNonNegativeInt(transferSizeBytes);
  final storage = safeOfflineMapNonNegativeInt(storageSizeBytes);
  if (!offlineMapEstimateSizesUsable(
    transferSizeBytes: transfer,
    storageSizeBytes: storage,
  )) {
    return offlineMapEstimateUnavailableLabel(language);
  }

  final transferLabel = formatOfflineMapByteCount(transfer);
  final storageLabel = formatOfflineMapByteCount(storage);
  final margin = safeOfflineMapErrorMargin(errorMargin);
  final marginPct = margin == null ? null : (margin * 100).round();

  switch (language) {
    case AppLanguage.nl:
      if (marginPct == null) {
        return 'Geschatte download: $transferLabel · opslag: $storageLabel';
      }
      return 'Geschatte download: $transferLabel · opslag: $storageLabel '
          '(schatting ±$marginPct%)';
    case AppLanguage.fr:
      if (marginPct == null) {
        return 'Téléchargement estimé : $transferLabel · stockage : $storageLabel';
      }
      return 'Téléchargement estimé : $transferLabel · stockage : $storageLabel '
          '(estimation ±$marginPct%)';
    case AppLanguage.es:
      if (marginPct == null) {
        return 'Descarga estimada: $transferLabel · almacenamiento: $storageLabel';
      }
      return 'Descarga estimada: $transferLabel · almacenamiento: $storageLabel '
          '(estimación ±$marginPct%)';
    case AppLanguage.de:
      if (marginPct == null) {
        return 'Geschätzter Download: $transferLabel · Speicher: $storageLabel';
      }
      return 'Geschätzter Download: $transferLabel · Speicher: $storageLabel '
          '(Schätzung ±$marginPct%)';
    case AppLanguage.en:
      if (marginPct == null) {
        return 'Estimated download: $transferLabel · storage: $storageLabel';
      }
      return 'Estimated download: $transferLabel · storage: $storageLabel '
          '(estimate ±$marginPct%)';
  }
}
