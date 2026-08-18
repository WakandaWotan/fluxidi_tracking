import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_fleet_operational.dart';
import 'package:fluxidi_tracking/company/extra_vehicle_addon_purchase.dart';
import 'package:fluxidi_tracking/company/fluxidi_play_distribution.dart';
import 'package:fluxidi_tracking/company/subscription_fiscal_treatment.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/driver_creator_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

@immutable
class _VehicleThemeTokens {
  const _VehicleThemeTokens({
    required this.palette,
    required this.pageBg,
    required this.cardBg,
    required this.panelBg,
    required this.accent,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.sheetBg,
    required this.inputFill,
    required this.dropdownBg,
    required this.inputBorder,
    required this.overlayDark,
    required this.overlaySoft,
    required this.success,
    required this.linkedAccent,
    required this.danger,
  });

  final BusinessThemePalette palette;
  final Color pageBg;
  final Color cardBg;
  final Color panelBg;
  final Color accent;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;
  final Color sheetBg;
  final Color inputFill;
  final Color dropdownBg;
  final Color inputBorder;
  final Color overlayDark;
  final Color overlaySoft;
  final Color success;
  final Color linkedAccent;
  final Color danger;
}

_VehicleThemeTokens _vehicleThemeTokensFor(BusinessThemeVariant variant) {
  final palette = paletteForBusinessTheme(variant);
  final isClean = variant == BusinessThemeVariant.cleanProfessional;
  final isGold = variant == BusinessThemeVariant.brandSignatureGold;
  final linkedAccent = variant == BusinessThemeVariant.executiveGold
      ? const Color(0xFF6BCBFF)
      : palette.accent;
  return _VehicleThemeTokens(
    palette: palette,
    pageBg: palette.background,
    cardBg: palette.surface,
    panelBg: palette.surfaceAlt,
    accent: palette.accent,
    border: palette.border.withOpacity(isClean ? 0.9 : 0.62),
    textPrimary: palette.textPrimary,
    textSecondary: palette.textSecondary,
    textMuted: palette.textMuted.withOpacity(isClean ? 0.98 : 0.9),
    textFaint: palette.textMuted.withOpacity(isClean ? 0.9 : 0.74),
    sheetBg: isClean || isGold ? palette.surface : palette.surfaceAlt,
    inputFill: isClean || isGold
        ? palette.surfaceAlt.withOpacity(isClean ? 0.95 : 1)
        : const Color(0xFF0B0B0B),
    dropdownBg: isClean || isGold ? palette.surface : const Color(0xFF111111),
    inputBorder: palette.border.withOpacity(isClean ? 0.8 : 0.44),
    overlayDark: isClean ? const Color(0xB31C2430) : const Color(0xB8000000),
    overlaySoft: isClean ? const Color(0xA61C2430) : const Color(0x8A000000),
    success: palette.success,
    linkedAccent: linkedAccent,
    danger: palette.danger,
  );
}

abstract final class _VehicleComplianceDocumentTypes {
  static const taxiPermit = 'taxi_permit';
  static const registration = 'registration';
  static const inspection = 'inspection';
  static const insurance = 'insurance';
  static const permit = 'permit';
  static const other = 'other';

  static const all = <String>[
    taxiPermit,
    registration,
    inspection,
    insurance,
    permit,
    other,
  ];
}

abstract final class _VehicleComplianceDocumentStatuses {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const expired = 'expired';

  static const all = <String>[pending, approved, rejected, expired];
}

@immutable
class _VehicleComplianceDocument {
  const _VehicleComplianceDocument({
    required this.documentId,
    required this.tenantId,
    required this.companyId,
    required this.vehicleId,
    required this.type,
    required this.title,
    required this.referencePath,
    required this.expiryDate,
    required this.status,
    required this.notes,
    required this.isTestDocument,
    required this.createdAt,
    required this.updatedAt,
  });

  final String documentId;
  final String tenantId;
  final String companyId;
  final String vehicleId;
  final String type;
  final String title;
  final String referencePath;
  final String expiryDate;
  final String status;
  final String notes;
  final bool isTestDocument;
  final String createdAt;
  final String updatedAt;

