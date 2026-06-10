import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/driver_document_sheet.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Directory, File, Platform;

/// Chauffeur-facing compliance documents (same store as company admin).
class DriverMyDocumentsPage extends StatefulWidget {
  const DriverMyDocumentsPage({super.key, this.themeListenable});

  final ValueListenable<DriverThemeVariant>? themeListenable;

  @override
  State<DriverMyDocumentsPage> createState() => _DriverMyDocumentsPageState();
}

class _RequiredDocumentDef {
  const _RequiredDocumentDef({
    required this.id,
    required this.icon,
    required this.labelNl,
    required this.labelEn,
    required this.labelFr,
    required this.labelEs,
    required this.matchTypes,
  });

  final String id;
  final IconData icon;
  final String labelNl;
  final String labelEn;
  final String labelFr;
  final String labelEs;
  final List<String> matchTypes;
}

class _DriverDocumentsThemeTokens {
  const _DriverDocumentsThemeTokens({
    required this.background,
    required this.cardGradient,
    required this.panelGradient,
    required this.cardBorder,
    required this.panelBorder,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.textPrimary,
    required this.textMuted,
    required this.textSubtle,
    required this.primaryButtonForeground,
    required this.bottomSheetBackground,
  });

  final Color background;
  final Gradient cardGradient;
  final Gradient panelGradient;
  final Color cardBorder;
  final Color panelBorder;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color textPrimary;
  final Color textMuted;
  final Color textSubtle;
  final Color primaryButtonForeground;
  final Color bottomSheetBackground;
}

class _DriverMyDocumentsPageState extends State<DriverMyDocumentsPage> {
  final ImagePicker _imagePicker = ImagePicker();
  static const Color _green = Color(0xFF4ADE80);
  static const Color _red = Color(0xFFF97373);
  static const Color _orange = Color(0xFFF59E0B);

