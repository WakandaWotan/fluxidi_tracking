// LIMOUSINE-MARKETPLACE-P2D4C1D — full-page Limousine-instellingen.
// Reuses the committed offer contract, fleet classification and pricing API.
// Does not invent a second vehicle schema or booking engine.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import '../vehicle_management_page.dart';
import 'limousine_brand_logo.dart';
import 'limousine_business_setup.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_cover_gallery_picker.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_hero_contract.dart';
import 'limousine_offer_binding.dart';
import 'limousine_offer_editor.dart';
import 'limousine_offers.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_profile_identity.dart';
import 'limousine_public_company_card.dart';
import 'limousine_public_cover_view.dart';
import 'limousine_quote_requests_nav.dart';
import 'limousine_setup_media_pick.dart';
import 'limousine_simple_offer_editor.dart';
import 'limousine_pricing_local_store.dart';
import 'limousine_pricing_overlay.dart';
import 'limousine_vehicle_persist.dart';
import 'limousine_vehicle_public_copy.dart';
import 'limousine_vehicle_public_copy_editor.dart';
import '../vehicle_gallery_contract.dart';

export 'limousine_setup_media_pick.dart' show LimousineSetupPickedImage;

typedef LimousinePricingLoader = Future<Map<String, dynamic>> Function();
typedef LimousinePricingSaver =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> section);
typedef LimousineSetupImagePicker =
    Future<LimousineSetupPickedImage?> Function();
typedef LimousineSetupLostImageRecoverer =
    Future<LimousineSetupPickedImage?> Function();
typedef LimousineSetupMediaUploader =
    Future<Map<String, dynamic>> Function({
      required String mediaType,
      required String filePath,
      required String filename,
      Uint8List? fileBytes,
    });

class LimousineBusinessSetupPage extends StatefulWidget {
  const LimousineBusinessSetupPage({
    super.key,
    this.loadPricing,
    this.savePricing,
    this.vehicles,
    this.knownClassIds,
    this.language,
    this.backgroundColor,
    this.entryEnabled = false,
    this.companyName = '',
    this.logoUrl = '',
    this.logoImage,
    this.onConfigureVehicle,
    this.persistVehicles,
    this.pickImage,
    this.recoverLostImage,
    this.uploadMedia,
  });

  final LimousinePricingLoader? loadPricing;
  final LimousinePricingSaver? savePricing;
  final List<VehicleProfile>? vehicles;
  final List<String>? knownClassIds;
  final AppLanguage? language;
  final Color? backgroundColor;
  final bool entryEnabled;
  final String companyName;
  final String logoUrl;
  final ImageProvider? logoImage;
  final VoidCallback? onConfigureVehicle;
  final Future<void> Function(List<VehicleProfile> vehicles)? persistVehicles;
  final LimousineSetupImagePicker? pickImage;
  final LimousineSetupLostImageRecoverer? recoverLostImage;
  final LimousineSetupMediaUploader? uploadMedia;

  @override
  State<LimousineBusinessSetupPage> createState() =>
      _LimousineBusinessSetupPageState();
}