  _VehicleComplianceDocument copyWith({
    String? documentId,
    String? tenantId,
    String? companyId,
    String? vehicleId,
    String? type,
    String? title,
    String? referencePath,
    String? expiryDate,
    String? status,
    String? notes,
    bool? isTestDocument,
    String? createdAt,
    String? updatedAt,
  }) {
    return _VehicleComplianceDocument(
      documentId: documentId ?? this.documentId,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      vehicleId: vehicleId ?? this.vehicleId,
      type: type ?? this.type,
      title: title ?? this.title,
      referencePath: referencePath ?? this.referencePath,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      isTestDocument: isTestDocument ?? this.isTestDocument,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'document_id': documentId,
      'tenant_id': tenantId,
      'company_id': companyId,
      'vehicle_id': vehicleId,
      'type': type,
      'title': title,
      'reference_path': referencePath,
      'expiry_date': expiryDate,
      'status': status,
      'notes': notes,
      'is_test_document': isTestDocument,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory _VehicleComplianceDocument.fromJson(Map<String, dynamic> json) {
    bool boolField(dynamic value, {bool fallback = false}) {
      if (value is bool) return value;
      final token = (value ?? '').toString().trim().toLowerCase();
      if (token == 'true') return true;
      if (token == 'false') return false;
      return fallback;
    }

    String textField(List<String> keys, {String fallback = ''}) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    return _VehicleComplianceDocument(
      documentId: textField(const ['document_id', 'documentId']),
      tenantId: textField(const ['tenant_id', 'tenantId']),
      companyId: textField(const ['company_id', 'companyId']),
      vehicleId: textField(const ['vehicle_id', 'vehicleId']),
      type: textField(const ['type']),
      title: textField(const ['title']),
      referencePath: textField(const [
        'reference_path',
        'referencePath',
        'reference',
        'path',
      ]),
      expiryDate: textField(const ['expiry_date', 'expiryDate']),
      status: textField(const ['status']),
      notes: textField(const ['notes']),
      isTestDocument: boolField(
        json['is_test_document'] ?? json['isTestDocument'],
      ),
      createdAt: textField(const ['created_at', 'createdAt']),
      updatedAt: textField(const ['updated_at', 'updatedAt']),
    );
  }
}

class _VehicleComplianceDocumentStore {
  _VehicleComplianceDocumentStore._();

  static final _VehicleComplianceDocumentStore instance =
      _VehicleComplianceDocumentStore._();

  final List<_VehicleComplianceDocument> _documents =
      <_VehicleComplianceDocument>[];
  String _loadedScopeKey = '';
  bool _loading = false;

  List<_VehicleComplianceDocument> documentsForVehicle({
    required String tenantId,
    required String companyId,
    required String vehicleId,
  }) {
    final tid = tenantId.trim();
    final cid = companyId.trim();
    final vid = vehicleId.trim();
    return _documents
        .where(
          (doc) =>
              doc.tenantId == tid &&
              doc.companyId == cid &&
              doc.vehicleId == vid,
        )
        .toList(growable: false);
  }

  Future<void> ensureLoaded({
    required String tenantId,
    required String companyId,
  }) async {
    if (kIsWeb) return;
    final tid = tenantId.trim();
    final cid = companyId.trim();
    if (tid.isEmpty || cid.isEmpty) return;
    final scopeKey = '$tid::$cid';
    if (_loading) return;
    if (_loadedScopeKey == scopeKey) return;
    _loading = true;
    try {
      final file = await _scopeFile(tenantId: tid, companyId: cid);
      if (!await file.exists()) {
        _documents.clear();
        _loadedScopeKey = scopeKey;
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        _documents.clear();
        _loadedScopeKey = scopeKey;
        return;
      }
      _documents
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map(
                (row) => _VehicleComplianceDocument.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .where(
                (doc) =>
                    doc.documentId.isNotEmpty &&
                    doc.vehicleId.isNotEmpty &&
                    doc.tenantId == tid &&
                    doc.companyId == cid,
              ),
        );
      _loadedScopeKey = scopeKey;
    } catch (_) {
      // Local-only foundation: keep UI resilient if storage fails.
    } finally {
      _loading = false;
    }
  }

  Future<void> upsert(_VehicleComplianceDocument document) async {
    if (kIsWeb) return;
    final index = _documents.indexWhere(
      (doc) => doc.documentId == document.documentId,
    );
    if (index >= 0) {
      _documents[index] = document;
    } else {
      _documents.add(document);
    }
    await _persistScope(document.tenantId, document.companyId);
  }

  Future<void> remove({
    required String tenantId,
    required String companyId,
    required String documentId,
  }) async {
    if (kIsWeb) return;
    _documents.removeWhere(
      (doc) =>
          doc.documentId == documentId &&
          doc.tenantId == tenantId.trim() &&
          doc.companyId == companyId.trim(),
    );
    await _persistScope(tenantId, companyId);
  }

  Future<void> removeAllForVehicle({
    required String tenantId,
    required String companyId,
    required String vehicleId,
  }) async {
    if (kIsWeb) return;
    final tid = tenantId.trim();
    final cid = companyId.trim();
    final vid = vehicleId.trim();
    _documents.removeWhere(
      (doc) =>
          doc.tenantId == tid && doc.companyId == cid && doc.vehicleId == vid,
    );
    await _persistScope(tid, cid);
  }

  Future<File> _scopeFile({
    required String tenantId,
    required String companyId,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final sanitizedTenant = tenantId.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final sanitizedCompany = companyId.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}tenant_state'
      '${Platform.pathSeparator}vehicle_compliance'
      '${Platform.pathSeparator}tenant_$sanitizedTenant'
      '${Platform.pathSeparator}company_$sanitizedCompany',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(
      '${dir.path}${Platform.pathSeparator}vehicle_compliance_documents_v1.json',
    );
  }

  Future<void> _persistScope(String tenantId, String companyId) async {
    final tid = tenantId.trim();
    final cid = companyId.trim();
    if (tid.isEmpty || cid.isEmpty) return;
    final file = await _scopeFile(tenantId: tid, companyId: cid);
    final scoped = _documents
        .where((doc) => doc.tenantId == tid && doc.companyId == cid)
        .map((doc) => doc.toJson())
        .toList(growable: false);
    await file.writeAsString(jsonEncode(scoped));
    _loadedScopeKey = '$tid::$cid';
  }
}

class VehicleManagementPage extends StatefulWidget {
  const VehicleManagementPage({
    super.key,
    this.autoOpenNewVehicleEditor = false,
    this.popPageAfterSuccessfulNewVehicleSave = false,
  });

  /// When true, opens the canonical new-vehicle editor once after first frame.
  /// Used by first-company fleet bootstrap — not a second CRUD path.
  final bool autoOpenNewVehicleEditor;

  /// When true, after a successful *new* vehicle save the page pops with
  /// `true` so the first-run bootstrap can advance.
  final bool popPageAfterSuccessfulNewVehicleSave;

  @override
  State<VehicleManagementPage> createState() => _VehicleManagementPageState();
}

class _VehicleManagementPageState extends State<VehicleManagementPage>
    with WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();
  static const int _maxPhotosPerVehicle = 5;
  bool _vehicleDocumentsLoaded = false;
  bool _didAutoOpenNewVehicleEditor = false;
  bool _startingExtraVehiclePurchase = false;
  bool _awaitingExtraVehicleActivation = false;
  int _capacityBeforeExtraVehiclePurchase = 0;
  ExtraVehiclePurchaseSession? _extraVehiclePurchaseSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureVehicleDocumentsLoaded(refreshUi: true));
      unawaited(_maybeAutoOpenNewVehicleEditor());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _awaitingExtraVehicleActivation) {
      unawaited(_completeExtraVehicleActivationIfReady());
    }
  }

  Future<void> _maybeAutoOpenNewVehicleEditor() async {
    if (!widget.autoOpenNewVehicleEditor || _didAutoOpenNewVehicleEditor) {
      return;
    }
    _didAutoOpenNewVehicleEditor = true;
    if (!mounted) return;
    if (!await _confirmVehicleUpsellIfNeeded()) {
      if (widget.popPageAfterSuccessfulNewVehicleSave && mounted) {
        Navigator.of(context).pop(false);
      }
      return;
    }
    if (!mounted) return;
    final saved = await _openVehicleEditor();
    if (widget.popPageAfterSuccessfulNewVehicleSave && mounted) {
      Navigator.of(context).pop(saved == true);
    }
  }

  Future<void> _ensureVehicleDocumentsLoaded({bool refreshUi = false}) async {
    final scope = _activeFleetScope();
    if (scope == null) return;
    await _VehicleComplianceDocumentStore.instance.ensureLoaded(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    _vehicleDocumentsLoaded = true;
    if (refreshUi && mounted) setState(() {});
  }

  _VehicleThemeTokens get _theme =>
      _vehicleThemeTokensFor(businessThemeNotifier.value);
  Color get _pageBg => _theme.pageBg;
  Color get _cardBg => _theme.cardBg;
  Color get _panelBg => _theme.panelBg;
  Color get _gold => _theme.accent;
  Color get _textPrimary => _theme.textPrimary;
  Color get _textSecondary => _theme.textSecondary;
  Color get _textMuted => _theme.textMuted;
  Color get _textFaint => _theme.textFaint;
  Color get _sheetBg => _theme.sheetBg;
  Color get _inputFill => _theme.inputFill;
  Color get _dropdownBg => _theme.dropdownBg;
  Color get _inputBorder => _theme.inputBorder;
  Color get _overlayDark => _theme.overlayDark;
  Color get _overlaySoft => _theme.overlaySoft;
  Color get _success => _theme.success;
  Color get _linkedAccent => _theme.linkedAccent;
  Color get _danger => _theme.danger;
  AppLanguage get _lang => appConfig.currentLanguage;

  ButtonStyle _editorOutlinedStyle() {
    final isDark = _theme.palette.isDark;
    return OutlinedButton.styleFrom(
      foregroundColor: isDark ? _gold.withOpacity(0.95) : _textPrimary,
      side: BorderSide(
        color: isDark
            ? _gold.withOpacity(0.44)
            : _theme.border.withOpacity(0.95),
      ),
      backgroundColor: isDark
          ? _panelBg
          : _theme.palette.surfaceAlt.withOpacity(0.92),
    );
  }

  String _t({
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
      case AppLanguage.de:
        return en;
    }
  }

  String _tierLabel(String tierId) {
    for (final t in appConfig.enabledTiers) {
      if (t.id == tierId) return t.labelFor(_lang);
    }
    return tierId;
  }

  /// LIMOUSINE-MARKETPLACE-P2A: optional limousine configuration inside the
  /// existing vehicle editor. Default OFF; explicit category + authoritative
  /// active service class; entitlement-gated read-only state without any
  /// upgrade/checkout CTA. Editing brand/model cannot alter this.
  Widget _limousineVehicleConfigSection({
    required bool limousineEntitled,
    required bool limousineEnabled,
    required String? limousineClassId,
    required ValueChanged<bool> onToggle,
    required ValueChanged<String?> onClassChanged,
  }) {
    final header = Text(
      _t(
        nl: 'Limousineservice (optioneel)',
        en: 'Limousine service (optional)',
        fr: 'Service limousine (optionnel)',
        es: 'Servicio de limusina (opcional)',
      ),
      style: const TextStyle(fontWeight: FontWeight.w700),
    );

    if (!limousineEntitled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _inputFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _inputBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: _textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t(
                      nl: 'Niet beschikbaar in je huidige abonnement.',
                      en: 'Unavailable under your current subscription.',
                      fr: 'Indisponible avec votre abonnement actuel.',
                      es: 'No disponible con tu suscripción actual.',
                    ),
                    style: TextStyle(color: _textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final classes = appConfig.enabledLimousineServiceClasses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _t(
                  nl: 'Limousineservice inschakelen',
                  en: 'Enable limousine service',
                  fr: 'Activer le service limousine',
                  es: 'Activar el servicio de limusina',
                ),
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: limousineEnabled,
              activeColor: _gold,
              activeTrackColor: _gold.withOpacity(
                _theme.palette.isDark ? 0.46 : 0.34,
              ),
              inactiveThumbColor: _textSecondary,
              inactiveTrackColor: _panelBg.withOpacity(0.72),
              onChanged: onToggle,
            ),
          ],
        ),
        if (limousineEnabled) ...[
          const SizedBox(height: 8),
          if (classes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _inputBorder),
              ),
              child: Text(
                _t(
                  nl: 'Er zijn nog geen limousineklassen geconfigureerd.',
                  en: 'No limousine classes are configured yet.',
                  fr: 'Aucune classe de limousine n est encore configurée.',
                  es: 'Aún no hay clases de limusina configuradas.',
                ),
                style: TextStyle(color: _textSecondary),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: limousineClassId,
              isExpanded: true,
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
              iconEnabledColor: _textPrimary,
              iconDisabledColor: _textMuted,
              dropdownColor: _dropdownBg,
              items: classes
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(
                        c.labelFor(_lang),
                        style: TextStyle(color: _textPrimary),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onClassChanged,
              decoration: InputDecoration(
                labelText: _t(
                  nl: 'Limousineklasse *',
                  en: 'Limousine class *',
                  fr: 'Classe de limousine *',
                  es: 'Clase de limusina *',
                ),
                filled: true,
                fillColor: _inputFill,
                labelStyle: TextStyle(color: _textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _inputBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _gold.withOpacity(0.7)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            _t(
              nl: 'Een actieve limousineklasse is vereist. De taxicategorie blijft ongewijzigd.',
              en: 'An active limousine class is required. The taxi category is unaffected.',
              fr: 'Une classe de limousine active est requise. La catégorie taxi reste inchangée.',
              es: 'Se requiere una clase de limusina activa. La categoría de taxi no cambia.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  void _showMissingCompanyScopeSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Backend synchronisatie vereist een actieve bedrijfssessie. Herkoppel of herstel eerst uw bedrijf.',
            en: 'Backend synchronization requires an active company session. Relink or recover your company first.',
            fr: 'La synchronisation backend nécessite une session entreprise active. Reliez ou récupérez d’abord votre entreprise.',
            es: 'La sincronización del backend requiere una sesión activa de empresa. Vuelve a vincular o recuperar tu empresa primero.',
          ),
        ),
      ),
    );
  }

  Future<void> _syncFleetOrShowError() async {
    final scopeId = _activeCompanyIdForFleetUi();
    if (scopeId == null) {
      debugPrint('[FLEET_SYNC][SKIP] reason=missing_active_company_context');
      _showMissingCompanyScopeSnackbar();
      return;
    }
    final ok = await syncFleetInventoryToBackend(
      tenantId: scopeId,
      companyId: scopeId,
    );
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Voertuigen lokaal opgeslagen, maar backend-sync mislukt. Controleer beheerderstoegang of netwerk.',
            en: 'Vehicles were saved locally, but backend sync failed. Check admin access or network.',
            fr: 'Véhicules enregistrés localement, mais la synchronisation backend a échoué. Vérifiez l’accès administrateur ou le réseau.',
            es: 'Los vehículos se guardaron localmente, pero la sincronización backend falló. Verifica el acceso de administrador o la red.',
          ),
        ),
      ),
    );
  }

  Future<bool> _persistVehiclePublicPhotoAfterUpload({
    required String vehicleId,
    required VehicleProfile? existing,
    required String publicPhotoUrl,
    required TextEditingController publicPhotoUrlCtrl,
    required StateSetter setLocalState,
  }) async {
    final url = resolvePublicHttpsMediaUrl(publicPhotoUrl);
    if (url.isEmpty) return false;
    setLocalState(() {
      publicPhotoUrlCtrl.text = url;
    });
    debugPrint(
      '[VEHICLE_PUBLIC_PHOTO][UPLOAD_OK] vehicle=${maskVehicleIdForLog(vehicleId)} has_public_url=true',
    );
    final scopeId = _vehicleMediaScopeId(existing);
    final updated = applyVehiclePublicPhotoUrlToNotifier(
      vehicleId: vehicleId,
      publicPhotoUrl: url,
      companyId: scopeId,
    );
    if (!updated) {
      debugPrint(
        '[VEHICLE_PUBLIC_PHOTO][DEFERRED] vehicle=${maskVehicleIdForLog(vehicleId)} reason=vehicle_not_in_notifier_yet',
      );
      return true;
    }
    await _syncFleetOrShowError();
    return true;
  }

  Future<String?> _resolvePublicPhotoUrlForVehicleSave({
    required String vehicleId,
    required String controllerUrl,
    required String primaryPhotoRef,
    required VehicleProfile? existing,
  }) async {
    final fromController = resolvePublicHttpsMediaUrl(controllerUrl);
    if (fromController.isNotEmpty) return fromController;

    final notifierVehicle = vehicleProfileById(vehicleId);
    final fromNotifier = resolvePublicHttpsMediaUrl(
      notifierVehicle?.publicPhotoUrl ?? '',
    );
    if (fromNotifier.isNotEmpty) return fromNotifier;

    final fromPrimary = resolvePublicHttpsMediaUrl(primaryPhotoRef);
    if (fromPrimary.isNotEmpty) return fromPrimary;

    final localPrimary = primaryPhotoRef.trim();
    if (localPrimary.isEmpty ||
        _isAssetRef(localPrimary) ||
        kIsWeb ||
        !isLocalOrPrivateMediaRef(localPrimary)) {
      return null;
    }
    final scopeId = _vehicleMediaScopeId(existing);
    if (scopeId == null) return null;
    final source = File(localPrimary);
    if (!await source.exists()) return null;
    try {
      final uploaded = await uploadPublicPartnerMedia(
        tenantId: scopeId,
        companyId: scopeId,
        mediaType: 'vehicle_photo',
        entityId: vehicleId,
        filePath: localPrimary,
      );
      final url = (uploaded['url'] ?? '').toString().trim();
      final resolved = resolvePublicHttpsMediaUrl(url);
      if (resolved.isEmpty) return null;
      debugPrint(
        '[VEHICLE_PUBLIC_PHOTO][UPLOAD_OK] vehicle=${maskVehicleIdForLog(vehicleId)} has_public_url=true source=save_promote_local',
      );
      applyVehiclePublicPhotoUrlToNotifier(
        vehicleId: vehicleId,
        publicPhotoUrl: resolved,
        companyId: scopeId,
      );
      return resolved;
    } catch (_) {
      return null;
    }
  }

  bool _isAssetRef(String value) =>
      value.trim().toLowerCase().startsWith('assets/');

  bool _isPublicHttpsUrl(String value) =>
      value.trim().toLowerCase().startsWith('https://');

  bool _isNetworkUrl(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  String _publicVehicleUploadFailureMessage() {
    return _t(
      nl: 'Upload mislukt. Controleer of dit een JPG, PNG of WEBP-afbeelding is.',
      en: 'Upload failed. Please check that this is a JPG, PNG, or WEBP image.',
      fr: 'Échec de l’importation. Vérifiez qu’il s’agit d’une image JPG, PNG ou WEBP.',
      es: 'Error al subir. Comprueba que sea una imagen JPG, PNG o WEBP.',
    );
  }

  String? _vehicleMediaScopeId(VehicleProfile? existing) {
    final cid = _scopedVehicleCompanyId(existing);
    if (cid?.trim().isNotEmpty ?? false) return cid!.trim();
    return _activeCompanyIdForFleetUi();
  }

  Future<void> _useExistingVehiclePhotoAsPublic({
    required String photoRef,
    required String vehicleId,
    required VehicleProfile? existing,
    required TextEditingController publicPhotoUrlCtrl,
    required StateSetter setLocalState,
  }) async {
    final clean = photoRef.trim();
    if (clean.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Selecteer eerst een voertuigfoto.',
              en: 'Select a vehicle photo first.',
              fr: 'Sélectionnez d’abord une photo du véhicule.',
              es: 'Primero selecciona una foto del vehículo.',
            ),
          ),
        ),
      );
      return;
    }
    if (_isAssetRef(clean)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Deze lokale app-afbeelding kan niet als publieke voertuigfoto worden gebruikt.',
              en: 'This local app asset cannot be used as a public vehicle photo.',
              fr: 'Cette ressource locale de l’application ne peut pas être utilisée comme photo publique du véhicule.',
              es: 'Este recurso local de la aplicación no se puede usar como foto pública del vehículo.',
            ),
          ),
        ),
      );
      return;
    }
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Gebruik op web de uploadknop voor publieke voertuigfoto.',
              en: 'On web, use the upload public vehicle photo button.',
              fr: 'Sur le web, utilisez le bouton d’importation de photo publique du véhicule.',
              es: 'En web, usa el botón de subir foto pública del vehículo.',
            ),
          ),
        ),
      );
      return;
    }
    final source = File(clean);
    if (!await source.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'De geselecteerde lokale foto is niet beschikbaar.',
              en: 'The selected local photo is not available.',
              fr: 'La photo locale sélectionnée n’est pas disponible.',
              es: 'La foto local seleccionada no está disponible.',
            ),
          ),
        ),
      );
      return;
    }

    final scopeId = _vehicleMediaScopeId(existing);
    if (scopeId == null) {
      debugPrint('[VEHICLE_MEDIA][SKIP] reason=missing_active_company_context');
      _showMissingCompanyScopeSnackbar();
      return;
    }
    try {
      final uploaded = await uploadPublicPartnerMedia(
        tenantId: scopeId,
        companyId: scopeId,
        mediaType: 'vehicle_photo',
        entityId: vehicleId,
        filePath: clean,
      );
      final url = (uploaded['url'] ?? '').toString().trim();
      if (!_isPublicHttpsUrl(url)) {
        throw Exception('Upload did not return a valid HTTPS URL');
      }
      await _persistVehiclePublicPhotoAfterUpload(
        vehicleId: vehicleId,
        existing: existing,
        publicPhotoUrl: url,
        publicPhotoUrlCtrl: publicPhotoUrlCtrl,
        setLocalState: setLocalState,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Publieke voertuigfoto bijgewerkt.',
              en: 'Public vehicle photo updated.',
              fr: 'Photo publique du véhicule mise à jour.',
              es: 'Foto pública del vehículo actualizada.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_publicVehicleUploadFailureMessage())),
      );
    }
  }

  /// Vehicle row scoped to current local tenant when present; preserves stored id on edit.
  String? _scopedVehicleCompanyId(VehicleProfile? existing) {
    if (existing != null) {
      final t = existing.companyId?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return _activeCompanyIdForFleetUi();
  }

  String? _activeCompanyIdForFleetUi() {
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (profileCompanyId.isNotEmpty) return profileCompanyId;
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) return sessionCompanyId;
    return null;
  }

  bool _driverVisibleInManagementUi(DriverProfile driver) {
    if (isSeededOrPlaceholderDriver(driver)) return false;
    final activeCompanyId = _activeCompanyIdForFleetUi();
    if (activeCompanyId == null) {
      return fleetRecordBelongsToActiveCompanyOrLegacy(driver.companyId);
    }
    // Company-scoped management views avoid showing legacy/companyless rows as active-company data.
    return (driver.companyId?.trim() ?? '') == activeCompanyId;
  }

  bool _vehicleVisibleInManagementUi(VehicleProfile vehicle) {
    // Demo seed (`vh_1` / Tesla Model 3) must never appear as a real fleet row.
    if (isSeededOrPlaceholderVehicle(vehicle)) return false;
    final activeCompanyId = _activeCompanyIdForFleetUi();
    if (activeCompanyId == null) {
      return fleetRecordBelongsToActiveCompanyOrLegacy(vehicle.companyId);
    }
    return (vehicle.companyId?.trim() ?? '') == activeCompanyId;
  }

  bool _canAssignDriverToVehicleInManagementUi(
    DriverProfile driver,
    String? vehicleCompanyId,
  ) {
    final activeCompanyId = _activeCompanyIdForFleetUi();
    if (activeCompanyId == null) {
      return canAssignDriverToVehicleCompany(driver, vehicleCompanyId);
    }
    return (driver.companyId?.trim() ?? '') == activeCompanyId &&
        (vehicleCompanyId?.trim() ?? '') == activeCompanyId;
  }

  DriverProfile? _driverById(String? driverId) {
    if (driverId == null || driverId.trim().isEmpty) return null;
    for (final d in driversNotifier.value) {
      if (d.id == driverId && _driverVisibleInManagementUi(d)) return d;
    }
    return null;
  }

  String _displayVehicleName(String rawName) {
    final trimmed = rawName.trim();
    final normalized = trimmed.toLowerCase();
    if (trimmed.isEmpty ||
        normalized == 'hoofdwagen' ||
        normalized == 'main vehicle' ||
        normalized == 'véhicule principal' ||
        normalized == 'vehículo principal') {
      return _t(
        nl: 'Hoofdwagen',
        en: 'Main vehicle',
        fr: 'Véhicule principal',
        es: 'Vehículo principal',
      );
    }
    return trimmed;
  }

  String _displayColor(String rawColor) {
    final trimmed = rawColor.trim();
    final normalized = trimmed.toLowerCase();
    if (normalized == 'zwart' ||
        normalized == 'black' ||
        normalized == 'noir' ||
        normalized == 'negro') {
      return _t(nl: 'Zwart', en: 'Black', fr: 'Noir', es: 'Negro');
    }
    return trimmed.isEmpty ? '—' : trimmed;
  }

  String _displayDriverName(String rawName) {
    final trimmed = rawName.trim();
    final normalized = trimmed.toLowerCase();
    if (normalized == 'standaard chauffeur' ||
        normalized == 'default driver' ||
        normalized == 'chauffeur standard' ||
        normalized == 'conductor estándar') {
      return _t(
        nl: 'Standaard chauffeur',
        en: 'Default driver',
        fr: 'Chauffeur standard',
        es: 'Conductor estándar',
      );
    }
    return trimmed;
  }

  ({String tenantId, String companyId})? _activeFleetScope() {
    final companyId = _activeCompanyIdForFleetUi();
    if (companyId == null || companyId.trim().isEmpty) return null;
    final scoped = companyId.trim();
    return (tenantId: scoped, companyId: scoped);
  }

  String _vehicleDocumentTypeLabel(String typeId) {
    switch (typeId) {
      case _VehicleComplianceDocumentTypes.taxiPermit:
        return _t(
          nl: 'Taxivergunning / exploitatievergunning',
          en: 'Taxi permit / operating licence',
          fr: 'Licence taxi / licence d’exploitation',
          es: 'Licencia taxi / licencia de explotación',
        );
      case _VehicleComplianceDocumentTypes.registration:
        return _t(
          nl: 'Kentekenbewijs / inschrijving',
          en: 'Registration certificate',
          fr: 'Certificat d’immatriculation',
          es: 'Certificado de matriculación',
        );
      case _VehicleComplianceDocumentTypes.inspection:
        return _t(
          nl: 'Keuringsbewijs',
          en: 'Inspection certificate',
          fr: 'Certificat de contrôle',
          es: 'Certificado de inspección',
        );
      case _VehicleComplianceDocumentTypes.insurance:
        return _t(
          nl: 'Verzekering',
          en: 'Insurance',
          fr: 'Assurance',
          es: 'Seguro',
        );
      case _VehicleComplianceDocumentTypes.permit:
        return _t(
          nl: 'Vergunning / machtiging',
          en: 'Permit / authorization',
          fr: 'Autorisation / permis',
          es: 'Permiso / autorización',
        );
      case _VehicleComplianceDocumentTypes.other:
      default:
        return _t(nl: 'Overig', en: 'Other', fr: 'Autre', es: 'Otro');
    }
  }

  String _vehicleDocumentStatusLabel(String statusId) {
    switch (statusId) {
      case _VehicleComplianceDocumentStatuses.approved:
        return _t(
          nl: 'Goedgekeurd',
          en: 'Approved',
          fr: 'Approuvé',
          es: 'Aprobado',
        );
      case _VehicleComplianceDocumentStatuses.rejected:
        return _t(
          nl: 'Afgekeurd',
          en: 'Rejected',
          fr: 'Refusé',
          es: 'Rechazado',
        );
      case _VehicleComplianceDocumentStatuses.expired:
        return _t(nl: 'Vervallen', en: 'Expired', fr: 'Expiré', es: 'Caducado');
      case _VehicleComplianceDocumentStatuses.pending:
      default:
        return _t(
          nl: 'In behandeling',
          en: 'Pending review',
          fr: 'En cours',
          es: 'En revisión',
        );
    }
  }

  Color _vehicleDocumentStatusColor(String statusId) {
    switch (statusId) {
      case _VehicleComplianceDocumentStatuses.approved:
        return _success;
      case _VehicleComplianceDocumentStatuses.rejected:
        return _danger;
      case _VehicleComplianceDocumentStatuses.expired:
        return const Color(0xFFE6A23C);
      case _VehicleComplianceDocumentStatuses.pending:
      default:
        return _linkedAccent;
    }
  }

  String _vehicleDocumentReferenceLabel(String referencePath) {
    final trimmed = referencePath.trim();
    if (trimmed.isEmpty) {
      return _t(
        nl: 'Geen bijlage',
        en: 'No attachment',
        fr: 'Aucune pièce jointe',
        es: 'Sin adjunto',
      );
    }
    final slash = trimmed.lastIndexOf(Platform.pathSeparator);
    final altSlash = trimmed.lastIndexOf('/');
    final start = slash > altSlash ? slash : altSlash;
    final fileName = start >= 0 ? trimmed.substring(start + 1) : trimmed;
    if (fileName.length <= 42) return fileName;
    return '${fileName.substring(0, 18)}…${fileName.substring(fileName.length - 18)}';
  }

  Future<String?> _persistVehicleComplianceDocumentFile(
    String sourcePath,
  ) async {
    try {
      final source = sourcePath.trim();
      if (source.isEmpty) return null;
      final src = File(source);
      if (!await src.exists()) return null;

      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}tenant_state'
        '${Platform.pathSeparator}vehicle_compliance_files',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final lower = source.toLowerCase();
      final dot = lower.lastIndexOf('.');
      final ext = dot > 0 ? lower.substring(dot + 1) : 'bin';
      final fileName =
          'vehicle_doc_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final target = File('${dir.path}${Platform.pathSeparator}$fileName');
      await src.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _pickVehicleComplianceDocumentAttachment({
    required ImageSource source,
  }) async {
    try {
      if (source == ImageSource.camera || source == ImageSource.gallery) {
        final picked = await _imagePicker.pickImage(
          source: source,
          imageQuality: 90,
        );
        if (picked == null) return null;
        return _persistVehicleComplianceDocumentFile(picked.path);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _pickVehicleComplianceDocumentFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return null;
      final path = picked.files.single.path;
      if (path == null || path.trim().isEmpty) return null;
      return _persistVehicleComplianceDocumentFile(path);
    } catch (_) {
      return null;
    }
  }

  InputDecoration _vehicleDocumentFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: _inputFill,
      labelStyle: TextStyle(color: _textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _gold.withOpacity(0.7)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Future<_VehicleComplianceDocument?> _openVehicleDocumentEditor({
    required String vehicleId,
    required String tenantId,
    required String companyId,
    _VehicleComplianceDocument? existing,
  }) async {
    var typeId = existing?.type ?? _VehicleComplianceDocumentTypes.taxiPermit;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final referenceCtrl = TextEditingController(
      text: existing?.referencePath ?? '',
    );
    final expiryCtrl = TextEditingController(text: existing?.expiryDate ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var statusId =
        existing?.status ?? _VehicleComplianceDocumentStatuses.pending;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: _sheetBg,
              title: Text(
                existing == null
                    ? _t(
                        nl: 'Document toevoegen',
                        en: 'Add document',
                        fr: 'Ajouter un document',
                        es: 'Agregar documento',
                      )
                    : _t(
                        nl: 'Document bewerken',
                        en: 'Edit document',
                        fr: 'Modifier le document',
                        es: 'Editar documento',
                      ),
                style: TextStyle(color: _textPrimary),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: typeId,
                        isExpanded: true,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: _textPrimary,
                        dropdownColor: _dropdownBg,
                        items: _VehicleComplianceDocumentTypes.all
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(
                                  _vehicleDocumentTypeLabel(type),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: _textPrimary),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => typeId = value);
                        },
                        decoration: _vehicleDocumentFieldDecoration(
                          _t(
                            nl: 'Documenttype',
                            en: 'Document type',
                            fr: 'Type de document',
                            es: 'Tipo de documento',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: titleCtrl,
                        style: TextStyle(color: _textPrimary),
                        decoration: _vehicleDocumentFieldDecoration(
                          _t(
                            nl: 'Titel (optioneel)',
                            en: 'Title (optional)',
                            fr: 'Titre (optionnel)',
                            es: 'Título (opcional)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final path =
                                  await _pickVehicleComplianceDocumentAttachment(
                                    source: ImageSource.camera,
                                  );
                              if (path == null) return;
                              referenceCtrl.text = path;
                              setDialogState(() {});
                            },
                            style: _editorOutlinedStyle(),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(
                              _t(
                                nl: 'Foto nemen',
                                en: 'Take photo',
                                fr: 'Prendre une photo',
                                es: 'Tomar foto',
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final path =
                                  await _pickVehicleComplianceDocumentAttachment(
                                    source: ImageSource.gallery,
                                  );
                              if (path == null) return;
                              referenceCtrl.text = path;
                              setDialogState(() {});
                            },
                            style: _editorOutlinedStyle(),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              _t(
                                nl: 'Kies uit galerij',
                                en: 'Choose from gallery',
                                fr: 'Choisir dans la galerie',
                                es: 'Elegir de la galería',
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final path =
                                  await _pickVehicleComplianceDocumentFile();
                              if (path == null) return;
                              referenceCtrl.text = path;
                              setDialogState(() {});
                            },
                            style: _editorOutlinedStyle(),
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              _t(
                                nl: 'Bestand/PDF kiezen',
                                en: 'Choose file/PDF',
                                fr: 'Choisir fichier/PDF',
                                es: 'Elegir archivo/PDF',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: referenceCtrl,
                        style: TextStyle(color: _textPrimary),
                        decoration: _vehicleDocumentFieldDecoration(
                          _t(
                            nl: 'Referentie / pad / bestandsnaam',
                            en: 'Reference / path / file label',
                            fr: 'Référence / chemin / libellé fichier',
                            es: 'Referencia / ruta / etiqueta de archivo',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: expiryCtrl,
                        readOnly: true,
                        style: TextStyle(color: _textPrimary),
                        onTap: () async {
                          final initial = DateTime.tryParse(expiryCtrl.text);
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: initial ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked == null) return;
                          expiryCtrl.text = picked
                              .toIso8601String()
                              .split('T')
                              .first;
                          setDialogState(() {});
                        },
                        decoration: _vehicleDocumentFieldDecoration(
                          _t(
                            nl: 'Vervaldatum',
                            en: 'Expiry date',
                            fr: 'Date d’expiration',
                            es: 'Fecha de caducidad',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: statusId,
                        isExpanded: true,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: _textPrimary,
                        dropdownColor: _dropdownBg,
                        items: _VehicleComplianceDocumentStatuses.all
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(
                                  _vehicleDocumentStatusLabel(status),
                                  style: TextStyle(color: _textPrimary),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => statusId = value);
                        },
                        decoration: _vehicleDocumentFieldDecoration(
                          _t(
                            nl: 'Status',
                            en: 'Status',
                            fr: 'Statut',
                            es: 'Estado',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesCtrl,
                        minLines: 2,
                        maxLines: 4,
                        style: TextStyle(color: _textPrimary),
                        decoration: _vehicleDocumentFieldDecoration(
                          _t(
                            nl: 'Notities',
                            en: 'Notes',
                            fr: 'Notes',
                            es: 'Notas',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(foregroundColor: _textSecondary),
                  child: Text(
                    _t(
                      nl: 'Annuleren',
                      en: 'Cancel',
                      fr: 'Annuler',
                      es: 'Cancelar',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _theme.palette.textOnAccent,
                  ),
                  child: Text(
                    _t(
                      nl: 'Opslaan',
                      en: 'Save',
                      fr: 'Enregistrer',
                      es: 'Guardar',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      titleCtrl.dispose();
      referenceCtrl.dispose();
      expiryCtrl.dispose();
      notesCtrl.dispose();
      return null;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final resolvedTitle = titleCtrl.text.trim().isNotEmpty
        ? titleCtrl.text.trim()
        : _vehicleDocumentTypeLabel(typeId);
    final referencePath = referenceCtrl.text.trim();
    final expiryDate = expiryCtrl.text.trim();
    final notes = notesCtrl.text.trim();
    titleCtrl.dispose();
    referenceCtrl.dispose();
    expiryCtrl.dispose();
    notesCtrl.dispose();

    return _VehicleComplianceDocument(
      documentId:
          existing?.documentId ??
          'vehdoc_${DateTime.now().millisecondsSinceEpoch}',
      tenantId: tenantId,
      companyId: companyId,
      vehicleId: vehicleId,
      type: typeId,
      title: resolvedTitle,
      referencePath: referencePath,
      expiryDate: expiryDate,
      status: statusId,
      notes: notes,
      isTestDocument: false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Widget _vehicleComplianceDocumentChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _vehicleComplianceDocumentsSection({
    required String vehicleId,
    required String tenantId,
    required String companyId,
    required List<_VehicleComplianceDocument> documents,
    required VoidCallback onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t(
            nl: 'Documenten & vergunningen',
            en: 'Documents & permits',
            fr: 'Documents et autorisations',
            es: 'Documentos y permisos',
          ),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Text(
          _t(
            nl: 'Documenten zijn optioneel. Gebruik dit als digitale bedrijfsmap voor uw voertuigen.',
            en: 'Documents are optional. Use this as a digital company folder for your vehicles.',
            fr: 'Les documents sont facultatifs. Utilisez ceci comme dossier numérique pour vos véhicules.',
            es: 'Los documentos son opcionales. Use esto como carpeta digital para sus vehículos.',
          ),
          style: TextStyle(color: _textMuted, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 10),
        if (documents.isEmpty)
          Text(
            _t(
              nl: 'Nog geen voertuigdocumenten opgeslagen.',
              en: 'No vehicle documents saved yet.',
              fr: 'Aucun document véhicule enregistré.',
              es: 'Aún no hay documentos del vehículo guardados.',
            ),
            style: TextStyle(color: _textSecondary, fontSize: 12),
          )
        else
          ...documents.map(
            (doc) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _panelBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _inputBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title.trim().isNotEmpty
                        ? doc.title.trim()
                        : _vehicleDocumentTypeLabel(doc.type),
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _vehicleComplianceDocumentChip(
                        label: _vehicleDocumentTypeLabel(doc.type),
                        color: _linkedAccent,
                      ),
                      _vehicleComplianceDocumentChip(
                        label: _vehicleDocumentStatusLabel(doc.status),
                        color: _vehicleDocumentStatusColor(doc.status),
                      ),
                    ],
                  ),
                  if (doc.expiryDate.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_t(nl: 'Vervalt', en: 'Expires', fr: 'Expire', es: 'Caduca')}: ${doc.expiryDate.trim()}',
                      style: TextStyle(color: _textSecondary, fontSize: 11),
                    ),
                  ],
                  if (doc.referencePath.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_t(nl: 'Referentie', en: 'Reference', fr: 'Référence', es: 'Referencia')}: ${_vehicleDocumentReferenceLabel(doc.referencePath)}',
                      style: TextStyle(color: _textMuted, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (doc.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      doc.notes.trim(),
                      style: TextStyle(color: _textFaint, fontSize: 11),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: _sheetBg,
                            title: Text(
                              _t(
                                nl: 'Document verwijderen?',
                                en: 'Remove document?',
                                fr: 'Supprimer le document ?',
                                es: '¿Eliminar documento?',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(
                                  _t(
                                    nl: 'Annuleren',
                                    en: 'Cancel',
                                    fr: 'Annuler',
                                    es: 'Cancelar',
                                  ),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _danger,
                                  side: BorderSide(
                                    color: _danger.withOpacity(0.55),
                                  ),
                                ),
                                child: Text(
                                  _t(
                                    nl: 'Verwijderen',
                                    en: 'Remove',
                                    fr: 'Supprimer',
                                    es: 'Eliminar',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await _VehicleComplianceDocumentStore.instance.remove(
                          tenantId: tenantId,
                          companyId: companyId,
                          documentId: doc.documentId,
                        );
                        onChanged();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _danger,
                        side: BorderSide(color: _danger.withOpacity(0.5)),
                        backgroundColor: _danger.withOpacity(0.12),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(
                        _t(
                          nl: 'Verwijderen',
                          en: 'Remove',
                          fr: 'Supprimer',
                          es: 'Eliminar',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final created = await _openVehicleDocumentEditor(
              vehicleId: vehicleId,
              tenantId: tenantId,
              companyId: companyId,
            );
            if (created == null) return;
            await _VehicleComplianceDocumentStore.instance.upsert(created);
            onChanged();
          },
          style: _editorOutlinedStyle(),
          icon: const Icon(Icons.note_add_outlined),
          label: Text(
            _t(
              nl: 'Document toevoegen',
              en: 'Add document',
              fr: 'Ajouter un document',
              es: 'Agregar documento',
            ),
          ),
        ),
      ],
    );
  }

  /// Gate for the "add vehicle" action (Patch 2.4H).
  ///
  /// Uses the live paid entitlement (`max_vehicles`) from the company
  /// subscription profile instead of the hardcoded base-plan included count.
  /// Returns true when a new vehicle may be added (current scoped count below
  /// the effective limit); returns false and shows a limit dialog when the
  /// company is at/over its paid vehicle capacity. A transient profile fetch
  /// failure falls back to the base plan limit and never hard-blocks.
  Future<bool> _confirmVehicleUpsellIfNeeded() async {
    final scopedCount = vehiclesNotifier.value
        .where(_vehicleVisibleInManagementUi)
        .length;

    int effectiveMax = includedVehicleLimit > 0 ? includedVehicleLimit : 1;
    String limitSource = 'fallback';
    BackendSubscriptionProfile? liveProfile;

    final scopeId = _activeCompanyIdForFleetUi();
    if (scopeId != null && scopeId.trim().isNotEmpty) {
      try {
        final profile = await fetchCompanySubscriptionProfile(
          tenantId: scopeId,
          companyId: scopeId,
        );
        liveProfile = profile;
        if (profile.maxVehicles > 0) {
          effectiveMax = profile.maxVehicles;
          limitSource = 'profile.maxVehicles';
        } else if (profile.includedVehicles > 0) {
          effectiveMax = profile.includedVehicles;
          limitSource = 'profile.includedVehicles';
        }
      } catch (_) {
        // Keep the safe fallback limit; a transient profile fetch failure must
        // not block a legitimate add within the base plan.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  nl: 'Kon de abonnementslimiet niet vernieuwen. Standaardlimiet gebruikt.',
                  en: 'Could not refresh the subscription limit. Using the default limit.',
                  fr: 'Impossible d’actualiser la limite d’abonnement. Limite par défaut utilisée.',
                  es: 'No se pudo actualizar el límite de la suscripción. Se usó el límite predeterminado.',
                ),
              ),
            ),
          );
        }
      }
    }

    debugPrint(
      '[VEHICLE_ADD_GATE] scoped_count=$scopedCount effective_max=$effectiveMax source=$limitSource',
    );

    if (scopedCount < effectiveMax) return true;
    if (!mounted) return false;
    if (liveProfile == null || scopeId == null || scopeId.trim().isEmpty) {
      return false;
    }
    return _purchaseExtraVehicleSlotThenAllowCreate(
      profile: liveProfile,
      scopeId: scopeId,
      usedVehicles: scopedCount,
      capacity: effectiveMax,
    );
  }

  SubscriptionFiscalVerdict _vehicleFiscalVerdict({
    SubscriptionDisplayQuotes? quotes,
  }) {
    var productTreatment = quotes?.products['extra_vehicle']?.taxTreatment ?? '';
    if (knownSubscriptionTaxTreatment(productTreatment) == null &&
        quotes != null) {
      for (final quote in quotes.products.values) {
        if (knownSubscriptionTaxTreatment(quote.taxTreatment) != null) {
          productTreatment = quote.taxTreatment;
          break;
        }
      }
    }
    final business = localBackendBusinessProfileNotifier.value;
    final company = companyProfileNotifier.value;
    final tax = localBackendTaxProfileNotifier.value;
    return resolveCompanySubscriptionFiscalTreatment(
      quoteTaxTreatment: quotes?.current?.taxTreatment ?? '',
      productQuoteTaxTreatment: productTreatment,
      billingCountry: business?.country ?? '',
      companyCountry: company?.countryCode ?? '',
      vatNumber: resolveAuthoritativeVatNumber(
        businessVatNumber: business?.vatNumber ?? '',
        companyVatNumber: company?.vatNumber ?? '',
      ),
      vatEnabled: tax?.vatEnabled,
    );
  }

  ExtraVehiclePurchasePreview _vehicleExtraVehiclePreview(
    BackendSubscriptionProfile profile, {
    required int usedVehicles,
    required int capacity,
  }) {
    final catalog = resolveSubscriptionCatalogEntryForMarket(
      profile.market.trim().isNotEmpty
          ? profile.market
          : resolveActiveCompanyPricingMarket(),
    );
    var vehicleQty = profile.extraVehicleActiveQuantity;
    if (vehicleQty <= 0) {
      final derived = profile.maxVehicles - profile.includedVehicles;
      vehicleQty = derived > 0 ? derived : 0;
    }
    return extraVehiclePurchasePreviewFromAuthoritative(
      usedVehicles: usedVehicles,
      capacity: capacity,
      catalogExtraVehicleExclCents: catalog.extraVehiclePriceCents,
      profileRecurringAmountCents: profile.recurringAmountCents,
      baseExclCents: profile.lockedPriceCents ?? catalog.normalPriceCents,
      extraDriverUnitExclCents: catalog.extraDriverPriceCents,
      extraVehicleActiveQuantity: vehicleQty,
      extraDriverActiveQuantity: profile.extraDriverActiveQuantity,
    );
  }

  Future<void> _openVatSettingsFromVehicleGate() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BusinessSettingsPage(
          initialSection: BusinessSettingsInitialSection.vatSettings,
        ),
      ),
    );
  }

  Future<void> _showVehicleFiscalBlocked(SubscriptionFiscalVerdict verdict) {
    final language = currentLanguageCode;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheetBg,
        title: Text(
          _t(
            nl: 'Checkout geblokkeerd',
            en: 'Checkout blocked',
            fr: 'Paiement bloqué',
            es: 'Pago bloqueado',
          ),
        ),
        content: Text(
          subscriptionFiscalBlockedMessage(
            languageCode: language,
            missingFields: verdict.missingFields,
          ),
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: _textSecondary),
            child: Text(
              _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_openVatSettingsFromVehicleGate());
            },
            style: TextButton.styleFrom(foregroundColor: _gold),
            child: Text(openVatSettingsActionLabel(language)),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmExtraVehiclePurchaseDialog(
    ExtraVehiclePurchasePreview preview,
  ) async {
    final language = currentLanguageCode;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheetBg,
        title: Text(extraVehicleConfirmActionLabel(language)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(extraVehicleCapacityLine(languageCode: language, preview: preview)),
            const SizedBox(height: 6),
            Text(
              extraVehicleAdditionalSlotLine(
                languageCode: language,
                preview: preview,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              extraVehicleUnitPriceLine(languageCode: language, preview: preview),
            ),
            const SizedBox(height: 6),
            Text(
              extraVehicleNewSubtotalLine(
                languageCode: language,
                preview: preview,
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: _textSecondary),
            child: Text(extraVehicleCancelActionLabel(language)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _gold),
            child: Text(extraVehicleConfirmActionLabel(language)),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  Future<bool> _purchaseExtraVehicleSlotThenAllowCreate({
    required BackendSubscriptionProfile profile,
    required String scopeId,
    required int usedVehicles,
    required int capacity,
  }) async {
    if (!kFluxidiCompanySaasCheckoutEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fluxidiPlaySaasManagedOutsideMessage(
                languageCode: currentLanguageCode,
              ),
            ),
          ),
        );
      }
      return false;
    }
    if (_startingExtraVehiclePurchase || _awaitingExtraVehicleActivation) {
      return false;
    }

    final quotes = await fetchCompanySubscriptionDisplayQuotes(
      tenantId: scopeId,
      companyId: scopeId,
    );
    if (!mounted) return false;
    final fiscal = _vehicleFiscalVerdict(quotes: quotes);
    final session = ExtraVehiclePurchaseSession(
      startingCapacity: capacity,
      fiscal: fiscal,
    );
    _extraVehiclePurchaseSession = session;
    if (session.beginConfirmation() == ExtraVehiclePurchasePhase.blockedFiscal) {
      await _showVehicleFiscalBlocked(fiscal);
      return false;
    }

    final preview = _vehicleExtraVehiclePreview(
      profile,
      usedVehicles: usedVehicles,
      capacity: capacity,
    );
    final confirmed = await _confirmExtraVehiclePurchaseDialog(preview);
    if (!confirmed) {
      session.cancelConfirmation();
      return false;
    }
    if (!session.acceptConfirmation()) return false;
    if (!mounted) return false;

    _startingExtraVehiclePurchase = true;
    _capacityBeforeExtraVehiclePurchase = capacity;
    try {
      final quote =
          quotes?.products['extra_vehicle'] ??
          await fetchCompanySubscriptionCheckoutQuote(
            tenantId: scopeId,
            companyId: scopeId,
            addonCode: 'extra_vehicle',
          );
      if (!mounted) return false;
      if (quote == null || quote.mollieAmountCents == null) {
        session.markUpstreamFailure();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Prijsopgave niet beschikbaar. Probeer later opnieuw.',
                en: 'Checkout quote unavailable. Please try again later.',
                fr: 'Devis indisponible. Réessayez plus tard.',
                es: 'Presupuesto no disponible. Inténtalo más tarde.',
              ),
            ),
          ),
        );
        return false;
      }
      final result = await startCompanySubscriptionAddonCheckout(
        tenantId: scopeId,
        companyId: scopeId,
        addonCode: 'extra_vehicle',
        quantity: 1,
        quoteId: quote.quoteId,
        returnUrl:
            '${appConfig.bookingBaseUrl}/company/subscription/add-ons/checkout/return',
      );
      if (!mounted) return false;
      if (!result.ok) {
        session.markUpstreamFailure();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Activeren is niet gelukt. Controleer je verbinding en probeer opnieuw.',
                en: 'Activation failed. Check your connection and try again.',
                fr: 'Échec de l’activation. Vérifiez votre connexion et réessayez.',
                es: 'Error en la activación. Comprueba tu conexión e inténtalo de nuevo.',
              ),
            ),
          ),
        );
        return false;
      }
      final url = result.checkoutUrl.trim();
      final uri = Uri.tryParse(url);
      if (url.isEmpty || uri == null || !uri.isScheme('https')) {
        session.markUpstreamFailure();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Activeren is niet gelukt. Controleer je verbinding en probeer opnieuw.',
                en: 'Activation failed. Check your connection and try again.',
                fr: 'Échec de l’activation. Vérifiez votre connexion et réessayez.',
                es: 'Error en la activación. Comprueba tu conexión e inténtalo de nuevo.',
              ),
            ),
          ),
        );
        return false;
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return false;
      if (!launched) {
        session.markUpstreamFailure();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Kon het betaalvenster niet openen.',
                en: 'Could not open the payment window.',
                fr: 'Impossible d’ouvrir la fenêtre de paiement.',
                es: 'No se pudo abrir la ventana de pago.',
              ),
            ),
          ),
        );
        return false;
      }
      session.markAwaitingPayment();
      _awaitingExtraVehicleActivation = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Betaalvenster geopend. Na betaling wordt je add-on automatisch bijgewerkt.',
              en: 'Payment window opened. After payment, your add-on will update automatically.',
              fr: 'Fenêtre de paiement ouverte. Après le paiement, votre option sera mise à jour automatiquement.',
              es: 'Ventana de pago abierta. Después del pago, tu complemento se actualizará automáticamente.',
            ),
          ),
        ),
      );
      return false;
    } catch (_) {
      session.markUpstreamFailure();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Er ging iets mis. Probeer opnieuw.',
                en: 'Something went wrong. Please try again.',
                fr: 'Une erreur est survenue. Veuillez réessayer.',
                es: 'Algo salió mal. Inténtalo de nuevo.',
              ),
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _startingExtraVehiclePurchase = false);
    }
  }

  Future<void> _completeExtraVehicleActivationIfReady() async {
    if (!_awaitingExtraVehicleActivation) return;
    final scopeId = _activeCompanyIdForFleetUi();
    if (scopeId == null || scopeId.trim().isEmpty) return;
    try {
      final profile = await fetchCompanySubscriptionProfile(
        tenantId: scopeId,
        companyId: scopeId,
      );
      final nextCapacity = profile.maxVehicles > 0
          ? profile.maxVehicles
          : _capacityBeforeExtraVehiclePurchase;
      if (nextCapacity <= _capacityBeforeExtraVehiclePurchase) {
        return;
      }
      _awaitingExtraVehicleActivation = false;
      _extraVehiclePurchaseSession?.markActivated(newCapacity: nextCapacity);
      if (!mounted) return;
      if (_extraVehiclePurchaseSession?.mayOpenVehicleCreateForm != true) {
        return;
      }
      await _openVehicleEditor();
    } catch (_) {
      // Leave capacity and vehicles unchanged; the user can retry.
    }
  }

  /// Gate for the "add driver" action (Patch 2.7).
  ///
  /// Mirrors [_confirmVehicleUpsellIfNeeded]: it uses the live driver
  /// entitlement (`max_drivers`) from the company subscription profile to
  /// decide whether another driver may be created. The base plan grants
  /// 3 drivers per included vehicle, and each extra vehicle add-on adds 3 more
  /// driver slots. Returns true when the current scoped driver count is below
  /// the effective limit; returns false and shows a limit dialog when the
  /// company is at/over its driver capacity. A transient profile fetch failure
  /// falls back to the base-plan limit and never hard-blocks.
  Future<bool> _confirmDriverAddGate() async {
    final scopedCount = driversNotifier.value
        .where(_driverVisibleInManagementUi)
        .length;

    int effectiveMax =
        (includedVehicleLimit > 0 ? includedVehicleLimit : 1) * 3;
    String limitSource = 'fallback';

    final scopeId = _activeCompanyIdForFleetUi();
    if (scopeId != null && scopeId.trim().isNotEmpty) {
      try {
        final profile = await fetchCompanySubscriptionProfile(
          tenantId: scopeId,
          companyId: scopeId,
        );
        if (profile.maxDrivers > 0) {
          effectiveMax = profile.maxDrivers;
          limitSource = 'profile.maxDrivers';
        } else if (profile.includedVehicles > 0 &&
            profile.includedDriversPerVehicle > 0) {
          effectiveMax =
              profile.includedVehicles * profile.includedDriversPerVehicle;
          limitSource = 'profile.includedVehicles*includedDriversPerVehicle';
        }
      } catch (_) {
        // Keep the safe fallback limit; a transient profile fetch failure must
        // not block a legitimate add within the base plan.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  nl: 'Kon de chauffeurlimiet niet vernieuwen. Standaardlimiet gebruikt.',
                  en: 'Could not refresh the driver limit. Using the default limit.',
                  fr: 'Impossible d’actualiser la limite de chauffeurs. Limite par défaut utilisée.',
                  es: 'No se pudo actualizar el límite de conductores. Se usó el límite predeterminado.',
                ),
              ),
            ),
          );
        }
      }
    }

    debugPrint(
      '[DRIVER_ADD_GATE] scoped_count=$scopedCount effective_max=$effectiveMax source=$limitSource',
    );

    if (scopedCount < effectiveMax) return true;

    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheetBg,
        title: Text(
          _t(
            nl: 'Chauffeurlimiet bereikt',
            en: 'Driver limit reached',
            fr: 'Limite de chauffeurs atteinte',
            es: 'Límite de conductores alcanzado',
          ),
        ),
        content: Text(
          _t(
            nl: 'Je huidige limiet is $effectiveMax chauffeurs.\nJe plan bevat 3 chauffeurs per voertuig. Voeg een extra voertuig toe via Abonnement & facturatie om 3 extra chauffeursplekken te krijgen.',
            en: 'Your current limit is $effectiveMax drivers.\nYour plan includes 3 drivers per vehicle. Add an extra vehicle via Subscription & billing to unlock 3 additional driver slots.',
            fr: 'Votre limite actuelle est de $effectiveMax chauffeurs.\nVotre plan inclut 3 chauffeurs par véhicule. Ajoutez un véhicule via Abonnement et facturation pour débloquer 3 places de chauffeur supplémentaires.',
            es: 'Tu límite actual es de $effectiveMax conductores.\nTu plan incluye 3 conductores por vehículo. Agrega un vehículo en Suscripción y facturación para desbloquear 3 plazas de conductor adicionales.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: _textSecondary),
            child: Text(
              _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
        ],
      ),
    );
    return false;
  }

  Future<DriverProfile?> _openDriverCreator({DriverProfile? existing}) async {
    // Only gate brand-new driver creation; editing an existing driver must
    // never be blocked by the entitlement limit.
    if (existing == null) {
      final allowed = await _confirmDriverAddGate();
      if (!allowed) return null;
    }
    if (!mounted) return null;
    return showDriverCreatorDialog(
      context,
      existing: existing,
      companyId: _activeCompanyIdForFleetUi(),
      style: DriverCreatorDialogStyle(
        sheetBg: _sheetBg,
        textPrimary: _textPrimary,
        textSecondary: _textSecondary,
        inputFill: _inputFill,
        inputBorder: _inputBorder,
        gold: _gold,
        textOnAccent: _theme.palette.textOnAccent,
      ),
    );
  }

  Future<void> _pickVehiclePhoto({
    required String currentRef,
    required void Function(String ref) onPicked,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      final persisted = await _persistPickedVehiclePhoto(picked.path);
      // Persisted copy in app documents survives image_picker cache cleanup.
      // Fallback to the original picker path on copy failure to preserve UX.
      onPicked(persisted ?? picked.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon geen foto selecteren.',
              en: 'Could not select photo.',
              fr: 'Impossible de selectionner la photo.',
              es: 'No se pudo seleccionar la foto.',
            ),
          ),
        ),
      );
      onPicked(currentRef);
    }
  }

  Future<List<String>> _pickVehiclePhotos() async {
    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 90);
      if (picked.isEmpty) return const <String>[];
      final refs = <String>[];
      for (final x in picked) {
        final raw = x.path.trim();
        if (raw.isEmpty) continue;
        final persisted = await _persistPickedVehiclePhoto(raw);
        refs.add((persisted ?? raw).trim());
      }
      return refs.where((p) => p.trim().isNotEmpty).toList(growable: false);
    } catch (_) {
      if (!mounted) return const <String>[];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon geen foto\'s selecteren.',
              en: 'Could not select photos.',
              fr: 'Impossible de selectionner les photos.',
              es: 'No se pudieron seleccionar las fotos.',
            ),
          ),
        ),
      );
      return const <String>[];
    }
  }

  Future<String?> _persistPickedVehiclePhoto(String sourcePath) async {
    try {
      final source = sourcePath.trim();
      if (source.isEmpty) return null;
      final src = File(source);
      if (!await src.exists()) return null;

      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}tenant_state'
        '${Platform.pathSeparator}vehicle_photos',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = _vehiclePhotoFileExtension(source);
      final fileName =
          'vehicle_photo_${DateTime.now().millisecondsSinceEpoch}'
          '${ext.isEmpty ? '' : '.$ext'}';
      final target = File('${dir.path}${Platform.pathSeparator}$fileName');
      await src.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  String _vehiclePhotoFileExtension(String path) {
    final lower = path.toLowerCase();
    final slash = lower.lastIndexOf(Platform.pathSeparator);
    final altSlash = lower.lastIndexOf('/');
    final base = lower.substring((slash > altSlash ? slash : altSlash) + 1);
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    final raw = base.substring(dot + 1);
    const allowed = <String>{
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
      'heic',
    };
    return allowed.contains(raw) ? raw : '';
  }

  Widget _photoPreviewBox({
    required String photoRef,
    String? fallbackPhotoRef,
    required double height,
    required VoidCallback? onTap,
    required String placeholderText,
  }) {
    final primary = photoRef.trim();
    final fallback = (fallbackPhotoRef ?? '').trim();
    final effectiveRef = primary.isNotEmpty ? primary : fallback;
    final fallbackNetwork = _isNetworkUrl(fallback);
    final isAsset = _isAssetRef(effectiveRef);
    final isNetwork = _isNetworkUrl(effectiveRef);
    final hasRef = effectiveRef.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withOpacity(0.34)),
        ),
        child: isAsset
            ? ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  effectiveRef,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _photoPlaceholder(placeholderText),
                ),
              )
            : (hasRef
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: isNetwork
                          ? Image.network(
                              effectiveRef,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _photoPlaceholder(placeholderText),
                            )
                          : Image.file(
                              File(effectiveRef),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                if (fallbackNetwork &&
                                    fallback != effectiveRef) {
                                  return Image.network(
                                    fallback,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _photoPlaceholder(placeholderText),
                                  );
                                }
                                return _photoPlaceholder(placeholderText);
                              },
                            ),
                    )
                  : _photoPlaceholder(placeholderText)),
      ),
    );
  }

  Widget _photoPlaceholder(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_filled_outlined, color: _gold, size: 28),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(color: _textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _publicVehiclePhotoPreview(String url) {
    if (!_isPublicHttpsUrl(url)) {
      return Container(
        height: 118,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withOpacity(0.22)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_car_filled_outlined,
                color: _gold.withOpacity(0.9),
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Nog geen publieke voertuigfoto',
                  en: 'No public vehicle photo yet',
                  fr: 'Pas encore de photo publique du véhicule',
                  es: 'Aún no hay foto pública del vehículo',
                ),
                style: TextStyle(color: _textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      height: 118,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.28)),
        color: _panelBg,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.network(
          url.trim(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: _cardBg,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  color: _gold.withOpacity(0.9),
                  size: 22,
                ),
                const SizedBox(height: 5),
                Text(
                  _t(
                    nl: 'Voorbeeld niet beschikbaar',
                    en: 'Preview unavailable',
                    fr: 'Aperçu indisponible',
                    es: 'Vista previa no disponible',
                  ),
                  style: TextStyle(color: _textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _openVehicleEditor({VehicleProfile? existing}) async {
    final resolvedExisting = existing == null
        ? null
        : (vehicleProfileById(existing.id) ?? existing);
    final vehicleId =
        resolvedExisting?.id ?? 'vh_${DateTime.now().millisecondsSinceEpoch}';
    // New-vehicle identity fields start EMPTY. Demo values like Tesla /
    // Model 3 come only from the seeded `vh_1` row (filtered from UI) and
    // must never be controller defaults for create.
    final nameCtrl = TextEditingController(
      text: resolvedExisting?.vehicleName ?? '',
    );
    final modelCtrl = TextEditingController(
      text: resolvedExisting?.brandModel ?? '',
    );
    final plateCtrl = TextEditingController(
      text: resolvedExisting?.licensePlate ?? '',
    );
    final exploitationLicenseCtrl = TextEditingController(
      text: resolvedExisting?.exploitationLicenseNumber ?? '',
    );
    final vehicleRegistrationCtrl = TextEditingController(
      text: resolvedExisting?.vehicleRegistrationNumber ?? '',
    );
    final colorCtrl = TextEditingController(
      text: resolvedExisting?.color ?? '',
    );
    final isNewVehicle = resolvedExisting == null;
    var primaryPhotoRef = resolvedExisting?.primaryPhotoRef ?? '';
    var galleryPhotoRefs = List<String>.from(
      resolvedExisting?.galleryPhotoRefs ?? const <String>[],
    );
    final publicPhotoUrlCtrl = TextEditingController(
      text: resolvedExisting?.publicPhotoUrl ?? '',
    );
    var publicPhotoUploading = false;
    final paxCtrl = TextEditingController(
      text: (resolvedExisting?.passengerCapacity ?? 3).toString(),
    );
    final bagsCtrl = TextEditingController(
      text: (resolvedExisting?.luggageCapacity ?? 3).toString(),
    );
    var tierId = resolvedExisting?.tierId ?? appConfig.enabledTiers.first.id;
    String? linkedDriverId = resolvedExisting?.driverId;
    {
      final cid = _scopedVehicleCompanyId(resolvedExisting);
      final dr0 = _driverById(linkedDriverId);
      if (dr0 == null || !_canAssignDriverToVehicleInManagementUi(dr0, cid)) {
        linkedDriverId = null;
      }
    }
    var active = resolvedExisting?.isActive ?? true;
    // LIMOUSINE-MARKETPLACE-P2A: optional, explicit, default-OFF limousine
    // configuration. Category and class are independent of the taxi tier and are
    // never inferred from brand/model/name.
    var limousineEnabled =
        (resolvedExisting?.serviceCategory ?? '').trim().toLowerCase() ==
        'limousine';
    String? limousineClassId = () {
      final id = (resolvedExisting?.serviceClassId ?? '').trim();
      return isKnownActiveLimousineServiceClassId(id) ? id : null;
    }();
    var limousineEntitled = false;
    {
      final scopeId = _activeCompanyIdForFleetUi();
      if (scopeId != null && scopeId.trim().isNotEmpty) {
        try {
          final subProfile = await fetchCompanySubscriptionProfile(
            tenantId: scopeId,
            companyId: scopeId,
          );
          limousineEntitled = subProfile.features['limousine'] == true;
        } catch (_) {
          // Fail closed to a read-only unavailable state on a transient error.
          limousineEntitled = false;
        }
      }
    }
    final fleetScope = _activeFleetScope();
    final documentTenantId =
        fleetScope?.tenantId ?? _scopedVehicleCompanyId(resolvedExisting) ?? '';
    final documentCompanyId =
        fleetScope?.companyId ??
        _scopedVehicleCompanyId(resolvedExisting) ??
        '';
    if (documentTenantId.isNotEmpty && documentCompanyId.isNotEmpty) {
      await _VehicleComplianceDocumentStore.instance.ensureLoaded(
        tenantId: documentTenantId,
        companyId: documentCompanyId,
      );
    }
    var vehicleDocuments = documentTenantId.isEmpty || documentCompanyId.isEmpty
        ? <_VehicleComplianceDocument>[]
        : _VehicleComplianceDocumentStore.instance.documentsForVehicle(
            tenantId: documentTenantId,
            companyId: documentCompanyId,
            vehicleId: vehicleId,
          );

    var didSave = false;
    if (!mounted) return false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheetBg,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolvedExisting == null
                            ? _t(
                                nl: 'Voertuig toevoegen',
                                en: 'Add vehicle',
                                fr: 'Ajouter un véhicule',
                                es: 'Agregar vehículo',
                              )
                            : _t(
                                nl: 'Voertuig bewerken',
                                en: 'Edit vehicle',
                                fr: 'Modifier le véhicule',
                                es: 'Editar vehículo',
                              ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _txt(
                        nameCtrl,
                        _t(
                          nl: 'Voertuignaam',
                          en: 'Vehicle name',
                          fr: 'Nom du véhicule',
                          es: 'Nombre del vehículo',
                        ),
                        hintText: isNewVehicle
                            ? _t(
                                nl: 'Bijv. Hoofdwagen',
                                en: 'E.g. Main vehicle',
                                fr: 'Ex. Véhicule principal',
                                es: 'Ej. Vehículo principal',
                              )
                            : null,
                      ),
                      _txt(
                        modelCtrl,
                        _t(
                          nl: 'Merk/model',
                          en: 'Make/model',
                          fr: 'Marque/modèle',
                          es: 'Marca/modelo',
                        ),
                        hintText: isNewVehicle
                            ? _t(
                                nl: 'Bijv. Tesla Model 3',
                                en: 'E.g. Tesla Model 3',
                                fr: 'Ex. Tesla Model 3',
                                es: 'Ej. Tesla Model 3',
                              )
                            : null,
                      ),
                      _txt(
                        plateCtrl,
                        _t(
                          nl: 'Nummerplaat',
                          en: 'Plate',
                          fr: 'Plaque',
                          es: 'Matrícula',
                        ),
                        hintText: isNewVehicle
                            ? _t(
                                nl: 'Bijv. 1-ABC-123',
                                en: 'E.g. 1-ABC-123',
                                fr: 'Ex. 1-ABC-123',
                                es: 'Ej. 1-ABC-123',
                              )
                            : null,
                      ),
                      _txt(
                        exploitationLicenseCtrl,
                        _t(
                          nl: 'Exploitatievergunning',
                          en: 'Operating license number',
                          fr: 'N° de licence d’exploitation',
                          es: 'N.º licencia de explotación',
                        ),
                      ),
                      _txt(
                        vehicleRegistrationCtrl,
                        _t(
                          nl: 'Inschrijving/VIN/chassis',
                          en: 'Registration/VIN/chassis',
                          fr: 'Immatriculation/VIN/châssis',
                          es: 'Matrícula/VIN/chasis',
                        ),
                      ),
                      _txt(
                        colorCtrl,
                        _t(
                          nl: 'Kleur',
                          en: 'Color',
                          fr: 'Couleur',
                          es: 'Color',
                        ),
                        hintText: isNewVehicle
                            ? _t(
                                nl: 'Bijv. Zwart',
                                en: 'E.g. Black',
                                fr: 'Ex. Noir',
                                es: 'Ej. Negro',
                              )
                            : null,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _txt(
                              paxCtrl,
                              _t(
                                nl: 'Passagierscapaciteit',
                                en: 'Passenger capacity',
                                fr: 'Capacité passagers',
                                es: 'Capacidad pasajeros',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _txt(
                              bagsCtrl,
                              _t(
                                nl: 'Bagagecapaciteit',
                                en: 'Luggage capacity',
                                fr: 'Capacité bagages',
                                es: 'Capacidad equipaje',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: tierId,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: _textPrimary,
                        iconDisabledColor: _textMuted,
                        isExpanded: true,
                        items: appConfig.enabledTiers
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  t.labelFor(_lang),
                                  style: TextStyle(color: _textPrimary),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocalState(() => tierId = v);
                        },
                        decoration: InputDecoration(
                          labelText: _t(
                            nl: 'Categorie',
                            en: 'Category',
                            fr: 'Catégorie',
                            es: 'Categoría',
                          ),
                          filled: true,
                          fillColor: _inputFill,
                          labelStyle: TextStyle(color: _textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _inputBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: _gold.withOpacity(0.7),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        dropdownColor: _dropdownBg,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _t(
                                  nl: 'Actief',
                                  en: 'Active',
                                  fr: 'Actif',
                                  es: 'Activo',
                                ),
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch(
                              value: active,
                              activeColor: _gold,
                              activeTrackColor: _gold.withOpacity(
                                _theme.palette.isDark ? 0.46 : 0.34,
                              ),
                              inactiveThumbColor: _textSecondary,
                              inactiveTrackColor: _panelBg.withOpacity(0.72),
                              onChanged: (v) => setLocalState(() => active = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _limousineVehicleConfigSection(
                        limousineEntitled: limousineEntitled,
                        limousineEnabled: limousineEnabled,
                        limousineClassId: limousineClassId,
                        onToggle: (v) => setLocalState(() {
                          limousineEnabled = v;
                          if (!v) limousineClassId = null;
                        }),
                        onClassChanged: (v) =>
                            setLocalState(() => limousineClassId = v),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _t(
                          nl: 'Gekoppelde chauffeur',
                          en: 'Linked driver',
                          fr: 'Chauffeur lié',
                          es: 'Conductor vinculado',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: linkedDriverId,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        iconEnabledColor: _textPrimary,
                        iconDisabledColor: _textMuted,
                        isExpanded: true,
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text(
                              _t(
                                nl: 'Geen chauffeur',
                                en: 'No driver',
                                fr: 'Aucun chauffeur',
                                es: 'Sin conductor',
                              ),
                              style: TextStyle(color: _textPrimary),
                            ),
                          ),
                          ...driversNotifier.value
                              .where(
                                (d) =>
                                    _driverVisibleInManagementUi(d) &&
                                    _canAssignDriverToVehicleInManagementUi(
                                      d,
                                      _scopedVehicleCompanyId(resolvedExisting),
                                    ) &&
                                    !fleetExplicitCompanyMismatch(
                                      d.companyId,
                                      _scopedVehicleCompanyId(resolvedExisting),
                                    ),
                              )
                              .map(
                                (d) => DropdownMenuItem<String>(
                                  value: d.id,
                                  child: Text(
                                    '${d.fullName} (${d.employeeNumber})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: _textPrimary),
                                  ),
                                ),
                              ),
                        ],
                        onChanged: (v) =>
                            setLocalState(() => linkedDriverId = v),
                        decoration: InputDecoration(
                          labelText: _t(
                            nl: 'Selecteer chauffeur',
                            en: 'Select driver',
                            fr: 'Selectionner chauffeur',
                            es: 'Seleccionar conductor',
                          ),
                          filled: true,
                          fillColor: _inputFill,
                          labelStyle: TextStyle(color: _textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _inputBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _inputBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: _gold.withOpacity(0.7),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        dropdownColor: _dropdownBg,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final created = await _openDriverCreator();
                          if (created == null) return;
                          setLocalState(() => linkedDriverId = created.id);
                        },
                        style: _editorOutlinedStyle().copyWith(
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            const Icon(Icons.person_add_alt_1),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _t(
                                  nl: 'Chauffeur toevoegen',
                                  en: 'Add new driver',
                                  fr: 'Ajouter un chauffeur',
                                  es: 'Agregar nuevo conductor',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_driverById(linkedDriverId) != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.08),
                            border: Border.all(color: _gold.withOpacity(0.34)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Builder(
                            builder: (context) {
                              final d = _driverById(linkedDriverId)!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      nl: 'Chauffeurgegevens',
                                      en: 'Driver details',
                                      fr: 'Details du chauffeur',
                                      es: 'Detalles del conductor',
                                    ),
                                    style: TextStyle(
                                      color: _gold,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _driverInfoLine(
                                    _t(
                                      nl: 'Naam',
                                      en: 'Name',
                                      fr: 'Nom',
                                      es: 'Nombre',
                                    ),
                                    d.fullName,
                                  ),
                                  const SizedBox(height: 4),
                                  _driverInfoLine(
                                    _t(
                                      nl: 'Chauffeur-ID',
                                      en: 'Driver ID',
                                      fr: 'ID chauffeur',
                                      es: 'ID conductor',
                                    ),
                                    d.employeeNumber,
                                  ),
                                  const SizedBox(height: 4),
                                  _driverInfoLine(
                                    _t(
                                      nl: 'Telefoonnummer',
                                      en: 'Phone number',
                                      fr: 'Numéro de téléphone',
                                      es: 'Número de teléfono',
                                    ),
                                    d.phone,
                                  ),
                                  const SizedBox(height: 4),
                                  _driverInfoLine(
                                    _t(
                                      nl: 'Chauffeurskaartnummer',
                                      en: 'Driver card number',
                                      fr: 'N° carte chauffeur',
                                      es: 'N.º tarjeta de conductor',
                                    ),
                                    d.taxiDriverCardNumber,
                                  ),
                                  const SizedBox(height: 4),
                                  _driverInfoLine(
                                    _t(
                                      nl: 'Vervaldatum chauffeurskaart',
                                      en: 'Driver card expiry',
                                      fr: 'Expiration carte chauffeur',
                                      es: 'Caducidad tarjeta de conductor',
                                    ),
                                    d.taxiDriverCardExpiry,
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final updated =
                                            await _openDriverCreator(
                                              existing: d,
                                            );
                                        if (updated == null) return;
                                        setLocalState(() {
                                          linkedDriverId = updated.id;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _textPrimary,
                                        side: BorderSide(
                                          color: _theme.border.withOpacity(0.9),
                                        ),
                                        backgroundColor: _theme.palette.surface
                                            .withOpacity(0.88),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                      ),
                                      label: Text(
                                        _t(
                                          nl: 'Chauffeur bewerken',
                                          en: 'Edit driver',
                                          fr: 'Modifier chauffeur',
                                          es: 'Editar conductor',
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (documentTenantId.isNotEmpty &&
                          documentCompanyId.isNotEmpty)
                        _vehicleComplianceDocumentsSection(
                          vehicleId: vehicleId,
                          tenantId: documentTenantId,
                          companyId: documentCompanyId,
                          documents: vehicleDocuments,
                          onChanged: () {
                            setLocalState(() {
                              vehicleDocuments = _VehicleComplianceDocumentStore
                                  .instance
                                  .documentsForVehicle(
                                    tenantId: documentTenantId,
                                    companyId: documentCompanyId,
                                    vehicleId: vehicleId,
                                  );
                            });
                          },
                        ),
                      if (documentTenantId.isNotEmpty &&
                          documentCompanyId.isNotEmpty)
                        const SizedBox(height: 12),
                      _photoPreviewBox(
                        photoRef: primaryPhotoRef,
                        height: 120,
                        onTap: () async {
                          await _pickVehiclePhoto(
                            currentRef: primaryPhotoRef,
                            onPicked: (ref) => setLocalState(() {
                              primaryPhotoRef = ref;
                              if (ref.trim().isNotEmpty &&
                                  !galleryPhotoRefs.contains(ref)) {
                                galleryPhotoRefs =
                                    <String>[ref, ...galleryPhotoRefs]
                                        .where((e) => e.trim().isNotEmpty)
                                        .toSet()
                                        .toList(growable: false);
                                if (galleryPhotoRefs.length >
                                    _maxPhotosPerVehicle) {
                                  galleryPhotoRefs = galleryPhotoRefs
                                      .take(_maxPhotosPerVehicle)
                                      .toList(growable: false);
                                }
                              }
                            }),
                          );
                        },
                        placeholderText: _t(
                          nl: 'Geen foto ingesteld',
                          en: 'No photo set',
                          fr: 'Aucune photo définie',
                          es: 'Sin foto configurada',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            publicPhotoUploading ||
                                primaryPhotoRef.trim().isEmpty
                            ? null
                            : () async {
                                setLocalState(
                                  () => publicPhotoUploading = true,
                                );
                                try {
                                  await _useExistingVehiclePhotoAsPublic(
                                    photoRef: primaryPhotoRef,
                                    vehicleId: vehicleId,
                                    existing: resolvedExisting,
                                    publicPhotoUrlCtrl: publicPhotoUrlCtrl,
                                    setLocalState: setLocalState,
                                  );
                                } finally {
                                  setLocalState(
                                    () => publicPhotoUploading = false,
                                  );
                                }
                              },
                        icon: const Icon(Icons.public_outlined, size: 16),
                        label: Text(
                          _t(
                            nl: 'Gebruik als publieke foto',
                            en: 'Use as public photo',
                            fr: 'Utiliser comme photo publique',
                            es: 'Usar como foto pública',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: _editorOutlinedStyle(),
                      ),
                      const SizedBox(height: 8),
                      if (galleryPhotoRefs.isNotEmpty) ...[
                        Text(
                          _t(
                            nl: 'Galerijfoto\'s',
                            en: 'Gallery photos',
                            fr: 'Photos galerie',
                            es: 'Fotos de galeria',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 82,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: galleryPhotoRefs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final ref = galleryPhotoRefs[i];
                              final isMain = ref == primaryPhotoRef;
                              return Stack(
                                children: [
                                  Container(
                                    width: 110,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isMain
                                            ? _gold
                                            : _theme.border.withOpacity(0.8),
                                        width: isMain ? 2 : 1,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: _photoPreviewBox(
                                        photoRef: ref,
                                        height: 80,
                                        onTap: () => setLocalState(
                                          () => primaryPhotoRef = ref,
                                        ),
                                        placeholderText: _t(
                                          nl: 'Geen foto',
                                          en: 'No photo',
                                          fr: 'Pas de photo',
                                          es: 'Sin foto',
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 3,
                                    top: 3,
                                    child: InkWell(
                                      onTap: publicPhotoUploading
                                          ? null
                                          : () async {
                                              setLocalState(
                                                () =>
                                                    publicPhotoUploading = true,
                                              );
                                              try {
                                                await _useExistingVehiclePhotoAsPublic(
                                                  photoRef: ref,
                                                  vehicleId: vehicleId,
                                                  existing: resolvedExisting,
                                                  publicPhotoUrlCtrl:
                                                      publicPhotoUrlCtrl,
                                                  setLocalState: setLocalState,
                                                );
                                              } finally {
                                                setLocalState(
                                                  () => publicPhotoUploading =
                                                      false,
                                                );
                                              }
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _overlayDark,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: _gold.withOpacity(0.65),
                                          ),
                                        ),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 48,
                                          ),
                                          child: Text(
                                            _t(
                                              nl: 'Publiek',
                                              en: 'Public',
                                              fr: 'Public',
                                              es: 'Pública',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: _textPrimary,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 2,
                                    top: 2,
                                    child: InkWell(
                                      onTap: () => setLocalState(() {
                                        galleryPhotoRefs = List<String>.from(
                                          galleryPhotoRefs,
                                        )..remove(ref);
                                        if (primaryPhotoRef == ref) {
                                          primaryPhotoRef =
                                              galleryPhotoRefs.isNotEmpty
                                              ? galleryPhotoRefs.first
                                              : '';
                                        }
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: _overlaySoft,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isMain)
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _overlaySoft,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          _t(
                                            nl: 'Hoofd',
                                            en: 'Main',
                                            fr: 'Principale',
                                            es: 'Principal',
                                          ),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                galleryPhotoRefs.length >= _maxPhotosPerVehicle
                                ? null
                                : () async {
                                    final pickedRefs =
                                        await _pickVehiclePhotos();
                                    if (pickedRefs.isEmpty) return;
                                    final freeSlots =
                                        _maxPhotosPerVehicle -
                                        galleryPhotoRefs.length;
                                    final accepted = pickedRefs
                                        .take(freeSlots)
                                        .toList(growable: false);
                                    if (accepted.isEmpty) return;
                                    setLocalState(() {
                                      galleryPhotoRefs =
                                          <String>[
                                                ...galleryPhotoRefs,
                                                ...accepted,
                                              ]
                                              .where((e) => e.trim().isNotEmpty)
                                              .toSet()
                                              .take(_maxPhotosPerVehicle)
                                              .toList(growable: false);
                                      if (primaryPhotoRef.trim().isEmpty &&
                                          galleryPhotoRefs.isNotEmpty) {
                                        primaryPhotoRef =
                                            galleryPhotoRefs.first;
                                      }
                                    });
                                    if (pickedRefs.length > accepted.length &&
                                        mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _t(
                                              nl: 'Niet alle foto\'s toegevoegd (maximaal 5).',
                                              en: 'Not all photos added (maximum 5).',
                                              fr: 'Toutes les photos n\'ont pas ete ajoutees (maximum 5).',
                                              es: 'No se agregaron todas las fotos (maximo 5).',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _theme.palette.textOnAccent,
                            ),
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              _t(
                                nl: 'Foto\'s toevoegen',
                                en: 'Add photos',
                                fr: 'Ajouter des photos',
                                es: 'Agregar fotos',
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: primaryPhotoRef.trim().isEmpty
                                ? null
                                : () => _pickVehiclePhoto(
                                    currentRef: primaryPhotoRef,
                                    onPicked: (ref) => setLocalState(() {
                                      if (ref.trim().isEmpty) return;
                                      primaryPhotoRef = ref;
                                      if (!galleryPhotoRefs.contains(ref)) {
                                        galleryPhotoRefs =
                                            <String>[ref, ...galleryPhotoRefs]
                                                .where(
                                                  (e) => e.trim().isNotEmpty,
                                                )
                                                .toSet()
                                                .toList(growable: false);
                                        if (galleryPhotoRefs.length >
                                            _maxPhotosPerVehicle) {
                                          galleryPhotoRefs = galleryPhotoRefs
                                              .take(_maxPhotosPerVehicle)
                                              .toList(growable: false);
                                        }
                                      }
                                    }),
                                  ),
                            style: _editorOutlinedStyle(),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              _t(
                                nl: 'Hoofdfoto wijzigen',
                                en: 'Change main photo',
                                fr: 'Changer photo principale',
                                es: 'Cambiar foto principal',
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => setLocalState(() {
                              primaryPhotoRef = '';
                              galleryPhotoRefs = <String>[];
                            }),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _danger,
                              side: BorderSide(color: _danger.withOpacity(0.5)),
                              backgroundColor: _danger.withOpacity(0.14),
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(
                              _t(
                                nl: 'Alle foto\'s verwijderen',
                                en: 'Remove all photos',
                                fr: 'Supprimer toutes les photos',
                                es: 'Eliminar todas las fotos',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          nl: 'Maximaal 5 foto\'s per voertuig',
                          en: 'Maximum 5 photos per vehicle',
                          fr: 'Maximum 5 photos par véhicule',
                          es: 'Máximo 5 fotos por vehículo',
                        ),
                        style: TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          nl: 'Publieke voertuigfoto',
                          en: 'Public vehicle photo',
                          fr: 'Photo publique du véhicule',
                          es: 'Foto pública del vehículo',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _publicVehiclePhotoPreview(
                        publicPhotoUrlCtrl.text.trim(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          nl: 'Upload een veilige publieke voertuigfoto. Fluxidi maakt automatisch een publieke link.',
                          en: 'Upload a safe public vehicle photo. Fluxidi automatically creates a public link.',
                          fr: 'Importez une photo publique sûre du véhicule. Fluxidi crée automatiquement un lien public.',
                          es: 'Sube una foto pública segura del vehículo. Fluxidi crea automáticamente un enlace público.',
                        ),
                        style: TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: publicPhotoUploading
                            ? null
                            : () async {
                                setLocalState(
                                  () => publicPhotoUploading = true,
                                );
                                try {
                                  final picked = await _imagePicker.pickImage(
                                    source: ImageSource.gallery,
                                    maxWidth: 1600,
                                    imageQuality: 82,
                                  );
                                  if (picked == null) return;
                                  final scopeId = _vehicleMediaScopeId(
                                    resolvedExisting,
                                  );
                                  if (scopeId == null) {
                                    debugPrint(
                                      '[VEHICLE_MEDIA][SKIP] reason=missing_active_company_context',
                                    );
                                    _showMissingCompanyScopeSnackbar();
                                    return;
                                  }
                                  final bytes = kIsWeb
                                      ? await picked.readAsBytes()
                                      : null;
                                  final uploaded =
                                      await uploadPublicPartnerMedia(
                                        tenantId: scopeId,
                                        companyId: scopeId,
                                        mediaType: 'vehicle_photo',
                                        entityId: vehicleId,
                                        filePath: kIsWeb ? null : picked.path,
                                        fileBytes: bytes,
                                        filename: picked.name,
                                      );
                                  final url = (uploaded['url'] ?? '')
                                      .toString()
                                      .trim();
                                  if (!_isPublicHttpsUrl(url)) {
                                    throw Exception(
                                      'Upload did not return a valid HTTPS URL',
                                    );
                                  }
                                  await _persistVehiclePublicPhotoAfterUpload(
                                    vehicleId: vehicleId,
                                    existing: resolvedExisting,
                                    publicPhotoUrl: url,
                                    publicPhotoUrlCtrl: publicPhotoUrlCtrl,
                                    setLocalState: setLocalState,
                                  );
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _t(
                                          nl: 'Publieke voertuigfoto geüpload.',
                                          en: 'Public vehicle photo uploaded.',
                                          fr: 'Photo publique du véhicule importée.',
                                          es: 'Foto pública del vehículo subida.',
                                        ),
                                      ),
                                    ),
                                  );
                                } catch (_) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _publicVehicleUploadFailureMessage(),
                                      ),
                                    ),
                                  );
                                } finally {
                                  setLocalState(
                                    () => publicPhotoUploading = false,
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _theme.palette.textOnAccent,
                        ),
                        icon: publicPhotoUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          _isPublicHttpsUrl(publicPhotoUrlCtrl.text)
                              ? _t(
                                  nl: 'Vervang publieke voertuigfoto',
                                  en: 'Replace public vehicle photo',
                                  fr: 'Remplacer la photo publique du véhicule',
                                  es: 'Reemplazar foto pública del vehículo',
                                )
                              : _t(
                                  nl: 'Upload publieke voertuigfoto',
                                  en: 'Upload public vehicle photo',
                                  fr: 'Importer une photo publique du véhicule',
                                  es: 'Subir foto pública del vehículo',
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          _t(
                            nl: 'Geavanceerd: handmatige publieke URL (fallback)',
                            en: 'Advanced: manual public URL (fallback)',
                            fr: 'Avancé : URL publique manuelle (secours)',
                            es: 'Avanzado: URL pública manual (respaldo)',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        iconColor: _gold.withOpacity(0.9),
                        collapsedIconColor: _textSecondary,
                        children: [
                          _txt(
                            publicPhotoUrlCtrl,
                            _t(
                              nl: 'Publieke voertuigfoto-URL',
                              en: 'Public vehicle photo URL',
                              fr: 'URL photo véhicule publique',
                              es: 'URL pública de foto del vehículo',
                            ),
                            onChanged: () => setLocalState(() {}),
                          ),
                        ],
                      ),
                      Text(
                        _t(
                          nl: 'Deze foto kan op het publieke partnerprofiel verschijnen. Alleen HTTPS-links worden gepubliceerd.',
                          en: 'This photo can appear on the public partner profile. Only HTTPS links are published.',
                          fr: 'Cette photo peut apparaître sur le profil partenaire public. Seuls les liens HTTPS sont publiés.',
                          es: 'Esta foto puede aparecer en el perfil público del socio. Solo se publican enlaces HTTPS.',
                        ),
                        style: TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                      if (publicPhotoUrlCtrl.text.trim().isNotEmpty &&
                          !publicPhotoUrlCtrl.text
                              .trim()
                              .toLowerCase()
                              .startsWith('https://')) ...[
                        const SizedBox(height: 6),
                        Text(
                          _t(
                            nl: 'Waarschuwing: enkel URLs die met https:// starten worden gepubliceerd.',
                            en: 'Warning: only URLs starting with https:// are published.',
                            fr: 'Avertissement : seules les URLs commençant par https:// sont publiées.',
                            es: 'Advertencia: solo se publican URLs que empiezan por https://.',
                          ),
                          style: TextStyle(color: _gold, fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SafeArea(
                        top: false,
                        minimum: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: _editorOutlinedStyle().copyWith(
                                  padding: WidgetStateProperty.all(
                                    const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                ),
                                child: Text(
                                  _t(
                                    nl: 'Annuleren',
                                    en: 'Cancel',
                                    fr: 'Annuler',
                                    es: 'Cancelar',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final cid =
                                      _scopedVehicleCompanyId(
                                        resolvedExisting,
                                      ) ??
                                      _activeCompanyIdForFleetUi();
                                  if (linkedDriverId != null) {
                                    final dr = _driverById(linkedDriverId);
                                    if (dr != null &&
                                        !_canAssignDriverToVehicleInManagementUi(
                                          dr,
                                          cid,
                                        )) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _t(
                                              nl: 'Deze chauffeur hoort niet bij dit bedrijf.',
                                              en: 'This driver does not belong to this company.',
                                              fr: 'Ce chauffeur n appartient pas a cette entreprise.',
                                              es: 'Este conductor no pertenece a esta empresa.',
                                            ),
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                  }
                                  // LIMOUSINE-MARKETPLACE-P2A: enabling limousine
                                  // requires entitlement + an authoritative
                                  // active service class. Fails closed with a
                                  // localized validation; never inferred.
                                  final wantsLimousine =
                                      limousineEntitled && limousineEnabled;
                                  if (wantsLimousine &&
                                      !isKnownActiveLimousineServiceClassId(
                                        limousineClassId,
                                      )) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _t(
                                            nl: 'Kies een limousineklasse om de limousineservice op te slaan.',
                                            en: 'Select a limousine class to save the limousine service.',
                                            fr: 'Choisissez une classe de limousine pour enregistrer le service limousine.',
                                            es: 'Selecciona una clase de limusina para guardar el servicio de limusina.',
                                          ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final resolvedServiceCategory = wantsLimousine
                                      ? 'limousine'
                                      : '';
                                  final resolvedServiceClassId = wantsLimousine
                                      ? (limousineClassId ?? '')
                                      : '';
                                  final resolvedPublicPhoto =
                                      await _resolvePublicPhotoUrlForVehicleSave(
                                        vehicleId: vehicleId,
                                        controllerUrl: publicPhotoUrlCtrl.text,
                                        primaryPhotoRef: primaryPhotoRef,
                                        existing: resolvedExisting,
                                      );
                                  if (resolvedPublicPhoto != null &&
                                      resolvedPublicPhoto.isNotEmpty) {
                                    publicPhotoUrlCtrl.text =
                                        resolvedPublicPhoto;
                                  }
                                  final vehicle = VehicleProfile(
                                    id: vehicleId,
                                    vehicleName: nameCtrl.text.trim(),
                                    brandModel: modelCtrl.text.trim(),
                                    licensePlate: plateCtrl.text.trim(),
                                    exploitationLicenseNumber:
                                        exploitationLicenseCtrl.text.trim(),
                                    vehicleRegistrationNumber:
                                        vehicleRegistrationCtrl.text.trim(),
                                    color: colorCtrl.text.trim(),
                                    passengerCapacity:
                                        int.tryParse(paxCtrl.text.trim()) ?? 0,
                                    luggageCapacity:
                                        int.tryParse(bagsCtrl.text.trim()) ?? 0,
                                    tierId: tierId,
                                    isActive: active,
                                    driverId: linkedDriverId,
                                    companyId: cid,
                                    primaryPhotoRef: primaryPhotoRef.trim(),
                                    galleryPhotoRefs: galleryPhotoRefs
                                        .where((e) => e.trim().isNotEmpty)
                                        .take(_maxPhotosPerVehicle)
                                        .toList(growable: false),
                                    publicPhotoUrl: resolvedPublicPhoto,
                                    serviceCategory: resolvedServiceCategory,
                                    serviceClassId: resolvedServiceClassId,
                                  );
                                  if (resolvedExisting == null) {
                                    addVehicle(vehicle);
                                  } else {
                                    updateVehicle(resolvedExisting.id, vehicle);
                                  }
                                  await _syncFleetOrShowError();
                                  didSave = true;
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _gold,
                                  foregroundColor: _theme.palette.textOnAccent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                child: Text(
                                  _t(
                                    nl: 'Opslaan',
                                    en: 'Save',
                                    fr: 'Enregistrer',
                                    es: 'Guardar',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      await _ensureVehicleDocumentsLoaded(refreshUi: true);
    }
    return didSave;
  }

  Widget _txt(
    TextEditingController ctrl,
    String label, {
    VoidCallback? onChanged,
    bool enabled = true,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        onChanged: onChanged == null ? null : (_) => onChanged(),
        style: TextStyle(
          color: enabled ? _textPrimary : _textPrimary.withOpacity(0.88),
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          hintStyle: TextStyle(color: _textMuted.withOpacity(0.75)),
          labelStyle: TextStyle(color: _textSecondary),
          filled: true,
          fillColor: _inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorder),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorder.withOpacity(0.8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _gold.withOpacity(0.7)),
          ),
        ),
      ),
    );
  }

  Widget _driverInfoLine(String label, String value, {IconData? icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: _gold.withOpacity(0.9)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: _textPrimary),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: value.isEmpty ? '—' : value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Compact two-line label/value cell used inside the landscape 4-column
  // vehicle card. Kept private and small so it can't be reused elsewhere by
  // accident — phone portrait and tablet portrait layouts continue to use
  // _driverInfoLine / inline Text widgets unchanged.
  //
  // [tablet] scales paddings, icon and font sizes up for tablet landscape
  // while leaving the approved phone-landscape look byte-identical when the
  // default `tablet: false` is used.
  Widget _compactCellLine(
    String label,
    String value, {
    IconData? icon,
    bool tablet = false,
  }) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    final iconSize = tablet ? 14.0 : 11.5;
    final iconGap = tablet ? 6.0 : 4.0;
    final bottomPad = tablet ? 3.0 : 2.0;
    final fontSize = tablet ? 12.6 : 10.8;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: _gold.withOpacity(0.85)),
            SizedBox(width: iconGap),
          ],
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(color: _textPrimary, fontSize: fontSize),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: shown,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactSectionHeading(String label, {bool tablet = false}) {
    final bottomPad = tablet ? 5.0 : 3.0;
    final fontSize = tablet ? 13.4 : 11.4;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _gold.withOpacity(0.96),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _vehicleCompactLandscapeCard({
    required VehicleProfile v,
    required DriverProfile? linkedDriver,
    required String status,
    bool tablet = false,
  }) {
    // Density tokens. With `tablet: false` every value below collapses to
    // the previously-approved phone-landscape constants byte-for-byte. With
    // `tablet: true` the same 4-column layout is used, but paddings, photo
    // height, font sizes, chip and button touch targets are scaled up so it
    // stays compact yet professional and readable on tablet landscape.
    final cardPad = tablet ? 14.0 : 8.0;
    final cardMarginBottom = tablet ? 12.0 : 8.0;
    final colGap = tablet ? 12.0 : 8.0;
    final photoHeight = tablet ? 168.0 : 130.0;
    final statusOffset = tablet ? 8.0 : 6.0;
    final statusPillH = tablet ? 10.0 : 7.0;
    final statusPillV = tablet ? 4.0 : 2.0;
    final statusFontSize = tablet ? 12.4 : 10.4;
    final nameFontSize = tablet ? 16.4 : 13.2;
    final brandFontSize = tablet ? 13.4 : 11.0;
    final plateFontSize = tablet ? 12.4 : 10.4;
    final chipSpacing = tablet ? 6.0 : 4.0;
    final chipPadH = tablet ? 9.0 : 6.0;
    final chipPadV = tablet ? 4.0 : 2.0;
    final chipFontSize = tablet ? 12.0 : 10.2;
    final companyLabelFontSize = tablet ? 12.0 : 10.2;
    final companyIdFontSize = tablet ? 12.4 : 10.4;
    final btnPadH = tablet ? 12.0 : 8.0;
    final btnPadV = tablet ? 10.0 : 6.0;
    final btnMinHeight = tablet ? 38.0 : 30.0;
    final btnFontSize = tablet ? 13.0 : 11.4;
    final btnIconSize = tablet ? 16.0 : 14.0;
    final col2HeaderGap = tablet ? 4.0 : 2.0;
    final col2ChipsGap = tablet ? 8.0 : 6.0;
    final col3SectionGap = tablet ? 6.0 : 4.0;
    final col4LabelGap = tablet ? 4.0 : 2.0;
    final col4BeforeButtons = tablet ? 12.0 : 8.0;
    final col4BetweenButtons = tablet ? 6.0 : 4.0;

    return Container(
      margin: EdgeInsets.only(bottom: cardMarginBottom),
      padding: EdgeInsets.fromLTRB(cardPad, cardPad, cardPad, cardPad),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column 1: photo + status overlay (flex 34)
          Expanded(
            flex: 34,
            child: Stack(
              children: [
                _photoPreviewBox(
                  photoRef: v.primaryPhotoRef,
                  fallbackPhotoRef: v.publicPhotoUrl,
                  height: photoHeight,
                  onTap: null,
                  placeholderText: _t(
                    nl: 'Geen voertuigfoto',
                    en: 'No vehicle photo',
                    fr: 'Pas de photo véhicule',
                    es: 'Sin foto del vehículo',
                  ),
                ),
                Positioned(
                  top: statusOffset,
                  left: statusOffset,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: statusPillH,
                      vertical: statusPillV,
                    ),
                    decoration: BoxDecoration(
                      color: v.isActive
                          ? _success.withOpacity(0.85)
                          : _panelBg.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: v.isActive
                            ? _success.withOpacity(0.7)
                            : _theme.border.withOpacity(0.85),
                      ),
                    ),
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: v.isActive ? Colors.white : _textPrimary,
                        fontSize: statusFontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: colGap),
          // Column 2: vehicle identity + short specs (flex 24)
          Expanded(
            flex: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayVehicleName(v.vehicleName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: nameFontSize,
                  ),
                ),
                SizedBox(height: col2HeaderGap),
                Text(
                  v.brandModel.trim().isEmpty ? '—' : v.brandModel.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: brandFontSize,
                  ),
                ),
                Text(
                  '${_t(nl: 'Nummerplaat', en: 'Plate', fr: 'Plaque', es: 'Matrícula')}: ${v.licensePlate.isEmpty ? '—' : v.licensePlate}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: plateFontSize,
                  ),
                ),
                SizedBox(height: col2ChipsGap),
                Wrap(
                  spacing: chipSpacing,
                  runSpacing: chipSpacing,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: chipPadH,
                        vertical: chipPadV,
                      ),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _gold.withOpacity(0.42)),
                      ),
                      child: Text(
                        _tierLabel(v.tierId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _gold.withOpacity(0.98),
                          fontWeight: FontWeight.w700,
                          fontSize: chipFontSize,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: chipPadH,
                        vertical: chipPadV,
                      ),
                      decoration: BoxDecoration(
                        color: _panelBg.withOpacity(0.48),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _theme.border.withOpacity(0.8),
                        ),
                      ),
                      child: Text(
                        '${v.passengerCapacity} ${_t(nl: 'pass.', en: 'pax', fr: 'pass.', es: 'pas.')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: chipFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: chipPadH,
                        vertical: chipPadV,
                      ),
                      decoration: BoxDecoration(
                        color: _panelBg.withOpacity(0.48),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _theme.border.withOpacity(0.8),
                        ),
                      ),
                      child: Text(
                        '${v.luggageCapacity} ${_t(nl: 'koffers', en: 'bags', fr: 'bagages', es: 'maletas')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: chipFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: colGap),
          // Column 3: driver + permit/registration (flex 28)
          Expanded(
            flex: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _compactSectionHeading(
                  _t(
                    nl: 'Chauffeur',
                    en: 'Driver',
                    fr: 'Chauffeur',
                    es: 'Conductor',
                  ),
                  tablet: tablet,
                ),
                _compactCellLine(
                  _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                  linkedDriver == null
                      ? '—'
                      : _displayDriverName(linkedDriver.fullName),
                  icon: Icons.person_outline,
                  tablet: tablet,
                ),
                if (linkedDriver != null) ...[
                  _compactCellLine(
                    _t(nl: 'ID', en: 'ID', fr: 'ID', es: 'ID'),
                    linkedDriver.employeeNumber,
                    icon: Icons.badge_outlined,
                    tablet: tablet,
                  ),
                  _compactCellLine(
                    _t(nl: 'Tel.', en: 'Phone', fr: 'Tél.', es: 'Tel.'),
                    linkedDriver.phone,
                    icon: Icons.phone_outlined,
                    tablet: tablet,
                  ),
                ],
                SizedBox(height: col3SectionGap),
                _compactSectionHeading(
                  _t(
                    nl: 'Vergunning',
                    en: 'Permit',
                    fr: 'Permis',
                    es: 'Permiso',
                  ),
                  tablet: tablet,
                ),
                _compactCellLine(
                  _t(
                    nl: 'Vergunning',
                    en: 'License',
                    fr: 'Licence',
                    es: 'Licencia',
                  ),
                  v.exploitationLicenseNumber,
                  icon: Icons.verified_user_outlined,
                  tablet: tablet,
                ),
                _compactCellLine(
                  _t(
                    nl: 'VIN/chassis',
                    en: 'VIN/chassis',
                    fr: 'VIN/châssis',
                    es: 'VIN/chasis',
                  ),
                  v.vehicleRegistrationNumber,
                  icon: Icons.numbers_outlined,
                  tablet: tablet,
                ),
                _compactCellLine(
                  _t(nl: 'Kleur', en: 'Color', fr: 'Couleur', es: 'Color'),
                  _displayColor(v.color),
                  icon: Icons.palette_outlined,
                  tablet: tablet,
                ),
                if (_vehicleDocumentsLoaded) ...[
                  Builder(
                    builder: (context) {
                      final scope = _activeFleetScope();
                      if (scope == null) return const SizedBox.shrink();
                      final docs = _VehicleComplianceDocumentStore.instance
                          .documentsForVehicle(
                            tenantId: scope.tenantId,
                            companyId: scope.companyId,
                            vehicleId: v.id,
                          );
                      if (docs.isEmpty) return const SizedBox.shrink();
                      final pendingCount = docs
                          .where(
                            (doc) =>
                                doc.status ==
                                _VehicleComplianceDocumentStatuses.pending,
                          )
                          .length;
                      final summary = pendingCount > 0
                          ? _t(
                              nl: '$pendingCount in behandeling / ${docs.length} totaal',
                              en: '$pendingCount pending / ${docs.length} total',
                              fr: '$pendingCount en cours / ${docs.length} au total',
                              es: '$pendingCount en revisión / ${docs.length} total',
                            )
                          : '${docs.length}';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: col3SectionGap),
                          _compactSectionHeading(
                            _t(
                              nl: 'Documenten',
                              en: 'Documents',
                              fr: 'Documents',
                              es: 'Documentos',
                            ),
                            tablet: tablet,
                          ),
                          _compactCellLine(
                            _t(
                              nl: 'Compliance-docs',
                              en: 'Compliance docs',
                              fr: 'Docs conformité',
                              es: 'Docs cumplimiento',
                            ),
                            summary,
                            icon: Icons.description_outlined,
                            tablet: tablet,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: colGap),
          // Column 4: company + actions (flex 16)
          Expanded(
            flex: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t(
                    nl: 'Bedrijf',
                    en: 'Company',
                    fr: 'Entreprise',
                    es: 'Empresa',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: companyLabelFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: col4LabelGap),
                Text(
                  (v.companyId?.trim().isNotEmpty ?? false)
                      ? v.companyId!.trim()
                      : _t(
                          nl: '(legacy)',
                          en: '(legacy)',
                          fr: '(ancien)',
                          es: '(legacy)',
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: _textFaint,
                    fontSize: companyIdFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: col4BeforeButtons),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openVehicleEditor(existing: v),
                    icon: Icon(Icons.edit_outlined, size: btnIconSize),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gold.withOpacity(0.95),
                      side: BorderSide(color: _gold.withOpacity(0.42)),
                      backgroundColor: _panelBg,
                      padding: EdgeInsets.symmetric(
                        horizontal: btnPadH,
                        vertical: btnPadV,
                      ),
                      minimumSize: Size(0, btnMinHeight),
                      textStyle: TextStyle(fontSize: btnFontSize),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    label: Text(
                      _t(
                        nl: 'Bewerken',
                        en: 'Edit',
                        fr: 'Modifier',
                        es: 'Editar',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                SizedBox(height: col4BetweenButtons),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final scope = _activeFleetScope();
                      if (scope != null) {
                        await _VehicleComplianceDocumentStore.instance
                            .removeAllForVehicle(
                              tenantId: scope.tenantId,
                              companyId: scope.companyId,
                              vehicleId: v.id,
                            );
                      }
                      deleteVehicle(v.id);
                      await _syncFleetOrShowError();
                    },
                    icon: Icon(Icons.delete_outline, size: btnIconSize),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _danger,
                      side: BorderSide(color: _danger.withOpacity(0.45)),
                      backgroundColor: _danger.withOpacity(0.16),
                      padding: EdgeInsets.symmetric(
                        horizontal: btnPadH,
                        vertical: btnPadV,
                      ),
                      minimumSize: Size(0, btnMinHeight),
                      textStyle: TextStyle(fontSize: btnFontSize),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    label: Text(
                      _t(
                        nl: 'Verwijder',
                        en: 'Delete',
                        fr: 'Supprimer',
                        es: 'Eliminar',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    bool compact = false,
    // Phone-landscape needs even smaller KPI tiles than tablet's compact
    // mode. `dense` only takes effect when `compact == true`, so phone
    // portrait and tablet layouts are unaffected.
    bool dense = false,
    // Tablet landscape uses a third density tier between [dense] (phone
    // landscape) and the original [compact] values. It keeps numbers and
    // labels readable but trims the oversized icon bubble and value font
    // that previously made the tablet-landscape KPI band too tall. Only
    // takes effect when [compact] is true and [dense] is false. Phone
    // portrait and tablet portrait are unaffected.
    bool tabletLandscape = false,
  }) {
    final bool denseCompact = compact && dense;
    final bool tabletCompact = compact && !dense && tabletLandscape;
    final tilePadding = denseCompact
        ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
        : tabletCompact
        ? const EdgeInsets.fromLTRB(12, 6, 12, 6)
        : compact
        ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
        : const EdgeInsets.fromLTRB(12, 9, 12, 9);
    final iconBubble = denseCompact
        ? 28.0
        : tabletCompact
        ? 40.0
        : compact
        ? 58.0
        : 46.0;
    final iconSize = denseCompact
        ? 15.0
        : tabletCompact
        ? 22.0
        : compact
        ? 34.0
        : 28.0;
    final gap = denseCompact
        ? 6.0
        : tabletCompact
        ? 12.0
        : compact
        ? 16.0
        : 12.0;
    final labelFontSize = denseCompact
        ? 10.4
        : tabletCompact
        ? 12.4
        : compact
        ? 14.0
        : 12.5;
    final valueFontSize = denseCompact
        ? 15.6
        : tabletCompact
        ? 20.0
        : compact
        ? 30.0
        : 23.0;
    return Container(
      padding: tilePadding,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Row(
        children: [
          Container(
            width: iconBubble,
            height: iconBubble,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.15),
              border: Border.all(color: accent.withOpacity(0.5)),
            ),
            child: Icon(icon, size: iconSize, color: accent),
          ),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: valueFontSize,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        appLanguageNotifier,
        businessThemeNotifier,
        brandSignaturePaletteNotifier,
      ]),
      builder: (context, _) => Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          foregroundColor: _textPrimary,
          title: Text(
            _t(
              nl: 'Voertuigen',
              en: 'Vehicles',
              fr: 'Véhicules',
              es: 'Vehículos',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t(
                nl: 'Voertuig toevoegen',
                en: 'Add vehicle',
                fr: 'Ajouter un véhicule',
                es: 'Agregar vehículo',
              ),
              onPressed: () async {
                if (!await _confirmVehicleUpsellIfNeeded()) return;
                await _openVehicleEditor();
              },
              icon: Icon(Icons.add, color: _gold.withOpacity(0.95)),
            ),
          ],
        ),
        body: ValueListenableBuilder<List<VehicleProfile>>(
          valueListenable: vehiclesNotifier,
          builder: (context, vehicles, _) {
            final media = MediaQuery.of(context);
            final isTabletLandscape =
                media.size.width >= 900 &&
                media.orientation == Orientation.landscape;
            // Phone-class landscape with a short height: intro/KPIs and the
            // vehicle card must pack more densely so vehicle identity and
            // assignment are visible without scrolling far. Tablet landscape
            // and portrait orientations are unchanged.
            final isCompactLandscape =
                !isTabletLandscape &&
                media.orientation == Orientation.landscape &&
                media.size.height < 500;
            final visible = vehicles
                .where((v) => _vehicleVisibleInManagementUi(v))
                .toList(growable: false);
            final totalCount = visible.length;
            final activeCount = visible.where((v) => v.isActive).length;
            final linkedCount = visible
                .where((v) => (v.driverId?.trim().isNotEmpty ?? false))
                .length;
            final summaryAspectRatio = isCompactLandscape
                ? 3.6
                : isTabletLandscape
                ? 3.6
                : 2.05;
            return SafeArea(
              top: false,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: isCompactLandscape
                          ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
                          : isTabletLandscape
                          ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
                          : const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: isCompactLandscape
                                ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
                                : isTabletLandscape
                                ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
                                : const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            decoration: BoxDecoration(
                              color: _cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _gold.withOpacity(0.30),
                              ),
                            ),
                            child: isCompactLandscape
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Voertuigen',
                                          en: 'Vehicles',
                                          fr: 'Véhicules',
                                          es: 'Vehículos',
                                        ),
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.2,
                                        ),
                                      ),
                                      Text(
                                        '  ·  ',
                                        style: TextStyle(
                                          color: _textMuted.withOpacity(0.7),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11.6,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _t(
                                            nl: 'Beheer wagenpark, chauffeurskoppeling en documenten',
                                            en: 'Manage fleet, driver assignment and documents',
                                            fr: 'Gérez la flotte, les chauffeurs liés et les documents',
                                            es: 'Gestiona la flota, conductores vinculados y documentos',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _textMuted,
                                            fontSize: 10.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Voertuigen',
                                          en: 'Vehicles',
                                          fr: 'Véhicules',
                                          es: 'Vehículos',
                                        ),
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _t(
                                          nl: 'Beheer wagenpark, chauffeurskoppeling en documenten',
                                          en: 'Manage fleet, driver assignment and documents',
                                          fr: 'Gérez la flotte, les chauffeurs liés et les documents',
                                          es: 'Gestiona la flota, conductores vinculados y documentos',
                                        ),
                                        style: TextStyle(
                                          color: _textMuted,
                                          fontSize: 12.4,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          SizedBox(
                            height: isCompactLandscape
                                ? 4
                                : isTabletLandscape
                                ? 6
                                : 10,
                          ),
                          Container(
                            width: double.infinity,
                            padding: isCompactLandscape
                                ? const EdgeInsets.all(4)
                                : isTabletLandscape
                                ? const EdgeInsets.fromLTRB(8, 6, 8, 6)
                                : const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _panelBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _gold.withOpacity(0.30),
                              ),
                            ),
                            child: GridView.count(
                              crossAxisCount: 3,
                              crossAxisSpacing: isCompactLandscape ? 4 : 8,
                              mainAxisSpacing: isCompactLandscape ? 4 : 8,
                              childAspectRatio: summaryAspectRatio,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _summaryTile(
                                  label: _t(
                                    nl: 'Totaal',
                                    en: 'Total',
                                    fr: 'Total',
                                    es: 'Total',
                                  ),
                                  value: '$totalCount',
                                  icon: Icons.directions_car_filled_outlined,
                                  accent: _gold,
                                  compact:
                                      isTabletLandscape || isCompactLandscape,
                                  dense: isCompactLandscape,
                                  tabletLandscape: isTabletLandscape,
                                ),
                                _summaryTile(
                                  label: _t(
                                    nl: 'Actief',
                                    en: 'Active',
                                    fr: 'Actifs',
                                    es: 'Activos',
                                  ),
                                  value: '$activeCount',
                                  icon: Icons.verified_outlined,
                                  accent: _success,
                                  compact:
                                      isTabletLandscape || isCompactLandscape,
                                  dense: isCompactLandscape,
                                  tabletLandscape: isTabletLandscape,
                                ),
                                _summaryTile(
                                  label: _t(
                                    nl: 'Gekoppeld',
                                    en: 'Linked',
                                    fr: 'Liés',
                                    es: 'Vinculados',
                                  ),
                                  value: '$linkedCount',
                                  icon: Icons.link_rounded,
                                  accent: _linkedAccent,
                                  compact:
                                      isTabletLandscape || isCompactLandscape,
                                  dense: isCompactLandscape,
                                  tabletLandscape: isTabletLandscape,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _gold.withOpacity(0.24),
                              ),
                            ),
                            child: Text(
                              _t(
                                nl: 'Nog geen voertuigen.',
                                en: 'No vehicles yet.',
                                fr: 'Aucun véhicule.',
                                es: 'Sin vehículos.',
                              ),
                              style: TextStyle(color: _textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: isCompactLandscape
                          ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
                          : const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final v = visible[i];
                          final linkedDriver = _driverById(v.driverId);
                          final status = v.isActive
                              ? _t(
                                  nl: 'Actief',
                                  en: 'Active',
                                  fr: 'Actif',
                                  es: 'Activo',
                                )
                              : _t(
                                  nl: 'Inactief',
                                  en: 'Inactive',
                                  fr: 'Inactif',
                                  es: 'Inactivo',
                                );
                          if (isCompactLandscape) {
                            return _vehicleCompactLandscapeCard(
                              v: v,
                              linkedDriver: linkedDriver,
                              status: status,
                            );
                          }
                          // Tablet landscape reuses the same 4-column model as
                          // phone landscape, but with tablet-scaled paddings,
                          // photo height, font sizes and button targets so the
                          // card stays compact yet professional and readable.
                          // Phone portrait, phone landscape, and tablet
                          // portrait paths fall through to the existing card.
                          if (isTabletLandscape) {
                            return _vehicleCompactLandscapeCard(
                              v: v,
                              linkedDriver: linkedDriver,
                              status: status,
                              tablet: true,
                            );
                          }
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            decoration: BoxDecoration(
                              color: _cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _gold.withOpacity(0.28),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _photoPreviewBox(
                                  photoRef: v.primaryPhotoRef,
                                  fallbackPhotoRef: v.publicPhotoUrl,
                                  height: isCompactLandscape ? 110 : 176,
                                  onTap: null,
                                  placeholderText: _t(
                                    nl: 'Geen voertuigfoto',
                                    en: 'No vehicle photo',
                                    fr: 'Pas de photo véhicule',
                                    es: 'Sin foto del vehículo',
                                  ),
                                ),
                                SizedBox(height: isCompactLandscape ? 6 : 9),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _displayVehicleName(v.vehicleName),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: isCompactLandscape
                                              ? 13.6
                                              : 15.8,
                                          color: _textPrimary,
                                        ),
                                        maxLines: isCompactLandscape ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: v.isActive
                                            ? _success.withOpacity(0.16)
                                            : _panelBg.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: v.isActive
                                              ? _success.withOpacity(0.5)
                                              : _theme.border.withOpacity(0.8),
                                        ),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: v.isActive
                                              ? _success
                                              : _textSecondary,
                                          fontSize: 11.6,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  v.brandModel.trim().isEmpty
                                      ? '—'
                                      : v.brandModel.trim(),
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${_t(nl: 'Nummerplaat', en: 'Plate', fr: 'Plaque', es: 'Matrícula')}: ${v.licensePlate.isEmpty ? '—' : v.licensePlate}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _gold.withOpacity(0.13),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: _gold.withOpacity(0.42),
                                        ),
                                      ),
                                      child: Text(
                                        _tierLabel(v.tierId),
                                        style: TextStyle(
                                          color: _gold.withOpacity(0.98),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11.6,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _panelBg.withOpacity(0.48),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: _theme.border.withOpacity(0.8),
                                        ),
                                      ),
                                      child: Text(
                                        '${v.passengerCapacity} ${_t(nl: 'passagiers', en: 'passengers', fr: 'passagers', es: 'pasajeros')}',
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontSize: 11.4,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _panelBg.withOpacity(0.48),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: _theme.border.withOpacity(0.8),
                                        ),
                                      ),
                                      child: Text(
                                        '${v.luggageCapacity} ${_t(nl: 'koffers', en: 'bags', fr: 'bagages', es: 'maletas')}',
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontSize: 11.4,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _panelBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _gold.withOpacity(0.22),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Chauffeur',
                                          en: 'Driver',
                                          fr: 'Chauffeur',
                                          es: 'Conductor',
                                        ),
                                        style: TextStyle(
                                          color: _gold.withOpacity(0.96),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _driverInfoLine(
                                        _t(
                                          nl: 'Gekoppelde chauffeur',
                                          en: 'Linked driver',
                                          fr: 'Chauffeur lié',
                                          es: 'Conductor vinculado',
                                        ),
                                        linkedDriver == null
                                            ? '—'
                                            : _displayDriverName(
                                                linkedDriver.fullName,
                                              ),
                                        icon: Icons.person_outline,
                                      ),
                                      if (linkedDriver != null) ...[
                                        const SizedBox(height: 4),
                                        _driverInfoLine(
                                          _t(
                                            nl: 'Chauffeur-ID',
                                            en: 'Driver ID',
                                            fr: 'ID chauffeur',
                                            es: 'ID conductor',
                                          ),
                                          linkedDriver.employeeNumber,
                                          icon: Icons.badge_outlined,
                                        ),
                                        const SizedBox(height: 4),
                                        _driverInfoLine(
                                          _t(
                                            nl: 'Telefoon',
                                            en: 'Phone',
                                            fr: 'Téléphone',
                                            es: 'Teléfono',
                                          ),
                                          linkedDriver.phone,
                                          icon: Icons.phone_outlined,
                                        ),
                                        const SizedBox(height: 4),
                                        _driverInfoLine(
                                          _t(
                                            nl: 'Chauffeurskaartnummer',
                                            en: 'Driver card number',
                                            fr: 'N° carte chauffeur',
                                            es: 'N.º tarjeta de conductor',
                                          ),
                                          linkedDriver.taxiDriverCardNumber,
                                          icon: Icons.credit_card_outlined,
                                        ),
                                        const SizedBox(height: 4),
                                        _driverInfoLine(
                                          _t(
                                            nl: 'Vervaldatum chauffeurskaart',
                                            en: 'Driver card expiry',
                                            fr: 'Expiration carte chauffeur',
                                            es: 'Caducidad tarjeta de conductor',
                                          ),
                                          linkedDriver.taxiDriverCardExpiry,
                                          icon: Icons.event_note_outlined,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _panelBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _theme.border.withOpacity(0.8),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Vergunning & registratie',
                                          en: 'Permit & registration',
                                          fr: 'Permis et immatriculation',
                                          es: 'Permiso y registro',
                                        ),
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _driverInfoLine(
                                        _t(
                                          nl: 'Exploitatievergunning',
                                          en: 'Operating license number',
                                          fr: 'N° de licence d’exploitation',
                                          es: 'N.º licencia de explotación',
                                        ),
                                        v.exploitationLicenseNumber,
                                        icon: Icons.verified_user_outlined,
                                      ),
                                      const SizedBox(height: 4),
                                      _driverInfoLine(
                                        _t(
                                          nl: 'Inschrijving/VIN/chassis',
                                          en: 'Registration/VIN/chassis',
                                          fr: 'Immatriculation/VIN/châssis',
                                          es: 'Matrícula/VIN/chasis',
                                        ),
                                        v.vehicleRegistrationNumber,
                                        icon: Icons.numbers_outlined,
                                      ),
                                      const SizedBox(height: 4),
                                      _driverInfoLine(
                                        _t(
                                          nl: 'Kleur',
                                          en: 'Color',
                                          fr: 'Couleur',
                                          es: 'Color',
                                        ),
                                        _displayColor(v.color),
                                        icon: Icons.palette_outlined,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (v.galleryPhotoRefs.length > 1) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _t(
                                      nl: '+${v.galleryPhotoRefs.length - 1} extra foto\'s',
                                      en: '+${v.galleryPhotoRefs.length - 1} more photos',
                                      fr: '+${v.galleryPhotoRefs.length - 1} photos supplémentaires',
                                      es: '+${v.galleryPhotoRefs.length - 1} fotos adicionales',
                                    ),
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  '${_t(nl: 'Bedrijf (lokaal)', en: 'Company (local)', fr: 'Entreprise (locale)', es: 'Empresa (local)')}: '
                                  '${(v.companyId?.trim().isNotEmpty ?? false) ? v.companyId!.trim() : _t(nl: '(legacy)', en: '(legacy)', fr: '(ancien)', es: '(legacy)')}',
                                  style: TextStyle(
                                    color: _textFaint,
                                    fontSize: 10.8,
                                  ),
                                ),
                                SizedBox(height: isCompactLandscape ? 6 : 8),
                                Wrap(
                                  spacing: isCompactLandscape ? 6 : 8,
                                  runSpacing: isCompactLandscape ? 6 : 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _openVehicleEditor(existing: v),
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: isCompactLandscape ? 14 : 16,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _gold.withOpacity(
                                          0.95,
                                        ),
                                        side: BorderSide(
                                          color: _gold.withOpacity(0.42),
                                        ),
                                        backgroundColor: _panelBg,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isCompactLandscape
                                              ? 9
                                              : 10,
                                          vertical: isCompactLandscape ? 6 : 8,
                                        ),
                                        minimumSize: isCompactLandscape
                                            ? const Size(0, 32)
                                            : null,
                                        textStyle: isCompactLandscape
                                            ? const TextStyle(fontSize: 11.6)
                                            : null,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                      label: Text(
                                        _t(
                                          nl: 'Bewerken',
                                          en: 'Edit',
                                          fr: 'Modifier',
                                          es: 'Editar',
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        deleteVehicle(v.id);
                                        await _syncFleetOrShowError();
                                      },
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: isCompactLandscape ? 14 : 16,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _danger,
                                        side: BorderSide(
                                          color: _danger.withOpacity(0.45),
                                        ),
                                        backgroundColor: _danger.withOpacity(
                                          0.16,
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isCompactLandscape
                                              ? 9
                                              : 10,
                                          vertical: isCompactLandscape ? 6 : 8,
                                        ),
                                        minimumSize: isCompactLandscape
                                            ? const Size(0, 32)
                                            : null,
                                        textStyle: isCompactLandscape
                                            ? const TextStyle(fontSize: 11.6)
                                            : null,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                      label: Text(
                                        _t(
                                          nl: 'Verwijder',
                                          en: 'Delete',
                                          fr: 'Supprimer',
                                          es: 'Eliminar',
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }, childCount: visible.length),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
