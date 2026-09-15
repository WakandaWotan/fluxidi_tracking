// COMPANY-AGENDA-P0 — vehicle visual contract. No homemade cutouts.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

const BoxFit kCompanyPlanVehicleVisualFit = BoxFit.contain;

class CompanyPlanVehicleVisualContract {
  const CompanyPlanVehicleVisualContract({
    this.sedanAsset = '',
    this.minivanAsset = '',
    this.vehiclePhotoUrl = '',
  });

  final String sedanAsset;
  final String minivanAsset;
  final String vehiclePhotoUrl;

  String genericAssetFor(CompanyPlanVehicleType type) {
    final configured = switch (type) {
      CompanyPlanVehicleType.sedan => sedanAsset.trim(),
      CompanyPlanVehicleType.minivan => minivanAsset.trim(),
    };
    if (configured.isNotEmpty) return configured;
    return companyPlanVehicleFallbackAsset(
      type == CompanyPlanVehicleType.minivan
          ? CompanyPlanVehicleCategory.minivan
          : CompanyPlanVehicleCategory.sedan,
    );
  }

  String genericAssetForCategory(CompanyPlanVehicleCategory category) {
    return companyPlanVehicleFallbackAsset(category);
  }
}

enum CompanyPlanVehicleVisualKind { companyPhoto, genericCutout, vectorFallback }

class CompanyPlanVehicleVisualResolved {
  const CompanyPlanVehicleVisualResolved({
    required this.kind,
    this.photoUrl = '',
    this.assetPath = '',
    required this.fallbackIcon,
  });

  final CompanyPlanVehicleVisualKind kind;
  final String photoUrl;
  final String assetPath;
  final IconData fallbackIcon;
}

IconData companyPlanVehicleVectorIcon(CompanyPlanVehicleType type) {
  return switch (type) {
    CompanyPlanVehicleType.sedan => Icons.directions_car_outlined,
    CompanyPlanVehicleType.minivan => Icons.airport_shuttle_outlined,
  };
}

bool companyPlanVehiclePhotoUrlIsAllowed(String raw, {String? bookingBaseUrl}) {
  final url = raw.trim();
  if (url.isEmpty) return false;
  if (isLocalOrPrivateMediaRef(url)) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.trim().toLowerCase();
  if (host.isEmpty) return false;
  if (host == '127.0.0.1' || host == 'localhost') return true;
  if (host.endsWith('.fluxidi.workers.dev') || host == 'fluxidi.workers.dev') {
    return true;
  }
  final base = Uri.tryParse((bookingBaseUrl ?? kBookingBaseUrl).trim());
  if (base != null && base.host.isNotEmpty && host == base.host.toLowerCase()) {
    return true;
  }
  return false;
}

CompanyPlanVehicleVisualResolved resolveCompanyPlanVehicleVisual({
  required CompanyPlanVehicleType type,
  CompanyPlanVehicleVisualContract contract = const CompanyPlanVehicleVisualContract(),
  String? vehiclePhotoUrl,
  String? bookingBaseUrl,
  CompanyPlanVehicleCategory? category,
}) {
  final photo = (vehiclePhotoUrl ?? contract.vehiclePhotoUrl).trim();
  if (companyPlanVehiclePhotoUrlIsAllowed(photo, bookingBaseUrl: bookingBaseUrl)) {
    return CompanyPlanVehicleVisualResolved(
      kind: CompanyPlanVehicleVisualKind.companyPhoto,
      photoUrl: photo,
      fallbackIcon: companyPlanVehicleVectorIcon(type),
    );
  }
  final generic = category != null
      ? contract.genericAssetForCategory(category)
      : contract.genericAssetFor(type);
  if (generic.isNotEmpty) {
    return CompanyPlanVehicleVisualResolved(
      kind: CompanyPlanVehicleVisualKind.genericCutout,
      assetPath: generic,
      fallbackIcon: companyPlanVehicleVectorIcon(type),
    );
  }
  return CompanyPlanVehicleVisualResolved(
    kind: CompanyPlanVehicleVisualKind.vectorFallback,
    fallbackIcon: companyPlanVehicleVectorIcon(type),
  );
}

class CompanyPlanVehicleVisual extends StatelessWidget {
  const CompanyPlanVehicleVisual({
    super.key,
    required this.type,
    required this.semanticLabel,
    this.contract = const CompanyPlanVehicleVisualContract(),
    this.vehiclePhotoUrl,
    this.category,
    this.height = 56,
  });

  final CompanyPlanVehicleType type;
  final String semanticLabel;
  final CompanyPlanVehicleVisualContract contract;
  final String? vehiclePhotoUrl;
  final CompanyPlanVehicleCategory? category;
  final double height;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveCompanyPlanVehicleVisual(
      type: type,
      contract: contract,
      vehiclePhotoUrl: vehiclePhotoUrl,
      category: category,
    );
    return Semantics(
      label: semanticLabel,
      image: resolved.kind != CompanyPlanVehicleVisualKind.vectorFallback,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: _visual(resolved),
      ),
    );
  }

  Widget _visual(CompanyPlanVehicleVisualResolved resolved) {
    switch (resolved.kind) {
      case CompanyPlanVehicleVisualKind.companyPhoto:
        return Image.network(
          resolved.photoUrl,
          fit: kCompanyPlanVehicleVisualFit,
          alignment: Alignment.center,
          cacheWidth: 512,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Image.asset(
            category != null
                ? contract.genericAssetForCategory(category!)
                : contract.genericAssetFor(type),
            fit: kCompanyPlanVehicleVisualFit,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => _fallback(resolved),
          ),
        );
      case CompanyPlanVehicleVisualKind.genericCutout:
        return Image.asset(
          resolved.assetPath,
          fit: kCompanyPlanVehicleVisualFit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _fallback(resolved),
        );
      case CompanyPlanVehicleVisualKind.vectorFallback:
        return _fallback(resolved);
    }
  }

  Widget _fallback(CompanyPlanVehicleVisualResolved resolved) {
    return Icon(resolved.fallbackIcon);
  }
}
