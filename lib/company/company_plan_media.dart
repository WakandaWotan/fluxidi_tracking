// COMPANY-AGENDA-P0 — branding/fleet/driver media from existing profile fields.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_visual.dart';
import 'package:fluxidi_tracking/vehicle_gallery_contract.dart'
    show publicMediaObjectIdentity;

const Key kCompanyPlanBrandKey = Key('company_plan_brand');
const Key kCompanyPlanAssignedCrewKey = Key('company_plan_assigned_crew');

class CompanyPlanCompanyBrand {
  const CompanyPlanCompanyBrand({
    required this.companyId,
    required this.companyName,
    this.logoUrl = '',
    this.initials = '',
  });

  final String companyId;
  final String companyName;
  final String logoUrl;
  final String initials;

  bool get hasLogo => logoUrl.trim().isNotEmpty;
  bool get hasName => companyName.trim().isNotEmpty;
}

class CompanyPlanVehicleMedia {
  const CompanyPlanVehicleMedia({
    required this.kind,
    this.photoUrl = '',
    this.assetPath = '',
    required this.fallbackIcon,
    required this.fit,
  });

  final CompanyPlanVehicleVisualKind kind;
  final String photoUrl;
  final String assetPath;
  final IconData fallbackIcon;
  final BoxFit fit;
}

class CompanyPlanDriverMedia {
  const CompanyPlanDriverMedia({
    required this.driverId,
    required this.displayName,
    this.photoUrl = '',
    this.initials = '?',
  });

  final String driverId;
  final String displayName;
  final String photoUrl;
  final String initials;

  bool get hasPhoto => photoUrl.trim().isNotEmpty;
}

class CompanyPlanAssignmentSnapshot {
  const CompanyPlanAssignmentSnapshot({
    this.driverId = '',
    this.driverName = '',
    this.driverPhotoUrl = '',
    this.vehicleId = '',
    this.vehicleName = '',
    this.vehiclePhotoUrl = '',
  });

  final String driverId;
  final String driverName;
  final String driverPhotoUrl;
  final String vehicleId;
  final String vehicleName;
  final String vehiclePhotoUrl;

  bool get hasDriver => driverId.trim().isNotEmpty;
  bool get hasVehicle => vehicleId.trim().isNotEmpty;
  bool get isAssigned => hasDriver || hasVehicle;
}

final _publicMediaScope = RegExp(r'public-media/([^/]+)/([^/]+)/');
final _localMediaCompany = RegExp(r'/local/media/([^/]+)/');

String companyPlanCompanyInitials(String name) => companyAgendaInitials(name);

bool companyPlanMediaMatchesScope(
  String raw, {
  String tenantId = '',
  String companyId = '',
}) {
  final url = raw.trim();
  if (url.isEmpty) return false;
  final public = _publicMediaScope.firstMatch(url.replaceAll('\\', '/'));
  if (public != null) {
    final tenant = public.group(1) ?? '';
    final company = public.group(2) ?? '';
    if (tenantId.isNotEmpty && tenant != tenantId.trim()) return false;
    if (companyId.isNotEmpty && company != companyId.trim()) return false;
    return true;
  }
  final local = _localMediaCompany.firstMatch(url);
  if (local != null && companyId.trim().isNotEmpty) {
    return local.group(1) == companyId.trim();
  }
  return companyPlanVehiclePhotoUrlIsAllowed(url);
}

String _firstText(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    final value = raw[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<String> _stringList(Object? raw) {
  if (raw is String && raw.trim().isNotEmpty) return <String>[raw.trim()];
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item != null && item.toString().trim().isNotEmpty) item.toString().trim(),
  ];
}

String companyPlanResolveDisplayUrl(
  String raw, {
  String tenantId = '',
  String companyId = '',
}) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (!companyPlanMediaMatchesScope(
        text,
        tenantId: tenantId,
        companyId: companyId,
      ) &&
      (text.contains('public-media/') || text.contains('/local/media/'))) {
    return '';
  }
  final https = resolvePublicHttpsMediaUrl(text);
  if (https.isNotEmpty &&
      companyPlanMediaMatchesScope(
        https,
        tenantId: tenantId,
        companyId: companyId,
      )) {
    return https;
  }
  final agenda = companyAgendaResolvedPhotoUrl(text);
  if (agenda.isEmpty) return '';
  if ((agenda.contains('public-media/') || agenda.contains('/local/media/')) &&
      !companyPlanMediaMatchesScope(
        agenda,
        tenantId: tenantId,
        companyId: companyId,
      )) {
    return '';
  }
  if (agenda.startsWith('http://') || agenda.startsWith('https://')) {
    if (!companyPlanVehiclePhotoUrlIsAllowed(agenda) &&
        !agenda.contains('/local/media/')) {
      return '';
    }
    return agenda;
  }
  return '';
}

