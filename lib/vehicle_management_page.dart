import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
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
    sheetBg: isClean ? palette.surface : palette.surfaceAlt,
    inputFill: isClean
        ? palette.surfaceAlt.withOpacity(0.95)
        : const Color(0xFF0B0B0B),
    dropdownBg: isClean ? palette.surface : const Color(0xFF111111),
    inputBorder: palette.border.withOpacity(isClean ? 0.8 : 0.44),
    overlayDark: isClean ? const Color(0xB31C2430) : const Color(0xB8000000),
    overlaySoft: isClean ? const Color(0xA61C2430) : const Color(0x8A000000),
    success: palette.success,
    linkedAccent: linkedAccent,
    danger: palette.danger,
  );
}

class VehicleManagementPage extends StatefulWidget {
  const VehicleManagementPage({super.key});

  @override
  State<VehicleManagementPage> createState() => _VehicleManagementPageState();
}

class _VehicleManagementPageState extends State<VehicleManagementPage> {
  final ImagePicker _imagePicker = ImagePicker();
  static const int _maxPhotosPerVehicle = 5;
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
    }
  }

  String _tierLabel(String tierId) {
    for (final t in appConfig.enabledTiers) {
      if (t.id == tierId) return t.labelFor(_lang);
    }
    return tierId;
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
      setLocalState(() {
        publicPhotoUrlCtrl.text = url;
      });
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
    final activeCompanyId = _activeCompanyIdForFleetUi();
    if (activeCompanyId == null) {
      return fleetRecordBelongsToActiveCompanyOrLegacy(driver.companyId);
    }
    // Company-scoped management views avoid showing legacy/companyless rows as active-company data.
    return (driver.companyId?.trim() ?? '') == activeCompanyId;
  }

  bool _vehicleVisibleInManagementUi(VehicleProfile vehicle) {
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

  Future<bool> _confirmVehicleUpsellIfNeeded() async {
    final currentCount = vehiclesNotifier.value.length;
    if (currentCount < includedVehicleLimit) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheetBg,
        title: Text(
          _t(
            nl: 'Extra voertuig',
            en: 'Additional vehicle',
            fr: 'Véhicule supplémentaire',
            es: 'Vehículo adicional',
          ),
        ),
        content: Text(
          _t(
            nl: 'Je abonnement bevat 1 voertuig. Extra voertuigen vallen onder een upsell van €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} per voertuig per maand.',
            en: 'Your subscription includes 1 vehicle. Additional vehicles use an upsell of €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} per vehicle per month.',
            fr: 'Votre abonnement inclut 1 véhicule. Les véhicules supplémentaires utilisent un supplément de €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} par véhicule et par mois.',
            es: 'Tu suscripción incluye 1 vehículo. Los vehículos adicionales aplican un cargo de €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} por vehículo al mes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: _textSecondary),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _theme.palette.textOnAccent,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _t(
                nl: 'Doorgaan',
                en: 'Continue',
                fr: 'Continuer',
                es: 'Continuar',
              ),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<DriverProfile?> _openDriverCreator({DriverProfile? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.fullName ?? '');
    final idCtrl = TextEditingController(text: existing?.employeeNumber ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final taxiCardNumberCtrl = TextEditingController(
      text: existing?.taxiDriverCardNumber ?? '',
    );
    final taxiCardExpiryCtrl = TextEditingController(
      text: existing?.taxiDriverCardExpiry ?? '',
    );
    DriverProfile? saved;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: _sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEdit
              ? _t(
                  nl: 'Chauffeur bewerken',
                  en: 'Edit driver',
                  fr: 'Modifier chauffeur',
                  es: 'Editar conductor',
                )
              : _t(
                  nl: 'Chauffeur toevoegen',
                  en: 'New driver',
                  fr: 'Ajouter un chauffeur',
                  es: 'Agregar conductor',
                ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _txt(
                nameCtrl,
                _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
              ),
              _txt(
                idCtrl,
                _t(
                  nl: 'Chauffeur-ID',
                  en: 'Driver ID',
                  fr: 'ID chauffeur',
                  es: 'ID conductor',
                ),
                enabled: !isEdit,
              ),
              _txt(
                phoneCtrl,
                _t(
                  nl: 'Telefoonnummer',
                  en: 'Phone number',
                  fr: 'Numéro de téléphone',
                  es: 'Número de teléfono',
                ),
              ),
              _txt(
                taxiCardNumberCtrl,
                _t(
                  nl: 'Kaartnummer',
                  en: 'Card number',
                  fr: 'N° carte',
                  es: 'N.º tarjeta',
                ),
              ),
              _txt(
                taxiCardExpiryCtrl,
                _t(
                  nl: 'Vervaldatum kaart',
                  en: 'Card expiry',
                  fr: 'Expiration carte',
                  es: 'Vencimiento tarjeta',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        _t(
                          nl: 'Annuleren',
                          en: 'Cancel',
                          fr: 'Annuler',
                          es: 'Cancelar',
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final fullName = nameCtrl.text.trim();
                        final employeeNumber = idCtrl.text.trim();
                        if (!isEdit &&
                            (fullName.isEmpty || employeeNumber.isEmpty)) {
                          return;
                        }
                        if (isEdit) {
                          saved = existing.copyWith(
                            fullName: fullName,
                            phone: phoneCtrl.text.trim(),
                            taxiDriverCardNumber: taxiCardNumberCtrl.text
                                .trim(),
                            taxiDriverCardExpiry: taxiCardExpiryCtrl.text
                                .trim(),
                          );
                          updateDriver(existing.id, saved!);
                        } else {
                          saved = DriverProfile(
                            id: 'drv_${DateTime.now().millisecondsSinceEpoch}',
                            fullName: fullName,
                            employeeNumber: employeeNumber,
                            phone: phoneCtrl.text.trim(),
                            taxiDriverCardNumber: taxiCardNumberCtrl.text
                                .trim(),
                            taxiDriverCardExpiry: taxiCardExpiryCtrl.text
                                .trim(),
                            isActive: true,
                            companyId: _activeCompanyIdForFleetUi(),
                          );
                          addDriver(saved!);
                        }
                        Navigator.pop(ctx);
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        isEdit
                            ? _t(
                                nl: 'Opslaan',
                                en: 'Save',
                                fr: 'Enregistrer',
                                es: 'Guardar',
                              )
                            : _t(
                                nl: 'Toevoegen',
                                en: 'Add',
                                fr: 'Ajouter',
                                es: 'Agregar',
                              ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return saved;
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

  Future<void> _openVehicleEditor({VehicleProfile? existing}) async {
    final vehicleId =
        existing?.id ?? 'vh_${DateTime.now().millisecondsSinceEpoch}';
    final nameCtrl = TextEditingController(text: existing?.vehicleName ?? '');
    final modelCtrl = TextEditingController(text: existing?.brandModel ?? '');
    final plateCtrl = TextEditingController(text: existing?.licensePlate ?? '');
    final exploitationLicenseCtrl = TextEditingController(
      text: existing?.exploitationLicenseNumber ?? '',
    );
    final vehicleRegistrationCtrl = TextEditingController(
      text: existing?.vehicleRegistrationNumber ?? '',
    );
    final colorCtrl = TextEditingController(text: existing?.color ?? '');
    var primaryPhotoRef = existing?.primaryPhotoRef ?? '';
    var galleryPhotoRefs = List<String>.from(
      existing?.galleryPhotoRefs ?? const <String>[],
    );
    final publicPhotoUrlCtrl = TextEditingController(
      text: existing?.publicPhotoUrl ?? '',
    );
    var publicPhotoUploading = false;
    final paxCtrl = TextEditingController(
      text: (existing?.passengerCapacity ?? 3).toString(),
    );
    final bagsCtrl = TextEditingController(
      text: (existing?.luggageCapacity ?? 3).toString(),
    );
    var tierId = existing?.tierId ?? appConfig.enabledTiers.first.id;
    String? linkedDriverId = existing?.driverId;
    {
      final cid = _scopedVehicleCompanyId(existing);
      final dr0 = _driverById(linkedDriverId);
      if (dr0 == null || !_canAssignDriverToVehicleInManagementUi(dr0, cid)) {
        linkedDriverId = null;
      }
    }
    var active = existing?.isActive ?? true;

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
                        existing == null
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
                      ),
                      _txt(
                        modelCtrl,
                        _t(
                          nl: 'Merk/model',
                          en: 'Make/model',
                          fr: 'Marque/modèle',
                          es: 'Marca/modelo',
                        ),
                      ),
                      _txt(
                        plateCtrl,
                        _t(
                          nl: 'Nummerplaat',
                          en: 'Plate',
                          fr: 'Plaque',
                          es: 'Matrícula',
                        ),
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
                                      _scopedVehicleCompanyId(existing),
                                    ) &&
                                    !fleetExplicitCompanyMismatch(
                                      d.companyId,
                                      _scopedVehicleCompanyId(existing),
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
                                    existing: existing,
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
                                                  existing: existing,
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
                                    existing,
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
                                  setLocalState(() {
                                    publicPhotoUrlCtrl.text = url;
                                  });
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
                                  final cid = _scopedVehicleCompanyId(existing);
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
                                    publicPhotoUrl:
                                        publicPhotoUrlCtrl.text.trim().isEmpty
                                        ? null
                                        : publicPhotoUrlCtrl.text.trim(),
                                  );
                                  if (existing == null) {
                                    addVehicle(vehicle);
                                  } else {
                                    updateVehicle(existing.id, vehicle);
                                  }
                                  await _syncFleetOrShowError();
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
  }

  Widget _txt(
    TextEditingController ctrl,
    String label, {
    VoidCallback? onChanged,
    bool enabled = true,
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

  Widget _summaryTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    bool compact = false,
  }) {
    final tilePadding = compact
        ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
        : const EdgeInsets.fromLTRB(12, 9, 12, 9);
    final iconBubble = compact ? 58.0 : 46.0;
    final iconSize = compact ? 34.0 : 28.0;
    final gap = compact ? 16.0 : 12.0;
    final labelFontSize = compact ? 14.0 : 12.5;
    final valueFontSize = compact ? 30.0 : 23.0;
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
      animation: Listenable.merge([appLanguageNotifier, businessThemeNotifier]),
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
            final visible = vehicles
                .where((v) => _vehicleVisibleInManagementUi(v))
                .toList(growable: false);
            final totalCount = visible.length;
            final activeCount = visible.where((v) => v.isActive).length;
            final linkedCount = visible
                .where((v) => (v.driverId?.trim().isNotEmpty ?? false))
                .length;
            final summaryAspectRatio = isTabletLandscape ? 2.7 : 2.05;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: BoxDecoration(
                            color: _cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _gold.withOpacity(0.30)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _panelBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _gold.withOpacity(0.30)),
                          ),
                          child: GridView.count(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
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
                                compact: isTabletLandscape,
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
                                compact: isTabletLandscape,
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
                                compact: isTabletLandscape,
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
                            border: Border.all(color: _gold.withOpacity(0.24)),
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
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                          decoration: BoxDecoration(
                            color: _cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _gold.withOpacity(0.28)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _photoPreviewBox(
                                photoRef: v.primaryPhotoRef,
                                fallbackPhotoRef: v.publicPhotoUrl,
                                height: 176,
                                onTap: null,
                                placeholderText: _t(
                                  nl: 'Geen voertuigfoto',
                                  en: 'No vehicle photo',
                                  fr: 'Pas de photo véhicule',
                                  es: 'Sin foto del vehículo',
                                ),
                              ),
                              const SizedBox(height: 9),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _displayVehicleName(v.vehicleName),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.8,
                                        color: _textPrimary,
                                      ),
                                      maxLines: 2,
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
                                      borderRadius: BorderRadius.circular(999),
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
                                      borderRadius: BorderRadius.circular(999),
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
                                      borderRadius: BorderRadius.circular(999),
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
                                      borderRadius: BorderRadius.circular(999),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _openVehicleEditor(existing: v),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _gold.withOpacity(0.95),
                                      side: BorderSide(
                                        color: _gold.withOpacity(0.42),
                                      ),
                                      backgroundColor: _panelBg,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
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
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _danger,
                                      side: BorderSide(
                                        color: _danger.withOpacity(0.45),
                                      ),
                                      backgroundColor: _danger.withOpacity(
                                        0.16,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
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
            );
          },
        ),
      ),
    );
  }
}
