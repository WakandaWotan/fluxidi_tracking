import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_document_sheet.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Directory, File, Platform;

/// Chauffeur-facing compliance documents (same store as company admin).
class DriverMyDocumentsPage extends StatefulWidget {
  const DriverMyDocumentsPage({super.key});

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

class _DriverMyDocumentsPageState extends State<DriverMyDocumentsPage> {
  final ImagePicker _imagePicker = ImagePicker();
  static const Color _bg = Color(0xFF07080C);
  static const Color _card = Color(0xFF101113);
  static const Color _panel = Color(0xFF15120A);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _green = Color(0xFF4ADE80);
  static const Color _red = Color(0xFFF97373);
  static const Color _orange = Color(0xFFF59E0B);
  static const Color _muted = Color(0xFFA3A3A3);

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
      return;
    }
    final tenantId = (session.tenantId ?? '').trim();
    final companyId = (session.companyId ?? '').trim();
    final driverId = session.driverId.trim();
    final companySessionToken =
        (activeCompanySessionNotifier.value?.companySessionToken ?? '').trim();
    if (companySessionToken.isEmpty) {
      debugPrint(
        '[DRIVER_DOCS][UI_REFRESH_SKIP] reason=missing_company_session_token',
      );
      return;
    }
    if (tenantId.isEmpty || companyId.isEmpty || driverId.isEmpty) {
      debugPrint('[DRIVER_DOCS][UI_REFRESH_SKIP] reason=missing_scope');
      return;
    }
    try {
      await DriverDocumentsStore.instance.refreshDriverDocumentsFromBackend(
        bookingBaseUrl: appConfig.bookingBaseUrl,
        companySessionToken: companySessionToken,
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
      );
      debugPrint('[DRIVER_DOCS][UI_REFRESH_DONE] ok=true');
    } catch (_) {
      debugPrint('[DRIVER_DOCS][UI_REFRESH_DONE] ok=false');
    }
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
    switch (status) {
      case DriverDocumentStatuses.approved:
        return 5;
      case DriverDocumentStatuses.pendingReview:
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
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return matches.first;
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

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _gold.withOpacity(0.96),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  DriverProfile? _driverForSession(ActiveDriverSession session) {
    final sessionDriverId = session.driverId.trim();
    final sessionCompanyId = (session.companyId ?? '').trim();
    for (final d in driversNotifier.value) {
      if (d.id.trim() != sessionDriverId) continue;
      final driverCompanyId = (d.companyId ?? '').trim();
      if (sessionCompanyId.isNotEmpty && driverCompanyId.isNotEmpty) {
        if (sessionCompanyId != driverCompanyId) continue;
      }
      return d;
    }
    return null;
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
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF141B2F),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _tr(
                  nl: 'Foto kiezen',
                  en: 'Choose photo',
                  fr: 'Choisir une photo',
                  es: 'Elegir foto',
                ),
              ),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(
                _tr(
                  nl: 'Selfie nemen',
                  en: 'Take selfie',
                  fr: 'Prendre un selfie',
                  es: 'Tomar selfie',
                ),
              ),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(
                _tr(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
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
      updateDriver(driver.id, driver.copyWith(profilePhotoPath: nextPath));
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
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
  }) {
    final path = driver.profilePhotoPath?.trim() ?? '';
    final hasLocalPhoto = _driverPhotoExists(path);
    final networkUrl = _driverNetworkPhotoUrl(driver, session);
    final hasPhoto = hasLocalPhoto || networkUrl != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF17120A),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.42)),
            ),
            child: ClipOval(
              child: hasLocalPhoto
                  ? Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          _driverInitials(driver),
                          style: const TextStyle(
                            color: Colors.white,
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              _driverInitials(driver),
                              style: const TextStyle(
                                color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white,
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
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold.withOpacity(0.98),
              side: BorderSide(color: _gold.withOpacity(0.44)),
              backgroundColor: _panel,
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
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            title: Text(
              _tr(
                nl: 'Mijn documenten',
                en: 'My documents',
                fr: 'Mes documents',
                es: 'Mis documentos',
              ),
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
                      style: const TextStyle(color: Colors.white70),
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
                      style: const TextStyle(color: Colors.white70),
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
                  final pending = docs
                      .where(
                        (e) => e.status == DriverDocumentStatuses.pendingReview,
                      )
                      .length;

                  final hasCoreGap = DriverDocumentsStore.instance
                      .hasCoreDocumentGapForDriver(driver.id);
                  final actionRequired = docs.isEmpty || hasCoreGap;
                  final requiredDocs = _requiredDocumentDefs
                      .map(
                        (def) => (
                          def: def,
                          doc: _bestDocForTypes(docs, def.matchTypes),
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
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _gold.withOpacity(0.30)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _gold.withOpacity(0.15),
                                    border: Border.all(
                                      color: _gold.withOpacity(0.45),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.verified_user_outlined,
                                    color: _gold.withOpacity(0.98),
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
                                    style: const TextStyle(
                                      color: Colors.white,
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
                                color: Colors.white.withOpacity(0.72),
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
                      _profilePhotoActionCard(driver, session: session),
                      const SizedBox(height: 2),
                      _sectionTitle(
                        _tr(
                          nl: 'Vereiste documenten',
                          en: 'Required documents',
                          fr: 'Documents requis',
                          es: 'Documentos requeridos',
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...requiredDocs.map((entry) {
                        final def = entry.def;
                        final doc = entry.doc;
                        final state = _docStateChip(doc);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _gold.withOpacity(0.26)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _panel,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _gold.withOpacity(0.35),
                                  ),
                                ),
                                child: Icon(
                                  def.icon,
                                  size: 18,
                                  color: _gold.withOpacity(0.96),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _requiredDocLabel(def),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
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
                                  foregroundColor: _gold.withOpacity(0.95),
                                  side: BorderSide(
                                    color: _gold.withOpacity(0.38),
                                  ),
                                  backgroundColor: _panel,
                                  minimumSize: const Size(0, 34),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                onPressed: () => showDriverDocumentEditorSheet(
                                  context,
                                  driver: driver,
                                  driverSelfService: true,
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
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _gold.withOpacity(0.28)),
                          ),
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
                                style: const TextStyle(
                                  color: Colors.white,
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
                                  color: Colors.white.withOpacity(0.72),
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
                                color: Colors.white.withOpacity(0.72),
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
                        ),
                        const SizedBox(height: 8),
                        ...docs.map(
                          (doc) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _driverSelfDocTile(context, doc),
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: Colors.black,
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
                          color: Colors.white.withOpacity(0.54),
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
  }

  Widget _driverSelfDocTile(BuildContext context, DriverDocument doc) {
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
      if (d.backendSyncError.trim().isNotEmpty) {
        return _tr(
          nl: 'Synchronisatie mislukt',
          en: 'Sync failed',
          fr: 'Échec de synchronisation',
          es: 'Sincronización fallida',
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

    bool canOpenLocal(DriverDocument d) {
      final path = d.filePath.trim();
      if (path.isEmpty || kIsWeb) return false;
      try {
        return File(path).existsSync();
      } catch (_) {
        return false;
      }
    }

    final typeLabel = driverDocumentTypeLabel(doc.documentType, _lang);
    final expiredVisual =
        doc.isExpiredByDate || doc.status == DriverDocumentStatuses.expired;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expiredVisual
              ? _orange.withOpacity(0.55)
              : _gold.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            typeLabel,
            style: const TextStyle(
              color: Colors.white,
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
                  color: Colors.white.withOpacity(0.88),
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
              color: expiredVisual ? _orange : Colors.white70,
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
                style: const TextStyle(fontSize: 11, color: Colors.white54),
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
              color: Colors.white.withOpacity(0.70),
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
                foregroundColor: _gold.withOpacity(0.95),
                backgroundColor: _panel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: !canOpenLocal(doc)
                  ? null
                  : () => openDriverDocumentFile(context, doc.filePath, _lang),
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