CompanyPlanCompanyBrand resolveCompanyPlanBrand({
  CompanyOpsIdentity? identity,
  Map<String, dynamic>? profile,
  String companyId = '',
  String Function(String raw)? resolvePublicUrl,
}) {
  final fromIdentity = identity;
  if (fromIdentity != null && fromIdentity.hasCompany) {
    final logo = fromIdentity.logo;
    final logoUrl = logo.isCompanyOwned && logo.isRenderable &&
            logo.kind == CompanyLogoRefKind.network
        ? logo.ref
        : '';
    return CompanyPlanCompanyBrand(
      companyId: fromIdentity.companyId,
      companyName: fromIdentity.companyName,
      logoUrl: logoUrl,
      initials: companyPlanCompanyInitials(fromIdentity.companyName),
    );
  }
  if (profile != null) {
    final resolved = identityFromBusinessProfile(
      generation: 0,
      companyId: companyId,
      profile: profile,
      resolvePublicUrl: resolvePublicUrl ?? resolvePublicHttpsMediaUrl,
    );
    return resolveCompanyPlanBrand(identity: resolved, companyId: companyId);
  }
  return CompanyPlanCompanyBrand(
    companyId: companyId,
    companyName: '',
    initials: '?',
  );
}

List<String> companyPlanVehiclePhotoCandidates(Map<String, dynamic> raw) {
  final ordered = <String>[];
  final seen = <String>{};
  void add(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    final identity = publicMediaObjectIdentity(url);
    if (identity.isEmpty || !seen.add(identity)) return;
    ordered.add(url);
  }

  add(
    _firstText(raw, const [
      'primary_photo_url',
      'primaryPhotoUrl',
      'primary_photo_ref',
      'primaryPhotoRef',
      'public_photo_url',
      'publicPhotoUrl',
      'vehicle_photo_url',
      'vehiclePhotoUrl',
      'photo_url',
      'photoUrl',
      'photo_ref',
      'photoRef',
    ]),
  );
  for (final item in <String>[
    ..._stringList(raw['gallery_photo_urls']),
    ..._stringList(raw['galleryPhotoUrls']),
    ..._stringList(raw['gallery_photo_refs']),
    ..._stringList(raw['galleryPhotoRefs']),
  ]) {
    add(item);
  }
  return ordered;
}

Map<CompanyPlanVehicleCategory, String> companyPlanCategoryPhotoUrls({
  required List<Map<String, dynamic>> vehicles,
  String tenantId = '',
  String companyId = '',
}) {
  final out = <CompanyPlanVehicleCategory, String>{};
  for (final category in CompanyPlanVehicleCategory.values) {
    for (final vehicle in vehicles) {
      if (!companyAgendaVehicleIsActive(vehicle)) continue;
      if (classifyCompanyPlanVehicleCategory(vehicle) != category) continue;
      final media = resolveCompanyPlanVehicleMedia(
        vehicle: vehicle,
        tenantId: tenantId,
        companyId: companyId,
      );
      if (media.kind == CompanyPlanVehicleVisualKind.companyPhoto &&
          media.photoUrl.isNotEmpty) {
        out[category] = media.photoUrl;
        break;
      }
    }
  }
  return out;
}

Map<CompanyPlanVehicleCategory, int> companyPlanCategoryPassengerCaps({
  required List<Map<String, dynamic>> vehicles,
}) {
  final out = <CompanyPlanVehicleCategory, int>{};
  for (final vehicle in vehicles) {
    if (!companyAgendaVehicleIsActive(vehicle)) continue;
    final category = classifyCompanyPlanVehicleCategory(vehicle);
    if (category == null) continue;
    final cap = companyAgendaVehicleCapacity(vehicle);
    if (cap <= 0) continue;
    final previous = out[category];
    if (previous == null || cap > previous) {
      out[category] = cap;
    }
  }
  return out;
}

