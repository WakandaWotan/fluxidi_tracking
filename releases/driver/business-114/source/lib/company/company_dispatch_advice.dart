// Smart-dispatch advice for the existing planner driver list.
// Display only. Never selects or assigns a driver.

import 'package:fluxidi_tracking/app_strings.dart';

const LocalizedText kCompanyDispatchRecommended = LocalizedText(
  nl: 'Aanbevolen',
  en: 'Recommended',
  fr: 'Recommandé',
  es: 'Recomendado',
  de: 'Empfohlen',
);

const LocalizedText kCompanyDispatchEtaToPickup = LocalizedText(
  nl: '± {minutes} min naar ophaalpunt',
  en: '± {minutes} min to pickup',
  fr: '± {minutes} min vers le point de prise en charge',
  es: '± {minutes} min hasta el punto de recogida',
  de: '± {minutes} Min. zum Abholpunkt',
);

const LocalizedText kCompanyDispatchEtaShort = LocalizedText(
  nl: '± {minutes} min',
  en: '± {minutes} min',
  fr: '± {minutes} min',
  es: '± {minutes} min',
  de: '± {minutes} Min.',
);

const LocalizedText kCompanyDispatchScheduleFallback = LocalizedText(
  nl: 'Planning beschikbaar — live ETA niet beschikbaar',
  en: 'Schedule available — live ETA unavailable',
  fr: 'Planning disponible — ETA en direct indisponible',
  es: 'Planificación disponible — ETA en vivo no disponible',
  de: 'Planung verfügbar — Live-ETA nicht verfügbar',
);

class CompanyDispatchCandidate {
  const CompanyDispatchCandidate({
    required this.driverId,
    required this.vehicleId,
    this.etaSeconds,
    this.locationFeed = '',
    this.reliableForEta = false,
  });

  final String driverId;
  final String vehicleId;
  final int? etaSeconds;
  final String locationFeed;
  final bool reliableForEta;
}

class CompanyDispatchAdvice {
  const CompanyDispatchAdvice({
    required this.mode,
    this.recommendedDriverId = '',
    this.recommendedVehicleId = '',
    this.candidates = const <CompanyDispatchCandidate>[],
    this.unavailable = false,
  });

  /// Tracking or the choices request failed. The driver list stays usable.
  const CompanyDispatchAdvice.unavailable()
    : this(
        mode: 'schedule_fallback',
        unavailable: true,
      );

  final String mode;
  final String recommendedDriverId;
  final String recommendedVehicleId;
  final List<CompanyDispatchCandidate> candidates;
  final bool unavailable;

  bool get isLiveEta => mode == 'live_eta';
  bool get isScheduleFallback => !isLiveEta;
}

class CompanyDispatchDriverNote {
  const CompanyDispatchDriverNote({
    this.recommended = false,
    this.etaLine = '',
  });

  final bool recommended;
  final String etaLine;

  bool get isEmpty => !recommended && etaLine.isEmpty;
}

/// Ignores a late assignment-choices response so older advice cannot replace newer advice.
class CompanyDispatchAdviceSlot {
  int _generation = 0;
  CompanyDispatchAdvice? advice;

  int begin() => ++_generation;

  bool apply(int token, CompanyDispatchAdvice? next) {
    if (token != _generation) return false;
    advice = next;
    return true;
  }
}

/// Returns null when the payload has none of the new dispatch fields.
CompanyDispatchAdvice? parseCompanyDispatchAdvice(Map<String, dynamic> json) {
  const keys = <String>{
    'recommended_driver_id',
    'recommended_vehicle_id',
    'dispatch_mode',
    'eta_seconds',
    'distance_meters',
    'location_feed',
    'reliable_for_eta',
    'dispatch_candidates',
  };
  if (!keys.any(json.containsKey)) return null;
  final rawCandidates = json['dispatch_candidates'];
  final candidates = <CompanyDispatchCandidate>[];
  if (rawCandidates is List) {
    for (final row in rawCandidates.whereType<Map>()) {
      final driverId = (row['driver_id'] ?? row['id'] ?? '').toString().trim();
      if (driverId.isEmpty) continue;
      candidates.add(
        CompanyDispatchCandidate(
          driverId: driverId,
          vehicleId: (row['vehicle_id'] ?? '').toString().trim(),
          etaSeconds: _optionalInt(row['eta_seconds']),
          locationFeed: (row['location_feed'] ?? '').toString().trim(),
          reliableForEta: row['reliable_for_eta'] == true,
        ),
      );
    }
  }
  final mode = (json['dispatch_mode'] ?? '').toString().trim();
  return CompanyDispatchAdvice(
    mode: mode == 'live_eta' ? 'live_eta' : 'schedule_fallback',
    recommendedDriverId: (json['recommended_driver_id'] ?? '').toString().trim(),
    recommendedVehicleId:
        (json['recommended_vehicle_id'] ?? '').toString().trim(),
    candidates: candidates,
  );
}

int? companyDispatchEtaMinutes(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  final minutes = ((seconds + 30) / 60).floor();
  return minutes < 1 ? 1 : minutes;
}

bool companyDispatchCandidateHasLiveEta(CompanyDispatchCandidate candidate) {
  return candidate.reliableForEta &&
      candidate.locationFeed == 'live' &&
      companyDispatchEtaMinutes(candidate.etaSeconds) != null;
}

CompanyDispatchDriverNote companyDispatchDriverNote({
  required CompanyDispatchAdvice? advice,
  required String driverId,
  required AppLanguage language,
}) {
  if (advice == null || !advice.isLiveEta) {
    return const CompanyDispatchDriverNote();
  }
  final id = driverId.trim();
  CompanyDispatchCandidate? candidate;
  for (final row in advice.candidates) {
    if (row.driverId == id) {
      candidate = row;
      break;
    }
  }
  if (candidate == null || !companyDispatchCandidateHasLiveEta(candidate)) {
    return const CompanyDispatchDriverNote();
  }
  final minutes = companyDispatchEtaMinutes(candidate.etaSeconds)!;
  final recommended = advice.recommendedDriverId == id;
  final template = recommended
      ? kCompanyDispatchEtaToPickup.of(language)
      : kCompanyDispatchEtaShort.of(language);
  return CompanyDispatchDriverNote(
    recommended: recommended,
    etaLine: template.replaceAll('{minutes}', '$minutes'),
  );
}

String companyDispatchAdviceNotice(
  CompanyDispatchAdvice? advice,
  AppLanguage language,
) {
  if (advice == null || advice.isLiveEta) return '';
  return kCompanyDispatchScheduleFallback.of(language);
}

int? _optionalInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}
