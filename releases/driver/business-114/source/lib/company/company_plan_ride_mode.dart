// COMPANY-AGENDA-P0 — airport_ride is a service mode, never a vehicle type.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_visual.dart';

const String kCompanyPlanRideModeDir = 'assets/booking/modes/v1';

const String kCompanyPlanAirportModeAsset =
    '$kCompanyPlanRideModeDir/fluxidi_mode_airport_ride_v1.webp';

const IconData kCompanyPlanAirportModeIcon = Icons.flight_takeoff;

bool companyPlanRideModeIsAirport(String? raw) {
  switch (raw?.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_') ??
      '') {
    case 'airport':
    case 'airport_ride':
      return true;
    default:
      return false;
  }
}

class CompanyPlanAirportModeVisual extends StatelessWidget {
  const CompanyPlanAirportModeVisual({
    super.key,
    required this.semanticLabel,
    this.height = 104,
    this.compact = false,
  });

  final String semanticLabel;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Icon(
        kCompanyPlanAirportModeIcon,
        semanticLabel: semanticLabel,
      );
    }
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(
          kCompanyPlanAirportModeAsset,
          fit: kCompanyPlanVehicleVisualFit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Icon(
            kCompanyPlanAirportModeIcon,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}