CompanyPlanVehicleMedia resolveCompanyPlanVehicleMedia({
  required Map<String, dynamic> vehicle,
  CompanyPlanVehicleType type = CompanyPlanVehicleType.sedan,
  CompanyPlanVehicleVisualContract contract =
      const CompanyPlanVehicleVisualContract(),
  String tenantId = '',
  String companyId = '',
}) {
  final category = companyPlanVehicleFallbackCategory(vehicle);
  final resolvedType = companyPlanVehicleTypeForCategory(category);
  for (final candidate in [
    ...companyPlanVehiclePhotoCandidates(vehicle),
    contract.vehiclePhotoUrl,
  ]) {
    final url = companyPlanResolveDisplayUrl(
      candidate,
      tenantId: tenantId,
      companyId: companyId,
    );
    if (url.isEmpty) continue;
    return CompanyPlanVehicleMedia(
      kind: CompanyPlanVehicleVisualKind.companyPhoto,
      photoUrl: url,
      assetPath: contract.genericAssetForCategory(category),
      fallbackIcon: companyPlanVehicleVectorIcon(resolvedType),
      fit: kCompanyPlanVehicleVisualFit,
    );
  }
  final generic = contract.genericAssetForCategory(category);
  if (generic.isNotEmpty) {
    return CompanyPlanVehicleMedia(
      kind: CompanyPlanVehicleVisualKind.genericCutout,
      assetPath: generic,
      fallbackIcon: companyPlanVehicleVectorIcon(resolvedType),
      fit: kCompanyPlanVehicleVisualFit,
    );
  }
  return CompanyPlanVehicleMedia(
    kind: CompanyPlanVehicleVisualKind.vectorFallback,
    fallbackIcon: companyPlanVehicleVectorIcon(type),
    fit: kCompanyPlanVehicleVisualFit,
  );
}

CompanyPlanDriverMedia resolveCompanyPlanDriverMedia({
  required Map<String, dynamic> driver,
  String tenantId = '',
  String companyId = '',
}) {
  final look = companyAgendaDriverLook(driver);
  final raw = _firstText(driver, const [
    'public_photo_url',
    'publicPhotoUrl',
    'driver_photo_url',
    'driverPhotoUrl',
    'public_portrait_url',
    'publicPortraitUrl',
    'profile_photo_url',
    'profilePhotoUrl',
    'avatar_url',
    'avatarUrl',
    'photo_url',
    'photoUrl',
  ]);
  final url = companyPlanResolveDisplayUrl(
    raw.isNotEmpty ? raw : look.photoUrl,
    tenantId: tenantId,
    companyId: companyId,
  );
  return CompanyPlanDriverMedia(
    driverId: look.driverId,
    displayName: look.displayName,
    photoUrl: url,
    initials: look.initials,
  );
}

CompanyPlanAssignmentSnapshot parseCompanyPlanAssignmentSnapshot(
  Map<String, dynamic> raw, {
  String tenantId = '',
  String companyId = '',
}) {
  final driverId = _firstText(raw, const [
    'assigned_driver_id',
    'assignedDriverId',
    'driver_id',
    'driverId',
  ]);
  final vehicleId = _firstText(raw, const [
    'assigned_vehicle_id',
    'assignedVehicleId',
    'vehicle_id',
    'vehicleId',
  ]);
  return CompanyPlanAssignmentSnapshot(
    driverId: driverId,
    driverName: () {
      final name = _firstText(raw, const [
        'assigned_driver_name',
        'assignedDriverName',
        'driver_name',
        'driverName',
        'display_name',
        'displayName',
      ]);
      return companyPlanLooksLikeInternalId(name) ? '' : name;
    }(),
    driverPhotoUrl: companyPlanResolveDisplayUrl(
      _firstText(raw, const [
        'driver_photo_url',
        'driverPhotoUrl',
        'assigned_driver_photo_url',
      ]),
      tenantId: tenantId,
      companyId: companyId,
    ),
    vehicleId: vehicleId,
    vehicleName: _firstText(raw, const [
      'assigned_vehicle_name',
      'assignedVehicleName',
      'vehicle_name',
      'vehicleName',
    ]),
    vehiclePhotoUrl: companyPlanResolveDisplayUrl(
      _firstText(raw, const [
        'vehicle_photo_url',
        'vehiclePhotoUrl',
        'public_photo_url',
        'assigned_vehicle_photo_url',
      ]),
      tenantId: tenantId,
      companyId: companyId,
    ),
  );
}

class CompanyPlanBrandMark extends StatelessWidget {
  const CompanyPlanBrandMark({
    super.key,
    required this.brand,
    this.size = 36,
  });

  final CompanyPlanCompanyBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: kCompanyPlanBrandKey,
      label: brand.hasName ? brand.companyName : brand.initials,
      child: SizedBox(
        width: size,
        height: size,
        child: brand.hasLogo
            ? ClipOval(
                child: Image.network(
                  brand.logoUrl,
                  fit: BoxFit.contain,
                  cacheWidth: 128,
                  cacheHeight: 128,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => _initials(theme),
                ),
              )
            : _initials(theme),
      ),
    );
  }

  Widget _initials(ThemeData theme) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        brand.initials.isEmpty ? '?' : brand.initials,
        style: theme.textTheme.labelLarge,
      ),
    );
  }
}

class CompanyPlanDriverAvatar extends StatelessWidget {
  const CompanyPlanDriverAvatar({
    super.key,
    required this.media,
    this.radius = 18,
  });

