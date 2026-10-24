const String kAirportAutoCalcOutsideFixedFaresField =
    'airport_auto_calc_outside_fixed_fares';
const String kAirportAutoCalcOutsideFixedFaresCamel =
    'airportAutoCalcOutsideFixedFares';
const String kAirportFixedFareMinLeadHoursField =
    'airport_fixed_fare_min_lead_hours';
const String kAirportFixedFareMinLeadHoursCamel =
    'airportFixedFareMinLeadHours';

const int kAirportFixedFareMinLeadHoursMax = 720;

class AirportPricePolicyView {
  const AirportPricePolicyView({
    required this.autoCalcEnabled,
    required this.autoCalcStored,
    required this.minLeadDeclared,
    required this.minLeadHours,
  });

  final bool autoCalcEnabled;
  final bool autoCalcStored;
  final bool minLeadDeclared;
  final num? minLeadHours;

  String get minLeadText => formatAirportFixedFareMinLeadHours(
        hours: minLeadHours,
        declared: minLeadDeclared,
      );
}

class AirportPricePolicyWrite {
  const AirportPricePolicyWrite._({
    this.profile,
    this.invalidLead = false,
    this.unchanged = false,
  });

  const AirportPricePolicyWrite.profile(Map<String, dynamic> profile)
      : this._(profile: profile);

  const AirportPricePolicyWrite.invalidLead() : this._(invalidLead: true);

  const AirportPricePolicyWrite.unchanged() : this._(unchanged: true);

  final Map<String, dynamic>? profile;
  final bool invalidLead;
  final bool unchanged;
}

bool profileDeclaresAirportAutoCalc(Map<dynamic, dynamic> profile) {
  return profile.containsKey(kAirportAutoCalcOutsideFixedFaresField) ||
      profile.containsKey(kAirportAutoCalcOutsideFixedFaresCamel);
}

bool profileDeclaresAirportFixedFareMinLead(Map<dynamic, dynamic> profile) {
  return profile.containsKey(kAirportFixedFareMinLeadHoursField) ||
      profile.containsKey(kAirportFixedFareMinLeadHoursCamel);
}

dynamic _declaredValue(
  Map<dynamic, dynamic> profile,
  String snake,
  String camel,
) {
  if (profile.containsKey(snake)) return profile[snake];
  return profile[camel];
}

bool airportAutoCalcOutsideFixedFaresEnabled(Map<dynamic, dynamic> profile) {
  if (!profileDeclaresAirportAutoCalc(profile)) return true;
  final raw = _declaredValue(
    profile,
    kAirportAutoCalcOutsideFixedFaresField,
    kAirportAutoCalcOutsideFixedFaresCamel,
  );
  if (raw == false || raw == 0) return false;
  final text = '$raw'.trim().toLowerCase();
  if (text == 'false' || text == '0' || text == 'off' || text == 'nee') {
    return false;
  }
  return true;
}

AirportPricePolicyView readAirportPricePolicy(Map<dynamic, dynamic> profile) {
  final declaredLead = profileDeclaresAirportFixedFareMinLead(profile);
  num? hours;
  if (declaredLead) {
    final raw = _declaredValue(
      profile,
      kAirportFixedFareMinLeadHoursField,
      kAirportFixedFareMinLeadHoursCamel,
    );
    if (raw is num && raw.isFinite) {
      hours = raw;
    } else if (raw != null && '$raw'.trim().isNotEmpty) {
      hours = num.tryParse('$raw'.trim().replaceAll(',', '.'));
    }
  }
  return AirportPricePolicyView(
    autoCalcEnabled: airportAutoCalcOutsideFixedFaresEnabled(profile),
    autoCalcStored: profileDeclaresAirportAutoCalc(profile),
    minLeadDeclared: declaredLead,
    minLeadHours: hours,
  );
}

String formatAirportFixedFareMinLeadHours({
  required num? hours,
  required bool declared,
}) {
  if (!declared || hours == null) return '';
  if (hours == hours.roundToDouble()) return hours.round().toString();
  return hours.toString();
}

AirportPricePolicyWrite buildAirportPricePolicyProfile({
  required Map<String, dynamic> stored,
  required bool autoCalcEnabled,
  required String leadText,
}) {
  final current = readAirportPricePolicy(stored);
  final parsed = _parseLeadText(leadText);
  if (parsed.invalid) return const AirportPricePolicyWrite.invalidLead();

  final next = Map<String, dynamic>.from(stored);
  var changed = false;
  if (autoCalcEnabled != current.autoCalcEnabled) {
    next[kAirportAutoCalcOutsideFixedFaresField] = autoCalcEnabled;
    next[kAirportAutoCalcOutsideFixedFaresCamel] = autoCalcEnabled;
    changed = true;
  }

  final loaded = current.minLeadText;
  final typed = leadText.trim().replaceAll(',', '.');
  final leadChanged = typed != loaded;
  if (leadChanged) {
    if (parsed.empty) {
      if (current.minLeadDeclared) {
        next[kAirportFixedFareMinLeadHoursField] = null;
        next[kAirportFixedFareMinLeadHoursCamel] = null;
        changed = true;
      }
    } else {
      next[kAirportFixedFareMinLeadHoursField] = parsed.hours;
      next[kAirportFixedFareMinLeadHoursCamel] = parsed.hours;
      changed = true;
    }
  }

  if (!changed) return const AirportPricePolicyWrite.unchanged();
  return AirportPricePolicyWrite.profile(next);
}

class _LeadParse {
  const _LeadParse({this.hours, this.empty = false, this.invalid = false});

  final num? hours;
  final bool empty;
  final bool invalid;
}

_LeadParse _parseLeadText(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return const _LeadParse(empty: true);
  final hours = num.tryParse(text);
  if (hours == null || !hours.isFinite) return const _LeadParse(invalid: true);
  if (hours < 0 || hours > kAirportFixedFareMinLeadHoursMax) {
    return const _LeadParse(invalid: true);
  }
  if (hours == hours.roundToDouble()) {
    return _LeadParse(hours: hours.round());
  }
  return _LeadParse(hours: hours);
}
