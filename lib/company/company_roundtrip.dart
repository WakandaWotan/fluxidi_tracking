import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';

enum CompanyRoundtripChoice { single, splitNoWait, continuousWait }

CompanyRoundtripChoice parseCompanyRoundtripChoice(Object? raw) {
  final text = raw?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
  switch (text) {
    case 'split_no_wait':
    case 'split':
    case 'no_wait':
    case 'heen_terug_geen_wacht':
      return CompanyRoundtripChoice.splitNoWait;
    case 'continuous_wait':
    case 'continuous':
    case 'wait':
    case 'heen_terug_wacht':
      return CompanyRoundtripChoice.continuousWait;
    default:
      return CompanyRoundtripChoice.single;
  }
}

String companyRoundtripChoiceWire(CompanyRoundtripChoice choice) {
  return switch (choice) {
    CompanyRoundtripChoice.single => 'single',
    CompanyRoundtripChoice.splitNoWait => 'split_no_wait',
    CompanyRoundtripChoice.continuousWait => 'continuous_wait',
  };
}

LocalizedText companyRoundtripChoiceLabel(CompanyRoundtripChoice choice) {
  return switch (choice) {
    CompanyRoundtripChoice.single => kCompanyRoundtripSingle,
    CompanyRoundtripChoice.splitNoWait => kCompanyRoundtripSplit,
    CompanyRoundtripChoice.continuousWait => kCompanyRoundtripContinuous,
  };
}

LocalizedText? companyAgendaRideLegLabel(CompanyAgendaRide ride) {
  switch (ride.legType) {
    case 'outbound':
      return kCompanyRoundtripOutbound;
    case 'return':
      return kCompanyRoundtripReturn;
    case 'continuous':
      return kCompanyRoundtripContinuousShort;
    default:
      return ride.roundtripChoice == CompanyRoundtripChoice.continuousWait
          ? kCompanyRoundtripContinuousShort
          : null;
  }
}

String companyAgendaRideDisplayTitle(CompanyAgendaRide ride, AppLanguage language) {
  final prefix = companyAgendaRideLegLabel(ride)?.of(language);
  final name = ride.customerName.trim();
  if (prefix == null || prefix.isEmpty) return name;
  if (name.isEmpty) return prefix;
  return '$prefix · $name';
}

String companyAgendaRideDetailId(CompanyAgendaRide ride) {
  final parent = ride.parentBookingId.trim();
  if (parent.isNotEmpty) return parent;
  return ride.bookingId.trim();
}

int? companyPlanReturnDurationMin({
  required CompanyRoundtripChoice choice,
  int? outboundDurationMin,
  int? quotedReturnDurationMin,
  String returnDurationText = '',
}) {
  if (choice == CompanyRoundtripChoice.continuousWait) {
    if (quotedReturnDurationMin != null && quotedReturnDurationMin > 0) {
      return quotedReturnDurationMin;
    }
    return outboundDurationMin != null && outboundDurationMin > 0
        ? outboundDurationMin
        : null;
  }
  if (choice == CompanyRoundtripChoice.splitNoWait) {
    if (quotedReturnDurationMin != null && quotedReturnDurationMin > 0) {
      return quotedReturnDurationMin;
    }
    final typed = int.tryParse(returnDurationText.trim());
    if (typed != null && typed > 0) return typed;
    return outboundDurationMin != null && outboundDurationMin > 0
        ? outboundDurationMin
        : null;
  }
  return null;
}

int? companyOccupancyWaitMinutes({
  required DateTime outboundLocal,
  required int? outboundDurationMin,
  required DateTime? returnLocal,
}) {
  if (outboundDurationMin == null || outboundDurationMin <= 0 || returnLocal == null) {
    return null;
  }
  final outboundEnd = outboundLocal.add(Duration(minutes: outboundDurationMin));
  final wait = returnLocal.difference(outboundEnd).inMinutes;
  return wait < 0 ? 0 : wait;
}