  final CompanyPlanDriverMedia media;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: media.displayName,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        backgroundImage: media.hasPhoto ? NetworkImage(media.photoUrl) : null,
        onBackgroundImageError: media.hasPhoto ? (_, _) {} : null,
        child: media.hasPhoto
            ? null
            : Text(
                media.initials,
                style: theme.textTheme.labelMedium,
              ),
      ),
    );
  }
}

class CompanyPlanVehicleThumb extends StatelessWidget {
  const CompanyPlanVehicleThumb({
    super.key,
    required this.media,
    this.width = 56,
    this.height = 36,
    this.semanticLabel = '',
  });

  final CompanyPlanVehicleMedia media;
  final double width;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: media.kind != CompanyPlanVehicleVisualKind.vectorFallback,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _child(),
        ),
      ),
    );
  }

  Widget _child() {
    switch (media.kind) {
      case CompanyPlanVehicleVisualKind.companyPhoto:
        return Image.network(
          media.photoUrl,
          fit: kCompanyPlanVehicleVisualFit,
          alignment: Alignment.center,
          cacheWidth: 512,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => media.assetPath.isEmpty
              ? Icon(media.fallbackIcon)
              : Image.asset(
                  media.assetPath,
                  fit: kCompanyPlanVehicleVisualFit,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) => Icon(media.fallbackIcon),
                ),
        );
      case CompanyPlanVehicleVisualKind.genericCutout:
        return Image.asset(
          media.assetPath,
          fit: kCompanyPlanVehicleVisualFit,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => Icon(media.fallbackIcon),
        );
      case CompanyPlanVehicleVisualKind.vectorFallback:
        return Icon(media.fallbackIcon);
    }
  }
}

class CompanyPlanAssignedCrew extends StatelessWidget {
  const CompanyPlanAssignedCrew({
    super.key,
    required this.snapshot,
    this.driver,
    this.vehicle,
    this.tenantId = '',
    this.companyId = '',
  });

  final CompanyPlanAssignmentSnapshot snapshot;
  final Map<String, dynamic>? driver;
  final Map<String, dynamic>? vehicle;
  final String tenantId;
  final String companyId;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.isAssigned) return const SizedBox.shrink();
    final driverMedia = driver != null
        ? resolveCompanyPlanDriverMedia(
            driver: driver!,
            tenantId: tenantId,
            companyId: companyId,
          )
        : CompanyPlanDriverMedia(
            driverId: snapshot.driverId,
            displayName: snapshot.driverName,
            photoUrl: snapshot.driverPhotoUrl,
            initials: companyAgendaInitials(
              snapshot.driverName.isEmpty ? snapshot.driverId : snapshot.driverName,
            ),
          );
    final vehicleMedia = vehicle == null
        ? CompanyPlanVehicleMedia(
            kind: snapshot.vehiclePhotoUrl.isEmpty
                ? CompanyPlanVehicleVisualKind.vectorFallback
                : CompanyPlanVehicleVisualKind.companyPhoto,
            photoUrl: snapshot.vehiclePhotoUrl,
            fallbackIcon: Icons.directions_car_outlined,
            fit: kCompanyPlanVehicleVisualFit,
          )
        : resolveCompanyPlanVehicleMedia(
            vehicle: vehicle!,
            tenantId: tenantId,
            companyId: companyId,
          );
    final rawName = driverMedia.displayName.isEmpty
        ? snapshot.driverName
        : driverMedia.displayName;
    final name = rawName.trim().isEmpty ||
            companyPlanLooksLikeInternalId(rawName)
        ? kCompanyAgendaDriverFallback.of(AppLanguage.nl)
        : rawName;
    final rawVehicle = snapshot.vehicleName.isNotEmpty
        ? snapshot.vehicleName
        : companyAgendaVehicleLabel(vehicle ?? const <String, dynamic>{});
    final vehicleName = companyPlanLooksLikeInternalId(rawVehicle)
        ? kCompanyAgendaVehicleFallback.of(AppLanguage.nl)
        : rawVehicle;
    return KeyedSubtree(
      key: ValueKey<String>(
        'crew-${snapshot.driverId}-${snapshot.vehicleId}',
      ),
      child: Row(
        key: kCompanyPlanAssignedCrewKey,
        children: [
          if (snapshot.hasDriver) CompanyPlanDriverAvatar(media: driverMedia),
          if (snapshot.hasDriver) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.hasDriver)
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (snapshot.hasVehicle)
                  Text(
                    vehicleName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (snapshot.hasVehicle)
            CompanyPlanVehicleThumb(
              media: vehicleMedia,
              semanticLabel: vehicleName,
            ),
        ],
      ),
    );
  }
}