  _DriverDocumentsThemeTokens _themeTokens(DriverThemeVariant variant) {
    if (variant == DriverThemeVariant.midnightBlue) {
      return const _DriverDocumentsThemeTokens(
        background: Color(0xFF060B16),
        cardGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101F36), Color(0xFF0A1629)],
        ),
        panelGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF163052), Color(0xFF0D2139)],
        ),
        cardBorder: Color(0x66559BD8),
        panelBorder: Color(0x8062BBFF),
        accentPrimary: Color(0xFF4DA3FF),
        accentSecondary: Color(0xFF8FD0FF),
        textPrimary: Color(0xFFEAF6FF),
        textMuted: Color(0xFFAFCBEA),
        textSubtle: Color(0xFF8FB4D8),
        primaryButtonForeground: Color(0xFF04172C),
        bottomSheetBackground: Color(0xFF0D1A2D),
      );
    }
    if (variant == DriverThemeVariant.highContrast) {
      return const _DriverDocumentsThemeTokens(
        background: Color(0xFF171108),
        cardGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2B17), Color(0xFF22170C)],
        ),
        panelGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5D4321), Color(0xFF362510)],
        ),
        cardBorder: Color(0x66E8C57E),
        panelBorder: Color(0x99FFDFA3),
        accentPrimary: Color(0xFFFFDFA3),
        accentSecondary: Color(0xFFE8C57E),
        textPrimary: Color(0xFFFFF0D0),
        textMuted: Color(0xFFE1CCA0),
        textSubtle: Color(0xFFC9B182),
        primaryButtonForeground: Color(0xFF3A2406),
        bottomSheetBackground: Color(0xFF2B1B09),
      );
    }
    return const _DriverDocumentsThemeTokens(
      background: Color(0xFF07080C),
      cardGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101113), Color(0xFF0B0C0F)],
      ),
      panelGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A140A), Color(0xFF13100A)],
      ),
      cardBorder: Color(0x4DE5B641),
      panelBorder: Color(0x66E5B641),
      accentPrimary: Color(0xFFE5B641),
      accentSecondary: Color(0xFFFFDFA3),
      textPrimary: Colors.white,
      textMuted: Color(0xFFC5C5C5),
      textSubtle: Color(0xFF8F8F8F),
      primaryButtonForeground: Colors.black,
      bottomSheetBackground: Color(0xFF141B2F),
    );
  }

  BoxDecoration _cardDecoration(
    _DriverDocumentsThemeTokens theme, {
    Color? borderColor,
  }) {
    return BoxDecoration(
      gradient: theme.cardGradient,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderColor ?? theme.cardBorder),
    );
  }

  BoxDecoration _panelCircleDecoration(_DriverDocumentsThemeTokens theme) {
    return BoxDecoration(
      gradient: theme.panelGradient,
      shape: BoxShape.circle,
      border: Border.all(color: theme.panelBorder),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadAndRefreshDocsBestEffort());
  }

  Future<void> _loadAndRefreshDocsBestEffort() async {
    await DriverDocumentsStore.instance.load();
    debugPrint('[DRIVER_DOCS][UI_REFRESH_START] source=driver_page_init');
    final session = activeDriverSessionNotifier.value;
    if (session == null) {
      debugPrint(
        '[DRIVER_DOCS][UI_REFRESH_SKIP] reason=missing_driver_session',
      );
      debugPrint('[DRIVER_DOCS][UI_RETRY_SKIP] reason=missing_driver_session');
      return;
    }
    final tenantId = (session.tenantId ?? '').trim();
    final companyId = (session.companyId ?? '').trim();
    final driverId = session.driverId.trim();
    if (tenantId.isEmpty || companyId.isEmpty || driverId.isEmpty) {
      debugPrint('[DRIVER_DOCS][UI_REFRESH_SKIP] reason=missing_scope');
      debugPrint('[DRIVER_DOCS][UI_RETRY_SKIP] reason=missing_scope');
      return;
    }
    final bearerToken = _selfDriverDocsBearerToken(session);
    if (bearerToken == null) {
      debugPrint('[DRIVER_DOCS][UI_REFRESH_SKIP] reason=missing_self_token');
      debugPrint('[DRIVER_DOCS][UI_RETRY_SKIP] reason=missing_self_token');
      return;
    }
    final driverSessionToken = (session.driverSessionToken ?? '').trim();
    final useSelfServiceRetry =
        session.isStandaloneLoginSession &&
        driverSessionToken.isNotEmpty &&
        bearerToken == driverSessionToken;
    try {
      await DriverDocumentsStore.instance.refreshDriverDocumentsFromBackend(
        bookingBaseUrl: appConfig.bookingBaseUrl,
        companySessionToken: bearerToken,
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
      );
      debugPrint('[DRIVER_DOCS][UI_RETRY_START] source=driver_page_init');
      final Future<void> retryFuture = useSelfServiceRetry
          ? DriverDocumentsStore.instance
                .retryPendingDriverDocumentSyncSelfService(
                  bookingBaseUrl: appConfig.bookingBaseUrl,
                  driverSessionToken: driverSessionToken,
                )
          : DriverDocumentsStore.instance.retryPendingDriverDocumentSync(
              bookingBaseUrl: appConfig.bookingBaseUrl,
              companySessionToken: bearerToken,
              tenantId: tenantId,
              companyId: companyId,
              driverId: driverId,
            );
      unawaited(
        retryFuture
            .then((_) {
              debugPrint('[DRIVER_DOCS][UI_RETRY_DONE] ok=true');
            })
            .catchError((_) {
              debugPrint('[DRIVER_DOCS][UI_RETRY_DONE] ok=false');
            }),
      );
      debugPrint('[DRIVER_DOCS][UI_REFRESH_DONE] ok=true');
    } catch (_) {
      debugPrint('[DRIVER_DOCS][UI_RETRY_SKIP] reason=refresh_failed');
      debugPrint('[DRIVER_DOCS][UI_REFRESH_DONE] ok=false');
    }
  }

  /// Selects the bearer token to use for self-service driver-document
  /// requests on this page. Returns the standalone driver session token
  /// when available; otherwise falls back to the active company session
  /// token only when its scope exactly matches the driver session
  /// tenant/company. Returns null in mixed contexts where neither
  /// option is safe (e.g. business=A while standalone driver=B), so the
  /// caller skips the request rather than authenticating with the wrong
  /// scope.
  String? _selfDriverDocsBearerToken(ActiveDriverSession session) {
    final tenantId = (session.tenantId ?? '').trim();
    final companyId = (session.companyId ?? '').trim();
    final driverId = session.driverId.trim();
    final driverToken = (session.driverSessionToken ?? '').trim();
    if (session.isStandaloneLoginSession &&
        tenantId.isNotEmpty &&
        companyId.isNotEmpty &&
        driverId.isNotEmpty &&
        driverToken.isNotEmpty) {
      debugPrint(
        '[DRIVER_DOCS_SELF][AUTH_TOKEN] source=driver_session reason=standalone_session',
      );
      return driverToken;
    }
    final companySession = activeCompanySessionNotifier.value;
    final companyId2 = (companySession?.companyId ?? '').trim();
    final companyToken = (companySession?.companySessionToken ?? '').trim();
    if (companyToken.isNotEmpty &&
        companyId2.isNotEmpty &&
        tenantId.isNotEmpty &&
        companyId.isNotEmpty &&
        companyId2 == tenantId &&
        companyId2 == companyId) {
      debugPrint(
        '[DRIVER_DOCS_SELF][AUTH_TOKEN] source=company_session_match reason=scope_matches_driver',
      );
      return companyToken;
    }
    final reason = driverToken.isEmpty
        ? 'missing_driver_session_token'
        : (companyToken.isEmpty
              ? 'missing_company_session_token'
              : 'scope_mismatch');
    debugPrint('[DRIVER_DOCS_SELF][AUTH_TOKEN] source=missing reason=$reason');
    return null;
  }

  AppLanguage get _lang => appConfig.currentLanguage;

  String _tr({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
    }
  }

  String _requiredDocLabel(_RequiredDocumentDef def) {
    return _tr(
      nl: def.labelNl,
      en: def.labelEn,
      fr: def.labelFr,
      es: def.labelEs,
    );
  }

  List<_RequiredDocumentDef> get _requiredDocumentDefs => const [
    _RequiredDocumentDef(
      id: 'driving_license',
      icon: Icons.badge_outlined,
      labelNl: 'Rijbewijs',
      labelEn: 'Driving license',
      labelFr: 'Permis de conduire',
      labelEs: 'Permiso de conducir',
      matchTypes: [DriverDocumentTypes.drivingLicense],
    ),
    _RequiredDocumentDef(
      id: 'taxi_driver_card',
      icon: Icons.credit_card_outlined,
      labelNl: 'Bestuurderspas',
      labelEn: 'Driver card',
      labelFr: 'Carte chauffeur',
      labelEs: 'Tarjeta de conductor',
      matchTypes: [DriverDocumentTypes.taxiDriverCard],
    ),
    _RequiredDocumentDef(
      id: 'identity_document',
      icon: Icons.perm_identity_outlined,
      labelNl: 'Identiteitsbewijs',
      labelEn: 'Identity document',
      labelFr: 'Pièce d\'identité',
      labelEs: 'Documento de identidad',
      matchTypes: [DriverDocumentTypes.identityDocument],
    ),
    _RequiredDocumentDef(
      id: 'permit_or_inspection',
      icon: Icons.verified_user_outlined,
      labelNl: 'Vergunning / Keuring',
      labelEn: 'Permit / inspection',
      labelFr: 'Permis / contrôle',
      labelEs: 'Permiso / inspección',
      matchTypes: [
        DriverDocumentTypes.workPermit,
        DriverDocumentTypes.medicalCertificate,
        DriverDocumentTypes.postingDeclaration,
      ],
    ),
  ];

  int _docStatusPriority(String status) {
    switch (status.trim().toLowerCase()) {
      case DriverDocumentStatuses.approved:
        return 5;
      case DriverDocumentStatuses.pendingReview:
      case 'active':
      case 'verified':
        return 4;
      case DriverDocumentStatuses.expired:
        return 3;
      case DriverDocumentStatuses.rejected:
        return 2;
      case DriverDocumentStatuses.missing:
      default:
        return 1;
    }
  }

  DriverDocument? _bestDocForTypes(
    List<DriverDocument> docs,
    List<String> types,
  ) {
    final matches = docs
        .where((d) => types.contains(d.documentType.trim()))
        .toList(growable: false);
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final prio = _docStatusPriority(
        b.status.trim(),
      ).compareTo(_docStatusPriority(a.status.trim()));
      if (prio != 0) return prio;
      final bUpdated = b.updatedAt.trim();
      final aUpdated = a.updatedAt.trim();
      if (bUpdated != aUpdated) return bUpdated.compareTo(aUpdated);
      return b.createdAt.trim().compareTo(a.createdAt.trim());
    });
    return matches.first;
  }

  DriverDocument? _bestRequiredDocForScope({
    required String tenantId,
    required String companyId,
    required String driverId,
    required List<String> types,
  }) {
    final scopedTenant = tenantId.trim();
    final scopedCompany = companyId.trim();
    final scopedDriver = driverId.trim();
    final allowedTypes = types.map((e) => e.trim()).toSet();
    if (scopedTenant.isEmpty ||
        scopedCompany.isEmpty ||
        scopedDriver.isEmpty ||
        allowedTypes.isEmpty) {
      return null;
    }
    final scoped = driverDocumentsNotifier.value
        .where((doc) {
          return doc.tenantId.trim() == scopedTenant &&
              doc.companyId.trim() == scopedCompany &&
              doc.driverId.trim() == scopedDriver &&
              allowedTypes.contains(doc.documentType.trim());
        })
        .toList(growable: false);
    return _bestDocForTypes(scoped, types);
  }

  ({String text, Color color}) _docStateChip(DriverDocument? doc) {
    if (doc == null) {
      return (
        text: _tr(nl: 'Ontbreekt', en: 'Missing', fr: 'Manquant', es: 'Falta'),
        color: _red,
      );
    }
    final status = doc.status.trim();
    switch (status) {
      case DriverDocumentStatuses.approved:
        return (
          text: _tr(
            nl: 'Goedgekeurd',
            en: 'Approved',
            fr: 'Approuvé',
            es: 'Aprobado',
          ),
          color: _green,
        );
      case DriverDocumentStatuses.pendingReview:
        return (
          text: _tr(
            nl: 'In afwachting',
            en: 'Pending',
            fr: 'En attente',
            es: 'Pendiente',
          ),
          color: _orange,
        );
      case DriverDocumentStatuses.expired:
        return (
          text: _tr(
            nl: 'Verlopen',
            en: 'Expired',
            fr: 'Expiré',
            es: 'Caducado',
          ),
          color: _orange,
        );
      case DriverDocumentStatuses.rejected:
        return (
          text: _tr(
            nl: 'Geweigerd',
            en: 'Rejected',
            fr: 'Refusé',
            es: 'Rechazado',
          ),
          color: _red,
        );
      case DriverDocumentStatuses.missing:
      default:
        return (
          text: _tr(
            nl: 'Ontbreekt',
            en: 'Missing',
            fr: 'Manquant',
            es: 'Falta',
          ),
          color: _red,
        );
    }
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.52)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, _DriverDocumentsThemeTokens theme) {
    return Text(
      text,
      style: TextStyle(
        color: theme.accentSecondary.withOpacity(0.96),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  bool _isDriverInNotifier(String driverId) {
    final id = driverId.trim();
    if (id.isEmpty) return false;
    for (final d in driversNotifier.value) {
      if (d.id.trim() == id) return true;
    }
    return false;
  }

  DriverProfile? _driverForSession(ActiveDriverSession session) {
    final sessionDriverId = session.driverId.trim();
    final sessionTenantField = session.tenantId;
    final sessionCompanyId = (session.companyId ?? '').trim();
    final hasDriverId = sessionDriverId.isNotEmpty;
    final hasTenant = (sessionTenantField ?? '').trim().isNotEmpty;
    final hasCompany = sessionCompanyId.isNotEmpty;

    if (hasDriverId) {
      for (final d in driversNotifier.value) {
        if (d.id.trim() != sessionDriverId) continue;
        final driverCompanyId = (d.companyId ?? '').trim();
        if (hasCompany && driverCompanyId.isNotEmpty) {
          if (sessionCompanyId != driverCompanyId) continue;
        }
        debugPrint(
          '[DRIVER_DOCS_SELF][PROFILE_RESOLVE] source=notifier '
          'has_driver_id=$hasDriverId has_tenant=$hasTenant has_company=$hasCompany',
        );
        return d;
      }
    }

    final fullName = session.fullName.trim();
    final employeeNumber = session.employeeNumber.trim();
    final tenantOk =
        sessionTenantField == null || sessionTenantField.trim().isNotEmpty;
    final canSynthesize =
        hasDriverId &&
        hasCompany &&
        tenantOk &&
        (fullName.isNotEmpty || employeeNumber.isNotEmpty);

    if (!canSynthesize) {
      debugPrint(
        '[DRIVER_DOCS_SELF][PROFILE_RESOLVE] source=missing '
        'has_driver_id=$hasDriverId has_tenant=$hasTenant has_company=$hasCompany',
      );
      return null;
    }

    final sessionPhotoUrl = (session.driverPhotoUrl ?? '').trim();
    final synthesizedPortraitUrl = _isHttpUrl(sessionPhotoUrl)
        ? sessionPhotoUrl
        : null;
    debugPrint(
      '[DRIVER_DOCS_SELF][PROFILE_RESOLVE] source=standalone_session '
      'has_driver_id=$hasDriverId has_tenant=$hasTenant has_company=$hasCompany',
    );
    return DriverProfile(
      id: sessionDriverId,
      fullName: fullName.isNotEmpty ? fullName : employeeNumber,
      employeeNumber: employeeNumber,
      phone: session.phone.trim(),
      isActive: true,
      companyId: sessionCompanyId,
      publicPortraitUrl: synthesizedPortraitUrl,
    );
  }

  bool _driverPhotoExists(String? path) {
    final clean = path?.trim() ?? '';
    if (clean.isEmpty || kIsWeb) return false;
    try {
      return File(clean).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool _isHttpUrl(String? value) {
    final lower = (value ?? '').trim().toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  String? _driverNetworkPhotoUrl(
    DriverProfile driver,
    ActiveDriverSession? session,
  ) {
    final publicPortraitUrl = (driver.publicPortraitUrl ?? '').trim();
    if (_isHttpUrl(publicPortraitUrl)) return publicPortraitUrl;

    final sessionPhotoUrl = (session?.driverPhotoUrl ?? '').trim();
    if (_isHttpUrl(sessionPhotoUrl)) return sessionPhotoUrl;

    final profilePhotoPath = (driver.profilePhotoPath ?? '').trim();
    if (_isHttpUrl(profilePhotoPath)) return profilePhotoPath;

    return null;
  }

  String _driverInitials(DriverProfile driver) {
    final raw = driver.fullName.trim();
    if (raw.isEmpty) return 'D';
    final parts = raw
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return raw[0].toUpperCase();
  }

  String _driverPhotoExtension(String path) {
    final lower = path.toLowerCase();
    final slash = lower.lastIndexOf(Platform.pathSeparator);
    final altSlash = lower.lastIndexOf('/');
    final base = lower.substring((slash > altSlash ? slash : altSlash) + 1);
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    const allowed = <String>{
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
      'heic',
    };
    final ext = base.substring(dot + 1);
    return allowed.contains(ext) ? ext : '';
  }

  String _safeDriverPhotoId(String driverId) {
    final cleaned = driverId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    if (cleaned.isEmpty) return 'driver';
    return cleaned;
  }

  Future<String?> _persistPickedDriverPhoto(
    String sourcePath, {
    required String driverId,
  }) async {
    try {
      if (kIsWeb) return null;
      final source = sourcePath.trim();
      if (source.isEmpty) return null;
      final src = File(source);
      if (!await src.exists()) return null;
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}driver_profile_photos',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ext = _driverPhotoExtension(source);
      final safeDriverId = _safeDriverPhotoId(driverId);
      final fileName =
          'driver_${safeDriverId}_${DateTime.now().millisecondsSinceEpoch}'
          '${ext.isEmpty ? '' : '.$ext'}';
      final target = File('${dir.path}${Platform.pathSeparator}$fileName');
      await src.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<ImageSource?> _askProfilePhotoSource() async {
    final theme = _themeTokens(
      (widget.themeListenable ?? driverThemeNotifier).value,
    );
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: theme.bottomSheetBackground,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: theme.accentPrimary,
              ),
              title: Text(
                _tr(
                  nl: 'Foto kiezen',
                  en: 'Choose photo',
                  fr: 'Choisir une photo',
                  es: 'Elegir foto',
                ),
                style: TextStyle(color: theme.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: theme.accentPrimary,
              ),
              title: Text(
                _tr(
                  nl: 'Selfie nemen',
                  en: 'Take selfie',
                  fr: 'Prendre un selfie',
                  es: 'Tomar selfie',
                ),
                style: TextStyle(color: theme.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.close, color: theme.textMuted),
              title: Text(
                _tr(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
                style: TextStyle(color: theme.textMuted),
              ),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoSelectionError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Foto kon niet worden gekozen.',
            en: 'Photo could not be selected.',
            fr: 'La photo n’a pas pu être sélectionnée.',
            es: 'No se pudo seleccionar la foto.',
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSaveProfilePhoto(
    DriverProfile driver,
    ImageSource source,
  ) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return;
      final persisted = await _persistPickedDriverPhoto(
        picked.path,
        driverId: driver.id,
      );
      final nextPath = (persisted ?? '').trim();
      if (nextPath.isEmpty) return;
      final standaloneOnly = !_isDriverInNotifier(driver.id);
      if (standaloneOnly) {
        debugPrint(
          '[DRIVER_DOCS_SELF][PHOTO_SAVE] mode=standalone_session_only inventory_sync=skipped',
        );
      } else {
        updateDriver(driver.id, driver.copyWith(profilePhotoPath: nextPath));
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            standaloneOnly
                ? _tr(
                    nl: 'Pasfoto opgeslagen op dit toestel.',
                    en: 'Profile photo saved on this device.',
                    fr: 'Photo de profil enregistrée sur cet appareil.',
                    es: 'Foto de perfil guardada en este dispositivo.',
                  )
                : _tr(
                    nl: 'Pasfoto opgeslagen.',
                    en: 'Profile photo saved.',
                    fr: 'Photo de profil enregistrée.',
                    es: 'Foto de perfil guardada.',
                  ),
          ),
        ),
      );
    } catch (_) {
      _showPhotoSelectionError();
    }
  }

  Future<void> _onProfilePhotoActionTap(DriverProfile driver) async {
    final source = await _askProfilePhotoSource();
    if (source == null) return;
    try {
      await _pickAndSaveProfilePhoto(driver, source);
    } catch (_) {
      _showPhotoSelectionError();
    }
  }

  Widget _profilePhotoActionCard(
    DriverProfile driver, {
    ActiveDriverSession? session,
    required _DriverDocumentsThemeTokens theme,
  }) {
    final path = driver.profilePhotoPath?.trim() ?? '';
    final hasLocalPhoto = _driverPhotoExists(path);
    final networkUrl = _driverNetworkPhotoUrl(driver, session);
    final hasPhoto = hasLocalPhoto || networkUrl != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: _panelCircleDecoration(theme),
            child: ClipOval(
              child: hasLocalPhoto
                  ? Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          _driverInitials(driver),
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  : (networkUrl != null
                        ? Image.network(
                            networkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                _driverInitials(driver),
                                style: TextStyle(
                                  color: theme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              _driverInitials(driver),
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    nl: 'Pasfoto',
                    en: 'Profile photo',
                    fr: 'Photo de profil',
                    es: 'Foto de perfil',
                  ),
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhoto
                      ? _tr(
                          nl: 'Foto aanwezig',
                          en: 'Photo available',
                          fr: 'Photo disponible',
                          es: 'Foto disponible',
                        )
                      : _tr(
                          nl: 'Nog geen pasfoto',
                          en: 'No profile photo yet',
                          fr: 'Pas encore de photo',
                          es: 'Aún sin foto',
                        ),
                  style: TextStyle(
                    color: theme.textMuted.withOpacity(0.92),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accentPrimary.withOpacity(0.98),
              side: BorderSide(color: theme.panelBorder),
              backgroundColor:
                  (theme.panelGradient as LinearGradient).colors.first,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            onPressed: () => _onProfilePhotoActionTap(driver),
            child: Text(
              _tr(nl: 'Wijzigen', en: 'Change', fr: 'Modifier', es: 'Cambiar'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, lang, _) {
        return ValueListenableBuilder<DriverThemeVariant>(
          valueListenable: widget.themeListenable ?? driverThemeNotifier,
          builder: (context, themeVariant, _) {
            final theme = _themeTokens(themeVariant);
            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                foregroundColor: theme.textPrimary,
                title: Text(
                  _tr(
                    nl: 'Mijn documenten',
                    en: 'My documents',
                    fr: 'Mes documents',
                    es: 'Mis documentos',
                  ),
                  style: TextStyle(color: theme.textPrimary),
                ),
              ),
              body: ValueListenableBuilder<ActiveDriverSession?>(
                valueListenable: activeDriverSessionNotifier,
                builder: (context, session, _) {
                  if (session == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _tr(
                            nl: 'Log in met je chauffeur-ID om je documenten te zien.',
                            en: 'Sign in with your driver ID to view your documents.',
                            fr: 'Connectez-vous avec votre ID chauffeur pour voir vos documents.',
                            es: 'Inicia sesión con tu ID de conductor para ver tus documentos.',
                          ),
                          style: TextStyle(color: theme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final driver = _driverForSession(session);
                  if (driver == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _tr(
                            nl: 'Je chauffeurprofiel is niet gevonden in deze app. Neem contact op met je bedrijf.',
                            en: 'Your driver profile was not found in this app. Contact your company.',
                            fr: 'Profil chauffeur introuvable dans cette application. Contactez votre entreprise.',
                            es: 'No se encontró tu perfil de conductor en esta app. Contacta a tu empresa.',
                          ),
                          style: TextStyle(color: theme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return ValueListenableBuilder<List<DriverDocument>>(
                    valueListenable: driverDocumentsNotifier,
                    builder: (context, _, __) {
                      final docs = DriverDocumentsStore.instance
                          .documentsVisibleForDriver(driver.id);
                      final scopedTenant = (session.tenantId ?? '').trim();
                      final scopedCompany = (session.companyId ?? '').trim();
                      final scopedDriver = session.driverId.trim();
                      final pending = docs
                          .where(
                            (e) =>
                                e.status ==
                                DriverDocumentStatuses.pendingReview,
                          )
                          .length;

                      final hasCoreGap = DriverDocumentsStore.instance
                          .hasCoreDocumentGapForDriver(driver.id);
                      final actionRequired = docs.isEmpty || hasCoreGap;
                      final requiredDocs = _requiredDocumentDefs
                          .map(
                            (def) => (
                              def: def,
                              doc: _bestRequiredDocForScope(
                                tenantId: scopedTenant,
                                companyId: scopedCompany,
                                driverId: scopedDriver,
                                types: def.matchTypes,
                              ),
                            ),
                          )
                          .toList(growable: false);
                      final presentRequired = requiredDocs
                          .where((entry) => entry.doc != null)
                          .length;

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: _cardDecoration(theme),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: _panelCircleDecoration(theme),
                                      child: Icon(
                                        Icons.verified_user_outlined,
                                        color: theme.accentPrimary.withOpacity(
                                          0.98,
                                        ),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _tr(
                                          nl: 'Documentstatus',
                                          en: 'Document status',
                                          fr: 'Statut des documents',
                                          es: 'Estado de documentos',
                                        ),
                                        style: TextStyle(
                                          color: theme.textPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _tr(
                                    nl: '$presentRequired/4 compleet',
                                    en: '$presentRequired/4 complete',
                                    fr: '$presentRequired/4 complets',
                                    es: '$presentRequired/4 completos',
                                  ),
                                  style: TextStyle(
                                    color: theme.textMuted.withOpacity(0.92),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                _chip(
                                  _tr(
                                    nl: actionRequired
                                        ? 'Actie vereist'
                                        : 'Documenten aanwezig',
                                    en: actionRequired
                                        ? 'Action required'
                                        : 'Documents available',
                                    fr: actionRequired
                                        ? 'Action requise'
                                        : 'Documents disponibles',
                                    es: actionRequired
                                        ? 'Acción requerida'
                                        : 'Documentos disponibles',
                                  ),
                                  actionRequired ? _orange : _green,
                                ),
                              ],
                            ),
                          ),
                          _profilePhotoActionCard(
                            driver,
                            session: session,
                            theme: theme,
                          ),
                          const SizedBox(height: 2),
                          _sectionTitle(
                            _tr(
                              nl: 'Vereiste documenten',
                              en: 'Required documents',
                              fr: 'Documents requis',
                              es: 'Documentos requeridos',
                            ),
                            theme,
                          ),
                          const SizedBox(height: 8),
                          ...requiredDocs.map((entry) {
                            final def = entry.def;
                            final doc = entry.doc;
                            final state = _docStateChip(doc);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                              decoration: _cardDecoration(theme),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: _panelCircleDecoration(theme),
                                    child: Icon(
                                      def.icon,
                                      size: 18,
                                      color: theme.accentPrimary.withOpacity(
                                        0.96,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _requiredDocLabel(def),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: theme.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            height: 1.2,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        _chip(state.text, state.color),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: theme.accentPrimary
                                          .withOpacity(0.95),
                                      side: BorderSide(
                                        color: theme.panelBorder,
                                      ),
                                      backgroundColor:
                                          (theme.panelGradient
                                                  as LinearGradient)
                                              .colors
                                              .first,
                                      minimumSize: const Size(0, 34),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    onPressed: () =>
                                        showDriverDocumentEditorSheet(
                                          context,
                                          driver: driver,
                                          existing: doc,
                                          driverSelfService: true,
                                          initialDocumentType: doc == null
                                              ? def.matchTypes.first
                                              : null,
                                        ),
                                    child: Text(
                                      doc == null
                                          ? _tr(
                                              nl: 'Toevoegen',
                                              en: 'Add',
                                              fr: 'Ajouter',
                                              es: 'Añadir',
                                            )
                                          : _tr(
                                              nl: 'Beheer',
                                              en: 'Manage',
                                              fr: 'Gérer',
                                              es: 'Gestionar',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                          if (docs.isEmpty)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: _cardDecoration(theme),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _tr(
                                      nl: 'Nog geen documenten',
                                      en: 'No documents yet',
                                      fr: 'Pas encore de documents',
                                      es: 'Aún sin documentos',
                                    ),
                                    style: TextStyle(
                                      color: theme.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _tr(
                                      nl: 'Voeg je rijbewijs, bestuurderspas of andere vereiste documenten toe.',
                                      en: 'Add your driving license, driver card, or other required documents.',
                                      fr: 'Ajoutez votre permis, carte chauffeur ou autres documents requis.',
                                      es: 'Añade tu permiso, tarjeta de conductor u otros documentos requeridos.',
                                    ),
                                    style: TextStyle(
                                      color: theme.textMuted.withOpacity(0.92),
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            if (pending > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  _tr(
                                    nl: 'Documenten in behandeling worden zichtbaar voor je bedrijf en moeten nog nagekeken worden.',
                                    en: 'Documents under review are visible to your company and still need to be checked.',
                                    fr: 'Les documents en cours de vérification sont visibles par votre entreprise et doivent encore être contrôlés.',
                                    es: 'Los documentos en revisión son visibles para tu empresa y aún deben comprobarse.',
                                  ),
                                  style: TextStyle(
                                    color: theme.textMuted.withOpacity(0.92),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            _sectionTitle(
                              _tr(
                                nl: 'Geüploade documenten',
                                en: 'Uploaded documents',
                                fr: 'Documents téléversés',
                                es: 'Documentos subidos',
                              ),
                              theme,
                            ),
                            const SizedBox(height: 8),
                            ...docs.map(
                              (doc) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _driverSelfDocTile(context, doc, theme),
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.accentSecondary,
                              foregroundColor: theme.primaryButtonForeground,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => showDriverDocumentEditorSheet(
                              context,
                              driver: driver,
                              driverSelfService: true,
                            ),
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(
                              _tr(
                                nl: 'Document toevoegen',
                                en: 'Add document',
                                fr: 'Ajouter un document',
                                es: 'Añadir documento',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _tr(
                              nl: 'Gevoelige documenten moeten in productie veilig en versleuteld worden opgeslagen.',
                              en: 'Sensitive documents must be stored securely and encrypted in production.',
                              fr: 'Les documents sensibles doivent être stockés de manière sécurisée et chiffrée en production.',
                              es: 'Los documentos sensibles deben almacenarse de forma segura y cifrada en producción.',
                            ),
                            style: TextStyle(
                              color: theme.textSubtle.withOpacity(0.9),
                              fontSize: 11.2,
                              height: 1.35,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSelfDriverDocument(
    BuildContext context,
    DriverDocument doc,
  ) async {
    final source = driverDocumentArtifactSource(doc);
    debugPrint('[DRIVER_DOC_OPEN][SELF_SOURCE] source=$source');
    if (source == 'missing') {
      debugPrint('[DRIVER_DOC_OPEN][SELF_FAILED] reason=artifact_missing');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Documentbestand niet beschikbaar.',
              en: 'Document file not available.',
              fr: 'Fichier indisponible.',
              es: 'Archivo no disponible.',
            ),
          ),
        ),
      );
      return;
    }
    if (source == 'local') {
      await openDriverDocumentFile(context, doc.filePath, _lang);
      return;
    }

    final session = activeDriverSessionNotifier.value;
    final tenantId = doc.tenantId.trim();
    final companyId = doc.companyId.trim();
    final driverId = doc.driverId.trim();
    final documentId = doc.documentId.trim();
    final token = session == null ? null : _selfDriverDocsBearerToken(session);
    if (token == null ||
        tenantId.isEmpty ||
        companyId.isEmpty ||
        driverId.isEmpty ||
        documentId.isEmpty) {
      debugPrint(
        '[DRIVER_DOC_OPEN][SELF_FAILED] reason=missing_scope_or_token',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Cloud documenttoegang vereist een actieve bedrijfssessie.',
              en: 'Cloud document access requires an active company session.',
              fr: 'L’accès aux documents cloud nécessite une session entreprise active.',
              es: 'El acceso a documentos en la nube requiere una sesión activa de empresa.',
            ),
          ),
        ),
      );
      return;
    }

    debugPrint(
      '[DRIVER_DOC_OPEN][SELF_REQUEST] endpoint=/admin/driver-documents/file',
    );
    try {
      final downloaded = await downloadAdminDriverDocumentFile(
        bookingBaseUrl: kBookingBaseUrl,
        companySessionToken: token,
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        documentId: documentId,
      );
      final saved =
          downloaded.localPath.trim().isNotEmpty &&
          await File(downloaded.localPath).exists();
      if (!saved) {
        debugPrint('[DRIVER_DOC_OPEN][SELF_FAILED] reason=cache_save_failed');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                nl: 'Kon document niet openen. Probeer opnieuw.',
                en: 'Could not open document. Please try again.',
                fr: 'Impossible d’ouvrir le document. Réessayez.',
                es: 'No se pudo abrir el documento. Inténtalo de nuevo.',
              ),
            ),
          ),
        );
        return;
      }
      if (!context.mounted) return;
      await openDriverDocumentFile(context, downloaded.localPath, _lang);
    } catch (e) {
      final err = e.toString().toLowerCase();
      var reason = 'download_failed';
      if (err.contains('404')) reason = 'not_found';
      if (err.contains('401') || err.contains('403')) reason = 'unauthorized';
      if (err.contains('timeout')) reason = 'timeout';
      debugPrint('[DRIVER_DOC_OPEN][SELF_FAILED] reason=$reason');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Kon document niet openen. Probeer opnieuw.',
              en: 'Could not open document. Please try again.',
              fr: 'Impossible d’ouvrir le document. Réessayez.',
              es: 'No se pudo abrir el documento. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
    }
  }

  Widget _driverSelfDocTile(
    BuildContext context,
    DriverDocument doc,
    _DriverDocumentsThemeTokens theme,
  ) {
    bool isBackendSynced(DriverDocument d) =>
        d.storageState.trim().toLowerCase() == 'stored' ||
        d.backendSyncedAt.trim().isNotEmpty;
    bool hasBackendMetadata(DriverDocument d) =>
        d.backendFileName.trim().isNotEmpty ||
        d.backendContentType.trim().isNotEmpty ||
        d.backendSizeBytes > 0 ||
        d.storageState.trim().isNotEmpty ||
        d.backendSyncedAt.trim().isNotEmpty;
    String storageLabel(DriverDocument d) {
      if (d.backendPendingDelete) {
        return _tr(
          nl: 'Verwijderen in wachtrij',
          en: 'Delete pending',
          fr: 'Suppression en attente',
          es: 'Eliminacion pendiente',
        );
      }
      if (d.backendPendingUpload) {
        return _tr(
          nl: 'Synchronisatie in wachtrij',
          en: 'Sync pending',
          fr: 'Synchronisation en attente',
          es: 'Sincronizacion pendiente',
        );
      }
      if (d.backendSyncError.trim().isNotEmpty) {
        return _tr(
          nl: 'Synchronisatie opnieuw proberen',
          en: 'Sync needs retry',
          fr: 'Nouvelle tentative de synchro requise',
          es: 'Sincronizacion requiere reintento',
        );
      }
      if (isBackendSynced(d)) {
        return _tr(
          nl: 'In cloud opgeslagen',
          en: 'Cloud saved',
          fr: 'Enregistré dans le cloud',
          es: 'Guardado en la nube',
        );
      }
      if (d.filePath.trim().isNotEmpty) {
        return _tr(
          nl: 'Op dit toestel opgeslagen',
          en: 'Saved on this device',
          fr: 'Enregistré sur cet appareil',
          es: 'Guardado en este dispositivo',
        );
      }
      if (hasBackendMetadata(d)) {
        return _tr(
          nl: 'Cloud document',
          en: 'Cloud document',
          fr: 'Document cloud',
          es: 'Documento en la nube',
        );
      }
      return _tr(
        nl: 'Alleen lokale metadata',
        en: 'Local metadata only',
        fr: 'Métadonnées locales uniquement',
        es: 'Solo metadatos locales',
      );
    }

    final docArtifactSource = driverDocumentArtifactSource(doc);
    final canOpenDocument =
        docArtifactSource == 'local' || docArtifactSource == 'backend';

    final typeLabel = driverDocumentTypeLabel(doc.documentType, _lang);
    final expiredVisual =
        doc.isExpiredByDate || doc.status == DriverDocumentStatuses.expired;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(
        theme,
        borderColor: expiredVisual
            ? _orange.withOpacity(0.55)
            : theme.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            typeLabel,
            style: TextStyle(
              color: theme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.title.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                doc.title,
                style: TextStyle(
                  color: theme.textPrimary.withOpacity(0.9),
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${_tr(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: ${driverDocumentStatusLabel(doc.status, _lang)}'
            '${doc.isExpiredByDate && doc.status != DriverDocumentStatuses.expired ? ' (${_tr(nl: 'datum verlopen', en: 'date expired', fr: 'date expirée', es: 'fecha caducada')})' : ''}',
            style: TextStyle(
              color: expiredVisual ? _orange : theme.textMuted,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.expiryDate.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_tr(nl: 'Vervaldatum', en: 'Expiry', fr: 'Expiration', es: 'Caducidad')}: ${doc.expiryDate}',
                style: TextStyle(fontSize: 11, color: theme.textSubtle),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (doc.filePath.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            driverDocAttachmentPreview(doc.filePath, _lang),
          ],
          const SizedBox(height: 6),
          Text(
            storageLabel(doc),
            style: TextStyle(
              color: theme.textMuted.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: theme.accentPrimary.withOpacity(0.95),
                backgroundColor:
                    (theme.panelGradient as LinearGradient).colors.first,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: !canOpenDocument
                  ? null
                  : () => _openSelfDriverDocument(context, doc),
              child: Text(
                _tr(nl: 'Openen', en: 'Open', fr: 'Ouvrir', es: 'Abrir'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