class _LimousineBusinessSetupPageState
    extends State<LimousineBusinessSetupPage> {
  final _scroll = ScrollController();
  final _sectionKeys = <LimousineBusinessSetupSection, GlobalKey>{
    for (final section in LimousineBusinessSetupSection.values)
      section: GlobalKey(),
  };
  final _hourlyKey = GlobalKey();
  final _advancedKey = GlobalKey();

  late List<VehicleProfile> _vehicles;
  late List<VehicleProfile> _vehiclesSnapshot;
  final List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];
  late final LimousineLocalizedField _publicTitle;
  late final LimousineLocalizedField _publicDescription;

  bool _sectionEnabled = false;
  String _currency = 'EUR';
  int _revision = 0;
  bool _dirty = false;
  bool _saving = false;
  bool _loading = false;
  bool _advancedOpen = false;
  int _editEpoch = 0;
  int _saveEpoch = 0;
  String? _status;
  String? _error;
  late String _primaryLang;
  LimousineHeroSelection _hero = const LimousineHeroSelection();
  LimousineHeroSelection _publishedHero = const LimousineHeroSelection();
  Map<String, String> _publishedPublicTitle = <String, String>{};
  Map<String, String> _publishedPublicDescription = <String, String>{};
  Map<String, Map<String, String>> _vehiclePublicCopy =
      <String, Map<String, String>>{};
  Map<String, Map<String, String>> _publishedVehiclePublicCopy =
      <String, Map<String, String>>{};
  LimousineProfileLogoSelection _logo = const LimousineProfileLogoSelection();
  LimousineProfileLogoSelection _publishedLogo =
      const LimousineProfileLogoSelection();
  bool _heroUploading = false;
  bool _logoUploading = false;
  int _coverWriteEpoch = 0;
  int _logoWriteEpoch = 0;
  String? _coverStatus;
  String? _coverError;
  String? _logoStatus;
  String? _logoError;
  final ImagePicker _imagePicker = ImagePicker();

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;
  String _t(LocalizedText text) => text.of(_lang);
  String get _primaryLangCode => limousineBusinessSetupPrimaryLangCode(_lang);

  List<String> get _knownClasses =>
      widget.knownClassIds ??
      appConfig.enabledLimousineServiceClasses
          .map((item) => item.id)
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _vehicles = List<VehicleProfile>.from(
      widget.vehicles ?? vehiclesNotifier.value,
    );
    _vehiclesSnapshot = List<VehicleProfile>.from(_vehicles);
    _publicTitle = LimousineLocalizedField(const <String, String>{});
    _publicDescription = LimousineLocalizedField(const <String, String>{});
    _primaryLang = _primaryLangCode;
    if (widget.vehicles == null) {
      vehiclesNotifier.addListener(_onVehicles);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_recoverLostSetupPick());
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    if (widget.vehicles == null) {
      vehiclesNotifier.removeListener(_onVehicles);
    }
    _scroll.dispose();
    _publicTitle.dispose();
    _publicDescription.dispose();
    super.dispose();
  }

  void _onVehicles() {
    if (!mounted || widget.vehicles != null) return;
    setState(() {
      _vehicles = List<VehicleProfile>.from(vehiclesNotifier.value);
    });
  }

  void _markDirty() {
    _editEpoch += 1;
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
    _status = null;
  }

  LimousineUxTokens get _tokens {
    final palette = paletteForBusinessTheme(businessThemeNotifier.value);
    final base = LimousineUxTokens.fromBusiness(palette);
    if (widget.backgroundColor == null) return base;
    return LimousineUxTokens(
      background: widget.backgroundColor!,
      surface: base.surface,
      surfaceAlt: base.surfaceAlt,
      onSurface: base.onSurface,
      muted: base.muted,
      border: base.border,
      gold: base.gold,
      danger: base.danger,
      fieldFill: base.fieldFill,
      onHero: base.onHero,
      heroScrim: base.heroScrim,
      isDark: base.isDark,
    );
  }

  Color get _successColor =>
      paletteForBusinessTheme(businessThemeNotifier.value).success;

  LimousineBusinessSetupReadiness get _readiness {
    return limousineBusinessSetupReadiness(
      vehicles: _vehicles,
      offers: _offers,
      publicTitle: _publicTitle.toJson(),
      publicDescription: _publicDescription.toJson(),
      knownClassIds: _knownClasses,
      entryEnabled: widget.entryEnabled,
      sectionEnabled: _sectionEnabled,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loadPricing ?? () => fetchAdminLimousinePricing();
      final data = await loader();
      if (!mounted) return;
      await limousinePricingLocalStore.warm();
      if (!mounted) return;
      final rawSection = (data['limousine'] is Map)
          ? Map<String, dynamic>.from(data['limousine'] as Map)
          : <String, dynamic>{};
      final section = limousineMergePricingOverlay(
        section: rawSection,
        overlay: limousinePricingLocalStore.peekMerged(
          limousineDefaultLocalPricingScopeKeys(),
        ),
      );
      final offers = (section['offers'] is List)
          ? (section['offers'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      rememberLimousineQuoteRequestsConfirmedOffers(offers);
      setState(() {
        _offers
          ..clear()
          ..addAll(offers);
        _sectionEnabled = section['enabled'] == true;
        _currency = limousineCurrencyOf(section['currency']).isEmpty
            ? 'EUR'
            : limousineCurrencyOf(section['currency']);
        _revision = int.tryParse('${section['source_revision'] ?? 0}') ?? 0;
        if (_editEpoch == 0) {
          _applyPersistedPublicText(section);
          _applyPersistedSelectedVehicleIds(section);
          if (_coverWriteEpoch == 0 && !_heroUploading) {
            _applyPersistedHero(section, fromLoad: true);
          }
          if (_logoWriteEpoch == 0 && !_logoUploading) {
            _applyPersistedLogo(section, fromLoad: true);
          }
          _applyPersistedVehiclePublicCopy(section);
          _vehiclesSnapshot = List<VehicleProfile>.from(_vehicles);
        }
        _dirty = false;
        _seedPublicText();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = limousineFriendlyCompanyError(error, language: _lang);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _seedPublicText() {
    if (_offers.isEmpty) return;
    final first = _offers.first;
    final title = limousineLocalizedOf(first['title']);
    final description = limousineLocalizedOf(first['description']);
    for (final lang in const ['nl', 'en', 'fr', 'es']) {
      if (_publicTitle.controllers[lang]!.text.trim().isEmpty) {
        _publicTitle.controllers[lang]!.text = title[lang] ?? '';
      }
      if (_publicDescription.controllers[lang]!.text.trim().isEmpty) {
        _publicDescription.controllers[lang]!.text = description[lang] ?? '';
      }
    }
  }

  void _applyPersistedPublicText(Map<String, dynamic> section) {
    final title = limousineLocalizedOf(section['public_title']);
    final description = limousineLocalizedOf(section['public_description']);
    for (final lang in const ['nl', 'en', 'fr', 'es']) {
      final nextTitle = (title[lang] ?? '').trim();
      if (nextTitle.isNotEmpty) {
        _publicTitle.controllers[lang]!.text = nextTitle;
      }
      final nextDescription = (description[lang] ?? '').trim();
      if (nextDescription.isNotEmpty) {
        _publicDescription.controllers[lang]!.text = nextDescription;
      }
    }
    final publishedTitle = limousineLocalizedOf(
      section['published_public_title'],
    );
    final publishedDescription = limousineLocalizedOf(
      section['published_public_description'],
    );
    final hasPublishedTitle =
        section.containsKey('published_public_title') ||
        section.containsKey('publishedPublicTitle');
    final hasPublishedDescription =
        section.containsKey('published_public_description') ||
        section.containsKey('publishedPublicDescription');
    _publishedPublicTitle = hasPublishedTitle ? publishedTitle : title;
    _publishedPublicDescription = hasPublishedDescription
        ? publishedDescription
        : description;
  }

  void _applyPersistedVehiclePublicCopy(Map<String, dynamic> section) {
    _vehiclePublicCopy = limousineVehiclePublicCopyById(
      section[kLimousineVehiclePublicCopyKey] ??
          section['limousineVehiclePublicCopy'],
    );
    _publishedVehiclePublicCopy = limousineVehiclePublicCopyById(
      section[kLimousinePublishedVehiclePublicCopyKey] ??
          section['publishedLimousineVehiclePublicCopy'],
    );
  }

  void _rememberVehiclePublicCopyOverlay({required bool updatePublished}) {
    _rememberPricingOverlay(updatePublished: updatePublished);
  }

  Map<String, dynamic> _displayPayload({required bool publish}) {
    return limousinePublicDisplayPayload(
      publish: publish,
      title: _publicTitle.toJson(),
      description: _publicDescription.toJson(),
      hero: _hero.toSectionJson(),
      publishedTitle: _publishedPublicTitle,
      publishedDescription: _publishedPublicDescription,
      publishedHero: _publishedHero.toSectionJson(),
      logo: _logo.toSectionJson(),
      publishedLogo: _publishedLogo.toSectionJson(),
      taxiHeroUrls: _taxiHeroUrls,
    );
  }

  List<Map<String, dynamic>> _authoritativePublishedOffers() {
    return [
      for (final offer in limousinePreparePublishOffers(
        _offers,
        vehicles: _vehicles,
        knownClassIds: _knownClasses,
      ))
        if (offer['published'] == true && offer['enabled'] != false)
          Map<String, dynamic>.from(offer),
    ];
  }

  void _rememberPricingOverlay({required bool updatePublished}) {
    limousinePricingLocalStore.writeVehiclePublicCopy(
      scopeKeys: limousineDefaultLocalPricingScopeKeys(),
      working: _vehiclePublicCopy,
      published: updatePublished
          ? _vehiclePublicCopy
          : _publishedVehiclePublicCopy,
      updatePublished: updatePublished,
      revision: _revision,
    );
    limousinePricingLocalStore.writeOverlay(
      scopeKeys: limousineDefaultLocalPricingScopeKeys(),
      fields: limousinePublishedVisitingCardOverlayFields(
        displayPayload: _displayPayload(publish: updatePublished),
        publishedOffers: updatePublished
            ? _authoritativePublishedOffers()
            : const <Map<String, dynamic>>[],
        updatePublished: updatePublished,
      ),
      revision: _revision,
    );
  }

  Future<void> _persistWorkingDraft() async {
    _rememberPricingOverlay(updatePublished: false);
    _markDirty();
    await _persist(publish: false);
  }

  Future<void> _openVehiclePublicCopy(VehicleProfile vehicle) async {
    final vehicleId = limousineCanonicalVehicleId(vehicle.id);
    final saved = _vehiclePublicCopy[vehicleId] ?? const <String, String>{};
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return LimousineVehiclePublicCopyDialog(
          initial: saved,
          language: _lang,
          primaryLang: _primaryLang,
          backgroundColor: widget.backgroundColor,
        );
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      final next = limousineCloneVehiclePublicCopy(_vehiclePublicCopy);
      if (limousinePublicCopyHasText(result)) {
        next[vehicleId] = result;
      } else {
        next.remove(vehicleId);
      }
      _vehiclePublicCopy = next;
    });
    _rememberVehiclePublicCopyOverlay(updatePublished: false);
    _markDirty();
    await _persist(publish: false);
  }

  Iterable<String> get _taxiHeroUrls {
    final profile = localBackendBusinessProfileNotifier.value;
    return <String>[
      if ((profile?.publicHeroPhotoUrl ?? '').startsWith('https://'))
        profile!.publicHeroPhotoUrl,
    ];
  }

  void _applyPersistedHero(
    Map<String, dynamic> section, {
    bool fromLoad = false,
  }) {
    final incoming = limousineSanitizeProfileCover(
      limousineHeroFromSection(section),
      taxiHeroUrls: _taxiHeroUrls,
    );
    if (_coverWriteEpoch > 0 && !incoming.hasPhoto && _hero.hasPhoto) {
      return;
    }
    _hero = incoming;
    if (limousineHasPublishedProfileCoverKey(section)) {
      final publishedRaw = limousinePublishedProfileCoverRaw(section);
      _publishedHero = publishedRaw is Map
          ? limousineSanitizeProfileCover(
              limousineHeroFromSection(<String, dynamic>{
                kLimousineProfileCoverKey: publishedRaw,
                'limousine_hero': publishedRaw,
              }),
              taxiHeroUrls: _taxiHeroUrls,
            )
          : limousineSanitizeProfileCover(
              limousineHeroFromSection(<String, dynamic>{
                'limousine_hero_url': publishedRaw,
              }),
              taxiHeroUrls: _taxiHeroUrls,
            );
      return;
    }
    if (fromLoad) {
      _publishedHero = _hero;
    }
  }

  void _applyPersistedLogo(
    Map<String, dynamic> section, {
    bool fromLoad = false,
  }) {
    final incoming = limousineSanitizeProfileLogo(
      limousineLogoFromSection(section),
    );
    if ((_logoWriteEpoch > 0 || _logoUploading) &&
        !incoming.hasOverride &&
        _logo.hasOverride) {
      return;
    }
    _logo = incoming;
    if (limousineHasPublishedProfileLogoKey(section)) {
      _publishedLogo = limousineSanitizeProfileLogo(
        limousinePublishedLogoFromSection(section),
      );
      return;
    }
    if (fromLoad) {
      _publishedLogo = _logo;
    }
  }

  String get _companyLogoUrl {
    if (widget.logoUrl.startsWith('https://')) return widget.logoUrl;
    final url = localBackendBusinessProfileNotifier.value?.publicLogoUrl ?? '';
    return url.startsWith('https://') ? url : '';
  }

  String get _effectiveLogoUrl {
    return limousineEffectiveLogoUrl(
      overrideUrl: _logo.photoUrl,
      companyLogoUrl: _companyLogoUrl,
    );
  }

  List<String> get _fallbackHeroUrls {
    return [
      for (final vehicle in limousineSetupLimousineVehicles(_vehicles))
        if ((vehicle.publicPhotoUrl ?? '').startsWith('https://'))
          vehicle.publicPhotoUrl!
        else if (vehicle.primaryPhotoRef.startsWith('https://'))
          vehicle.primaryPhotoRef,
    ];
  }

  LimousineHeroSelection get _resolvedHero {
    if (_hero.hasPhoto) return _hero;
    return resolveLimousineHero(
      source: _hero.toSectionJson(),
      fallbackVehiclePhotoUrls: _fallbackHeroUrls,
    ).copyWith(alignment: _hero.alignment);
  }

  bool get _setupMediaBusy => _heroUploading || _logoUploading;

  Future<LimousineSetupPickedImage?> _pickSetupImage() async {
    final hook = widget.pickImage;
    if (hook != null) {
      final picked = await hook();
      if (picked != null) return picked;
      final recover = widget.recoverLostImage;
      if (recover != null) return recover();
      return null;
    }
    return limousinePickGalleryImage(picker: _imagePicker);
  }

  Future<void> _recoverLostSetupPick() async {
    if (widget.pickImage != null) return;
    if (_setupMediaBusy) return;
    final lost = await limousineRecoverLostPickedImage(_imagePicker);
    if (lost == null || !mounted || _setupMediaBusy) return;
    final kind =
        limousineSetupPendingMediaKind ?? LimousineSetupMediaKind.cover;
    _beginSetupMediaUpload(kind);
    try {
      final bytes = await limousineReadXFileBytes(lost);
      await _completeSetupMediaUpload(
        LimousineSetupPickedImage(
          path: lost.path,
          name: lost.name,
          bytes: bytes,
        ),
        kind,
      );
    } catch (error) {
      if (mounted) _setSetupMediaFailure(kind, error);
    } finally {
      limousineSetupPendingMediaKind = null;
      if (mounted) _endSetupMediaUpload(kind);
    }
  }

  Future<Map<String, dynamic>> _sendSetupMedia({
    required String mediaType,
    required String filename,
    Uint8List? fileBytes,
    String? entityId,
    String? mediaId,
  }) {
    final hook = widget.uploadMedia;
    if (hook != null) {
      return hook(
        mediaType: mediaType,
        filePath: '',
        filename: filename,
        fileBytes: fileBytes,
      );
    }
    final scopeId = resolveActiveCompanyIdForFleetUi();
    if (scopeId == null || scopeId.isEmpty) {
      throw const LimousineSetupMediaFailure(
        phase: 'tenant-scope',
        kind: LimousineSetupMediaKind.cover,
        code: 'missing_tenant_scope',
      );
    }
    return uploadPublicPartnerMedia(
      tenantId: scopeId,
      companyId: scopeId,
      mediaType: mediaType,
      entityId: entityId,
      mediaId: mediaId,
      filePath: (fileBytes != null && fileBytes.isNotEmpty) ? null : '',
      fileBytes: fileBytes,
      filename: filename,
      contentType: fileBytes == null
          ? null
          : limousineDetectImageMime(fileBytes),
    );
  }

  Future<Map<String, dynamic>> _uploadSetupMedia({
    required LimousineSetupMediaKind kind,
    required String mediaType,
    required String filename,
    Uint8List? fileBytes,
  }) async {
    final mime = fileBytes == null ? '' : limousineDetectImageMime(fileBytes);
    final bytes = fileBytes?.length ?? 0;
    final hasTenant = (resolveActiveCompanyIdForFleetUi() ?? '').isNotEmpty;
    final hasAuth = hasCompanyOwnerAuthContext();
    final isHook = widget.uploadMedia != null;
    if (!isHook) {
      limousineLogSetupMedia(
        kind: kind,
        phase: 'upload',
        mime: mime,
        bytes: bytes,
        hasAuth: hasAuth,
        hasTenant: hasTenant,
        route: mediaType,
      );
      if (!hasTenant) {
        throw LimousineSetupMediaFailure(
          phase: 'tenant-scope',
          kind: kind,
          code: 'missing_tenant_scope',
          mime: mime,
          bytes: bytes,
          hasAuth: hasAuth,
          hasTenant: false,
        );
      }
      if (!hasAuth) {
        throw LimousineSetupMediaFailure(
          phase: 'auth',
          kind: kind,
          code: 'missing_company_session',
          mime: mime,
          bytes: bytes,
          hasAuth: false,
          hasTenant: hasTenant,
        );
      }
    }
    try {
      return await limousineSendSetupMediaWithFallback(
        kind: kind,
        dedicatedMediaType: mediaType,
        newMediaId: newVehicleGalleryMediaId,
        send: ({required mediaType, entityId, mediaId}) async {
          if (!isHook && entityId != null) {
            limousineLogSetupMedia(
              kind: kind,
              phase: 'fallback-vehicle-photo',
              mime: mime,
              bytes: bytes,
              hasAuth: hasAuth,
              hasTenant: hasTenant,
              route: mediaType,
            );
          }
          try {
            final uploaded = await _sendSetupMedia(
              mediaType: mediaType,
              filename: filename,
              fileBytes: fileBytes,
              entityId: entityId,
              mediaId: mediaId,
            );
            if (!isHook) {
              limousineLogSetupMedia(
                kind: kind,
                phase: entityId == null ? 'upload-ok' : 'fallback-ok',
                mime: mime,
                bytes: bytes,
                status: 200,
                hasAuth: hasAuth,
                hasTenant: hasTenant,
                urlPresent: limousineHeroRefIsDurable(
                  (uploaded['url'] ?? '').toString(),
                ),
                route: mediaType,
              );
            }
            return uploaded;
          } catch (error) {
            if (!isHook) {
              limousineLogSetupMedia(
                kind: kind,
                phase: 'upload-http',
                mime: mime,
                bytes: bytes,
                status: limousineSetupMediaHttpStatus(error),
                code: limousineSetupMediaHttpErrorCode(error),
                hasAuth: hasAuth,
                hasTenant: hasTenant,
                route: mediaType,
              );
            }
            rethrow;
          }
        },
      );
    } catch (error) {
      if (error is LimousineSetupMediaFailure) rethrow;
      throw LimousineSetupMediaFailure(
        phase: 'upload',
        kind: kind,
        code: limousineSetupMediaHttpErrorCode(error).isNotEmpty
            ? limousineSetupMediaHttpErrorCode(error)
            : error.toString(),
        httpStatus: limousineSetupMediaHttpStatus(error),
        mime: mime,
        bytes: bytes,
        hasAuth: hasAuth,
        hasTenant: hasTenant,
      );
    }
  }

  void _beginSetupMediaUpload(LimousineSetupMediaKind kind) {
    setState(() {
      if (kind == LimousineSetupMediaKind.cover) {
        _heroUploading = true;
        _coverError = null;
        _coverStatus = _t(kLimousineBusinessSetupCoverUploading);
      } else {
        _logoUploading = true;
        _logoError = null;
        _logoStatus = _t(kLimousineBusinessSetupLogoUploading);
      }
      _error = null;
    });
  }

  void _endSetupMediaUpload(LimousineSetupMediaKind kind) {
    setState(() {
      if (kind == LimousineSetupMediaKind.cover) {
        _heroUploading = false;
      } else {
        _logoUploading = false;
      }
    });
  }

  void _cancelSetupMediaUpload(LimousineSetupMediaKind kind) {
    setState(() {
      if (kind == LimousineSetupMediaKind.cover) {
        _heroUploading = false;
        _coverStatus = null;
      } else {
        _logoUploading = false;
        _logoStatus = null;
      }
    });
  }

  void _setSetupMediaFailure(LimousineSetupMediaKind kind, Object error) {
    final message = limousineSetupMediaFailureMessage(
      kind: kind,
      error: error,
      language: _lang,
    );
    limousineLogSetupMedia(
      kind: kind,
      phase: error is LimousineSetupMediaFailure ? error.phase : 'error',
      code: error is LimousineSetupMediaFailure
          ? error.code
          : error is LimousinePickedMediaException
          ? error.code
          : limousineSetupMediaHttpErrorCode(error),
      status: error is LimousineSetupMediaFailure
          ? error.httpStatus
          : limousineSetupMediaHttpStatus(error),
    );
    setState(() {
      if (kind == LimousineSetupMediaKind.cover) {
        _coverError = message;
        _coverStatus = null;
      } else {
        _logoError = message;
        _logoStatus = null;
      }
      _error = message;
      _status = null;
    });
  }

  Future<void> _completeSetupMediaUpload(
    LimousineSetupPickedImage picked,
    LimousineSetupMediaKind kind,
  ) async {
    final target = limousineSetupMediaTarget(kind);
    final prepared = await limousinePreparePickedImageUpload(
      picked,
      target: target,
    );
    if (!mounted) return;
    final uploaded = await _uploadSetupMedia(
      kind: kind,
      mediaType: target.mediaType,
      filename: prepared.filename,
      fileBytes: prepared.bytes,
    );
    final url = (uploaded['url'] ?? '').toString().trim();
    if (!limousineHeroRefIsDurable(url)) {
      throw LimousineSetupMediaFailure(
        phase: 'response',
        kind: kind,
        code: 'upload-not-durable',
        mime: prepared.contentType,
        bytes: prepared.bytes.length,
        hasAuth: hasCompanyOwnerAuthContext(),
        hasTenant: (resolveActiveCompanyIdForFleetUi() ?? '').isNotEmpty,
        urlPresent: false,
      );
    }
    if (kind == LimousineSetupMediaKind.logo) {
      final safe = limousineSanitizeProfileLogoOverrideUrl(url);
      if (safe.isEmpty) {
        throw const LimousinePickedMediaException('upload-not-durable');
      }
      _logoWriteEpoch += 1;
      setState(() {
        _logo = LimousineProfileLogoSelection(
          photoUrl: safe,
          sourceRevision: _logo.sourceRevision + 1,
          explicitOverride: true,
        );
        _logoError = null;
        _logoStatus = _t(kLimousineBusinessSetupLogoUploadSuccess);
        _error = null;
      });
    } else {
      _coverWriteEpoch += 1;
      setState(() {
        _hero = LimousineHeroSelection(
          photoUrl: url,
          sourceKind: kLimousineHeroSourceUpload,
          alignment: _hero.alignment,
          sourceRevision: _hero.sourceRevision + 1,
          explicit: true,
        );
        _coverError = null;
        _coverStatus = _t(kLimousineBusinessSetupCoverUploadSuccess);
        _error = null;
      });
    }
    try {
      await _persistWorkingDraft();
    } catch (error) {
      throw LimousineSetupMediaFailure(
        phase: 'persist',
        kind: kind,
        code: limousineSetupMediaHttpErrorCode(error).isNotEmpty
            ? limousineSetupMediaHttpErrorCode(error)
            : 'draft-persist-failed',
        httpStatus: limousineSetupMediaHttpStatus(error),
        mime: prepared.contentType,
        bytes: prepared.bytes.length,
        hasAuth: hasCompanyOwnerAuthContext(),
        hasTenant: (resolveActiveCompanyIdForFleetUi() ?? '').isNotEmpty,
        urlPresent: true,
      );
    }
  }

  Future<void> _pickAndUploadSetupMedia(LimousineSetupMediaKind kind) async {
    if (_setupMediaBusy) return;
    limousineSetupPendingMediaKind = kind;
    _beginSetupMediaUpload(kind);
    try {
      final picked = await _pickSetupImage();
      if (picked == null) {
        if (mounted) _cancelSetupMediaUpload(kind);
        return;
      }
      await _completeSetupMediaUpload(picked, kind);
    } catch (error) {
      if (mounted) _setSetupMediaFailure(kind, error);
    } finally {
      limousineSetupPendingMediaKind = null;
      if (mounted) _endSetupMediaUpload(kind);
    }
  }

  Future<void> _uploadLimousineHero() {
    return _pickAndUploadSetupMedia(LimousineSetupMediaKind.cover);
  }

  Future<void> _uploadLimousineLogo() {
    return _pickAndUploadSetupMedia(LimousineSetupMediaKind.logo);
  }

  void _clearLimousineLogoOverride() {
    if (!_logo.hasOverride) return;
    _logoWriteEpoch += 1;
    setState(() {
      _logo = const LimousineProfileLogoSelection();
      _logoStatus = null;
      _logoError = null;
    });
    _persistWorkingDraft();
  }

  Future<void> _pickHeroFromGallery() async {
    if (_heroUploading) return;
    final items = limousineCoverGalleryItems(_vehicles);
    if (items.isEmpty || !mounted) return;
    final selected = await showLimousineCoverGalleryPicker(
      context: context,
      items: items,
      tokens: _tokens,
      language: _lang,
      selectedUrl: _hero.photoUrl,
    );
    if (selected == null || !mounted) return;
    final url = selected.url.trim();
    if (!limousineHeroRefIsDurable(url)) {
      setState(() {
        _coverError = _t(kLimousineBusinessSetupCoverUploadFailed);
        _coverStatus = null;
        _error = _t(kLimousineBusinessSetupCoverUploadFailed);
        _status = null;
      });
      return;
    }
    _coverWriteEpoch += 1;
    setState(() {
      _hero = LimousineHeroSelection(
        photoUrl: url,
        sourceKind: kLimousineHeroSourceVehicleMedia,
        vehicleId: selected.vehicleId,
        alignment: _hero.alignment,
        sourceRevision: _hero.sourceRevision + 1,
        explicit: true,
      );
      _coverError = null;
      _coverStatus = _t(kLimousineBusinessSetupCoverUploadSuccess);
      _error = null;
      _status = _t(kLimousineBusinessSetupCoverUploadSuccess);
    });
    await _persistWorkingDraft();
  }

  void _setHeroAlignment(String alignment) {
    setState(() {
      _hero = _hero.copyWith(alignment: alignment);
    });
    _markDirty();
  }

  void _applyPersistedSelectedVehicleIds(Map<String, dynamic> section) {
    if (!section.containsKey('selected_vehicle_ids') &&
        !section.containsKey('selectedVehicleIds')) {
      return;
    }
    final raw =
        section['selected_vehicle_ids'] ?? section['selectedVehicleIds'];
    if (raw is! List) return;
    final ids = <String>{
      for (final item in raw)
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    };
    if (ids.isEmpty) return;
    var changed = false;
    final next = _vehicles
        .map((vehicle) {
          if (!ids.contains(vehicle.id.trim())) return vehicle;
          if (limousineVehicleAppearsInLimousinePreview(vehicle))
            return vehicle;
          changed = true;
          final classId = limousineOfferToken(vehicle.serviceClassId).isEmpty
              ? (_knownClasses.isEmpty ? '' : _knownClasses.first)
              : vehicle.serviceClassId;
          return vehicle.copyWith(
            serviceCategory: 'limousine',
            serviceClassId: classId,
          );
        })
        .toList(growable: false);
    if (!changed) return;
    _vehicles = next;
    if (widget.vehicles == null) {
      for (final vehicle in next) {
        updateVehicle(vehicle.id, vehicle);
      }
    }
  }

  void _restoreVehicleSelectionFromSnapshot() {
    final originalById = <String, VehicleProfile>{
      for (final vehicle in _vehiclesSnapshot) vehicle.id: vehicle,
    };
    final restored = _vehicles
        .map((current) {
          final original = originalById[current.id];
          if (original == null) return current;
          return current.copyWith(
            serviceCategory: original.serviceCategory,
            serviceClassId: original.serviceClassId,
          );
        })
        .toList(growable: false);
    _vehicles = restored;
    if (widget.vehicles == null) {
      for (final vehicle in restored) {
        updateVehicle(vehicle.id, vehicle);
      }
    }
  }

  Future<void> _persistFleet() async {
    final hook = widget.persistVehicles;
    if (hook != null) {
      await hook(List<VehicleProfile>.from(_vehicles));
      return;
    }
    if (widget.vehicles != null) return;
    for (final vehicle in _vehicles) {
      updateVehicle(vehicle.id, vehicle);
    }
    await syncLocalCompanyInventoryToBackend(reason: 'limousine_setup_save');
  }

  Future<Map<String, dynamic>> _saveOffers({required bool publish}) {
    _applyPublicTextToOffers();
    final offers = publish
        ? limousinePreparePublishOffers(
            _offers,
            vehicles: _vehicles,
            knownClassIds: _knownClasses,
          )
        : limousinePrepareDraftOffers(_offers);
    final payload = <String, dynamic>{
      'enabled': publish ? true : _sectionEnabled,
      'currency': _currency,
      'source_revision': _revision,
      'offers': offers,
      'selected_vehicle_ids': limousineSelectedVehicleIds(_vehicles),
      ...limousinePublicDisplayPayload(
        publish: publish,
        title: _publicTitle.toJson(),
        description: _publicDescription.toJson(),
        hero: _hero.toSectionJson(),
        publishedTitle: _publishedPublicTitle,
        publishedDescription: _publishedPublicDescription,
        publishedHero: _publishedHero.toSectionJson(),
        logo: _logo.toSectionJson(),
        publishedLogo: _publishedLogo.toSectionJson(),
        taxiHeroUrls: _taxiHeroUrls,
      ),
      ...limousineVehiclePublicCopyPayload(
        publish: publish,
        working: _vehiclePublicCopy,
        published: _publishedVehiclePublicCopy,
      ),
    };
    final saver =
        widget.savePricing ?? (section) => saveAdminLimousinePricing(section);
    return saver(payload);
  }

  Future<void> _persist({required bool publish}) async {
    if (_saving) return;
    if (publish &&
        !limousineBusinessSetupPublishAllowed(
          saving: false,
          readiness: _readiness,
        )) {
      setState(() {
        _error = _t(kLimousineRequestIncompleteHint);
      });
      _scrollToFirstGap();
      return;
    }
    if (!publish &&
        !limousineBusinessSetupDraftSaveAllowed(dirty: _dirty, saving: false)) {
      return;
    }
    final startedAt = _editEpoch;
    final saveId = ++_saveEpoch;
    _saving = true;
    setState(() {
      _error = null;
      _status = null;
    });
    _rememberVehiclePublicCopyOverlay(updatePublished: false);
    try {
      await _persistFleet();
      if (!mounted || saveId != _saveEpoch) return;
      if (startedAt != _editEpoch) {
        setState(() {
          _saving = false;
          _status = _t(kLimousineBusinessSetupUnsaved);
        });
        return;
      }
      final data = await _saveOffers(publish: publish);
      if (!mounted || saveId != _saveEpoch) return;
      if (startedAt != _editEpoch) {
        setState(() {
          _saving = false;
          _status = _t(kLimousineBusinessSetupUnsaved);
        });
        return;
      }
      final offers = publish
          ? limousinePreparePublishOffers(
              _offers,
              vehicles: _vehicles,
              knownClassIds: _knownClasses,
            )
          : limousinePrepareDraftOffers(_offers);
      final section = (data['limousine'] is Map)
          ? Map<String, dynamic>.from(data['limousine'] as Map)
          : <String, dynamic>{};
      final responseOffers = (section['offers'] is List)
          ? (section['offers'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : offers;
      final visibleOffers = limousineKeepAuthoritativeOffers(
        sent: offers,
        server: responseOffers,
      );
      rememberLimousineQuoteRequestsConfirmedOffers(visibleOffers);
      final visible = publish && limousinePricingPublishConfirmedVisible(data);
      setState(() {
        _offers
          ..clear()
          ..addAll(
            visibleOffers.map((offer) => Map<String, dynamic>.from(offer)),
          );
        _revision = limousinePricingResponseRevision(data, fallback: _revision);
        if (section.containsKey(kLimousineProfileCoverKey) ||
            section.containsKey(kLimousinePublishedProfileCoverKey) ||
            section.containsKey('limousine_hero') ||
            section.containsKey('published_limousine_hero')) {
          _applyPersistedHero(
            limousineMergePricingOverlay(
              section: section,
              overlay: limousinePricingLocalStore.peekMerged(
                limousineDefaultLocalPricingScopeKeys(),
              ),
            ),
            fromLoad: false,
          );
        }
        if (section.containsKey(kLimousineProfileLogoKey) ||
            section.containsKey(kLimousinePublishedProfileLogoKey) ||
            section.containsKey('limousine_logo') ||
            section.containsKey('published_limousine_logo')) {
          _applyPersistedLogo(
            limousineMergePricingOverlay(
              section: section,
              overlay: limousinePricingLocalStore.peekMerged(
                limousineDefaultLocalPricingScopeKeys(),
              ),
            ),
            fromLoad: false,
          );
        }
        if (publish) {
          _publishedPublicTitle = _publicTitle.toJson();
          _publishedPublicDescription = _publicDescription.toJson();
          _publishedHero = _hero;
          _publishedLogo = _logo;
          _publishedVehiclePublicCopy = limousineCloneVehiclePublicCopy(
            _vehiclePublicCopy,
          );
          _rememberVehiclePublicCopyOverlay(updatePublished: true);
        }
        _sectionEnabled = publish ? true : _sectionEnabled;
        _dirty = false;
        _vehiclesSnapshot = List<VehicleProfile>.from(_vehicles);
        _status = publish
            ? (visible
                  ? _t(kLimousineBusinessSetupTestMessage)
                  : _t(kLimousineBusinessSetupPublishedLocal))
            : _t(kLimousineBusinessSetupDraftSaved);
      });
    } catch (error) {
      if (!mounted || saveId != _saveEpoch) return;
      setState(() {
        _error = limousineFriendlyCompanyError(error, language: _lang);
        _status = null;
      });
    } finally {
      if (mounted && saveId == _saveEpoch) {
        setState(() => _saving = false);
      }
    }
  }

  void _applyPublicTextToOffers() {
    final title = _publicTitle.toJson();
    final description = _publicDescription.toJson();
    for (var i = 0; i < _offers.length; i++) {
      final offer = Map<String, dynamic>.from(_offers[i]);
      final existingTitle = limousineLocalizedOf(offer['title']);
      final existingDescription = limousineLocalizedOf(offer['description']);
      offer['title'] = <String, String>{
        for (final lang in const ['nl', 'en', 'fr', 'es'])
          lang: (existingTitle[lang] ?? '').trim().isEmpty
              ? (title[lang] ?? '')
              : existingTitle[lang]!,
      };
      offer['description'] = <String, String>{
        for (final lang in const ['nl', 'en', 'fr', 'es'])
          lang: (existingDescription[lang] ?? '').trim().isEmpty
              ? (description[lang] ?? '')
              : existingDescription[lang]!,
      };
      _offers[i] = offer;
    }
  }

  Future<void> _editOffer({required int index}) async {
    if (index < 0 || index >= _offers.length) return;
    final existing = Map<String, dynamic>.from(_offers[index]);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => LimousineOfferEditorDialog(
        initialOffer: existing,
        vehicles: limousineSetupLimousineVehicles(_vehicles),
        currency: _currency,
        language: _lang,
        backgroundColor: _tokens.background,
        allowIncompleteDraft: true,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _offers[index] = result;
    });
    _markDirty();
  }

  int? _indexForMode(LimousineSimpleOfferMode mode) {
    int? first;
    int? valid;
    for (var i = 0; i < _offers.length; i++) {
      if (limousineSimpleOfferModeOf(_offers[i]) != mode) continue;
      first ??= i;
      final validation = limousineBusinessSetupOfferValidation(
        _offers[i],
        mode: mode,
        vehicles: _vehicles,
        knownClassIds: _knownClasses,
      );
      if (validation.isValid) {
        valid = i;
        break;
      }
    }
    return valid ?? first;
  }

  Future<void> _editSimpleOffer(LimousineSimpleOfferMode mode) async {
    final index = _indexForMode(mode);
    final existing = index == null
        ? limousineSimpleOfferDraft(
            presentation: limousineSimpleOfferPresentation(mode),
            currency: _currency,
            serviceClassId: _knownClasses.isEmpty ? '' : _knownClasses.first,
            title: _publicTitle.toJson(),
            description: _publicDescription.toJson(),
            hourlyEnabled:
                mode == LimousineSimpleOfferMode.hourly ||
                mode == LimousineSimpleOfferMode.package,
          )
        : Map<String, dynamic>.from(_offers[index]);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LimousineSimpleOfferEditor(
        initialOffer: existing,
        mode: mode,
        vehicles: limousineSetupLimousineVehicles(_vehicles),
        knownClassIds: _knownClasses,
        currency: _currency,
        language: _lang,
        tokens: _tokens,
        primaryLang: _primaryLang,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _offers.add(result);
      } else {
        _offers[index] = result;
      }
    });
    _markDirty();
  }

  void _setVehicleLimousine(VehicleProfile vehicle, bool enabled) {
    final classId = enabled
        ? (limousineOfferToken(vehicle.serviceClassId).isEmpty
              ? (_knownClasses.isEmpty ? '' : _knownClasses.first)
              : vehicle.serviceClassId)
        : '';
    final updated = vehicle.copyWith(
      serviceCategory: enabled ? 'limousine' : '',
      serviceClassId: classId,
    );
    _replaceVehicle(updated);
  }

  void _setVehicleClass(VehicleProfile vehicle, String classId) {
    _replaceVehicle(
      vehicle.copyWith(serviceCategory: 'limousine', serviceClassId: classId),
    );
  }

  void _replaceVehicle(VehicleProfile updated) {
    setState(() {
      _vehicles = _vehicles
          .map((vehicle) => vehicle.id == updated.id ? updated : vehicle)
          .toList(growable: false);
    });
    if (widget.vehicles == null) {
      updateVehicle(updated.id, updated);
    }
    _markDirty();
  }

  Future<void> _openVehicleSetup({String? vehicleId}) async {
    final custom = widget.onConfigureVehicle;
    if (custom != null) {
      custom();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleManagementPage(
          openVehicleId: vehicleId,
          openGallery: vehicleId != null,
        ),
      ),
    );
    if (!mounted) return;
    _onVehicles();
  }

  Future<void> _handleBack() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: kLimousineBusinessSetupLeaveDialogKey,
          title: Text(_t(kLimousineBusinessSetupUnsavedTitle)),
          content: Text(_t(kLimousineBusinessSetupUnsavedBody)),
          actions: [
            TextButton(
              key: kLimousineBusinessSetupLeaveCancelKey,
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              child: Text(_t(kLimousineBusinessSetupLeaveCancel)),
            ),
            TextButton(
              key: kLimousineBusinessSetupLeaveDiscardKey,
              onPressed: () => Navigator.of(dialogContext).pop('discard'),
              child: Text(_t(kLimousineBusinessSetupDiscard)),
            ),
            FilledButton(
              key: kLimousineBusinessSetupLeaveSaveKey,
              onPressed: () => Navigator.of(dialogContext).pop('save'),
              child: Text(_t(kLimousineBusinessSetupSave)),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (action == 'discard') {
      _restoreVehicleSelectionFromSnapshot();
      Navigator.of(context).pop();
      return;
    }
    if (action == 'save') {
      await _persist(publish: false);
      if (mounted && !_dirty) Navigator.of(context).pop();
    }
  }

  void _scrollTo(LimousineBusinessSetupSection section) {
    final key = _sectionKeys[section];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      alignment: 0.08,
    );
  }

  void _scrollToKey(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      alignment: 0.08,
    );
  }

  void _scrollToFirstGap() {
    for (final item in _readiness.items) {
      if (item.complete) continue;
      _scrollTo(item.section);
      return;
    }
    for (final offer in _offers) {
      final errors = limousineBusinessSetupOfferErrors(
        offer,
        vehicles: _vehicles,
        knownClassIds: _knownClasses,
      );
      if (errors.isEmpty) continue;
      final section = limousineBusinessSetupFieldSection(errors.first);
      if (section == 'hourly' || section == 'advanced') {
        if (section == 'advanced') {
          setState(() => _advancedOpen = true);
        }
        _scrollToKey(section == 'hourly' ? _hourlyKey : _advancedKey);
        return;
      }
      _scrollTo(LimousineBusinessSetupSection.offers);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens;
    final media = MediaQuery.of(context);
    final tablet = media.size.shortestSide >= 600;
    return Theme(
      data: limousineUxThemeData(tokens),
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          unawaited(_handleBack());
        },
        child: Scaffold(
          key: kLimousineBusinessSetupPageKey,
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.surface,
            foregroundColor: tokens.onSurface,
            elevation: 0,
            title: Text(_t(kLimousineBusinessSetupTitle)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => unawaited(_handleBack()),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  key: kLimousineBusinessSetupTestBadgeKey,
                  avatar: Icon(
                    Icons.science_outlined,
                    color: tokens.gold,
                    size: 16,
                  ),
                  label: Text(_t(kLimousineBusinessSetupTestBadge)),
                  side: BorderSide(color: tokens.gold),
                  backgroundColor: tokens.surfaceAlt,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: KeyedSubtree(
              key: tablet
                  ? kLimousineBusinessSetupTabletLayoutKey
                  : kLimousineBusinessSetupPhoneLayoutKey,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: limousineBusinessSetupContentWidth(
                            media.size.width,
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            kLimousineBusinessSetupStickyFooterReserve +
                                media.padding.bottom +
                                media.viewInsets.bottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _heroBanner(tokens),
                              const SizedBox(height: 16),
                              _sectionCard(
                                tokens,
                                section: LimousineBusinessSetupSection.vehicles,
                                index: 1,
                                hint: _t(kLimousineBusinessSetupVehiclesHint),
                                child: _vehiclesBody(tokens),
                              ),
                              const SizedBox(height: 16),
                              _sectionCard(
                                tokens,
                                section: LimousineBusinessSetupSection.offers,
                                index: 2,
                                child: _offersBody(tokens),
                              ),
                              const SizedBox(height: 16),
                              _sectionCard(
                                tokens,
                                section:
                                    LimousineBusinessSetupSection.publicText,
                                index: 3,
                                child: _publicBody(tokens, tablet, media.size),
                              ),
                              const SizedBox(height: 16),
                              _sectionCard(
                                tokens,
                                section: LimousineBusinessSetupSection.review,
                                index: 4,
                                child: _reviewBody(tokens),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _footer(tokens, media),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroBanner(LimousineUxTokens tokens) {
    final readiness = _readiness;
    return Container(
      key: kLimousineBusinessSetupHeroKey,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.gold.withOpacity(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.gold, width: 2),
                ),
                child: Icon(Icons.directions_car_filled, color: tokens.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      limousineBusinessSetupProfilePercent(
                        readiness.progress,
                        _lang,
                      ),
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _t(limousineBusinessSetupMissingCopy(readiness)),
                      style: TextStyle(color: tokens.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: readiness.progress,
              minHeight: 8,
              color: tokens.gold,
              backgroundColor: tokens.border,
            ),
          ),
          if (_dirty)
            Padding(
              key: kLimousineBusinessSetupDirtyKey,
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _t(kLimousineBusinessSetupUnsaved),
                style: TextStyle(
                  color: tokens.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    LimousineUxTokens tokens, {
    required LimousineBusinessSetupSection section,
    required int index,
    required Widget child,
    String? hint,
  }) {
    return Container(
      key: _sectionKeys[section],
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.gold.withOpacity(0.24)),
      ),
      child: Column(
        key: limousineBusinessSetupSectionKey(section),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: tokens.gold,
                foregroundColor: tokens.isDark
                    ? tokens.background
                    : tokens.surface,
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(limousineBusinessSetupSectionLabel(section)),
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint, style: TextStyle(color: tokens.muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _vehiclesBody(LimousineUxTokens tokens) {
    return Column(
      key: kLimousineBusinessSetupVehiclesKey,
      children: [
        for (final vehicle in _vehicles) _vehicleCard(tokens, vehicle),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openVehicleSetup,
            icon: const Icon(Icons.chevron_right),
            label: Text(_t(kLimousineBusinessSetupConfigureVehicle)),
          ),
        ),
      ],
    );
  }

  Widget _vehicleCard(LimousineUxTokens tokens, VehicleProfile vehicle) {
    final flags = limousineVehicleServiceFlags(vehicle);
    final name = vehicle.vehicleName.isEmpty
        ? vehicle.brandModel
        : vehicle.vehicleName;
    return Container(
      key: limousineBusinessSetupVehicleKey(vehicle.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: flags.limousine
              ? tokens.gold.withOpacity(0.45)
              : tokens.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mediaThumb(
            tokens,
            ref: vehicle.primaryPhotoRef,
            key: limousineBusinessSetupVehiclePhotoKey(vehicle.id),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _badge(
                      tokens,
                      flags.limousine
                          ? _t(kLimousineBusinessSetupLimousine)
                          : _t(kLimousineBusinessSetupTaxi),
                    ),
                    if (flags.limousine &&
                        vehicle.serviceClassId.trim().isNotEmpty)
                      _metaChip(
                        tokens,
                        Icons.workspace_premium_outlined,
                        limousineServiceClassLabel(
                          vehicle.serviceClassId,
                          _lang,
                        ),
                      ),
                    _metaChip(
                      tokens,
                      Icons.person_outline,
                      '${vehicle.passengerCapacity}',
                    ),
                    _metaChip(
                      tokens,
                      Icons.work_outline,
                      '${vehicle.luggageCapacity}',
                    ),
                  ],
                ),
                if (flags.limousine && _knownClasses.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isDense: true,
                        isExpanded: true,
                        value: _knownClasses.contains(vehicle.serviceClassId)
                            ? vehicle.serviceClassId
                            : _knownClasses.first,
                        items: [
                          for (final id in _knownClasses)
                            DropdownMenuItem<String>(
                              value: id,
                              child: Text(
                                limousineServiceClassLabel(id, _lang),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _setVehicleClass(vehicle, value);
                        },
                      ),
                    ),
                  ),
                if (flags.limousine)
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        key: limousineBusinessSetupEditPublicDetailsKey(
                          vehicle.id,
                        ),
                        onPressed: () =>
                            unawaited(_openVehiclePublicCopy(vehicle)),
                        icon: const Icon(Icons.notes_outlined, size: 16),
                        label: Text(
                          _t(kLimousineBusinessSetupEditPublicDetails),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                      TextButton.icon(
                        key: limousineBusinessSetupManagePhotosKey(vehicle.id),
                        onPressed: () =>
                            unawaited(_openVehicleSetup(vehicleId: vehicle.id)),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 16,
                        ),
                        label: Text(_t(kLimousineBusinessSetupManagePhotos)),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              Checkbox(
                value: flags.limousine,
                activeColor: tokens.gold,
                onChanged: (value) =>
                    _setVehicleLimousine(vehicle, value == true),
              ),
              Text(
                _t(kLimousineBusinessSetupLimousine),
                style: TextStyle(color: tokens.muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mediaThumb(
    LimousineUxTokens tokens, {
    required String ref,
    Key? key,
    double size = 72,
  }) {
    final raw = ref.trim();
    final network = resolvePublicHttpsMediaUrl(raw);
    Widget child = Icon(Icons.directions_car_filled, color: tokens.gold);
    if (network.isNotEmpty) {
      child = Image.network(
        network,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.directions_car_filled, color: tokens.gold),
      );
    } else if (raw.startsWith('assets/')) {
      child = Image.asset(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.directions_car_filled, color: tokens.gold),
      );
    } else if (raw.isNotEmpty) {
      child = Image.file(
        File(raw),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.directions_car_filled, color: tokens.gold),
      );
    }
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _fillPhoto(LimousineUxTokens tokens, String ref) {
    final raw = ref.trim();
    final network = resolvePublicHttpsMediaUrl(raw);
    if (network.isNotEmpty) {
      return Image.network(
        network,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(color: tokens.surface),
      );
    }
    if (raw.startsWith('assets/')) {
      return Image.asset(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(color: tokens.surface),
      );
    }
    if (raw.isNotEmpty) {
      return Image.file(
        File(raw),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ColoredBox(color: tokens.surface),
      );
    }
    return ColoredBox(color: tokens.surface);
  }

  Widget _badge(LimousineUxTokens tokens, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.gold.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metaChip(LimousineUxTokens tokens, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offersBody(LimousineUxTokens tokens) {
    return Column(
      key: kLimousineBusinessSetupOffersKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            final cardWidth = wide ? 248.0 : constraints.maxWidth;
            final cards = <Widget>[
              _simpleCard(
                tokens,
                mode: LimousineSimpleOfferMode.quote,
                presentation: LimousinePricePresentation.quoteRequired,
                title: _t(kLimousineBusinessSetupQuoteCard),
                hint: _t(kLimousineBusinessSetupQuoteHint),
                icon: Icons.description_outlined,
                width: cardWidth,
              ),
              _simpleCard(
                tokens,
                mode: LimousineSimpleOfferMode.fromPrice,
                presentation: LimousinePricePresentation.fromPrice,
                title: _fromTitle(),
                hint: _t(kLimousineBusinessSetupFromCard),
                icon: Icons.sell_outlined,
                width: cardWidth,
              ),
              _simpleCard(
                tokens,
                mode: LimousineSimpleOfferMode.fixed,
                presentation: LimousinePricePresentation.exactFixed,
                title: _t(kLimousineBusinessSetupFixedCard),
                hint: _fixedHint(),
                icon: Icons.price_check_outlined,
                width: cardWidth,
              ),
              KeyedSubtree(
                key: _hourlyKey,
                child: _simpleCard(
                  tokens,
                  mode: LimousineSimpleOfferMode.hourly,
                  presentation: LimousineJourneyTypeId.hourlyPackage,
                  title: _t(kLimousineBusinessSetupHourlyCard),
                  hint: _t(kLimousineBusinessSetupHourlyCard),
                  icon: Icons.schedule_outlined,
                  width: cardWidth,
                ),
              ),
              _simpleCard(
                tokens,
                mode: LimousineSimpleOfferMode.package,
                presentation: 'package',
                title: _t(kLimousineBusinessSetupPackageCard),
                hint: _t(kLimousineBusinessSetupPackageCard),
                icon: Icons.card_giftcard_outlined,
                width: cardWidth,
              ),
            ];
            if (!wide) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Wrap(spacing: 10, runSpacing: 10, children: cards);
          },
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: kLimousineBusinessSetupAdvancedKey,
          initiallyExpanded: _advancedOpen,
          onExpansionChanged: (open) => setState(() => _advancedOpen = open),
          title: Text(_t(kLimousineBusinessSetupAdvanced)),
          children: [
            KeyedSubtree(
              key: _advancedKey,
              child: Column(
                children: [
                  for (var i = 0; i < _offers.length; i++)
                    ListTile(
                      title: Text(
                        limousineBusinessSetupTextFallback(
                              _offers[i]['title'],
                              _lang,
                              primaryLang: _primaryLang,
                            ).isEmpty
                            ? '${_offers[i]['offer_id']}'
                            : limousineBusinessSetupTextFallback(
                                _offers[i]['title'],
                                _lang,
                                primaryLang: _primaryLang,
                              ),
                      ),
                      subtitle: Text(
                        limousinePresentationLabel(
                          limousineOfferToken(_offers[i]['price_presentation']),
                          _lang,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: _saving ? null : () => _editOffer(index: i),
                        child: Text(_t(kLimousineBusinessSetupEdit)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fromTitle() {
    final index = _indexForMode(LimousineSimpleOfferMode.fromPrice);
    if (index == null) return _t(kLimousineBusinessSetupFromCard);
    final cents = limousineCentsOf(_offers[index]['display_amount_cents']);
    if (cents == null) return _t(kLimousineBusinessSetupFromCard);
    return '${_t(kLimousineBusinessSetupFromCard)} ${_money(cents)}';
  }

  String _fixedHint() {
    final index = _indexForMode(LimousineSimpleOfferMode.fixed);
    if (index == null) return _t(kLimousineBusinessSetupFixedCard);
    final title = limousineBusinessSetupTextFallback(
      _offers[index]['title'],
      _lang,
      primaryLang: _primaryLang,
    );
    return title.isEmpty ? _t(kLimousineBusinessSetupFixedCard) : title;
  }

  String _money(int cents) {
    return '${(cents / 100).toStringAsFixed(0)} $_currency';
  }

  Widget _simpleCard(
    LimousineUxTokens tokens, {
    required LimousineSimpleOfferMode mode,
    required String presentation,
    required String title,
    required String hint,
    required IconData icon,
    double width = 248,
  }) {
    final index = _indexForMode(mode);
    final validation = limousineBusinessSetupOfferValidation(
      index == null ? null : _offers[index],
      mode: mode,
      vehicles: _vehicles,
      knownClassIds: _knownClasses,
    );
    final valid = validation.isValid;
    return SizedBox(
      width: width,
      child: Material(
        key: limousineBusinessSetupOfferCardKey(presentation),
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _editSimpleOffer(mode),
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: tokens.gold),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      hint,
                      style: TextStyle(color: tokens.muted, fontSize: 12),
                    ),
                    TextButton.icon(
                      onPressed: () => _editSimpleOffer(mode),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(_t(kLimousineBusinessSetupEdit)),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Semantics(
                  label: _t(
                    valid
                        ? kLimousineBusinessSetupOfferValid
                        : kLimousineBusinessSetupOfferIncomplete,
                  ),
                  child: Container(
                    key: limousineBusinessSetupOfferValidityKey(
                      presentation,
                      valid: valid,
                    ),
                    width: kLimousineBusinessSetupOfferValidityDotSize,
                    height: kLimousineBusinessSetupOfferValidityDotSize,
                    decoration: BoxDecoration(
                      color: valid ? _successColor : tokens.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverEditor(LimousineUxTokens tokens) {
    final resolved = _resolvedHero;
    return Column(
      key: kLimousineBusinessSetupCoverKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kLimousineBusinessSetupCoverTitle),
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _t(kLimousineBusinessSetupCoverHint),
          style: TextStyle(color: tokens.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        KeyedSubtree(
          key: kLimousineBusinessSetupCoverPreviewKey,
          child: LimousinePublicCoverFrame(
            imageUrl: resolved.hasPhoto ? resolved.photoUrl : '',
            spec: limousinePublicCoverSpec(
              viewport: MediaQuery.sizeOf(context),
              explicitCover: resolved.explicit && resolved.hasPhoto,
              alignment: _hero.flutterAlignment,
            ),
            background: tokens.surfaceAlt,
            gold: tokens.gold,
          ),
        ),
        if (_heroUploading) ...[
          const SizedBox(height: 8),
          Row(
            key: kLimousineBusinessSetupCoverUploadingKey,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(kLimousineBusinessSetupCoverUploading),
                  style: TextStyle(color: tokens.gold, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
        if (_coverStatus != null && !_heroUploading) ...[
          const SizedBox(height: 8),
          Text(
            _coverStatus!,
            key: kLimousineBusinessSetupMediaStatusKey,
            style: TextStyle(color: tokens.gold, fontSize: 12.5),
          ),
        ],
        if (_coverError != null) ...[
          const SizedBox(height: 8),
          Text(
            _coverError!,
            key: kLimousineBusinessSetupMediaErrorKey,
            style: TextStyle(color: tokens.danger, fontSize: 12.5),
          ),
        ],
        if (!resolved.explicit) ...[
          const SizedBox(height: 8),
          Text(
            key: kLimousineBusinessSetupCoverFallbackKey,
            _t(kLimousineBusinessSetupCoverFallback),
            style: TextStyle(color: tokens.gold, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: kLimousineBusinessSetupCoverUploadKey,
              onPressed: _heroUploading ? null : _uploadLimousineHero,
              icon: const Icon(Icons.upload_outlined),
              label: Text(
                resolved.explicit
                    ? _t(kLimousineBusinessSetupCoverReplace)
                    : _t(kLimousineBusinessSetupCoverUpload),
              ),
            ),
            OutlinedButton(
              key: kLimousineBusinessSetupCoverPickGalleryKey,
              onPressed: _heroUploading ? null : _pickHeroFromGallery,
              child: Text(_t(kLimousineBusinessSetupCoverPickGallery)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          key: kLimousineBusinessSetupCoverUploadHelpKey,
          _t(kLimousineBusinessSetupCoverUploadHelp),
          style: TextStyle(color: tokens.muted, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          key: kLimousineBusinessSetupCoverGalleryHelpKey,
          _t(kLimousineBusinessSetupCoverGalleryHelp),
          style: TextStyle(color: tokens.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          _t(kLimousineBusinessSetupCoverFocus),
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final alignment in kLimousineHeroAlignments)
              ChoiceChip(
                key: limousineBusinessSetupCoverFocusKey(alignment),
                label: Text(alignment),
                selected: _hero.alignment == alignment,
                onSelected: _heroUploading
                    ? null
                    : (_) => _setHeroAlignment(alignment),
              ),
          ],
        ),
      ],
    );
  }

  Widget _logoEditor(LimousineUxTokens tokens) {
    final override = _logo.hasOverride;
    final previewUrl = _effectiveLogoUrl;
    return Column(
      key: kLimousineBusinessSetupLogoKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kLimousineBusinessSetupLogoTitle),
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _t(kLimousineBusinessSetupLogoHint),
          style: TextStyle(color: tokens.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        Text(
          key: kLimousineBusinessSetupLogoStatusKey,
          override
              ? _t(kLimousineBusinessSetupLogoStatusOwn)
              : _t(kLimousineBusinessSetupLogoStatusCompany),
          style: TextStyle(
            color: tokens.gold,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          key: kLimousineBusinessSetupLogoActionsKey,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: override
                  ? kLimousineBusinessSetupLogoReplaceKey
                  : kLimousineBusinessSetupLogoPickKey,
              onPressed: _logoUploading ? null : _uploadLimousineLogo,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                override
                    ? _t(kLimousineBusinessSetupLogoReplace)
                    : _t(kLimousineBusinessSetupLogoPick),
              ),
            ),
            if (override)
              OutlinedButton(
                key: kLimousineBusinessSetupLogoClearKey,
                onPressed: _logoUploading ? null : _clearLimousineLogoOverride,
                child: Text(_t(kLimousineBusinessSetupLogoClear)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: KeyedSubtree(
              key: kLimousineBusinessSetupLogoPreviewKey,
              child: LimousineSetupLogoPreview(
                imageUrl: previewUrl,
                background: tokens.surfaceAlt,
                tablet: MediaQuery.sizeOf(context).shortestSide >= 600,
              ),
            ),
          ),
        ),
        if (_logoUploading) ...[
          const SizedBox(height: 8),
          Row(
            key: kLimousineBusinessSetupLogoUploadingKey,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(kLimousineBusinessSetupLogoUploading),
                  style: TextStyle(color: tokens.gold, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
        if (_logoStatus != null && !_logoUploading) ...[
          const SizedBox(height: 8),
          Text(
            _logoStatus!,
            key: kLimousineBusinessSetupLogoMediaStatusKey,
            style: TextStyle(color: tokens.gold, fontSize: 12.5),
          ),
        ],
        if (_logoError != null) ...[
          const SizedBox(height: 8),
          Text(
            _logoError!,
            key: kLimousineBusinessSetupLogoMediaErrorKey,
            style: TextStyle(color: tokens.danger, fontSize: 12.5),
          ),
        ],
        if (!override) ...[
          const SizedBox(height: 8),
          Text(
            _t(kLimousineBusinessSetupLogoFallback),
            style: TextStyle(color: tokens.gold, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  Widget _publicBody(LimousineUxTokens tokens, bool tablet, Size size) {
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: kLimousineBusinessSetupPublicTitleKey,
          controller: _publicTitle.controllers[_primaryLang],
          decoration: InputDecoration(
            labelText: _t(kLimousineBusinessSetupTitleField),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 10),
        TextField(
          key: kLimousineBusinessSetupPublicDescriptionKey,
          controller: _publicDescription.controllers[_primaryLang],
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: _t(kLimousineBusinessSetupDescriptionField),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 16),
        _coverEditor(tokens),
        const SizedBox(height: 16),
        _logoEditor(tokens),
        ExpansionTile(
          key: kLimousineBusinessSetupOtherLanguagesKey,
          title: Text(_t(kLimousineBusinessSetupOtherLanguages)),
          children: [
            for (final lang in const ['nl', 'en', 'fr', 'es'])
              if (lang != _primaryLang) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(
                      lang.toUpperCase(),
                      key: limousineBusinessSetupPublicLangKey(lang),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                TextField(
                  key: limousineBusinessSetupOtherLangTitleKey(lang),
                  controller: _publicTitle.controllers[lang],
                  decoration: InputDecoration(
                    labelText: _t(kLimousineBusinessSetupTitleField),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _publicDescription.controllers[lang],
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: _t(kLimousineBusinessSetupDescriptionField),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ],
          ],
        ),
      ],
    );
    final preview = _preview(tokens);
    if (!tablet || size.height >= size.width) {
      return Column(
        key: kLimousineBusinessSetupPublicKey,
        children: [editor, const SizedBox(height: 12), preview],
      );
    }
    return Row(
      key: kLimousineBusinessSetupPublicKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: editor),
        const SizedBox(width: 16),
        Expanded(child: preview),
      ],
    );
  }

  LimousineDiscoveryCard _setupPreviewCard() {
    return limousineDiscoveryCardFromSetupPreview(
      companyName: widget.companyName,
      logoUrl: _effectiveLogoUrl,
      publicTitle: _publicTitle.toJson(),
      publicDescription: _publicDescription.toJson(),
      cover: _resolvedHero.copyWith(alignment: _hero.alignment),
    );
  }

  Widget _preview(LimousineUxTokens tokens) {
    final card = _setupPreviewCard();
    return Column(
      key: kLimousineBusinessSetupPreviewKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kLimousineBusinessSetupPreviewHint),
          style: TextStyle(color: tokens.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        LimousinePublicCompanyCard(
          card: card,
          tokens: tokens,
          language: _lang,
          onOpenOffers: null,
          onOpenProfile: null,
        ),
      ],
    );
  }

  Widget _reviewBody(LimousineUxTokens tokens) {
    final readiness = _readiness;
    return Column(
      key: kLimousineBusinessSetupReviewKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in readiness.items)
          ListTile(
            key: limousineBusinessSetupChecklistKey(item.code),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item.code == 'live_status' && !item.complete
                  ? Icons.warning_amber_rounded
                  : (item.complete
                        ? Icons.check_circle
                        : Icons.circle_outlined),
              color: item.code == 'live_status' && !item.complete
                  ? tokens.gold
                  : (item.complete ? tokens.gold : tokens.muted),
            ),
            title: Text(_t(limousineBusinessSetupChecklistLabel(item.code))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _scrollTo(item.section),
          ),
        if (_status != null)
          Text(
            _status!,
            key: kLimousineBusinessSetupStatusKey,
            style: TextStyle(color: tokens.gold),
          ),
        if (_error != null)
          Text(
            _error!,
            key: kLimousineBusinessSetupErrorKey,
            style: TextStyle(color: tokens.danger),
          ),
        const SizedBox(height: 8),
        Text(
          _t(kLimousineBusinessSetupTransactionsOff),
          style: TextStyle(color: tokens.muted, fontSize: 12.5),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(color: tokens.gold),
          ),
      ],
    );
  }

  Widget _footer(LimousineUxTokens tokens, MediaQueryData media) {
    final draftOk = limousineBusinessSetupDraftSaveAllowed(
      dirty: _dirty,
      saving: _saving,
    );
    final publishOk = limousineBusinessSetupPublishAllowed(
      saving: _saving,
      readiness: _readiness,
    );
    return Material(
      key: kLimousineBusinessSetupFooterKey,
      color: tokens.surface,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            media.viewInsets.bottom > 0 ? 10 : 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: kLimousineBusinessSetupDraftSaveKey,
                  onPressed: draftOk ? () => _persist(publish: false) : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_t(kLimousineBusinessSetupDraftSave)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: kLimousineBusinessSetupPublishKey,
                  onPressed: publishOk ? () => _persist(publish: true) : null,
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: Text(_t(kLimousineBusinessSetupPublish)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void openLimousineBusinessSetup(
  BuildContext context, {
  AppLanguage? language,
  Color? backgroundColor,
  String companyName = '',
  bool entryEnabled = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LimousineBusinessSetupPage(
        language: language,
        backgroundColor: backgroundColor,
        companyName: companyName,
        entryEnabled: entryEnabled,
      ),
    ),
  );
}
