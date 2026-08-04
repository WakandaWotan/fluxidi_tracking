part of '../main.dart';

class _CompanyDriverManagementPageBody extends StatelessWidget {
  const _CompanyDriverManagementPageBody({
    this.onRequestAdminDriverDocumentsRefresh,
    this.onRequestMutationRefresh,
    this.documentRefreshFailedDriverIds = const <String>{},
    this.onPropagateConfirmedDriverState,
  });

  final Future<void> Function({
    required String reason,
    bool force,
    String? onlyDriverId,
  })?
  onRequestAdminDriverDocumentsRefresh;
  final Future<void> Function({required String reason})?
  onRequestMutationRefresh;
  final Set<String> documentRefreshFailedDriverIds;
  final void Function(DriverProfile updated)? onPropagateConfirmedDriverState;

  BusinessThemePalette get _palette =>
      paletteForBusinessTheme(businessThemeNotifier.value);
  bool get _isDark => _palette.isDark;
  Color get _pageBg => _palette.background;
  Color get _panelBg => _palette.surface;
  Color get _subPanelBg => _palette.surfaceAlt;
  Color get _gold => _palette.accent;
  Color get _textPrimary => _palette.textPrimary;
  Color get _textSecondary => _palette.textSecondary;
  Color get _textMuted => _palette.textMuted;
  Color get _textOnAccent => _palette.textOnAccent;
  Color get _border => _palette.border;
  Color get _success => _palette.success;
  Color get _danger => _palette.danger;
  Color get _shadow => _palette.shadow;
  bool get _isCleanProfessional =>
      businessThemeNotifier.value == BusinessThemeVariant.cleanProfessional;
  bool get _isCorporateBlue =>
      businessThemeNotifier.value == BusinessThemeVariant.corporateBlue;
  Color get _inputFill => _isDark
      ? (_isCorporateBlue ? const Color(0xFF0F1A2F) : const Color(0xFF0B0B0B))
      : const Color(0xFFF7F9FC);
  Color get _inputBorderColor =>
      _border.withOpacity(_isDark ? (_isCorporateBlue ? 0.72 : 0.55) : 0.92);
  Color get _inputFocusColor =>
      _gold.withOpacity(_isDark ? (_isCorporateBlue ? 0.95 : 0.9) : 0.95);
  Color get _dialogBg => _isDark ? _panelBg : _subPanelBg;
  Color get _dialogHelperTextColor =>
      _textMuted.withOpacity(_isCleanProfessional ? 0.98 : 0.9);
  static final Set<String> _avatarPrecacheQueuedUrls = <String>{};
  static String _lastDriverPageLogSignature = '';
  static String _lastAdminDocVisibilitySignature = '';

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  AppLanguage get _lang => appConfig.currentLanguage;

  String _docsInOrderLabel(DriverDocumentComplianceSummary summary) {
    return _t(
      nl: '${summary.validRequiredCount}/${summary.requiredTotal} documenten in orde',
      en: '${summary.validRequiredCount}/${summary.requiredTotal} documents in order',
      fr: '${summary.validRequiredCount}/${summary.requiredTotal} documents en ordre',
      es: '${summary.validRequiredCount}/${summary.requiredTotal} documentos en orden',
    );
  }

  String _missingRequiredLabel(int missingCount) {
    return _t(
      nl: '$missingCount documenten ontbreken',
      en: '$missingCount documents are missing',
      fr: '$missingCount documents manquants',
      es: 'Faltan $missingCount documentos',
    );
  }

  String _documentsNeedsActionLabel() {
    return _t(
      nl: 'Documenten vereisen controle.',
      en: 'Documents need action.',
      fr: 'Documents à vérifier.',
      es: 'Documentos requieren revisión.',
    );
  }

  Future<void> _openDriverDocumentArtifact(
    BuildContext context,
    DriverProfile driver,
    DriverDocument doc,
  ) async {
    final safeDriverRef = _shortDriverIdForDiag(driver.id);
    final safeDocRef = _shortDriverIdForDiag(doc.documentId);
    debugPrint(
      '[DRIVER_DOC_OPEN][START] driver=$safeDriverRef doc=$safeDocRef',
    );
    final localPath = doc.filePath.trim();
    final hasLocal =
        localPath.isNotEmpty && !kIsWeb && File(localPath).existsSync();
    final hasBackendArtifact =
        doc.storageState.trim().toLowerCase() == 'stored' &&
        doc.backendFileName.trim().isNotEmpty &&
        doc.backendContentType.trim().isNotEmpty &&
        doc.backendSizeBytes > 0;
    final source = hasLocal
        ? 'local'
        : (hasBackendArtifact ? 'backend' : 'missing');
    debugPrint(
      '[DRIVER_DOC_OPEN][SOURCE] driver=$safeDriverRef doc=$safeDocRef source=$source',
    );
    if (source == 'missing') {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Documentbestand niet beschikbaar. Upload opnieuw of synchroniseer documentbestand.',
              en: 'Document file not available. Re-upload or synchronize the document file.',
              fr: 'Fichier indisponible. Retéléversez ou synchronisez le fichier.',
              es: 'Archivo no disponible. Vuelve a subir o sincroniza el archivo.',
            ),
          ),
        ),
      );
      debugPrint(
        '[DRIVER_DOC_OPEN][FAILED] driver=$safeDriverRef doc=$safeDocRef error=artifact_missing',
      );
      return;
    }
    if (source == 'local') {
      await openDriverDocumentFile(context, localPath, _lang);
      debugPrint(
        '[DRIVER_DOC_OPEN][DONE] driver=$safeDriverRef doc=$safeDocRef',
      );
      return;
    }

    final token =
        (activeCompanySessionNotifier.value?.companySessionToken ?? '').trim();
    final tenantId = doc.tenantId.trim();
    final companyId = doc.companyId.trim();
    final driverId = doc.driverId.trim();
    final documentId = doc.documentId.trim();
    if (token.isEmpty ||
        tenantId.isEmpty ||
        companyId.isEmpty ||
        driverId.isEmpty ||
        documentId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Backend documenttoegang vereist een actieve bedrijfssessie.',
              en: 'Backend document access requires an active company session.',
              fr: 'L’accès backend au document nécessite une session entreprise active.',
              es: 'El acceso backend al documento requiere una sesión activa de empresa.',
            ),
          ),
        ),
      );
      debugPrint(
        '[DRIVER_DOC_OPEN][FAILED] driver=$safeDriverRef doc=$safeDocRef error=missing_scope_or_token',
      );
      return;
    }

    debugPrint(
      '[DRIVER_DOC_OPEN][REQUEST] driver=$safeDriverRef doc=$safeDocRef endpoint=/admin/driver-documents/file',
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
      debugPrint(
        '[DRIVER_DOC_OPEN][RESPONSE] driver=$safeDriverRef doc=$safeDocRef status=200 bytes=${downloaded.bytes}',
      );
      final saved =
          downloaded.localPath.trim().isNotEmpty &&
          await File(downloaded.localPath).exists();
      debugPrint(
        '[DRIVER_DOC_OPEN][LOCAL_CACHE] driver=$safeDriverRef doc=$safeDocRef saved=$saved',
      );
      if (!saved) {
        debugPrint(
          '[DRIVER_DOC_OPEN][FAILED] driver=$safeDriverRef doc=$safeDocRef error=cache_save_failed',
        );
        return;
      }
      if (!context.mounted) return;
      await openDriverDocumentFile(context, downloaded.localPath, _lang);
      debugPrint(
        '[DRIVER_DOC_OPEN][DONE] driver=$safeDriverRef doc=$safeDocRef',
      );
    } catch (e) {
      final err = e.toString().toLowerCase();
      var code = 'download_failed';
      if (err.contains('404')) code = 'not_found';
      if (err.contains('401') || err.contains('403')) code = 'unauthorized';
      if (err.contains('timeout')) code = 'timeout';
      debugPrint(
        '[DRIVER_DOC_OPEN][FAILED] driver=$safeDriverRef doc=$safeDocRef error=$code',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
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

  String _attachmentMissingLabel() {
    return _t(
      nl: 'Bijlage ontbreekt. Upload opnieuw of synchroniseer documentbestand.',
      en: 'Attachment missing. Re-upload or synchronize the document file.',
      fr: 'Pièce jointe manquante. Retéléversez ou synchronisez le fichier.',
      es: 'Falta el adjunto. Vuelve a subir o sincroniza el archivo.',
    );
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

  String _driverCodeLast4(DriverProfile driver) {
    final explicitDriverLast4 = (driver.driverCodeLast4 ?? '').trim();
    if (explicitDriverLast4.isNotEmpty) return explicitDriverLast4;
    final explicitLoginLast4 = (driver.loginCodeLast4 ?? '').trim();
    if (explicitLoginLast4.isNotEmpty) return explicitLoginLast4;
    final legacy = driver.employeeNumber.trim();
    if (legacy.length >= 4) return legacy.substring(legacy.length - 4);
    return '';
  }

  bool _driverHasLoginCode(DriverProfile driver) {
    if (driver.hasLoginCode) return true;
    return _driverCodeLast4(driver).isNotEmpty;
  }

  String _driverCodeStatusLabel(DriverProfile driver) {
    final last4 = _driverCodeLast4(driver);
    if (_driverHasLoginCode(driver)) {
      final suffix = last4.isEmpty ? '' : ' • ****$last4';
      return _t(
        nl: 'Code ingesteld$suffix',
        en: 'Code set$suffix',
        fr: 'Code defini$suffix',
        es: 'Codigo configurado$suffix',
      );
    }
    return _t(
      nl: 'Geen chauffeurcode ingesteld',
      en: 'No driver code set',
      fr: 'Aucun code chauffeur defini',
      es: 'No hay codigo de conductor configurado',
    );
  }

  String _normalizePublicCompanyCodeForDriverQr(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _isValidPublicCompanyCodeForDriverQr(String value) {
    final code = _normalizePublicCompanyCodeForDriverQr(value);
    if (code.isEmpty) return false;
    return RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(code);
  }

  String _resolvePublicCompanyCodeForDriverQr() {
    String? readFirstValidFromMap(Map<String, dynamic>? map) {
      if (map == null) return null;
      for (final key in const <String>[
        'public_company_code',
        'publicCompanyCode',
        'company_code',
        'companyCode',
      ]) {
        final normalized = _normalizePublicCompanyCodeForDriverQr(
          (map[key] ?? '').toString(),
        );
        if (_isValidPublicCompanyCodeForDriverQr(normalized)) {
          return normalized;
        }
      }
      return null;
    }

    final backendMap = localBackendBusinessProfileNotifier.value?.toJson();
    final profileMap = companyProfileNotifier.value?.toJson();
    final sessionCode = _normalizePublicCompanyCodeForDriverQr(
      activeCompanySessionNotifier.value?.companyCode ?? '',
    );

    if (_isValidPublicCompanyCodeForDriverQr(sessionCode)) {
      return sessionCode;
    }

    final backendCode = readFirstValidFromMap(
      backendMap is Map<String, dynamic> ? backendMap : null,
    );
    if (backendCode != null) return backendCode;

    final profileCode = readFirstValidFromMap(
      profileMap is Map<String, dynamic> ? profileMap : null,
    );
    if (profileCode != null) return profileCode;

    return '';
  }

  Future<void> _showGeneratedDriverCodeDialog(
    BuildContext context, {
    required String loginCode,
    required String driverName,
    required Future<void> Function() onCreateTemporaryQr,
  }) async {
    final trimmedCode = loginCode.trim();
    if (trimmedCode.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
        contentTextStyle: TextStyle(color: _textSecondary, fontSize: 12.8),
        title: Text(
          _t(
            nl: 'Nieuwe chauffeurcode',
            en: 'New driver code',
            fr: 'Nouveau code chauffeur',
            es: 'Nuevo codigo de conductor',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                nl: 'Bewaar deze code nu. Ze wordt niet opnieuw getoond.',
                en: 'Store this code now. It will not be shown again.',
                fr: 'Conservez ce code maintenant. Il ne sera plus affiche.',
                es: 'Guarda este codigo ahora. No se mostrara de nuevo.',
              ),
              style: TextStyle(
                color: Colors.orangeAccent.withOpacity(_isDark ? 0.95 : 1.0),
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              driverName.trim().isEmpty
                  ? _t(
                      nl: 'Chauffeur',
                      en: 'Driver',
                      fr: 'Chauffeur',
                      es: 'Conductor',
                    )
                  : _displayDriverName(driverName),
              style: TextStyle(
                color: _textSecondary,
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _gold.withOpacity(_isDark ? 0.38 : 0.7),
                ),
              ),
              child: SelectableText(
                trimmedCode,
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                nl: 'Voor QR-koppeling maak je een tijdelijke koppel-QR.',
                en: 'For QR pairing, create a temporary pairing QR.',
                fr: 'Pour le couplage QR, créez un QR de liaison temporaire.',
                es: 'Para vinculación por QR, crea un QR temporal de vinculación.',
              ),
              style: TextStyle(color: _textMuted, fontSize: 11.8, height: 1.3),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: trimmedCode));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      nl: 'Chauffeurcode gekopieerd.',
                      en: 'Driver code copied.',
                      fr: 'Code chauffeur copie.',
                      es: 'Codigo de conductor copiado.',
                    ),
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _textPrimary,
              side: BorderSide(color: _inputBorderColor),
            ),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text(
              _t(nl: 'Kopieren', en: 'Copy', fr: 'Copier', es: 'Copiar'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await onCreateTemporaryQr();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _textPrimary,
              side: BorderSide(color: _inputBorderColor),
            ),
            icon: const Icon(Icons.qr_code_2_outlined, size: 16),
            label: Text(
              _t(
                nl: 'Tijdelijke koppel-QR maken',
                en: 'Create temporary pairing QR',
                fr: 'Créer un QR de liaison temporaire',
                es: 'Crear QR temporal de vinculación',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _textOnAccent,
            ),
            child: Text(
              _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverField(
    TextEditingController ctrl,
    String label, {
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        style: TextStyle(
          color: enabled
              ? _textPrimary
              : _textMuted.withOpacity(_isDark ? 0.78 : 0.9),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _textSecondary.withOpacity(0.96)),
          filled: true,
          fillColor: _inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputFocusColor, width: 1.25),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: _inputBorderColor.withOpacity(_isDark ? 0.7 : 0.92),
            ),
          ),
        ),
      ),
    );
  }

  String _photoExtension(String path) {
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

  String _safePhotoSegment(String raw, {String fallback = '_'}) {
    final text = raw.trim();
    if (text.isEmpty) return fallback;
    final sanitized = text.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    if (sanitized.isEmpty) return fallback;
    return sanitized.length <= 80 ? sanitized : sanitized.substring(0, 80);
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

  String _initialsFromName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'D';
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  Future<String?> _persistPickedDriverPhoto({
    required String sourcePath,
    required DriverProfile driver,
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
      final ext = _photoExtension(source);
      final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
      final fromSession =
          activeCompanySessionNotifier.value?.companyId.trim() ?? '';
      final companySeg = _safePhotoSegment(
        driver.companyId?.trim().isNotEmpty == true
            ? driver.companyId!.trim()
            : (fromProfile.isNotEmpty
                  ? fromProfile
                  : (fromSession.isNotEmpty ? fromSession : '')),
        fallback: 'company',
      );
      final driverSeg = _safePhotoSegment(driver.id, fallback: 'driver');
      final fileName =
          'driver_${companySeg}_${driverSeg}_${DateTime.now().millisecondsSinceEpoch}'
          '${ext.isEmpty ? '' : '.$ext'}';
      final target = File('${dir.path}${Platform.pathSeparator}$fileName');
      await src.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<ImageSource?> _askProfilePhotoSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _panelBg,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _t(
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
                _t(
                  nl: 'Foto nemen',
                  en: 'Take photo',
                  fr: 'Prendre une photo',
                  es: 'Tomar foto',
                ),
              ),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(
                _t(
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

  Future<void> _openEditDriverDialog(
    BuildContext context,
    DriverProfile existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing.fullName);
    final phoneCtrl = TextEditingController(text: existing.phone);
    final taxiCardNumberCtrl = TextEditingController(
      text: existing.taxiDriverCardNumber,
    );
    final taxiCardExpiryCtrl = TextEditingController(
      text: existing.taxiDriverCardExpiry,
    );
    final publicDisplayNameCtrl = TextEditingController(
      text: existing.publicDisplayName ?? '',
    );
    final publicPortraitUrlCtrl = TextEditingController(
      text: existing.publicPortraitUrl ?? '',
    );
    var profilePhotoPath = existing.profilePhotoPath?.trim() ?? '';
    var publicProfileEnabled = existing.publicProfileEnabled;
    var publicPhotoEnabled = existing.publicPhotoEnabled;
    var publicPhotoUploading = false;
    var active = existing.isActive;
    bool isHttpsPublicUrl(String value) {
      final normalized = value.trim().toLowerCase();
      return normalized.startsWith('https://');
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final hasInternalPhoto = _driverPhotoExists(profilePhotoPath);
          final hasPublicPortraitUrl = isHttpsPublicUrl(
            publicPortraitUrlCtrl.text.trim(),
          );
          final publicPortraitNetworkUrl = hasPublicPortraitUrl
              ? publicPortraitUrlCtrl.text.trim()
              : null;
          final hasUsablePublicPhotoSource =
              hasInternalPhoto || hasPublicPortraitUrl;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            backgroundColor: _dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              _t(
                nl: 'Chauffeur bewerken',
                en: 'Edit driver',
                fr: 'Modifier le chauffeur',
                es: 'Editar conductor',
              ),
              style: TextStyle(color: _textPrimary),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _subPanelBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _border.withOpacity(_isDark ? 0.5 : 0.95),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _inputFill,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _border.withOpacity(
                                    _isDark ? 0.58 : 0.95,
                                  ),
                                ),
                              ),
                              child: ClipOval(
                                child: hasInternalPhoto
                                    ? Image.file(
                                        File(profilePhotoPath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(
                                            _initialsFromName(nameCtrl.text),
                                            style: TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      )
                                    : (publicPortraitNetworkUrl != null
                                          ? Image.network(
                                              publicPortraitNetworkUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Center(
                                                    child: Text(
                                                      _initialsFromName(
                                                        nameCtrl.text,
                                                      ),
                                                      style: TextStyle(
                                                        color: _textPrimary,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : Center(
                                              child: Text(
                                                _initialsFromName(
                                                  nameCtrl.text,
                                                ),
                                                style: TextStyle(
                                                  color: _textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            )),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      nl: 'Pasfoto',
                                      en: 'Profile photo',
                                      fr: 'Photo de profil',
                                      es: 'Foto de perfil',
                                    ),
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.6,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (hasInternalPhoto ||
                                            publicPortraitNetworkUrl != null)
                                        ? _t(
                                            nl: 'Foto aanwezig',
                                            en: 'Photo available',
                                            fr: 'Photo disponible',
                                            es: 'Foto disponible',
                                          )
                                        : _t(
                                            nl: 'Nog geen pasfoto',
                                            en: 'No profile photo yet',
                                            fr: 'Pas encore de photo',
                                            es: 'Aún sin foto',
                                          ),
                                    style: TextStyle(
                                      color: _textMuted.withOpacity(0.9),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            nl: 'Deze foto is enkel zichtbaar binnen het bedrijf.',
                            en: 'This photo is only visible inside the company.',
                            fr: 'Cette photo est uniquement visible dans l’entreprise.',
                            es: 'Esta foto solo es visible dentro de la empresa.',
                          ),
                          style: TextStyle(
                            color: _dialogHelperTextColor,
                            fontSize: 11.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _gold.withOpacity(0.98),
                                side: BorderSide(
                                  color: _gold.withOpacity(0.45),
                                ),
                                backgroundColor: _subPanelBg,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              onPressed: () async {
                                final source = await _askProfilePhotoSource(
                                  ctx,
                                );
                                if (source == null) return;
                                try {
                                  final picked = await ImagePicker().pickImage(
                                    source: source,
                                    imageQuality: 90,
                                  );
                                  if (picked == null) return;
                                  final persisted =
                                      await _persistPickedDriverPhoto(
                                        sourcePath: picked.path,
                                        driver: existing,
                                      );
                                  final nextPath = (persisted ?? '').trim();
                                  if (nextPath.isEmpty) return;
                                  setDialogState(
                                    () => profilePhotoPath = nextPath,
                                  );
                                } catch (_) {}
                              },
                              icon: Icon(
                                hasInternalPhoto
                                    ? Icons.photo_camera_outlined
                                    : Icons.add_a_photo_outlined,
                                size: 16,
                              ),
                              label: Text(
                                hasInternalPhoto
                                    ? _t(
                                        nl: 'Pasfoto wijzigen',
                                        en: 'Change profile photo',
                                        fr: 'Modifier la photo',
                                        es: 'Cambiar foto',
                                      )
                                    : _t(
                                        nl: 'Pasfoto toevoegen',
                                        en: 'Add profile photo',
                                        fr: 'Ajouter une photo',
                                        es: 'Añadir foto de perfil',
                                      ),
                              ),
                            ),
                            if (hasInternalPhoto)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: BorderSide(
                                    color: Colors.redAccent.withOpacity(0.45),
                                  ),
                                  backgroundColor: const Color(0xFF2A1518),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  minimumSize: const Size(0, 36),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                onPressed: () => setDialogState(() {
                                  profilePhotoPath = '';
                                  publicPhotoEnabled = false;
                                }),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  _t(
                                    nl: 'Pasfoto verwijderen',
                                    en: 'Remove profile photo',
                                    fr: 'Supprimer la photo',
                                    es: 'Eliminar foto',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _subPanelBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _border.withOpacity(_isDark ? 0.5 : 0.95),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            nl: 'Publiek partnerprofiel',
                            en: 'Public partner profile',
                            fr: 'Profil partenaire public',
                            es: 'Perfil público de socio',
                          ),
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: publicProfileEnabled,
                          activeColor: _gold,
                          activeTrackColor: _gold.withOpacity(0.5),
                          onChanged: (v) => setDialogState(() {
                            publicProfileEnabled = v;
                            if (!publicProfileEnabled) {
                              publicPhotoEnabled = false;
                            }
                          }),
                          title: Text(
                            _t(
                              nl: 'Toon chauffeur publiek',
                              en: 'Show driver publicly',
                              fr: 'Afficher le chauffeur publiquement',
                              es: 'Mostrar conductor públicamente',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: _textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value:
                              publicProfileEnabled &&
                              hasUsablePublicPhotoSource &&
                              publicPhotoEnabled,
                          activeColor: _gold,
                          activeTrackColor: _gold.withOpacity(0.5),
                          onChanged:
                              (!publicProfileEnabled ||
                                  !hasUsablePublicPhotoSource)
                              ? null
                              : (v) => setDialogState(
                                  () => publicPhotoEnabled = v,
                                ),
                          title: Text(
                            _t(
                              nl: 'Toon pasfoto publiek',
                              en: 'Show profile photo publicly',
                              fr: 'Afficher la photo publiquement',
                              es: 'Mostrar foto públicamente',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: _textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: (!hasUsablePublicPhotoSource)
                              ? Text(
                                  _t(
                                    nl: 'Voeg eerst een interne pasfoto toe of upload een publieke chauffeursfoto.',
                                    en: 'Add an internal profile photo or upload a public chauffeur photo first.',
                                    fr: 'Ajoutez d’abord une photo interne ou téléversez une photo publique du chauffeur.',
                                    es: 'Primero añade una foto interna o sube una foto pública del conductor.',
                                  ),
                                  style: TextStyle(
                                    color: _dialogHelperTextColor,
                                    fontSize: 11.2,
                                  ),
                                )
                              : null,
                        ),
                        _driverField(
                          publicDisplayNameCtrl,
                          _t(
                            nl: 'Publieke naam',
                            en: 'Public name',
                            fr: 'Nom public',
                            es: 'Nombre público',
                          ),
                        ),
                        _driverField(
                          publicPortraitUrlCtrl,
                          _t(
                            nl: 'Publieke foto-URL',
                            en: 'Public photo URL',
                            fr: 'URL photo publique',
                            es: 'URL pública de foto',
                          ),
                          enabled: publicProfileEnabled && publicPhotoEnabled,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _gold.withOpacity(0.98),
                              side: BorderSide(
                                color: _gold.withOpacity(_isDark ? 0.45 : 0.7),
                              ),
                              backgroundColor: _isCleanProfessional
                                  ? Colors.white
                                  : _subPanelBg,
                            ),
                            onPressed: publicPhotoUploading
                                ? null
                                : () async {
                                    final source = await _askProfilePhotoSource(
                                      ctx,
                                    );
                                    if (source == null) return;
                                    try {
                                      final picked = await ImagePicker()
                                          .pickImage(
                                            source: source,
                                            imageQuality: 88,
                                            maxWidth: 1200,
                                          );
                                      if (picked == null) return;
                                      setDialogState(
                                        () => publicPhotoUploading = true,
                                      );
                                      final scope =
                                          _activeCompanyScopeForDriverDelete(
                                            existing,
                                          );
                                      if (scope == null) {
                                        debugPrint(
                                          '[DRIVER_SCOPE][SKIP] reason=missing_strict_scope',
                                        );
                                        if (!context.mounted) return;
                                        _showMissingCompanyScopeSnackbar(
                                          context,
                                        );
                                        return;
                                      }
                                      final bytes = kIsWeb
                                          ? await picked.readAsBytes()
                                          : null;
                                      final uploaded =
                                          await uploadPublicPartnerMedia(
                                            tenantId: scope.tenantId,
                                            companyId: scope.companyId,
                                            mediaType: 'driver_photo',
                                            entityId: existing.id,
                                            filePath: kIsWeb
                                                ? null
                                                : picked.path,
                                            fileBytes: bytes,
                                            filename: picked.name,
                                          );
                                      final url = (uploaded['url'] ?? '')
                                          .toString()
                                          .trim();
                                      final isHttps = url
                                          .toLowerCase()
                                          .startsWith('https://');
                                      if (!isHttps) {
                                        throw Exception(
                                          'Upload did not return a valid HTTPS URL',
                                        );
                                      }
                                      setDialogState(() {
                                        publicPortraitUrlCtrl.text = url;
                                        publicPhotoEnabled = true;
                                      });
                                      final uploadedDriver = existing.copyWith(
                                        publicPortraitUrl: url,
                                        publicProfileEnabled:
                                            publicProfileEnabled,
                                        publicPhotoEnabled: true,
                                      );
                                      final persisted =
                                          await syncDriverIndexEntryToBackend(
                                            uploadedDriver,
                                            tenantId: scope.tenantId,
                                            companyId: scope.companyId,
                                            companySessionToken:
                                                activeCompanySessionNotifier
                                                    .value
                                                    ?.companySessionToken,
                                          );
                                      if (!context.mounted) return;
                                      if (!persisted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _t(
                                                nl: 'Publieke URL geüpload maar nog niet duurzaam opgeslagen. Probeer opnieuw op te slaan.',
                                                en: 'Public URL uploaded but not durably saved yet. Please try saving again.',
                                                fr: 'URL publique téléversée mais pas encore enregistrée durablement. Veuillez réessayer.',
                                                es: 'La URL pública se subió, pero aún no se guardó de forma duradera. Inténtalo de nuevo.',
                                              ),
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      updateDriver(
                                        existing.id,
                                        uploadedDriver,
                                        syncInventory: false,
                                      );
                                      unawaited(
                                        onRequestMutationRefresh?.call(
                                          reason: 'drivers_photo_upload_save',
                                        ),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _t(
                                              nl: 'Publieke chauffeursfoto geüpload.',
                                              en: 'Public chauffeur photo uploaded.',
                                              fr: 'Photo publique du chauffeur téléchargée.',
                                              es: 'Foto pública del conductor subida.',
                                            ),
                                          ),
                                        ),
                                      );
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _t(
                                              nl: 'Upload mislukt. Gebruik JPG, PNG of WEBP.',
                                              en: 'Upload failed. Please use JPG, PNG, or WEBP.',
                                              fr: 'Échec du téléchargement. Utilisez JPG, PNG ou WEBP.',
                                              es: 'La carga falló. Usa JPG, PNG o WEBP.',
                                            ),
                                          ),
                                        ),
                                      );
                                    } finally {
                                      setDialogState(
                                        () => publicPhotoUploading = false,
                                      );
                                    }
                                  },
                            icon: publicPhotoUploading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.upload_file_outlined,
                                    size: 16,
                                  ),
                            label: Text(
                              _t(
                                nl: 'Publieke chauffeursfoto uploaden',
                                en: 'Upload public chauffeur photo',
                                fr: 'Télécharger photo publique du chauffeur',
                                es: 'Subir foto pública del conductor',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            nl: 'Deze URL wordt later gebruikt voor het publieke profiel. De interne pasfoto blijft lokaal.',
                            en: 'This URL will be used later for the public profile. The internal profile photo remains local.',
                            fr: 'Cette URL sera utilisée plus tard pour le profil public. La photo interne reste locale.',
                            es: 'Esta URL se usará más adelante para el perfil público. La foto interna permanece local.',
                          ),
                          style: TextStyle(
                            color: _dialogHelperTextColor,
                            fontSize: 11.1,
                          ),
                        ),
                        if (publicPortraitUrlCtrl.text.trim().isNotEmpty &&
                            !publicPortraitUrlCtrl.text
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
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            nl: 'Deze instellingen publiceren nog niets automatisch. Publicatie gebeurt later via het publieke partnerprofiel.',
                            en: 'These settings do not publish anything automatically yet. Publishing happens later through the public partner profile.',
                            fr: 'Ces paramètres ne publient encore rien automatiquement. La publication se fera plus tard via le profil partenaire public.',
                            es: 'Estos ajustes aún no publican nada automáticamente. La publicación se hará más adelante mediante el perfil público del socio.',
                          ),
                          style: TextStyle(
                            color: _dialogHelperTextColor,
                            fontSize: 11.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            nl: 'Na upload en opslaan: publiceer het partnerprofiel opnieuw om de publieke pagina te vernieuwen.',
                            en: 'After upload and save: republish the partner profile to refresh the public page.',
                            fr: 'Après téléversement et enregistrement : republiez le profil partenaire pour actualiser la page publique.',
                            es: 'Después de subir y guardar: vuelve a publicar el perfil del socio para actualizar la página pública.',
                          ),
                          style: TextStyle(
                            color: _dialogHelperTextColor,
                            fontSize: 11.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _driverField(
                    nameCtrl,
                    _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _subPanelBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _border.withOpacity(_isDark ? 0.5 : 0.95),
                      ),
                    ),
                    child: Text(
                      _t(
                        nl: 'Chauffeurcode beheer: gebruik "Nieuwe chauffeurcode genereren".',
                        en: 'Driver code management: use "Generate new driver code".',
                        fr: 'Gestion du code chauffeur : utilisez "Generer un nouveau code chauffeur".',
                        es: 'Gestion del codigo de conductor: usa "Generar nuevo codigo de conductor".',
                      ),
                      style: TextStyle(
                        color: _textSecondary.withOpacity(0.92),
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _driverField(
                    phoneCtrl,
                    _t(
                      nl: 'Telefoonnummer',
                      en: 'Phone number',
                      fr: 'Numéro de téléphone',
                      es: 'Número de teléfono',
                    ),
                  ),
                  _driverField(
                    taxiCardNumberCtrl,
                    _t(
                      nl: 'Kaartnummer',
                      en: 'Card number',
                      fr: 'N° carte',
                      es: 'N.º tarjeta',
                    ),
                  ),
                  _driverField(
                    taxiCardExpiryCtrl,
                    _t(
                      nl: 'Vervaldatum kaart',
                      en: 'Card expiry',
                      fr: 'Expiration carte',
                      es: 'Caducidad tarjeta',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    activeColor: _gold,
                    activeTrackColor: _gold.withOpacity(0.5),
                    onChanged: (v) => setDialogState(() => active = v),
                    title: Text(
                      _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo'),
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textPrimary,
                            side: BorderSide(color: _border.withOpacity(0.7)),
                            backgroundColor: _subPanelBg,
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
                          style: FilledButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _textOnAccent,
                          ),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(ctx);
                            final navigator = Navigator.of(ctx);
                            final updated = existing.copyWith(
                              fullName: nameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              taxiDriverCardNumber: taxiCardNumberCtrl.text
                                  .trim(),
                              taxiDriverCardExpiry: taxiCardExpiryCtrl.text
                                  .trim(),
                              isActive: active,
                              profilePhotoPath: profilePhotoPath.trim().isEmpty
                                  ? null
                                  : profilePhotoPath.trim(),
                              publicProfileEnabled: publicProfileEnabled,
                              publicPhotoEnabled:
                                  publicProfileEnabled &&
                                  (hasInternalPhoto ||
                                      isHttpsPublicUrl(
                                        publicPortraitUrlCtrl.text.trim(),
                                      )) &&
                                  publicPhotoEnabled,
                              publicDisplayName:
                                  publicDisplayNameCtrl.text.trim().isEmpty
                                  ? null
                                  : publicDisplayNameCtrl.text.trim(),
                              publicPortraitUrl:
                                  publicPortraitUrlCtrl.text.trim().isEmpty
                                  ? null
                                  : publicPortraitUrlCtrl.text.trim(),
                            );
                            final scope = _activeCompanyScopeForDriverDelete(
                              existing,
                            );
                            if (scope == null) {
                              debugPrint(
                                '[DRIVER_SCOPE][SKIP] reason=missing_strict_scope',
                              );
                              _showMissingCompanyScopeSnackbar(ctx);
                              return;
                            }
                            debugPrint(
                              '[DRIVER_STATUS_SAVE][START] driver=${_shortDriverIdForDiag(updated.id)} desiredActive=${updated.isActive}',
                            );
                            debugPrint(
                              '[DRIVER_EDIT_SAVE][BEFORE_UPSERT] driver=${_shortDriverIdForDiag(updated.id)} name=${updated.fullName.trim()} isActive=${updated.isActive} tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)}',
                            );
                            final persistedResult =
                                await syncDriverStatusToBackend(
                                  updated,
                                  tenantId: scope.tenantId,
                                  companyId: scope.companyId,
                                  companySessionToken:
                                      activeCompanySessionNotifier
                                          .value
                                          ?.companySessionToken,
                                );
                            final persisted = persistedResult.ok;
                            debugPrint(
                              '[DRIVER_EDIT_SAVE][UPSERT_RESULT] driver=${_shortDriverIdForDiag(updated.id)} ok=$persisted',
                            );
                            if (!navigator.mounted) return;
                            if (!persisted) {
                              final statusCode = persistedResult.statusCode;
                              if (statusCode == 401 || statusCode == 403) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        nl: 'Uw bedrijfssessie is verlopen. Herkoppel of herstel uw bedrijf en probeer opnieuw.',
                                        en: 'Your company session expired. Relink or recover your company and try again.',
                                        fr: 'Votre session entreprise a expiré. Reliez ou récupérez votre entreprise puis réessayez.',
                                        es: 'Tu sesión de empresa expiró. Vuelve a vincular o recupera tu empresa e inténtalo de nuevo.',
                                      ),
                                    ),
                                  ),
                                );
                              } else if (statusCode == 400 ||
                                  statusCode == 422) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        nl: 'Bestuurdersgegevens zijn ongeldig voor opslaan. Controleer de velden en probeer opnieuw.',
                                        en: 'Driver data is invalid for save. Check the fields and try again.',
                                        fr: 'Les données du chauffeur sont invalides pour l’enregistrement. Vérifiez les champs et réessayez.',
                                        es: 'Los datos del conductor no son válidos para guardar. Revisa los campos e inténtalo de nuevo.',
                                      ),
                                    ),
                                  ),
                                );
                              } else {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        nl: 'Wijziging kon niet worden opgeslagen op de server. Probeer opnieuw.',
                                        en: 'Change could not be saved on the server. Please try again.',
                                        fr: 'La modification n’a pas pu être enregistrée sur le serveur. Réessayez.',
                                        es: 'No se pudo guardar el cambio en el servidor. Inténtalo de nuevo.',
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            onPropagateConfirmedDriverState?.call(updated);
                            unawaited(
                              onRequestMutationRefresh?.call(
                                reason: 'drivers_edit_save',
                              ),
                            );
                            debugPrint(
                              '[DRIVER_EDIT_SAVE][LOCAL_UPDATED] driver=${_shortDriverIdForDiag(updated.id)} isActive=${updated.isActive} syncInventory=false',
                            );
                            debugPrint(
                              '[DRIVER_STATUS_SAVE][DONE] driver=${_shortDriverIdForDiag(updated.id)} active=${updated.isActive}',
                            );
                            navigator.pop();
                          },
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _line(String label, String value, {IconData? icon}) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _gold.withOpacity(0.9)),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: _textMuted.withOpacity(0.9),
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(color: _textMuted),
                  ),
                  TextSpan(
                    text: shown,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayCompanyLoginCode(DriverProfile driver) {
    final scoped = driver.companyId?.trim() ?? '';
    if (scoped.isNotEmpty) return scoped;
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromSession.isNotEmpty) return fromSession;
    return '';
  }

  String _maskDriverForLog(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'unknown';
    if (text.length <= 4) return '…${text.substring(text.length - 1)}';
    return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
  }

  void _showMissingCompanyScopeSnackbar(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Backendsynchronisatie vereist een actieve bedrijfssessie. Herkoppel of herstel eerst uw bedrijf.',
            en: 'Backend synchronization requires an active company session. Relink or recover your company first.',
            fr: 'La synchronisation backend nécessite une session entreprise active. Reliez ou récupérez d’abord votre entreprise.',
            es: 'La sincronización del backend requiere una sesión activa de empresa. Vuelve a vincular o recuperar tu empresa primero.',
          ),
        ),
      ),
    );
  }

  ({String tenantId, String companyId})? _activeCompanyScopeForDriverDelete(
    DriverProfile driver,
  ) {
    final scoped = driver.companyId?.trim() ?? '';
    if (scoped.isNotEmpty) {
      return (tenantId: scoped, companyId: scoped);
    }
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) {
      return (tenantId: fromProfile, companyId: fromProfile);
    }
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromSession.isNotEmpty) {
      return (tenantId: fromSession, companyId: fromSession);
    }
    return null;
  }

  String _temporaryDriverLinkExpiryLabel({
    required String expiresAt,
    int? expiresInSeconds,
  }) {
    final iso = expiresAt.trim();
    if (iso.isNotEmpty) {
      return _t(
        nl: 'Geldig tot $iso',
        en: 'Valid until $iso',
        fr: 'Valide jusqu’à $iso',
        es: 'Válido hasta $iso',
      );
    }
    final seconds = expiresInSeconds ?? 0;
    if (seconds > 0) {
      final minutes = (seconds / 60).ceil();
      return _t(
        nl: 'Geldig ongeveer $minutes minuten',
        en: 'Valid for about $minutes minutes',
        fr: 'Valide environ $minutes minutes',
        es: 'Válido durante aproximadamente $minutes minutos',
      );
    }
    return _t(
      nl: 'Tijdelijke code verloopt binnenkort.',
      en: 'Temporary code expires soon.',
      fr: 'Le code temporaire expire bientôt.',
      es: 'El código temporal caduca pronto.',
    );
  }

  Future<void> _showTemporaryDriverLinkQrDialog(
    BuildContext context, {
    required String companyCode,
    required String pairingCode,
    required String challengeId,
    required String driverName,
    required String expiresAt,
    int? expiresInSeconds,
  }) async {
    final payload =
        'fluxidi://driver-link?company_code=${Uri.encodeComponent(companyCode)}&pairing_code=${Uri.encodeComponent(pairingCode)}&challenge_id=${Uri.encodeComponent(challengeId)}&v=1';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // Responsive layout: in phone-class landscape the dialog is very
        // short (~360 px tall) so the legacy vertical Column would push the
        // pairing-code container and AlertDialog actions into the QR area.
        // Detect that case and render the body as a horizontal Row (text on
        // the left, QR on the right). Tablet/portrait keep the original
        // vertical Column.
        final mq = MediaQuery.of(dialogContext);
        final screen = mq.size;
        final isCompactLandscape =
            screen.width > screen.height && screen.height < 500;
        // Clamp QR size between a minimum that stays scannable and a
        // maximum that fits the available dialog height. Tablet/portrait
        // keep the larger 200 px QR.
        final double qrSize = isCompactLandscape
            ? (screen.height * 0.5).clamp(140.0, 180.0)
            : 200.0;

        final driverNameWidget = Text(
          driverName.trim().isEmpty
              ? _t(
                  nl: 'Chauffeur',
                  en: 'Driver',
                  fr: 'Chauffeur',
                  es: 'Conductor',
                )
              : _displayDriverName(driverName),
          style: TextStyle(
            color: _textSecondary,
            fontSize: 12.8,
            fontWeight: FontWeight.w600,
          ),
        );
        final oneTimeWarning = Text(
          _t(
            nl: 'Deze QR is éénmalig bruikbaar.',
            en: 'This QR is one-time use.',
            fr: 'Ce QR est à usage unique.',
            es: 'Este QR es de un solo uso.',
          ),
          style: TextStyle(
            color: Colors.orangeAccent.withOpacity(_isDark ? 0.95 : 1.0),
            fontSize: 12.2,
            fontWeight: FontWeight.w700,
          ),
        );
        final expiryWidget = Text(
          _temporaryDriverLinkExpiryLabel(
            expiresAt: expiresAt,
            expiresInSeconds: expiresInSeconds,
          ),
          style: TextStyle(color: _textMuted, fontSize: 11.8),
        );
        final qrCard = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // QR inner background must remain white for scannability on
            // every theme.
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _border.withOpacity(_isDark ? 0.0 : 0.55),
            ),
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: qrSize,
            backgroundColor: Colors.white,
          ),
        );
        final pairingCodeContainer = Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withOpacity(_isDark ? 0.38 : 0.7)),
          ),
          child: SelectableText(
            pairingCode,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 0.4,
              fontFamily: 'monospace',
            ),
          ),
        );

        final Widget contentBody;
        if (isCompactLandscape) {
          contentBody = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    driverNameWidget,
                    const SizedBox(height: 8),
                    oneTimeWarning,
                    const SizedBox(height: 6),
                    expiryWidget,
                    const SizedBox(height: 10),
                    pairingCodeContainer,
                  ],
                ),
              ),
              const SizedBox(width: 14),
              qrCard,
            ],
          );
        } else {
          contentBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              driverNameWidget,
              const SizedBox(height: 10),
              oneTimeWarning,
              const SizedBox(height: 8),
              expiryWidget,
              const SizedBox(height: 10),
              Center(child: qrCard),
              const SizedBox(height: 10),
              pairingCodeContainer,
            ],
          );
        }

        return AlertDialog(
          backgroundColor: _dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // scrollable: true wraps title+content+actions in a scroll view so
          // that on very short heights the actions row is pushed below the
          // content instead of being pinned over the QR.
          scrollable: true,
          // Tighten the dialog inset so we have more horizontal room for the
          // two-column layout in phone landscape, while staying within the
          // safe area on every form factor.
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompactLandscape ? 24 : 40,
            vertical: 24,
          ),
          titleTextStyle: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
          contentTextStyle: TextStyle(color: _textSecondary, fontSize: 12.8),
          title: Text(
            _t(
              nl: 'Tijdelijke koppel-QR',
              en: 'Temporary pairing QR',
              fr: 'QR de liaison temporaire',
              es: 'QR temporal de vinculación',
            ),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              // Cap content width so that on tablet landscape the dialog
              // does not stretch oddly, and on phone landscape the Row has
              // enough room without forcing horizontal scroll.
              maxWidth: isCompactLandscape ? 560 : 360,
            ),
            child: contentBody,
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pairingCode));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      _t(
                        nl: 'Tijdelijke koppelcode gekopieerd.',
                        en: 'Temporary pairing code copied.',
                        fr: 'Code de liaison temporaire copié.',
                        es: 'Código temporal de vinculación copiado.',
                      ),
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _textPrimary,
                side: BorderSide(color: _inputBorderColor),
              ),
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: Text(
                _t(nl: 'Kopieren', en: 'Copy', fr: 'Copier', es: 'Copiar'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _textOnAccent,
              ),
              child: Text(
                _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openTemporaryDriverLinkQr(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final driverId = driver.id.trim();
    debugPrint('[DRIVER_LINK_QR][START] driver=${_maskDriverForLog(driverId)}');
    if (driverId.isEmpty) {
      debugPrint('[DRIVER_LINK_QR][NO_DRIVER_ID]');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Deze chauffeur heeft nog geen geldige driver-id.',
              en: 'This driver does not have a valid driver ID yet.',
              fr: 'Ce chauffeur n’a pas encore d’identifiant chauffeur valide.',
              es: 'Este conductor aún no tiene un ID de conductor válido.',
            ),
          ),
        ),
      );
      return;
    }
    final publicCompanyCode = _resolvePublicCompanyCodeForDriverQr();
    debugPrint(
      '[DRIVER_LINK_QR][PUBLIC_CODE] found=${_isValidPublicCompanyCodeForDriverQr(publicCompanyCode)} code=${_maskScopeForLog(publicCompanyCode)}',
    );
    if (!_isValidPublicCompanyCodeForDriverQr(publicCompanyCode)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Geen geldige publieke bedrijfscode beschikbaar voor tijdelijke koppel-QR.',
              en: 'No valid public company code available for temporary pairing QR.',
              fr: 'Aucun code entreprise public valide disponible pour le QR de liaison temporaire.',
              es: 'No hay un código público de empresa válido para el QR temporal de vinculación.',
            ),
          ),
        ),
      );
      return;
    }
    final scope = _activeCompanyScopeForDriverDelete(driver);
    if (scope == null) {
      debugPrint('[DRIVER_SCOPE][SKIP] reason=missing_strict_scope');
      _showMissingCompanyScopeSnackbar(context);
      return;
    }
    debugPrint(
      '[DRIVER_LINK_QR][SCOPE] tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)}',
    );
    debugPrint('[DRIVER_LINK_QR][CREATE_REQ]');
    final created = await createDriverLinkCode(
      driverId: driverId,
      tenantId: scope.tenantId,
      companyId: scope.companyId,
      companyCode: publicCompanyCode,
    );
    final ok = created != null && created['ok'] == true;
    final hasPairing = (created?['pairing_code'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasChallenge = (created?['challenge_id'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasExpires =
        (created?['expires_at'] ?? '').toString().trim().isNotEmpty ||
        (created?['expires_in_seconds'] ?? '').toString().trim().isNotEmpty;
    debugPrint(
      '[DRIVER_LINK_QR][CREATE_RES] ok=$ok has_pairing=$hasPairing has_challenge=$hasChallenge has_expires=$hasExpires',
    );
    if (!ok) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Tijdelijke koppel-QR kon niet worden aangemaakt.',
              en: 'Could not create temporary pairing QR.',
              fr: 'Impossible de créer le QR de liaison temporaire.',
              es: 'No se pudo crear el QR temporal de vinculación.',
            ),
          ),
        ),
      );
      return;
    }
    final companyCode = (created['company_code'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final pairingCode = (created['pairing_code'] ?? '').toString().trim();
    final challengeId = (created['challenge_id'] ?? '').toString().trim();
    final expiresAt = (created['expires_at'] ?? '').toString().trim();
    final expiresInSeconds = created['expires_in_seconds'] is int
        ? created['expires_in_seconds'] as int
        : int.tryParse((created['expires_in_seconds'] ?? '').toString().trim());
    if (companyCode.isEmpty || pairingCode.isEmpty || challengeId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Tijdelijke koppel-QR response is ongeldig.',
              en: 'Temporary pairing QR response is invalid.',
              fr: 'La réponse du QR de liaison temporaire est invalide.',
              es: 'La respuesta del QR temporal de vinculación no es válida.',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    debugPrint('[DRIVER_LINK_QR][SHOW_DIALOG]');
    await _showTemporaryDriverLinkQrDialog(
      context,
      companyCode: companyCode,
      pairingCode: pairingCode,
      challengeId: challengeId,
      driverName: driver.fullName,
      expiresAt: expiresAt,
      expiresInSeconds: expiresInSeconds,
    );
  }

  Future<void> _rotateDriverCode(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final scope = _activeCompanyScopeForDriverDelete(driver);
    if (scope == null) {
      debugPrint('[DRIVER_SCOPE][SKIP] reason=missing_strict_scope');
      _showMissingCompanyScopeSnackbar(context);
      return;
    }
    final rotated = await rotateDriverLoginCode(
      driverId: driver.id,
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    final ok = rotated != null && rotated['ok'] == true;
    if (!ok) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Nieuwe chauffeurcode kon niet worden gegenereerd.',
              en: 'Could not generate a new driver code.',
              fr: 'Impossible de generer un nouveau code chauffeur.',
              es: 'No se pudo generar un nuevo codigo de conductor.',
            ),
          ),
        ),
      );
      return;
    }
    final loginCode = (rotated['login_code'] ?? '').toString().trim();
    final driverCodeLast4 = (rotated['driver_code_last4'] ?? '')
        .toString()
        .trim();
    final loginCodeLast4 = (rotated['login_code_last4'] ?? '')
        .toString()
        .trim();
    final last4 = driverCodeLast4.isNotEmpty
        ? driverCodeLast4
        : (loginCodeLast4.isNotEmpty
              ? loginCodeLast4
              : (loginCode.length >= 4
                    ? loginCode.substring(loginCode.length - 4)
                    : ''));
    updateDriver(
      driver.id,
      driver.copyWith(
        hasLoginCode: true,
        driverCodeLast4: last4.isEmpty ? null : last4,
        loginCodeLast4: last4.isEmpty ? null : last4,
      ),
    );
    unawaited(onRequestMutationRefresh?.call(reason: 'drivers_code_rotate'));
    if (!context.mounted) return;
    await _showGeneratedDriverCodeDialog(
      context,
      loginCode: loginCode,
      driverName: driver.fullName,
      onCreateTemporaryQr: () => _openTemporaryDriverLinkQr(context, driver),
    );
  }

  /// Gate for the "add driver" action (Patch 2.7).
  ///
  /// Mirrors the vehicle add gate: uses the live driver entitlement
  /// (`max_drivers`) from the company subscription profile. The base plan
  /// grants 3 drivers per included vehicle, and each extra vehicle add-on adds
  /// 3 more driver slots. Returns true when another driver may be created;
  /// returns false and shows a limit dialog when the company is at/over its
  /// driver capacity. A transient profile fetch failure falls back to the
  /// base-plan limit and never hard-blocks.
  Future<bool> _confirmDriverAddGate(BuildContext context) async {
    final scopedCount = driversNotifier.value
        .where(
          (d) =>
              !isSeededOrPlaceholderDriver(d) &&
              fleetRecordBelongsToActiveCompanyOrLegacy(d.companyId),
        )
        .length;

    int effectiveMax = (includedVehicleLimit > 0 ? includedVehicleLimit : 1) * 3;
    String limitSource = 'fallback';

    final scopeId = resolveActiveCompanyIdForFleetUi();
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
        if (context.mounted) {
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

    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg,
        title: Text(
          _t(
            nl: 'Chauffeurlimiet bereikt',
            en: 'Driver limit reached',
            fr: 'Limite de chauffeurs atteinte',
            es: 'Límite de conductores alcanzado',
          ),
          style: TextStyle(color: _textPrimary),
        ),
        contentTextStyle: TextStyle(color: _textSecondary, fontSize: 12.8),
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

  Future<void> _openAddDriverFlow(BuildContext context) async {
    debugPrint('[DRIVER_MANAGEMENT][ADD_OPEN]');
    final allowed = await _confirmDriverAddGate(context);
    if (!allowed) return;
    if (!context.mounted) return;
    final created = await showDriverCreatorDialog(
      context,
      companyId: resolveActiveCompanyIdForFleetUi(),
      style: DriverCreatorDialogStyle(
        sheetBg: _dialogBg,
        textPrimary: _textPrimary,
        textSecondary: _textSecondary,
        inputFill: _inputFill,
        inputBorder: _inputBorderColor,
        gold: _gold,
        textOnAccent: _textOnAccent,
      ),
    );
    if (created == null) return;
    debugPrint(
      '[DRIVER_MANAGEMENT][ADD_SAVE] driver=${_shortDriverIdForDiag(created.id)}',
    );
    unawaited(onRequestMutationRefresh?.call(reason: 'drivers_add'));
  }

  Future<void> _deleteDriverFromBackendAndLocal(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final driverId = driver.id.trim();
    final scope = _activeCompanyScopeForDriverDelete(driver);
    if (scope == null) {
      debugPrint('[DRIVER_SCOPE][SKIP] reason=missing_strict_scope');
      _showMissingCompanyScopeSnackbar(context);
      return;
    }
    final maskedDriver = _maskDriverForLog(driverId);
    final maskedCompany = _maskScopeForLog(scope.companyId);
    if (isSeededOrPlaceholderDriver(driver)) {
      removeDriverLocallyAfterBackendDelete(
        driverId,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      unawaited(onRequestMutationRefresh?.call(reason: 'drivers_delete'));
      debugPrint(
        '[DRIVER_DELETE][LOCAL_ONLY] driver=$maskedDriver reason=placeholder company=$maskedCompany',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Chauffeur verwijderd.',
              en: 'Driver removed.',
              fr: 'Chauffeur supprimé.',
              es: 'Conductor eliminado.',
            ),
          ),
        ),
      );
      return;
    }
    debugPrint(
      '[DRIVER_DELETE][REQ] driver=$maskedDriver company=$maskedCompany',
    );

    final endpoint =
        Uri.parse(
          '$kBookingBaseUrl/admin/company/drivers/index/delete',
        ).replace(
          queryParameters: <String, String>{
            'tenant_id': scope.tenantId,
            'company_id': scope.companyId,
          },
        );
    final headers = <String, String>{
      ..._adminHeaders(),
      'Content-Type': 'application/json',
    };
    final payload = <String, dynamic>{
      'tenant_id': scope.tenantId,
      'company_id': scope.companyId,
      'driver_id': driverId,
    };

    try {
      final response = await http
          .post(endpoint, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        bool deleted = false;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            deleted = decoded['deleted'] == true;
          }
        } catch (_) {}
        removeDriverLocallyAfterBackendDelete(
          driverId,
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        unawaited(onRequestMutationRefresh?.call(reason: 'drivers_delete'));
        debugPrint('[DRIVER_DELETE][OK] driver=$maskedDriver deleted=$deleted');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Chauffeur verwijderd.',
                en: 'Driver removed.',
                fr: 'Chauffeur supprimé.',
                es: 'Conductor eliminado.',
              ),
            ),
          ),
        );
        return;
      }

      String reason = 'request_failed';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final text = (decoded['reason'] ?? decoded['error'] ?? '')
              .toString()
              .trim();
          if (text.isNotEmpty) reason = text;
        }
      } catch (_) {}
      debugPrint(
        '[DRIVER_DELETE][ERROR] status=${response.statusCode} reason=$reason driver=$maskedDriver',
      );
    } catch (_) {
      debugPrint(
        '[DRIVER_DELETE][ERROR] status=network reason=exception driver=$maskedDriver',
      );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Chauffeur kon niet verwijderd worden.',
            en: 'Driver could not be removed.',
            fr: 'Impossible de supprimer le chauffeur.',
            es: 'No se pudo eliminar el conductor.',
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDriver(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
        contentTextStyle: TextStyle(color: _textSecondary, fontSize: 13),
        title: Text(
          _t(
            nl: 'Chauffeur verwijderen?',
            en: 'Remove driver?',
            fr: 'Supprimer le chauffeur ?',
            es: '¿Eliminar conductor?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze chauffeur wordt uit de actieve bedrijfslijst verwijderd. Ritgeschiedenis blijft bewaard.',
            en: 'This driver will be removed from the active company list. Ride history will be kept.',
            fr: 'Ce chauffeur sera supprimé de la liste active de l’entreprise. L’historique des courses sera conservé.',
            es: 'Este conductor se eliminará de la lista activa de la empresa. El historial de viajes se conservará.',
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
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
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
    if (!context.mounted) return;
    await _deleteDriverFromBackendAndLocal(context, driver);
  }

  String _driverCardInitials(DriverProfile driver) {
    final raw = _displayDriverName(driver.fullName).trim();
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

  String? _driverCardPhotoPath(DriverProfile driver) {
    if (kIsWeb) return null;
    final path = driver.profilePhotoPath?.trim() ?? '';
    if (path.isEmpty) return null;
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  String? _driverCardNetworkPhotoUrl(DriverProfile driver) {
    bool isHttpUrl(String value) {
      final lower = value.trim().toLowerCase();
      return lower.startsWith('https://') || lower.startsWith('http://');
    }

    bool isPreferredFluxidiMediaUrl(String value) {
      final lower = value.trim().toLowerCase();
      return lower.contains('/public/media/') ||
          lower.contains('public-media/') ||
          lower.contains('/public-media/');
    }

    final profilePhotoPath = driver.profilePhotoPath?.trim() ?? '';
    final publicPortraitUrl = driver.publicPortraitUrl?.trim() ?? '';
    final ordered = <String>[];

    void addIfValid(String value) {
      final candidate = value.trim();
      if (!isHttpUrl(candidate)) return;
      if (ordered.contains(candidate)) return;
      ordered.add(candidate);
    }

    // Prefer backend/public portrait URL first.
    if (isPreferredFluxidiMediaUrl(publicPortraitUrl)) {
      addIfValid(publicPortraitUrl);
    }
    // Then any Fluxidi media alias carried in legacy local fields.
    if (isPreferredFluxidiMediaUrl(profilePhotoPath)) {
      addIfValid(profilePhotoPath);
    }
    // Then remote portrait URL, then any other remote avatar URL.
    addIfValid(publicPortraitUrl);
    addIfValid(profilePhotoPath);
    return ordered.isEmpty ? null : ordered.first;
  }

  void _queuePrecacheDriverAvatars(
    BuildContext context,
    List<DriverProfile> drivers,
  ) {
    final urls = <String>[];
    for (final driver in drivers) {
      final url = _driverCardNetworkPhotoUrl(driver);
      if (url == null || url.isEmpty) continue;
      if (_avatarPrecacheQueuedUrls.add(url)) {
        urls.add(url);
      }
    }
    if (urls.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      for (final url in urls) {
        precacheImage(NetworkImage(url), context).catchError((_) {});
      }
    });
  }

  Widget _driverCardInitialsFallback(DriverProfile driver) {
    return Center(
      child: Text(
        _driverCardInitials(driver),
        style: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _driverCardNetworkAvatarImage(
    DriverProfile driver,
    String networkUrl,
  ) {
    final initialsFallback = _driverCardInitialsFallback(driver);
    return Image.network(
      networkUrl,
      fit: BoxFit.cover,
      cacheWidth: 160,
      cacheHeight: 160,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return initialsFallback;
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return initialsFallback;
      },
      errorBuilder: (_, __, ___) => initialsFallback,
    );
  }

  Widget _driverCardLocalAvatarImage(DriverProfile driver, String photoPath) {
    final initialsFallback = _driverCardInitialsFallback(driver);
    return Image.file(
      File(photoPath),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => initialsFallback,
    );
  }

  Widget _driverCardAvatar(DriverProfile driver, {double size = 52}) {
    final photoPath = _driverCardPhotoPath(driver);
    final networkUrl = _driverCardNetworkPhotoUrl(driver);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _subPanelBg,
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withOpacity(0.5)),
      ),
      child: ClipOval(
        child: networkUrl != null
            ? _driverCardNetworkAvatarImage(driver, networkUrl)
            : (photoPath != null
                  ? _driverCardLocalAvatarImage(driver, photoPath)
                  : _driverCardInitialsFallback(driver)),
      ),
    );
  }

  Future<void> _confirmDeleteDocument(
    BuildContext context,
    DriverDocument doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
        contentTextStyle: TextStyle(color: _textSecondary, fontSize: 13),
        title: Text(
          _t(
            nl: 'Document verwijderen?',
            en: 'Delete document?',
            fr: 'Supprimer le document ?',
            es: '¿Eliminar documento?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze actie kan niet ongedaan worden gemaakt.',
            en: 'This action cannot be undone.',
            fr: 'Cette action est irreversible.',
            es: 'Esta acción no se puede deshacer.',
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
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(
              _t(
                nl: 'Verwijderen',
                en: 'Delete',
                fr: 'Supprimer',
                es: 'Eliminar',
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      bool hasBackendSyncState(DriverDocument d) {
        return d.storageState.trim().isNotEmpty ||
            d.backendFileName.trim().isNotEmpty ||
            d.backendContentType.trim().isNotEmpty ||
            d.backendSizeBytes > 0 ||
            d.backendSyncedAt.trim().isNotEmpty ||
            d.backendPendingUpload ||
            d.backendPendingDelete ||
            d.backendSyncError.trim().isNotEmpty;
      }

      final companySessionToken =
          (activeCompanySessionNotifier.value?.companySessionToken ?? '')
              .trim();
      final tenantId = doc.tenantId.trim();
      final companyId = doc.companyId.trim();
      final driverId = doc.driverId.trim();
      final documentId = doc.documentId.trim();
      final hasBackendDeleteScope =
          companySessionToken.isNotEmpty &&
          tenantId.isNotEmpty &&
          companyId.isNotEmpty &&
          driverId.isNotEmpty &&
          documentId.isNotEmpty;
      if (!hasBackendDeleteScope) {
        debugPrint(
          '[DRIVER_DOCS][UI_DELETE_BACKEND_SKIP] reason=missing_token_or_scope',
        );
        if (hasBackendSyncState(doc)) {
          debugPrint(
            '[DRIVER_DOCS][UI_DELETE_BACKEND_PENDING] reason=missing_scope_with_backend_state',
          );
          return;
        }
        debugPrint(
          '[DRIVER_DOCS][UI_DELETE_LOCAL_ONLY] reason=no_backend_state',
        );
        await DriverDocumentsStore.instance.deleteDocument(doc.documentId);
        unawaited(
          onRequestMutationRefresh?.call(reason: 'drivers_doc_delete_local'),
        );
        return;
      }
      debugPrint('[DRIVER_DOCS][UI_DELETE_BACKEND_START] requested=true');
      final removed = await DriverDocumentsStore.instance
          .deleteDocumentInBackendThenLocal(
            bookingBaseUrl: kBookingBaseUrl,
            companySessionToken: companySessionToken,
            tenantId: tenantId,
            companyId: companyId,
            driverId: driverId,
            documentId: documentId,
          );
      if (!removed) {
        debugPrint(
          '[DRIVER_DOCS][UI_DELETE_BACKEND_PENDING] reason=backend_delete_failed',
        );
      }
      debugPrint('[DRIVER_DOCS][UI_DELETE_BACKEND_DONE] ok=$removed');
      unawaited(
        onRequestAdminDriverDocumentsRefresh?.call(
          reason: 'drivers_doc_delete',
          onlyDriverId: driverId,
          force: true,
        ),
      );
      unawaited(onRequestMutationRefresh?.call(reason: 'drivers_doc_delete'));
    }
  }

  Future<void> _openDocumentEditor(
    BuildContext context,
    DriverProfile driver, {
    DriverDocument? existing,
  }) async {
    await showDriverDocumentEditorSheet(
      context,
      driver: driver,
      existing: existing,
      style: DriverDocumentSheetStyle(
        sheetBg: _dialogBg,
        textPrimary: _textPrimary,
        textSecondary: _textSecondary,
        textMuted: _textMuted,
        inputFill: _inputFill,
        inputBorder: _inputBorderColor,
        dropdownBg: _isDark ? _panelBg : _subPanelBg,
        isDark: _isDark,
        // Premium gold in dark themes; high-contrast dark text in light theme
        // (Clean Professional). Both keep the icon + label readable on the
        // pale sheet surface in light theme without losing the gold accent
        // in Night Gold / Corporate Blue.
        attachmentButtonForeground: _isDark ? _gold : _textPrimary,
      ),
    );
    final refreshReason = existing == null
        ? 'drivers_doc_add_or_edit'
        : 'drivers_doc_edit';
    unawaited(
      onRequestAdminDriverDocumentsRefresh?.call(
        reason: refreshReason,
        onlyDriverId: driver.id,
        force: true,
      ),
    );
    unawaited(onRequestMutationRefresh?.call(reason: refreshReason));
    // The sheet sync runs async after close; do one delayed pull too.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1200)).then((_) {
        return onRequestAdminDriverDocumentsRefresh?.call(
          reason: '${refreshReason}_delayed',
          onlyDriverId: driver.id,
          force: true,
        );
      }),
    );
  }

  Widget _driverDocumentTile(
    BuildContext context,
    DriverProfile driver,
    DriverDocument doc,
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
      final localPath = d.filePath.trim();
      var hasLocalArtifact = false;
      if (!kIsWeb && localPath.isNotEmpty) {
        try {
          hasLocalArtifact = File(localPath).existsSync();
        } catch (_) {
          hasLocalArtifact = false;
        }
      }
      final hasBackendArtifact =
          d.storageState.trim().toLowerCase() == 'stored' &&
          d.backendFileName.trim().isNotEmpty &&
          d.backendContentType.trim().isNotEmpty &&
          d.backendSizeBytes > 0;
      if (d.backendPendingDelete) {
        return _t(
          nl: 'Verwijderen in wachtrij',
          en: 'Delete pending',
          fr: 'Suppression en attente',
          es: 'Eliminacion pendiente',
        );
      }
      if (d.backendPendingUpload) {
        return _t(
          nl: 'Synchronisatie in wachtrij',
          en: 'Sync pending',
          fr: 'Synchronisation en attente',
          es: 'Sincronizacion pendiente',
        );
      }
      if (d.backendSyncError.trim().isNotEmpty) {
        return _t(
          nl: 'Synchronisatie opnieuw proberen',
          en: 'Sync needs retry',
          fr: 'Nouvelle tentative de synchro requise',
          es: 'Sincronizacion requiere reintento',
        );
      }
      if (hasBackendArtifact) {
        return _t(
          nl: 'Backend document beschikbaar',
          en: 'Backend document available',
          fr: 'Document backend disponible',
          es: 'Documento backend disponible',
        );
      }
      if (hasLocalArtifact) {
        return _t(
          nl: 'Nog niet gesynchroniseerd',
          en: 'Not synchronized yet',
          fr: 'Pas encore synchronisé',
          es: 'Aún no sincronizado',
        );
      }
      if (isBackendSynced(d) || hasBackendMetadata(d)) {
        return _t(
          nl: 'Opnieuw uploaden vereist',
          en: 'Re-upload required',
          fr: 'Retéléversement requis',
          es: 'Se requiere volver a subir',
        );
      }
      return _t(
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
    final statusLabel = driverDocumentStatusLabel(doc.status, _lang);
    final expiredVisual =
        doc.isExpiredByDate || doc.status == DriverDocumentStatuses.expired;
    final hasUsableArtifact = documentHasUsableAttachment(doc);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: expiredVisual
              ? Colors.orange.withOpacity(0.62)
              : _gold.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.title.trim().isNotEmpty)
            Text(
              doc.title,
              style: TextStyle(fontSize: 12, color: _textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: $statusLabel'
            '${doc.isExpiredByDate && doc.status != DriverDocumentStatuses.expired ? ' (${_t(nl: 'datum verlopen', en: 'date expired', fr: 'date expiree', es: 'fecha caducada')})' : ''}',
            style: TextStyle(
              color: expiredVisual ? Colors.orangeAccent : _textSecondary,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.expiryDate.trim().isNotEmpty)
            _line(
              _t(
                nl: 'Vervaldatum',
                en: 'Expiry',
                fr: 'Expiration',
                es: 'Caducidad',
              ),
              doc.expiryDate,
              icon: Icons.event_busy_outlined,
            ),
          if (doc.filePath.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            driverDocAttachmentPreview(doc.filePath, _lang),
          ],
          const SizedBox(height: 4),
          Text(
            storageLabel(doc),
            style: TextStyle(fontSize: 11, color: _textMuted.withOpacity(0.8)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!hasUsableArtifact) ...[
            const SizedBox(height: 4),
            Text(
              _t(
                nl: 'Bijlage ontbreekt - upload opnieuw of synchroniseer documentbestand.',
                en: 'Attachment missing - re-upload or synchronize the document file.',
                fr: 'Pièce jointe manquante - retéléversez ou synchronisez le fichier.',
                es: 'Falta el adjunto - vuelve a subir o sincroniza el archivo.',
              ),
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (doc.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_t(nl: 'Notities', en: 'Notes', fr: 'Notes', es: 'Notas')}: ${doc.notes}',
              style: TextStyle(
                fontSize: 11,
                color: _textMuted.withOpacity(0.8),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _gold.withOpacity(0.96),
                  side: BorderSide(color: _gold.withOpacity(0.40)),
                  backgroundColor: _subPanelBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: () =>
                    _openDriverDocumentArtifact(context, driver, doc),
                child: Text(
                  _t(nl: 'Openen', en: 'Open', fr: 'Ouvrir', es: 'Abrir'),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _textPrimary,
                  side: BorderSide(
                    color: _border.withOpacity(_isDark ? 0.45 : 0.92),
                  ),
                  backgroundColor: _panelBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: () =>
                    _openDocumentEditor(context, driver, existing: doc),
                child: Text(
                  _t(nl: 'Bewerken', en: 'Edit', fr: 'Modifier', es: 'Editar'),
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(color: Colors.redAccent.withOpacity(0.45)),
                  backgroundColor: const Color(0xFF2A1518),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: () => _confirmDeleteDocument(context, doc),
                child: Text(
                  _t(
                    nl: 'Verwijderen',
                    en: 'Delete',
                    fr: 'Supprimer',
                    es: 'Eliminar',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime? _parseExpiryDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final normalized = text.length >= 10 ? text.substring(0, 10) : text;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _isExpiryWithinDays(String raw, {int days = 30}) {
    final expiry = _parseExpiryDate(raw);
    if (expiry == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final delta = expiry.difference(today).inDays;
    return delta >= 0 && delta <= days;
  }

  Widget _summaryMetric({
    required IconData icon,
    required Color accent,
    required String label,
    required String value,
    String? subtitle,
    bool compact = false,
    // Phone-landscape KPI cards need to stay short, with smaller text and
    // numbers that don't dominate the row. `dense` only takes effect when
    // `compact == true` (tablet landscape compact path is unaffected).
    bool dense = false,
  }) {
    final bool denseCompact = compact && dense;
    final decoration = compact
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isDark
                  ? const [Color(0xFF090909), Color(0xFF101010)]
                  : [_subPanelBg, _panelBg],
            ),
            borderRadius: BorderRadius.circular(denseCompact ? 12 : 14),
            border: Border.all(
              color: _border.withOpacity(_isDark ? 0.42 : 0.92),
            ),
          )
        : BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _border.withOpacity(_isDark ? 0.34 : 0.9),
            ),
          );
    final double iconBoxSize = denseCompact
        ? 34
        : compact
        ? 56
        : 28;
    final double iconGlyphSize = denseCompact
        ? 18
        : compact
        ? 28
        : 15;
    final double horizontalPadding = denseCompact
        ? 10
        : compact
        ? 14
        : 10;
    final double verticalPadding = denseCompact
        ? 8
        : compact
        ? 12
        : 8;
    final double labelFontSize = denseCompact
        ? 11.4
        : compact
        ? 14.8
        : 10.8;
    final double valueFontSize = denseCompact
        ? 18.5
        : compact
        ? 29
        : 16;
    final double labelValueGap = denseCompact
        ? 1
        : compact
        ? 3
        : 2;
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        verticalPadding,
        horizontalPadding,
        verticalPadding,
      ),
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.15),
              border: Border.all(color: accent.withOpacity(0.52)),
            ),
            child: Icon(icon, size: iconGlyphSize, color: accent),
          ),
          SizedBox(
            width: denseCompact
                ? 8
                : compact
                ? 12
                : 8,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textMuted.withOpacity(0.9),
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: labelValueGap),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: valueFontSize,
                  ),
                ),
                if (compact &&
                    !denseCompact &&
                    subtitle != null &&
                    subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textMuted.withOpacity(0.88),
                      fontSize: 12.8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _landscapeDriverDetailLine({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _gold.withOpacity(0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: _textMuted.withOpacity(0.9),
                  fontSize: 13.6,
                  height: 1.26,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: _textMuted.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: shown,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLandscapeDriverDocumentsSheet(
    BuildContext context,
    DriverProfile driver,
    List<DriverDocument> docs,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _pageBg,
      builder: (sheetContext) {
        final maxHeight = math.min(
          MediaQuery.of(sheetContext).size.height * 0.76,
          640.0,
        );
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Documenten',
                      en: 'Documents',
                      fr: 'Documents',
                      es: 'Documentos',
                    ),
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: docs.isEmpty
                        ? Center(
                            child: Text(
                              _t(
                                nl: 'Nog geen documenten.',
                                en: 'No documents.',
                                fr: 'Aucun document.',
                                es: 'Sin documentos.',
                              ),
                              style: TextStyle(
                                color: _textMuted.withOpacity(0.8),
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final doc in docs)
                                _driverDocumentTile(sheetContext, driver, doc),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _openDocumentEditor(context, driver);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold.withOpacity(0.96),
                          side: BorderSide(color: _border.withOpacity(0.55)),
                          backgroundColor: _panelBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          _t(
                            nl: 'Document toevoegen',
                            en: 'Add document',
                            fr: 'Ajouter',
                            es: 'Agregar',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textMuted.withOpacity(0.92),
                          side: BorderSide(color: _border.withOpacity(0.55)),
                          backgroundColor: _panelBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.close, size: 16),
                        label: Text(
                          _t(
                            nl: 'Sluiten',
                            en: 'Close',
                            fr: 'Fermer',
                            es: 'Cerrar',
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
      },
    );
  }

  Widget _driverLandscapeReferenceCard(
    BuildContext context, {
    required DriverProfile driver,
    required String accountStatus,
    required String? operationalAvailabilityLabel,
    required List<DriverDocument> docs,
    required DriverDocumentComplianceSummary compliance,
    required bool refreshFailed,
  }) {
    final docsAllGood =
        compliance.hasAllRequiredDocuments &&
        !compliance.needsAction &&
        !refreshFailed;
    final statusIcon = docsAllGood
        ? Icons.check_circle_outline_rounded
        : Icons.warning_amber_rounded;
    final statusIconColor = docsAllGood
        ? Colors.greenAccent
        : Colors.orangeAccent;
    final docsStatus = refreshFailed
        ? _t(
            nl: 'Documentsynchronisatie mislukt.',
            en: 'Document sync failed.',
            fr: 'Échec de la synchronisation des documents.',
            es: 'La sincronización de documentos falló.',
          )
        : docsAllGood
        ? _t(
            nl: 'Alle vereiste documenten zijn in orde.',
            en: 'All required documents are in order.',
            fr: 'Tous les documents requis sont en ordre.',
            es: 'Todos los documentos requeridos están en orden.',
          )
        : (compliance.uploadedRequiredCount == 0
              ? _t(
                  nl: 'Vereiste documenten ontbreken.',
                  en: 'Required documents are missing.',
                  fr: 'Les documents requis sont manquants.',
                  es: 'Faltan documentos requeridos.',
                )
              : _docsInOrderLabel(compliance));
    final missingCount = compliance.missingRequiredTypeIds.length;
    final attachmentMissingCount =
        compliance.missingAttachmentRequiredTypeIds.length;
    final docsSubStatus = refreshFailed
        ? _t(
            nl: 'Controleer of herstel de bedrijfssessie en vernieuw opnieuw.',
            en: 'Check or recover the company session and refresh again.',
            fr: 'Vérifiez ou récupérez la session entreprise puis actualisez.',
            es: 'Verifica o recupera la sesión de empresa y actualiza de nuevo.',
          )
        : docsAllGood
        ? _t(
            nl: 'Geen actie vereist',
            en: 'No action required',
            fr: 'Aucune action requise',
            es: 'No se requiere acción',
          )
        : (attachmentMissingCount > 0
              ? _attachmentMissingLabel()
              : (missingCount > 0
                    ? _missingRequiredLabel(missingCount)
                    : _documentsNeedsActionLabel()));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isDark
              ? const [Color(0xFF07080C), Color(0xFF101010)]
              : [_subPanelBg, _panelBg],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withOpacity(_isDark ? 0.42 : 0.92)),
      ),
      child: SizedBox(
        // Extra height reserved for the Rapporten action that opens the
        // existing DriverKpiPage for this chauffeur.
        height: 310,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 48,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _driverCardAvatar(driver, size: 88),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driver.fullName.trim().isEmpty
                                    ? _t(
                                        nl: 'Naamloze chauffeur',
                                        en: 'Unnamed driver',
                                        fr: 'Chauffeur sans nom',
                                        es: 'Conductor sin nombre',
                                      )
                                    : _displayDriverName(driver.fullName),
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _driverStatusChipBg(driver.isActive),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _driverStatusChipBorder(
                                      driver.isActive,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  accountStatus,
                                  style: TextStyle(
                                    color: _driverStatusChipText(
                                      driver.isActive,
                                    ),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.4,
                                  ),
                                ),
                              ),
                              if ((operationalAvailabilityLabel ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.orangeAccent.withOpacity(
                                        0.44,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    operationalAvailabilityLabel!,
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.2,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _landscapeDriverDetailLine(
                      icon: Icons.business_outlined,
                      label: _t(
                        nl: 'Bedrijfscode',
                        en: 'Company ID',
                        fr: 'Code entreprise',
                        es: 'Código de empresa',
                      ),
                      value: _displayCompanyLoginCode(driver),
                    ),
                    _landscapeDriverDetailLine(
                      icon: Icons.badge_outlined,
                      label: _t(
                        nl: 'Chauffeurcode',
                        en: 'Driver code',
                        fr: 'Code chauffeur',
                        es: 'Código de conductor',
                      ),
                      value: _driverCodeStatusLabel(driver),
                    ),
                    _landscapeDriverDetailLine(
                      icon: Icons.phone_outlined,
                      label: _t(
                        nl: 'Telefoon',
                        en: 'Phone',
                        fr: 'Téléphone',
                        es: 'Teléfono',
                      ),
                      value: driver.phone,
                    ),
                    _landscapeDriverDetailLine(
                      icon: Icons.credit_card_outlined,
                      label: _t(
                        nl: 'Chauffeurskaartnummer',
                        en: 'Driver card number',
                        fr: 'N° carte chauffeur',
                        es: 'N.º tarjeta de conductor',
                      ),
                      value: driver.taxiDriverCardNumber,
                    ),
                    _landscapeDriverDetailLine(
                      icon: Icons.event_note_outlined,
                      label: _t(
                        nl: 'Vervaldatum chauffeurskaart',
                        en: 'Driver card expiry',
                        fr: 'Expiration carte chauffeur',
                        es: 'Caducidad tarjeta de conductor',
                      ),
                      value: driver.taxiDriverCardExpiry,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              color: _border.withOpacity(_isDark ? 0.18 : 0.55),
            ),
            Expanded(
              flex: 27,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        nl: 'Documenten',
                        en: 'Documents',
                        fr: 'Documents',
                        es: 'Documentos',
                      ),
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: docsAllGood
                            ? Colors.green.withOpacity(0.15)
                            : Colors.orange.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: docsAllGood
                              ? Colors.greenAccent.withOpacity(0.36)
                              : Colors.orangeAccent.withOpacity(0.36),
                        ),
                      ),
                      child: Text(
                        _docsInOrderLabel(compliance),
                        style: TextStyle(
                          color: docsAllGood
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: statusIconColor.withOpacity(0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: statusIconColor.withOpacity(0.42),
                            ),
                          ),
                          child: Icon(
                            statusIcon,
                            size: 34,
                            color: statusIconColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                docsStatus,
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.2,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                docsSubStatus,
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 13,
                                  height: 1.22,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openLandscapeDriverDocumentsSheet(
                          context,
                          driver,
                          docs,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          foregroundColor: _gold.withOpacity(0.98),
                          side: BorderSide(
                            color: _border.withOpacity(_isDark ? 0.45 : 0.92),
                          ),
                          backgroundColor: _subPanelBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.folder_open_outlined, size: 20),
                        label: Text(
                          _t(
                            nl: 'Controleer documenten',
                            en: 'Check documents',
                            fr: 'Vérifier les documents',
                            es: 'Revisar documentos',
                          ),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              color: _border.withOpacity(_isDark ? 0.18 : 0.55),
            ),
            Expanded(
              flex: 25,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _rotateDriverCode(context, driver),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: _gold.withOpacity(0.98),
                        side: BorderSide(color: _gold.withOpacity(0.34)),
                        backgroundColor: _subPanelBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.key_outlined, size: 20),
                      label: Text(
                        _t(
                          nl: 'Nieuwe chauffeurcode genereren',
                          en: 'Generate new driver code',
                          fr: 'Generer un nouveau code chauffeur',
                          es: 'Generar nuevo codigo de conductor',
                        ),
                        style: const TextStyle(
                          fontSize: 15.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openTemporaryDriverLinkQr(context, driver),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: _gold.withOpacity(0.98),
                        side: BorderSide(color: _gold.withOpacity(0.34)),
                        backgroundColor: _subPanelBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_2_outlined, size: 20),
                      label: Text(
                        _t(
                          nl: 'Tijdelijke koppel-QR',
                          en: 'Temporary pairing QR',
                          fr: 'QR de liaison temporaire',
                          es: 'QR temporal de vinculación',
                        ),
                        style: const TextStyle(
                          fontSize: 15.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_openCompanyDriverKpiPage(context, driver)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: _gold.withOpacity(0.98),
                        side: BorderSide(color: _gold.withOpacity(0.34)),
                        backgroundColor: _subPanelBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.insights_outlined, size: 20),
                      label: Text(
                        _t(
                          nl: 'Rapporten',
                          en: 'Reports',
                          fr: 'Rapports',
                          es: 'Informes',
                        ),
                        style: const TextStyle(
                          fontSize: 15.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openEditDriverDialog(context, driver),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: _textPrimary,
                        side: BorderSide(
                          color: _border.withOpacity(_isDark ? 0.45 : 0.92),
                        ),
                        backgroundColor: _subPanelBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: Text(
                        _t(
                          nl: 'Bewerken',
                          en: 'Edit driver',
                          fr: 'Modifier',
                          es: 'Editar',
                        ),
                        style: const TextStyle(
                          fontSize: 15.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _confirmDeleteDriver(context, driver),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(
                          color: Colors.redAccent.withOpacity(0.45),
                        ),
                        backgroundColor: const Color(0xFF2A1518),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: Text(
                        _t(
                          nl: 'Verwijderen',
                          en: 'Delete driver',
                          fr: 'Supprimer',
                          es: 'Eliminar',
                        ),
                        style: const TextStyle(
                          fontSize: 15.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _driverOperationalAvailabilityLabel(DriverProfile driver) {
    if (!driver.isActive) {
      return _t(
        nl: 'Niet beschikbaar',
        en: 'Not available',
        fr: 'Indisponible',
        es: 'No disponible',
      );
    }
    final availability = normalizeDriverAvailabilityState(
      driver.availabilityStatus,
      fallback: 'available',
    );
    switch (availability) {
      case 'paused':
        return _t(nl: 'Pauze', en: 'Paused', fr: 'Pause', es: 'Pausa');
      case 'busy':
        return _t(nl: 'Bezet', en: 'Busy', fr: 'Occupé', es: 'Ocupado');
      case 'offline':
        return _t(
          nl: 'Offline',
          en: 'Offline',
          fr: 'Hors ligne',
          es: 'Sin conexión',
        );
      default:
        return _t(
          nl: 'Beschikbaar',
          en: 'Available',
          fr: 'Disponible',
          es: 'Disponible',
        );
    }
  }

  Color _availabilityChipColor(DriverProfile driver) {
    if (!driver.isActive) {
      return _isCleanProfessional
          ? const Color(0xFF455468)
          : _textMuted.withOpacity(0.9);
    }
    final availability = normalizeDriverAvailabilityState(
      driver.availabilityStatus,
      fallback: 'available',
    );
    switch (availability) {
      case 'paused':
        return _isCleanProfessional
            ? const Color(0xFF9A5A00)
            : Colors.orangeAccent;
      case 'busy':
        return _isCleanProfessional
            ? const Color(0xFFA6430A)
            : Colors.deepOrangeAccent;
      case 'offline':
        return _isCleanProfessional
            ? const Color(0xFF58677A)
            : Colors.blueGrey.shade200;
      default:
        return _isCleanProfessional ? const Color(0xFF1E7A4B) : _success;
    }
  }

  Color _driverStatusChipBg(bool isActive) {
    if (isActive) {
      return _isCleanProfessional
          ? const Color(0xFFE2F3E8)
          : Colors.green.withOpacity(0.16);
    }
    if (_isCleanProfessional) return const Color(0xFFE8EEF5);
    if (_isCorporateBlue) return const Color(0xFF162538);
    return Colors.white.withOpacity(0.06);
  }

  Color _driverStatusChipBorder(bool isActive) {
    if (isActive) {
      return _isCleanProfessional
          ? const Color(0xFF90C8A7)
          : Colors.greenAccent.withOpacity(0.44);
    }
    if (_isCleanProfessional) return const Color(0xFFB7C4D3);
    if (_isCorporateBlue) return _border.withOpacity(0.8);
    return Colors.white24;
  }

  Color _driverStatusChipText(bool isActive) {
    if (isActive) {
      return _isCleanProfessional
          ? const Color(0xFF1A6E44)
          : Colors.greenAccent;
    }
    if (_isCleanProfessional) return const Color(0xFF34465A);
    return _textMuted.withOpacity(0.9);
  }

  String _driverVehicleSummary(
    DriverProfile driver,
    List<VehicleProfile> vehicles,
  ) {
    final assigned = _driverAssignedVehicle(driver, vehicles);
    if (assigned == null) {
      return _t(
        nl: 'Geen voertuig toegewezen',
        en: 'No vehicle assigned',
        fr: 'Aucun véhicule assigné',
        es: 'Sin vehículo asignado',
      );
    }
    final name = assigned.vehicleName.trim().isNotEmpty
        ? assigned.vehicleName.trim()
        : assigned.brandModel.trim();
    final plate = assigned.licensePlate.trim();
    if (name.isEmpty && plate.isEmpty) {
      return _t(
        nl: 'Voertuig toegewezen',
        en: 'Vehicle assigned',
        fr: 'Véhicule assigné',
        es: 'Vehículo asignado',
      );
    }
    if (name.isNotEmpty && plate.isNotEmpty) return '$name · $plate';
    return name.isNotEmpty ? name : plate;
  }

  VehicleProfile? _driverAssignedVehicle(
    DriverProfile driver,
    List<VehicleProfile> vehicles,
  ) {
    for (final vehicle in vehicles) {
      if (!fleetRecordBelongsToActiveCompanyOrLegacy(vehicle.companyId)) {
        continue;
      }
      if ((vehicle.driverId ?? '').trim() == driver.id.trim()) {
        return vehicle;
      }
    }
    return null;
  }

  Widget _portraitKpiChip({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.16),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withOpacity(0.50)),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary.withOpacity(0.92),
                    fontSize: 13.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    color: accent,
                    fontSize: 20.0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPortraitDriverManageSheet(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final isCleanProfessional = _isCleanProfessional;
    final helperPanelIconColor = isCleanProfessional
        ? _textSecondary
        : _gold.withOpacity(0.98);
    final helperPanelTextColor = isCleanProfessional
        ? _textSecondary
        : _textMuted.withOpacity(0.92);
    final actionIconColor = isCleanProfessional
        ? _textPrimary.withOpacity(0.9)
        : _textSecondary.withOpacity(0.96);
    final generateCodeIconColor = isCleanProfessional
        ? _gold.withOpacity(0.92)
        : _gold.withOpacity(0.98);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayDriverName(driver.fullName),
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _subPanelBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _border.withOpacity(_isDark ? 0.42 : 0.92),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.screen_rotation_alt_outlined,
                      color: helperPanelIconColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t(
                          nl: 'Voor volledig beheer draai je tablet naar landscape.',
                          en: 'For full management, rotate your tablet to landscape.',
                          fr: 'Pour la gestion complète, tournez la tablette en mode paysage.',
                          es: 'Para la gestión completa, gira la tablet a horizontal.',
                        ),
                        style: TextStyle(
                          color: helperPanelTextColor,
                          fontSize: 11.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined, color: actionIconColor),
                title: Text(
                  _t(nl: 'Beheren', en: 'Manage', fr: 'Gérer', es: 'Gestionar'),
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openEditDriverDialog(context, driver);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.description_outlined,
                  color: actionIconColor,
                ),
                title: Text(
                  _t(
                    nl: 'Documenten',
                    en: 'Documents',
                    fr: 'Documents',
                    es: 'Documentos',
                  ),
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openDocumentEditor(context, driver);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.key_outlined, color: generateCodeIconColor),
                title: Text(
                  _t(
                    nl: 'Code genereren',
                    en: 'Generate code',
                    fr: 'Générer un code',
                    es: 'Generar código',
                  ),
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openPortraitDriverCodeActions(context, driver);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.insights_outlined, color: actionIconColor),
                title: Text(
                  _t(
                    nl: 'Rapporten',
                    en: 'Reports',
                    fr: 'Rapports',
                    es: 'Informes',
                  ),
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_openCompanyDriverKpiPage(context, driver));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPortraitDriverCodeActions(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final isCleanProfessional = _isCleanProfessional;
    final titleTextColor = isCleanProfessional ? _textPrimary : Colors.white;
    final helperTextColor = isCleanProfessional
        ? _textSecondary
        : Colors.white.withOpacity(0.74);
    final actionTitleColor = isCleanProfessional ? _textPrimary : Colors.white;
    final actionIconColor = isCleanProfessional
        ? _gold.withOpacity(0.9)
        : _gold.withOpacity(0.98);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Chauffeur koppelen',
                  en: 'Pair driver',
                  fr: 'Associer le chauffeur',
                  es: 'Vincular conductor',
                ),
                style: TextStyle(
                  color: titleTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  nl: 'Gebruik de tijdelijke QR voor veilig éénmalig koppelen. De chauffeurcode is alleen manuele fallback.',
                  en: 'Use the temporary QR for secure one-time pairing. Driver code is manual fallback only.',
                  fr: 'Utilisez le QR temporaire pour un couplage sécurisé à usage unique. Le code chauffeur reste un fallback manuel.',
                  es: 'Usa el QR temporal para una vinculación segura de un solo uso. El código de conductor es solo respaldo manual.',
                ),
                style: TextStyle(
                  color: helperTextColor,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.qr_code_2_outlined, color: actionIconColor),
                title: Text(
                  _t(
                    nl: 'Tijdelijke koppel-QR',
                    en: 'Temporary pairing QR',
                    fr: 'QR de liaison temporaire',
                    es: 'QR temporal de vinculación',
                  ),
                  style: TextStyle(color: actionTitleColor),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openTemporaryDriverLinkQr(context, driver);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.key_outlined, color: actionIconColor),
                title: Text(
                  _t(
                    nl: 'Nieuwe chauffeurcode genereren',
                    en: 'Generate new driver code',
                    fr: 'Generer un nouveau code chauffeur',
                    es: 'Generar nuevo codigo de conductor',
                  ),
                  style: TextStyle(color: actionTitleColor),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _rotateDriverCode(context, driver);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPortraitDriverCodePicker(
    BuildContext context,
    List<DriverProfile> visible,
  ) async {
    if (visible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Geen chauffeurs beschikbaar.',
              en: 'No drivers available.',
              fr: 'Aucun chauffeur disponible.',
              es: 'No hay conductores disponibles.',
            ),
          ),
        ),
      );
      return;
    }
    final isCleanProfessional = _isCleanProfessional;
    final titleTextColor = isCleanProfessional ? _textPrimary : Colors.white;
    final itemTextColor = isCleanProfessional ? _textPrimary : Colors.white;
    final subtitleTextColor = isCleanProfessional
        ? _textSecondary
        : Colors.white.withOpacity(0.62);
    final trailingColor = isCleanProfessional
        ? _textSecondary.withOpacity(0.92)
        : _textMuted.withOpacity(0.72);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Kies chauffeur voor code',
                  en: 'Select driver for code',
                  fr: 'Sélectionnez le chauffeur',
                  es: 'Selecciona conductor',
                ),
                style: TextStyle(
                  color: titleTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...visible.map(
                (driver) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _displayDriverName(driver.fullName),
                    style: TextStyle(color: itemTextColor),
                  ),
                  subtitle: Text(
                    _driverCodeStatusLabel(driver),
                    style: TextStyle(color: subtitleTextColor),
                  ),
                  trailing: Icon(Icons.chevron_right, color: trailingColor),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openPortraitDriverCodeActions(context, driver);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the existing [DriverKpiPage] for [driver] under active company scope.
  Future<void> _openCompanyDriverKpiPage(
    BuildContext context,
    DriverProfile driver,
  ) async {
    final driverId = driver.id.trim();
    if (driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Chauffeur-id ontbreekt.',
              en: 'Driver id is missing.',
              fr: 'Identifiant chauffeur manquant.',
              es: 'Falta el id del conductor.',
            ),
          ),
        ),
      );
      return;
    }
    final scope = _activeCompanyScopeForDriverDelete(driver);
    if (scope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Bedrijfscontext ontbreekt voor rapporten.',
              en: 'Company scope is missing for reports.',
              fr: 'Contexte entreprise manquant pour les rapports.',
              es: 'Falta el alcance de empresa para informes.',
            ),
          ),
        ),
      );
      return;
    }
    final args = driverKpiRouteArgsForCompanyDriver(
      driverId: driverId,
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    final scopeSource =
        (activeCompanySessionNotifier.value?.companyId.trim() ?? '').isNotEmpty
        ? 'company_session'
        : 'company_profile';
    if (!context.mounted) return;
    await pushDriverKpiPage(
      context,
      args: args,
      accentColor: _gold,
      fetchRides: (_) => fetchDriverKpiRidesFromTripsHistory(
        tenantId: args.tenantId,
        companyId: args.companyId,
        driverId: args.driverKey,
        scopeSource: scopeSource,
        fetchContext: 'company_drivers_reports',
      ),
    );
  }

  Future<void> _openPortraitDriverReportsPicker(
    BuildContext context,
    List<DriverProfile> visible,
  ) async {
    if (visible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Geen chauffeurs beschikbaar.',
              en: 'No drivers available.',
              fr: 'Aucun chauffeur disponible.',
              es: 'No hay conductores disponibles.',
            ),
          ),
        ),
      );
      return;
    }
    if (visible.length == 1) {
      await _openCompanyDriverKpiPage(context, visible.first);
      return;
    }
    final isCleanProfessional = _isCleanProfessional;
    final titleTextColor = isCleanProfessional ? _textPrimary : Colors.white;
    final itemTextColor = isCleanProfessional ? _textPrimary : Colors.white;
    final subtitleTextColor = isCleanProfessional
        ? _textSecondary
        : Colors.white.withOpacity(0.62);
    final trailingColor = isCleanProfessional
        ? _textSecondary.withOpacity(0.92)
        : _textMuted.withOpacity(0.72);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Kies chauffeur voor rapporten',
                  en: 'Select driver for reports',
                  fr: 'Sélectionnez le chauffeur pour les rapports',
                  es: 'Selecciona conductor para informes',
                ),
                style: TextStyle(
                  color: titleTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...visible.map(
                (driver) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _displayDriverName(driver.fullName),
                    style: TextStyle(color: itemTextColor),
                  ),
                  subtitle: Text(
                    _driverCodeStatusLabel(driver),
                    style: TextStyle(color: subtitleTextColor),
                  ),
                  trailing: Icon(Icons.chevron_right, color: trailingColor),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_openCompanyDriverKpiPage(context, driver));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPortraitDocumentsFocus(
    BuildContext context, {
    required List<DriverProfile> visible,
    required Map<String, DriverDocumentComplianceSummary> complianceByDriverId,
  }) async {
    final flagged = visible
        .where((driver) {
          final compliance = complianceByDriverId[driver.id.trim()];
          return compliance?.needsAction == true;
        })
        .toList(growable: false);
    if (flagged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Geen documentacties vereist.',
              en: 'No document action required.',
              fr: 'Aucune action documentaire requise.',
              es: 'No se requiere acción documental.',
            ),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  nl: 'Documenten controleren',
                  en: 'Review documents',
                  fr: 'Vérifier les documents',
                  es: 'Revisar documentos',
                ),
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...flagged.map((driver) {
                final compliance = complianceByDriverId[driver.id.trim()];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _displayDriverName(driver.fullName),
                    style: TextStyle(color: _textPrimary),
                  ),
                  subtitle: Text(
                    _docsInOrderLabel(
                      compliance ??
                          DriverDocumentsStore.instance
                              .complianceSummaryForDocuments(
                                const <DriverDocument>[],
                              ),
                    ),
                    style: TextStyle(color: _textSecondary),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: _textMuted.withOpacity(0.72),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openDocumentEditor(context, driver);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portraitQuickActionDockItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active ? _gold : _textMuted.withOpacity(0.9);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? _gold.withOpacity(_isDark ? 0.14 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? _gold.withOpacity(_isDark ? 0.45 : 0.8)
                : _border.withOpacity(_isDark ? 0.0 : 0.42),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 25, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 10.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([appLanguageNotifier, businessThemeNotifier]),
      builder: (context, _) {
        final appMedia = MediaQuery.of(context);
        final isPortraitHeader = appMedia.size.width < appMedia.size.height;
        return Scaffold(
          backgroundColor: _pageBg,
          appBar: AppBar(
            backgroundColor: _pageBg,
            foregroundColor: _textPrimary,
            iconTheme: isPortraitHeader
                ? IconThemeData(size: 29, color: _textPrimary)
                : IconThemeData(color: _textPrimary),
            toolbarHeight: isPortraitHeader ? 92 : null,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Chauffeurs beheren',
                    en: 'Manage drivers',
                    fr: 'Gérer les chauffeurs',
                    es: 'Gestionar conductores',
                  ),
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: isPortraitHeader ? 27.0 : 20.0,
                  ),
                ),
                Text(
                  _t(
                    nl: 'Snel overzicht van je chauffeurs',
                    en: 'Quick overview of your drivers',
                    fr: 'Aperçu rapide de vos chauffeurs',
                    es: 'Resumen rápido de tus conductores',
                  ),
                  style: TextStyle(
                    color: _textMuted.withOpacity(0.88),
                    fontSize: isPortraitHeader ? 16.0 : 11.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          body: ValueListenableBuilder<List<DriverDocument>>(
            valueListenable: driverDocumentsNotifier,
            builder: (context, _, __) => ValueListenableBuilder<List<DriverProfile>>(
              valueListenable: driversNotifier,
              builder: (context, drivers, _) {
                final media = MediaQuery.of(context);
                final screenClass = FluxidiBreakpoints.classifyWidth(
                  media.size.width,
                );
                final isTabletLandscape =
                    (screenClass == FluxidiScreenClass.tablet ||
                        screenClass == FluxidiScreenClass.desktop) &&
                    media.size.width > media.size.height &&
                    media.size.height >= 700;
                final isPortraitOperational =
                    media.size.width < media.size.height;
                // Phone-class landscape with a short height: the page must
                // pack header / KPIs / driver card more densely so the
                // Documents section is reachable without scrolling far.
                // Tablet landscape and portrait orientations are unchanged.
                final isCompactLandscape =
                    !isTabletLandscape &&
                    media.size.width > media.size.height &&
                    media.size.height < 500;
                final visible = drivers
                    .where(
                      (d) =>
                          !isSeededOrPlaceholderDriver(d) &&
                          fleetRecordBelongsToActiveCompanyOrLegacy(
                            d.companyId,
                          ),
                    )
                    .toList(growable: false);
                final docsStore = DriverDocumentsStore.instance;
                final docsByDriverId = <String, List<DriverDocument>>{};
                final complianceByDriverId =
                    <String, DriverDocumentComplianceSummary>{};
                final visibleByDriverId = <String, DriverProfile>{
                  for (final d in visible) d.id.trim(): d,
                };
                for (final d in visible) {
                  final scope = _activeCompanyScopeForDriverDelete(d);
                  if (scope == null) {
                    debugPrint(
                      '[DRIVER_DOCS_ADMIN][VISIBLE_SKIP] reason=missing_strict_scope',
                    );
                    docsByDriverId[d.id.trim()] = const <DriverDocument>[];
                    complianceByDriverId[d.id.trim()] = docsStore
                        .complianceSummaryForDocuments(
                          const <DriverDocument>[],
                        );
                    continue;
                  }
                  final docs = docsStore.documentsVisibleForCompanyAdminDriver(
                    d.id,
                    tenantId: scope.tenantId,
                    companyId: scope.companyId,
                  );
                  docsByDriverId[d.id.trim()] = docs;
                  complianceByDriverId[d.id.trim()] = docsStore
                      .complianceSummaryForDocuments(docs);
                }
                final activeVisibleCount = visible
                    .where((d) => d.isActive)
                    .length;
                String photoSourceForDriver(DriverProfile driver) {
                  final network = _driverCardNetworkPhotoUrl(driver);
                  if ((network ?? '').trim().isNotEmpty) return 'network';
                  final local = _driverCardPhotoPath(driver);
                  if ((local ?? '').trim().isNotEmpty) return 'local';
                  return 'initials';
                }

                final signature = visible
                    .map(
                      (d) =>
                          '${d.id.trim()}:${d.isActive}:${photoSourceForDriver(d)}',
                    )
                    .join('|');
                if (signature != _lastDriverPageLogSignature) {
                  _lastDriverPageLogSignature = signature;
                  debugPrint(
                    '[DRIVER_PAGE][VISIBLE] count=${visible.length} active=$activeVisibleCount',
                  );
                  for (final d in visible) {
                    debugPrint(
                      '[DRIVER_PAGE][ROW] id=${_shortDriverIdForDiag(d.id)} name=${d.fullName.trim()} isActive=${d.isActive} photoSource=${photoSourceForDriver(d)}',
                    );
                  }
                }
                final adminDocSignature = docsByDriverId.entries
                    .map((e) => '${e.key}:${e.value.length}')
                    .join('|');
                if (adminDocSignature != _lastAdminDocVisibilitySignature) {
                  _lastAdminDocVisibilitySignature = adminDocSignature;
                  for (final entry in docsByDriverId.entries) {
                    final driver = visibleByDriverId[entry.key];
                    if (driver == null) continue;
                    debugPrint(
                      '[DRIVER_DOCS_ADMIN][VISIBLE] driver=${_shortDriverIdForDiag(driver.id)} count=${entry.value.length}',
                    );
                  }
                }
                _queuePrecacheDriverAvatars(context, visible);
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _t(
                          nl: 'Nog geen chauffeurs beschikbaar.',
                          en: 'No drivers available yet.',
                          fr: 'Aucun chauffeur disponible.',
                          es: 'Todavía no hay conductores disponibles.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textMuted.withOpacity(0.92)),
                      ),
                    ),
                  );
                }
                final totalDrivers = visible.length;
                final activeDrivers = visible.where((d) => d.isActive).length;
                final pausedDrivers = visible
                    .where(
                      (d) =>
                          d.isActive &&
                          normalizeDriverAvailabilityState(
                                d.availabilityStatus,
                                fallback: 'available',
                              ) ==
                              'paused',
                    )
                    .length;
                final inactiveDrivers = visible
                    .where((d) => !d.isActive)
                    .length;
                var gapDrivers = 0;
                var expiringSoon = 0;
                for (final d in visible) {
                  final docs =
                      docsByDriverId[d.id.trim()] ?? const <DriverDocument>[];
                  final compliance =
                      complianceByDriverId[d.id.trim()] ??
                      docsStore.complianceSummaryForDocuments(docs);
                  final refreshFailed = documentRefreshFailedDriverIds.contains(
                    d.id.trim(),
                  );
                  if (compliance.needsAction || refreshFailed) {
                    gapDrivers++;
                  }
                  for (final doc in docs) {
                    if (_isExpiryWithinDays(doc.expiryDate, days: 30)) {
                      expiringSoon++;
                    }
                  }
                }

                if (isPortraitOperational) {
                  final useThreeColumnPortrait =
                      media.size.width >= 760 ||
                      ((screenClass == FluxidiScreenClass.tablet ||
                              screenClass == FluxidiScreenClass.desktop) &&
                          media.size.width >= 620);
                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
                              decoration: BoxDecoration(
                                color: _subPanelBg,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: _border.withOpacity(
                                    _isDark ? 0.38 : 0.92,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.screen_rotation_alt_outlined,
                                    color: _gold.withOpacity(0.98),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _t(
                                            nl: 'Draai je tablet voor volledig chauffeurbeheer',
                                            en: 'Rotate your tablet for full driver management',
                                            fr: 'Tournez votre tablette pour la gestion complète',
                                            es: 'Gira tu tablet para la gestión completa',
                                          ),
                                          style: TextStyle(
                                            color: _textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14.2,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _t(
                                            nl: 'Voor bewerken, documenten, chauffeurcodes en instellingen.',
                                            en: 'For editing, documents, driver codes and settings.',
                                            fr: 'Pour modifier, gérer les documents, codes et paramètres.',
                                            es: 'Para editar, documentos, códigos y ajustes.',
                                          ),
                                          style: TextStyle(
                                            color: _textMuted.withOpacity(0.9),
                                            fontSize: 12.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                11,
                                10,
                                11,
                                10,
                              ),
                              decoration: BoxDecoration(
                                color: _subPanelBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _border.withOpacity(
                                    _isDark ? 0.36 : 0.9,
                                  ),
                                ),
                              ),
                              child: useThreeColumnPortrait
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: _portraitKpiChip(
                                            icon: Icons.groups_rounded,
                                            accent: _gold,
                                            label: _t(
                                              nl: 'Totaal',
                                              en: 'Total',
                                              fr: 'Total',
                                              es: 'Total',
                                            ),
                                            value: '$totalDrivers',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _portraitKpiChip(
                                            icon: Icons.verified_user_outlined,
                                            accent: Colors.greenAccent,
                                            label: _t(
                                              nl: 'Actief',
                                              en: 'Active',
                                              fr: 'Actifs',
                                              es: 'Activos',
                                            ),
                                            value: '$activeDrivers',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _portraitKpiChip(
                                            icon: Icons
                                                .pause_circle_outline_rounded,
                                            accent: Colors.orangeAccent,
                                            label: _t(
                                              nl: 'Pauze',
                                              en: 'Paused',
                                              fr: 'Pause',
                                              es: 'Pausa',
                                            ),
                                            value: '$pausedDrivers',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _portraitKpiChip(
                                            icon: Icons.person_off_outlined,
                                            accent: _textMuted.withOpacity(0.9),
                                            label: _t(
                                              nl: 'Inactief',
                                              en: 'Inactive',
                                              fr: 'Inactifs',
                                              es: 'Inactivos',
                                            ),
                                            value: '$inactiveDrivers',
                                          ),
                                        ),
                                      ],
                                    )
                                  : GridView.count(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 1.9,
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      children: [
                                        _portraitKpiChip(
                                          icon: Icons.groups_rounded,
                                          accent: _gold,
                                          label: _t(
                                            nl: 'Totaal',
                                            en: 'Total',
                                            fr: 'Total',
                                            es: 'Total',
                                          ),
                                          value: '$totalDrivers',
                                        ),
                                        _portraitKpiChip(
                                          icon: Icons.verified_user_outlined,
                                          accent: Colors.greenAccent,
                                          label: _t(
                                            nl: 'Actief',
                                            en: 'Active',
                                            fr: 'Actifs',
                                            es: 'Activos',
                                          ),
                                          value: '$activeDrivers',
                                        ),
                                        _portraitKpiChip(
                                          icon: Icons
                                              .pause_circle_outline_rounded,
                                          accent: Colors.orangeAccent,
                                          label: _t(
                                            nl: 'Pauze',
                                            en: 'Paused',
                                            fr: 'Pause',
                                            es: 'Pausa',
                                          ),
                                          value: '$pausedDrivers',
                                        ),
                                        _portraitKpiChip(
                                          icon: Icons.person_off_outlined,
                                          accent: _textMuted.withOpacity(0.9),
                                          label: _t(
                                            nl: 'Inactief',
                                            en: 'Inactive',
                                            fr: 'Inactifs',
                                            es: 'Inactivos',
                                          ),
                                          value: '$inactiveDrivers',
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 8),
                            for (final d in visible) ...[
                              Builder(
                                builder: (context) {
                                  final docs =
                                      docsByDriverId[d.id.trim()] ??
                                      const <DriverDocument>[];
                                  final compliance =
                                      complianceByDriverId[d.id.trim()] ??
                                      docsStore.complianceSummaryForDocuments(
                                        docs,
                                      );
                                  final status = d.isActive
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
                                  final availabilityLabel = d.isActive
                                      ? _driverOperationalAvailabilityLabel(d)
                                      : '';
                                  final availabilityColor =
                                      _availabilityChipColor(d);
                                  final availabilityState =
                                      normalizeDriverAvailabilityState(
                                        d.availabilityStatus,
                                        fallback: 'available',
                                      );
                                  final pausedForDispatch =
                                      d.isActive &&
                                      availabilityState == 'paused';
                                  final assignedVehicle =
                                      _driverAssignedVehicle(
                                        d,
                                        vehiclesNotifier.value,
                                      );
                                  final vehicleName = assignedVehicle == null
                                      ? _t(
                                          nl: 'Geen voertuig toegewezen',
                                          en: 'No vehicle assigned',
                                          fr: 'Aucun véhicule assigné',
                                          es: 'Sin vehículo asignado',
                                        )
                                      : (assignedVehicle.vehicleName
                                                .trim()
                                                .isNotEmpty
                                            ? assignedVehicle.vehicleName.trim()
                                            : (assignedVehicle.brandModel
                                                      .trim()
                                                      .isNotEmpty
                                                  ? assignedVehicle.brandModel
                                                        .trim()
                                                  : _t(
                                                      nl: 'Voertuig toegewezen',
                                                      en: 'Vehicle assigned',
                                                      fr: 'Véhicule assigné',
                                                      es: 'Vehículo asignado',
                                                    )));
                                  final plate =
                                      assignedVehicle?.licensePlate.trim() ??
                                      '';
                                  final progress =
                                      (compliance.validRequiredCount /
                                              compliance.requiredTotal)
                                          .clamp(0.0, 1.0);
                                  final hasPhone = d.phone.trim().isNotEmpty;
                                  Future<void> callDriver() async {
                                    if (!hasPhone) return;
                                    final uri = Uri.parse(
                                      'tel:${Uri.encodeComponent(d.phone.trim())}',
                                    );
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }

                                  final ratingLabel = () {
                                    final avg = d.ratingAvg;
                                    final count = d.ratingCount ?? 0;
                                    if (avg != null && count > 0) {
                                      final rounded = avg.toStringAsFixed(1);
                                      final value =
                                          (appConfig.currentLanguage ==
                                              AppLanguage.en)
                                          ? rounded
                                          : rounded.replaceAll('.', ',');
                                      final reviewsWord = _t(
                                        nl: count == 1
                                            ? 'beoordeling'
                                            : 'beoordelingen',
                                        en: count == 1 ? 'review' : 'reviews',
                                        fr: 'avis',
                                        es: count == 1 ? 'reseña' : 'reseñas',
                                      );
                                      return '$value · $count $reviewsWord';
                                    }
                                    return _t(
                                      nl: 'Nog geen score',
                                      en: 'No rating yet',
                                      fr: 'Pas encore de note',
                                      es: 'Sin puntuación todavía',
                                    );
                                  }();
                                  final pauseMeta = pausedForDispatch
                                      ? _t(
                                          nl: 'Niet beschikbaar voor dispatch',
                                          en: 'Not available for dispatch',
                                          fr: 'Non disponible pour le dispatch',
                                          es: 'No disponible para despacho',
                                        )
                                      : '';
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      13,
                                      14,
                                      13,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _panelBg,
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: _border.withOpacity(
                                          _isDark ? 0.42 : 0.95,
                                        ),
                                      ),
                                      boxShadow: _isCleanProfessional
                                          ? [
                                              BoxShadow(
                                                color: _shadow.withOpacity(
                                                  0.18,
                                                ),
                                                blurRadius: 14,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (useThreeColumnPortrait)
                                          IntrinsicHeight(
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  flex: 44,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          _driverCardAvatar(
                                                            d,
                                                            size: 96,
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  d.fullName
                                                                          .trim()
                                                                          .isEmpty
                                                                      ? _t(
                                                                          nl: 'Naamloze chauffeur',
                                                                          en: 'Unnamed driver',
                                                                          fr: 'Chauffeur sans nom',
                                                                          es: 'Conductor sin nombre',
                                                                        )
                                                                      : _displayDriverName(
                                                                          d.fullName,
                                                                        ),
                                                                  style: TextStyle(
                                                                    color:
                                                                        _textPrimary,
                                                                    fontSize:
                                                                        22.0,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                const SizedBox(
                                                                  height: 2,
                                                                ),
                                                                Row(
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .star_rounded,
                                                                      color: Colors
                                                                          .amberAccent
                                                                          .withOpacity(
                                                                            0.95,
                                                                          ),
                                                                      size: 17,
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 4,
                                                                    ),
                                                                    Text(
                                                                      ratingLabel,
                                                                      style: TextStyle(
                                                                        color:
                                                                            _textMuted,
                                                                        fontSize:
                                                                            14.8,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(
                                                                  height: 2,
                                                                ),
                                                                Row(
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .phone_outlined,
                                                                      color:
                                                                          _textMuted,
                                                                      size: 13,
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 4,
                                                                    ),
                                                                    Expanded(
                                                                      child: Text(
                                                                        hasPhone
                                                                            ? d.phone.trim()
                                                                            : _t(
                                                                                nl: 'Geen telefoon',
                                                                                en: 'No phone',
                                                                                fr: 'Pas de téléphone',
                                                                                es: 'Sin teléfono',
                                                                              ),
                                                                        style: TextStyle(
                                                                          color:
                                                                              _textMuted,
                                                                          fontSize:
                                                                              14.4,
                                                                        ),
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                    if (hasPhone)
                                                                      IconButton(
                                                                        onPressed: () => unawaited(
                                                                          callDriver().catchError(
                                                                            (
                                                                              _,
                                                                            ) {},
                                                                          ),
                                                                        ),
                                                                        visualDensity:
                                                                            VisualDensity.compact,
                                                                        splashRadius:
                                                                            18,
                                                                        icon: Icon(
                                                                          Icons
                                                                              .call,
                                                                          color: _gold.withOpacity(
                                                                            0.96,
                                                                          ),
                                                                          size:
                                                                              17,
                                                                        ),
                                                                      ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                VerticalDivider(
                                                  color: _border.withOpacity(
                                                    _isDark ? 0.35 : 0.9,
                                                  ),
                                                  width: 16,
                                                  thickness: 1,
                                                ),
                                                Expanded(
                                                  flex: 30,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 7,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  _driverStatusChipBg(
                                                                    d.isActive,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    999,
                                                                  ),
                                                              border: Border.all(
                                                                color:
                                                                    _driverStatusChipBorder(
                                                                      d.isActive,
                                                                    ),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              status,
                                                              style: TextStyle(
                                                                color:
                                                                    _driverStatusChipText(
                                                                      d.isActive,
                                                                    ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 15.6,
                                                              ),
                                                            ),
                                                          ),
                                                          if (availabilityLabel
                                                              .trim()
                                                              .isNotEmpty)
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        12,
                                                                    vertical: 7,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: availabilityColor
                                                                    .withOpacity(
                                                                      0.18,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      999,
                                                                    ),
                                                                border: Border.all(
                                                                  color: availabilityColor
                                                                      .withOpacity(
                                                                        0.48,
                                                                      ),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                availabilityLabel,
                                                                style: TextStyle(
                                                                  color:
                                                                      availabilityColor,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  fontSize:
                                                                      15.6,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      if (pauseMeta
                                                          .trim()
                                                          .isNotEmpty)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 7,
                                                              ),
                                                          child: Text(
                                                            pauseMeta,
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .orangeAccent
                                                                  .withOpacity(
                                                                    0.92,
                                                                  ),
                                                              fontSize: 13.6,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                VerticalDivider(
                                                  color: _border.withOpacity(
                                                    _isDark ? 0.35 : 0.9,
                                                  ),
                                                  width: 16,
                                                  thickness: 1,
                                                ),
                                                Expanded(
                                                  flex: 26,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        vehicleName,
                                                        style: TextStyle(
                                                          color: _textPrimary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 18.0,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        plate.isEmpty
                                                            ? _t(
                                                                nl: 'Kenteken onbekend',
                                                                en: 'Plate unavailable',
                                                                fr: 'Plaque indisponible',
                                                                es: 'Matrícula no disponible',
                                                              )
                                                            : plate,
                                                        style: TextStyle(
                                                          color: _textSecondary,
                                                          fontSize: 15.5,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 8),
                                                      InkWell(
                                                        onTap: () =>
                                                            _openPortraitDriverManageSheet(
                                                              context,
                                                              d,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              _t(
                                                                nl: 'Details',
                                                                en: 'Details',
                                                                fr: 'Détails',
                                                                es: 'Detalles',
                                                              ),
                                                              style: TextStyle(
                                                                color: _gold
                                                                    .withOpacity(
                                                                      0.98,
                                                                    ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 13.8,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Icon(
                                                              Icons
                                                                  .chevron_right,
                                                              color: _gold
                                                                  .withOpacity(
                                                                    0.98,
                                                                  ),
                                                              size: 16,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _driverCardAvatar(
                                                    d,
                                                    size: 80,
                                                  ),
                                                  const SizedBox(width: 9),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          d.fullName
                                                                  .trim()
                                                                  .isEmpty
                                                              ? _t(
                                                                  nl: 'Naamloze chauffeur',
                                                                  en: 'Unnamed driver',
                                                                  fr: 'Chauffeur sans nom',
                                                                  es: 'Conductor sin nombre',
                                                                )
                                                              : _displayDriverName(
                                                                  d.fullName,
                                                                ),
                                                          style: TextStyle(
                                                            color: _textPrimary,
                                                            fontSize: 19.0,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .star_rounded,
                                                              color: Colors
                                                                  .amberAccent
                                                                  .withOpacity(
                                                                    0.92,
                                                                  ),
                                                              size: 13,
                                                            ),
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                ratingLabel,
                                                                style: TextStyle(
                                                                  color:
                                                                      _textMuted,
                                                                  fontSize:
                                                                      13.6,
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (hasPhone) ...[
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          InkWell(
                                                            onTap: () =>
                                                                unawaited(
                                                                  callDriver()
                                                                      .catchError(
                                                                        (_) {},
                                                                      ),
                                                                ),
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .phone_outlined,
                                                                  size: 13,
                                                                  color: _gold
                                                                      .withOpacity(
                                                                        0.98,
                                                                      ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 3,
                                                                ),
                                                                Expanded(
                                                                  child: Text(
                                                                    d.phone
                                                                        .trim(),
                                                                    style: TextStyle(
                                                                      color:
                                                                          _textMuted,
                                                                      fontSize:
                                                                          13.8,
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    onPressed: () =>
                                                        _openPortraitDriverManageSheet(
                                                          context,
                                                          d,
                                                        ),
                                                    icon: Icon(
                                                      Icons.chevron_right,
                                                      color: _gold.withOpacity(
                                                        0.96,
                                                      ),
                                                    ),
                                                    splashRadius: 18,
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                          minWidth: 36,
                                                          minHeight: 36,
                                                        ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: d.isActive
                                                          ? Colors.green
                                                                .withOpacity(
                                                                  0.16,
                                                                )
                                                          : _subPanelBg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                      border: Border.all(
                                                        color: d.isActive
                                                            ? Colors.greenAccent
                                                                  .withOpacity(
                                                                    0.44,
                                                                  )
                                                            : _border
                                                                  .withOpacity(
                                                                    _isDark
                                                                        ? 0.42
                                                                        : 0.85,
                                                                  ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                        color: d.isActive
                                                            ? Colors.greenAccent
                                                            : _textMuted
                                                                  .withOpacity(
                                                                    0.9,
                                                                  ),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13.8,
                                                      ),
                                                    ),
                                                  ),
                                                  if (availabilityLabel
                                                      .trim()
                                                      .isNotEmpty)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: availabilityColor
                                                            .withOpacity(0.18),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                        border: Border.all(
                                                          color:
                                                              availabilityColor
                                                                  .withOpacity(
                                                                    0.48,
                                                                  ),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        availabilityLabel,
                                                        style: TextStyle(
                                                          color:
                                                              availabilityColor,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 13.8,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              if (pauseMeta.trim().isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 6,
                                                      ),
                                                  child: Text(
                                                    pauseMeta,
                                                    style: TextStyle(
                                                      color: Colors.orangeAccent
                                                          .withOpacity(0.90),
                                                      fontSize: 13.0,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              const SizedBox(height: 6),
                                              Text(
                                                plate.isEmpty
                                                    ? vehicleName
                                                    : '$vehicleName · $plate',
                                                style: TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 14.4,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: compliance.needsAction
                                                    ? Colors.orange.withOpacity(
                                                        0.14,
                                                      )
                                                    : Colors.green.withOpacity(
                                                        0.12,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: compliance.needsAction
                                                      ? Colors.orangeAccent
                                                            .withOpacity(0.48)
                                                      : Colors.greenAccent
                                                            .withOpacity(0.44),
                                                ),
                                              ),
                                              child: Text(
                                                _t(
                                                  nl: 'Docs ${compliance.validRequiredCount}/7',
                                                  en: 'Docs ${compliance.validRequiredCount}/7',
                                                  fr: 'Docs ${compliance.validRequiredCount}/7',
                                                  es: 'Docs ${compliance.validRequiredCount}/7',
                                                ),
                                                style: TextStyle(
                                                  color: compliance.needsAction
                                                      ? Colors.orangeAccent
                                                      : Colors.greenAccent,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13.4,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                child: LinearProgressIndicator(
                                                  minHeight: 7,
                                                  value: progress,
                                                  backgroundColor: _border
                                                      .withOpacity(
                                                        _isDark ? 0.42 : 0.55,
                                                      ),
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(
                                                        compliance.needsAction
                                                            ? Colors
                                                                  .orangeAccent
                                                            : Colors
                                                                  .greenAccent,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(
                          left: 14,
                          right: 14,
                          top: 4,
                          bottom: math.max(8.0, media.padding.bottom + 2),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _panelBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _border.withOpacity(_isDark ? 0.3 : 0.9),
                          ),
                          boxShadow: _isCleanProfessional
                              ? [
                                  BoxShadow(
                                    color: _shadow.withOpacity(0.16),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _portraitQuickActionDockItem(
                                icon: Icons.folder_open_outlined,
                                label: _t(
                                  nl: 'Documenten',
                                  en: 'Documents',
                                  fr: 'Documents',
                                  es: 'Documentos',
                                ),
                                active: true,
                                onTap: () => _openPortraitDocumentsFocus(
                                  context,
                                  visible: visible,
                                  complianceByDriverId: complianceByDriverId,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _portraitQuickActionDockItem(
                                icon: Icons.key_outlined,
                                label: _t(
                                  nl: 'Codes',
                                  en: 'Codes',
                                  fr: 'Codes',
                                  es: 'Códigos',
                                ),
                                onTap: () => _openPortraitDriverCodePicker(
                                  context,
                                  visible,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _portraitQuickActionDockItem(
                                icon: Icons.insights_outlined,
                                label: _t(
                                  nl: 'Rapporten',
                                  en: 'Reports',
                                  fr: 'Rapports',
                                  es: 'Informes',
                                ),
                                onTap: () => _openPortraitDriverReportsPicker(
                                  context,
                                  visible,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _portraitQuickActionDockItem(
                                icon: Icons.person_add_alt_1_outlined,
                                label: _t(
                                  nl: 'Nieuw',
                                  en: 'New',
                                  fr: 'Nouveau',
                                  es: 'Nuevo',
                                ),
                                onTap: () => _openAddDriverFlow(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                final listPadding = isTabletLandscape
                    ? EdgeInsets.fromLTRB(
                        14,
                        10,
                        14,
                        math.max(16, media.padding.bottom + 8),
                      )
                    : isCompactLandscape
                    ? EdgeInsets.fromLTRB(
                        12,
                        6,
                        12,
                        math.max(10, media.padding.bottom + 6),
                      )
                    : const EdgeInsets.fromLTRB(14, 12, 14, 16);
                final introPadding = isTabletLandscape
                    ? const EdgeInsets.fromLTRB(14, 8, 14, 8)
                    : isCompactLandscape
                    ? const EdgeInsets.fromLTRB(12, 6, 12, 6)
                    : const EdgeInsets.fromLTRB(14, 12, 14, 12);
                final introTitleFontSize = isTabletLandscape
                    ? 15.6
                    : isCompactLandscape
                    ? 13.6
                    : 16.0;
                final introSubtitleFontSize = isTabletLandscape
                    ? 11.8
                    : isCompactLandscape
                    ? 10.8
                    : 12.4;

                return SafeArea(
                  top: false,
                  child: ListView(
                    padding: listPadding,
                    children: [
                      Container(
                        padding: introPadding,
                        decoration: BoxDecoration(
                          color: _panelBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _border.withOpacity(_isDark ? 0.38 : 0.92),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Chauffeurs beheren',
                                en: 'Manage drivers',
                                fr: 'Gérer les chauffeurs',
                                es: 'Gestionar conductores',
                              ),
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: introTitleFontSize,
                              ),
                            ),
                            SizedBox(
                              height: isTabletLandscape || isCompactLandscape
                                  ? 2
                                  : 4,
                            ),
                            Text(
                              _t(
                                nl: 'Beheer chauffeurs, documenten en beschikbaarheid',
                                en: 'Manage drivers, documents and availability',
                                fr: 'Gérez les chauffeurs, documents et disponibilités',
                                es: 'Gestiona conductores, documentos y disponibilidad',
                              ),
                              style: TextStyle(
                                color: _textMuted.withOpacity(0.9),
                                fontSize: introSubtitleFontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isCompactLandscape ? 6 : 10),
                      if (isTabletLandscape || isCompactLandscape)
                        GridView.count(
                          crossAxisCount: 4,
                          crossAxisSpacing: isCompactLandscape ? 6 : 10,
                          mainAxisSpacing: isCompactLandscape ? 6 : 10,
                          childAspectRatio: isCompactLandscape ? 2.7 : 2.35,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _summaryMetric(
                              icon: Icons.groups_rounded,
                              accent: _gold,
                              label: isCompactLandscape
                                  ? _t(
                                      nl: 'Totaal',
                                      en: 'Total',
                                      fr: 'Total',
                                      es: 'Total',
                                    )
                                  : _t(
                                      nl: 'Totaal chauffeurs',
                                      en: 'Total drivers',
                                      fr: 'Total chauffeurs',
                                      es: 'Total conductores',
                                    ),
                              value: '$totalDrivers',
                              subtitle: isCompactLandscape
                                  ? null
                                  : _t(
                                      nl: 'Alle geregistreerde chauffeurs',
                                      en: 'All registered drivers',
                                      fr: 'Tous les chauffeurs inscrits',
                                      es: 'Todos los conductores registrados',
                                    ),
                              compact: true,
                              dense: isCompactLandscape,
                            ),
                            _summaryMetric(
                              icon: Icons.verified_user_outlined,
                              accent: Colors.greenAccent,
                              label: _t(
                                nl: 'Actief',
                                en: 'Active',
                                fr: 'Actifs',
                                es: 'Activos',
                              ),
                              value: '$activeDrivers',
                              subtitle: isCompactLandscape
                                  ? null
                                  : _t(
                                      nl: 'Momenteel actief',
                                      en: 'Currently active',
                                      fr: 'Actuellement actifs',
                                      es: 'Actualmente activos',
                                    ),
                              compact: true,
                              dense: isCompactLandscape,
                            ),
                            _summaryMetric(
                              icon: Icons.warning_amber_rounded,
                              accent: Colors.orangeAccent,
                              label: isCompactLandscape
                                  ? _t(
                                      nl: 'Docs',
                                      en: 'Docs',
                                      fr: 'Docs',
                                      es: 'Docs',
                                    )
                                  : _t(
                                      nl: 'Documenten actie vereist',
                                      en: 'Documents need action',
                                      fr: 'Documents: action requise',
                                      es: 'Documentos: acción requerida',
                                    ),
                              value: '$gapDrivers',
                              subtitle: isCompactLandscape
                                  ? null
                                  : _t(
                                      nl: 'Vereisen controle',
                                      en: 'Require attention',
                                      fr: 'Nécessitent une attention',
                                      es: 'Requieren atención',
                                    ),
                              compact: true,
                              dense: isCompactLandscape,
                            ),
                            _summaryMetric(
                              icon: Icons.event_available_outlined,
                              accent: Colors.lightBlueAccent,
                              label: isCompactLandscape
                                  ? _t(
                                      nl: 'Vervalt',
                                      en: 'Expiring',
                                      fr: 'Expire',
                                      es: 'Expira',
                                    )
                                  : _t(
                                      nl: 'Binnenkort vervallen',
                                      en: 'Expiring soon',
                                      fr: 'Expiration proche',
                                      es: 'Caducan pronto',
                                    ),
                              value: '$expiringSoon',
                              subtitle: isCompactLandscape
                                  ? null
                                  : _t(
                                      nl: 'Binnen 30 dagen',
                                      en: 'Within 30 days',
                                      fr: 'Dans les 30 jours',
                                      es: 'Dentro de 30 días',
                                    ),
                              compact: true,
                              dense: isCompactLandscape,
                            ),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _subPanelBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _gold.withOpacity(0.30)),
                          ),
                          child: GridView.count(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _summaryMetric(
                                icon: Icons.groups_rounded,
                                accent: _gold,
                                label: _t(
                                  nl: 'Totaal chauffeurs',
                                  en: 'Total drivers',
                                  fr: 'Total chauffeurs',
                                  es: 'Total conductores',
                                ),
                                value: '$totalDrivers',
                                compact: false,
                              ),
                              _summaryMetric(
                                icon: Icons.verified_user_outlined,
                                accent: Colors.greenAccent,
                                label: _t(
                                  nl: 'Actief',
                                  en: 'Active',
                                  fr: 'Actifs',
                                  es: 'Activos',
                                ),
                                value: '$activeDrivers',
                                compact: false,
                              ),
                              _summaryMetric(
                                icon: Icons.warning_amber_rounded,
                                accent: Colors.orangeAccent,
                                label: _t(
                                  nl: 'Documenten actie vereist',
                                  en: 'Documents need action',
                                  fr: 'Documents: action requise',
                                  es: 'Documentos: acción requerida',
                                ),
                                value: '$gapDrivers',
                                compact: false,
                              ),
                              _summaryMetric(
                                icon: Icons.event_available_outlined,
                                accent: Colors.lightBlueAccent,
                                label: _t(
                                  nl: 'Binnenkort vervallen',
                                  en: 'Expiring soon',
                                  fr: 'Expiration proche',
                                  es: 'Caducan pronto',
                                ),
                                value: '$expiringSoon',
                                compact: false,
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: isCompactLandscape ? 6 : 8),
                      for (final d in visible) ...[
                        Builder(
                          builder: (context) {
                            final status = d.isActive
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
                            final availabilityState =
                                normalizeDriverAvailabilityState(
                                  d.availabilityStatus,
                                  fallback: 'available',
                                );
                            final operationalAvailabilityLabel = !d.isActive
                                ? _t(
                                    nl: 'Niet beschikbaar',
                                    en: 'Not available',
                                    fr: 'Indisponible',
                                    es: 'No disponible',
                                  )
                                : (availabilityState == 'paused'
                                      ? _t(
                                          nl: 'Pauze',
                                          en: 'Paused',
                                          fr: 'Pause',
                                          es: 'Pausa',
                                        )
                                      : (availabilityState == 'busy'
                                            ? _t(
                                                nl: 'Bezet',
                                                en: 'Busy',
                                                fr: 'Occupé',
                                                es: 'Ocupado',
                                              )
                                            : (availabilityState == 'offline'
                                                  ? _t(
                                                      nl: 'Offline',
                                                      en: 'Offline',
                                                      fr: 'Hors ligne',
                                                      es: 'Sin conexión',
                                                    )
                                                  : '')));
                            final docs =
                                docsByDriverId[d.id.trim()] ??
                                const <DriverDocument>[];
                            final compliance =
                                complianceByDriverId[d.id.trim()] ??
                                docsStore.complianceSummaryForDocuments(docs);
                            final refreshFailed = documentRefreshFailedDriverIds
                                .contains(d.id.trim());
                            final gap = compliance.needsAction || refreshFailed;
                            final docsStatusText = refreshFailed
                                ? _t(
                                    nl: 'Documenten vereisen synchronisatie',
                                    en: 'Documents require synchronization',
                                    fr: 'Les documents nécessitent une synchronisation',
                                    es: 'Los documentos requieren sincronización',
                                  )
                                : _docsInOrderLabel(compliance);
                            final docsStatusDetail = refreshFailed
                                ? _t(
                                    nl: 'Controleer documenten',
                                    en: 'Check documents',
                                    fr: 'Vérifier les documents',
                                    es: 'Revise documentos',
                                  )
                                : (compliance.hasAllRequiredDocuments &&
                                          !compliance.needsAction
                                      ? ''
                                      : (compliance
                                                .missingAttachmentRequiredTypeIds
                                                .isNotEmpty
                                            ? _attachmentMissingLabel()
                                            : (compliance.uploadedRequiredCount ==
                                                      0
                                                  ? _t(
                                                      nl: 'Vereiste documenten ontbreken',
                                                      en: 'Required documents are missing',
                                                      fr: 'Documents requis manquants',
                                                      es: 'Faltan documentos requeridos',
                                                    )
                                                  : (compliance
                                                            .missingRequiredTypeIds
                                                            .isNotEmpty
                                                        ? _missingRequiredLabel(
                                                            compliance
                                                                .missingRequiredTypeIds
                                                                .length,
                                                          )
                                                        : _documentsNeedsActionLabel()))));
                            if (isTabletLandscape) {
                              return _driverLandscapeReferenceCard(
                                context,
                                driver: d,
                                accountStatus: status,
                                operationalAvailabilityLabel:
                                    operationalAvailabilityLabel,
                                docs: docs,
                                compliance: compliance,
                                refreshFailed: refreshFailed,
                              );
                            }
                            return Container(
                              margin: EdgeInsets.only(
                                bottom: isCompactLandscape ? 8 : 10,
                              ),
                              padding: isCompactLandscape
                                  ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                                  : const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              decoration: BoxDecoration(
                                color: _panelBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _gold.withOpacity(0.28),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _driverCardAvatar(d),
                                      SizedBox(
                                        width: isCompactLandscape ? 8 : 10,
                                      ),
                                      Expanded(
                                        child: Text(
                                          d.fullName.trim().isEmpty
                                              ? _t(
                                                  nl: 'Naamloze chauffeur',
                                                  en: 'Unnamed driver',
                                                  fr: 'Chauffeur sans nom',
                                                  es: 'Conductor sin nombre',
                                                )
                                              : _displayDriverName(d.fullName),
                                          style: TextStyle(
                                            fontSize: isCompactLandscape
                                                ? 13.0
                                                : 15.8,
                                            fontWeight: FontWeight.w800,
                                            color: _textPrimary,
                                          ),
                                          maxLines: isCompactLandscape ? 1 : 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: isCompactLandscape ? 6 : 8,
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isCompactLandscape
                                              ? 6
                                              : 8,
                                          vertical: isCompactLandscape ? 3 : 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _driverStatusChipBg(
                                            d.isActive,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: _driverStatusChipBorder(
                                              d.isActive,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            color: _driverStatusChipText(
                                              d.isActive,
                                            ),
                                            fontSize: isCompactLandscape
                                                ? 10.4
                                                : 11.6,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _confirmDeleteDriver(context, d),
                                        tooltip: _t(
                                          nl: 'Chauffeur verwijderen',
                                          en: 'Remove driver',
                                          fr: 'Supprimer le chauffeur',
                                          es: 'Eliminar conductor',
                                        ),
                                        icon: Icon(
                                          Icons.delete_outline,
                                          size: isCompactLandscape ? 16 : 18,
                                          color: Colors.redAccent.withOpacity(
                                            0.92,
                                          ),
                                        ),
                                        splashRadius: 20,
                                        constraints: BoxConstraints(
                                          minWidth: isCompactLandscape
                                              ? 32
                                              : 36,
                                          minHeight: isCompactLandscape
                                              ? 32
                                              : 36,
                                        ),
                                        padding: EdgeInsets.all(
                                          isCompactLandscape ? 4 : 6,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF2A1518,
                                          ),
                                          side: BorderSide(
                                            color: Colors.redAccent.withOpacity(
                                              0.35,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (operationalAvailabilityLabel
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: isCompactLandscape ? 4 : 6,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: isCompactLandscape
                                                ? 6
                                                : 8,
                                            vertical: isCompactLandscape
                                                ? 2
                                                : 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(
                                              0.14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: Colors.orangeAccent
                                                  .withOpacity(0.42),
                                            ),
                                          ),
                                          child: Text(
                                            operationalAvailabilityLabel,
                                            style: TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: isCompactLandscape
                                                  ? 10.2
                                                  : 11.2,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  SizedBox(height: isCompactLandscape ? 6 : 8),
                                  _line(
                                    _t(
                                      nl: 'Bedrijfscode',
                                      en: 'Company ID',
                                      fr: 'Code entreprise',
                                      es: 'Código de empresa',
                                    ),
                                    _displayCompanyLoginCode(d),
                                    icon: Icons.business_outlined,
                                  ),
                                  _line(
                                    _t(
                                      nl: 'Chauffeurcode',
                                      en: 'Driver code',
                                      fr: 'Code chauffeur',
                                      es: 'Código de conductor',
                                    ),
                                    _driverCodeStatusLabel(d),
                                    icon: Icons.badge_outlined,
                                  ),
                                  if (!isCompactLandscape) ...[
                                    _line(
                                      _t(
                                        nl: 'Telefoon',
                                        en: 'Phone',
                                        fr: 'Téléphone',
                                        es: 'Teléfono',
                                      ),
                                      d.phone,
                                      icon: Icons.phone_outlined,
                                    ),
                                    _line(
                                      _t(
                                        nl: 'Chauffeurskaartnummer',
                                        en: 'Driver card number',
                                        fr: 'N° carte chauffeur',
                                        es: 'N.º tarjeta de conductor',
                                      ),
                                      d.taxiDriverCardNumber,
                                      icon: Icons.credit_card_outlined,
                                    ),
                                    _line(
                                      _t(
                                        nl: 'Vervaldatum chauffeurskaart',
                                        en: 'Driver card expiry',
                                        fr: 'Expiration carte chauffeur',
                                        es: 'Caducidad tarjeta de conductor',
                                      ),
                                      d.taxiDriverCardExpiry,
                                      icon: Icons.event_note_outlined,
                                    ),
                                  ],
                                  SizedBox(height: isCompactLandscape ? 6 : 8),
                                  Container(
                                    width: double.infinity,
                                    padding: isCompactLandscape
                                        ? const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          )
                                        : const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _subPanelBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: gap
                                            ? Colors.orange.withOpacity(0.52)
                                            : _gold.withOpacity(0.30),
                                      ),
                                    ),
                                    child: Text(
                                      '$docsStatusText'
                                      '${gap && docsStatusDetail.trim().isNotEmpty ? ' · $docsStatusDetail' : ''}',
                                      style: TextStyle(
                                        color: gap
                                            ? Colors.orangeAccent
                                            : _textMuted.withOpacity(0.9),
                                        fontSize: isCompactLandscape
                                            ? 10.8
                                            : 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isCompactLandscape ? 6 : 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: _subPanelBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _gold.withOpacity(0.20),
                                      ),
                                    ),
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent,
                                      ),
                                      child: ExpansionTile(
                                        initiallyExpanded: isCompactLandscape,
                                        tilePadding: EdgeInsets.symmetric(
                                          horizontal: isCompactLandscape
                                              ? 8
                                              : 10,
                                          vertical: 2,
                                        ),
                                        childrenPadding: EdgeInsets.fromLTRB(
                                          isCompactLandscape ? 8 : 10,
                                          0,
                                          isCompactLandscape ? 8 : 10,
                                          isCompactLandscape ? 6 : 8,
                                        ),
                                        title: Text(
                                          _t(
                                            nl: 'Documenten',
                                            en: 'Documents',
                                            fr: 'Documents',
                                            es: 'Documentos',
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: isCompactLandscape
                                                ? 12.6
                                                : 13.5,
                                            color: _textPrimary,
                                          ),
                                        ),
                                        subtitle: Text(
                                          docs.isEmpty
                                              ? _t(
                                                  nl: 'Nog geen documenten.',
                                                  en: 'No documents.',
                                                  fr: 'Aucun document.',
                                                  es: 'Sin documentos.',
                                                )
                                              : _t(
                                                  nl: 'Tik om te bekijken en beheren',
                                                  en: 'Tap to view and manage',
                                                  fr: 'Touchez pour voir et gerer',
                                                  es: 'Toca para ver y gestionar',
                                                ),
                                          style: TextStyle(
                                            color: _textSecondary,
                                            fontSize: isCompactLandscape
                                                ? 11.2
                                                : 12,
                                          ),
                                        ),
                                        children: [
                                          if (docs.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Text(
                                                _t(
                                                  nl: 'Nog geen documenten.',
                                                  en: 'No documents.',
                                                  fr: 'Aucun document.',
                                                  es: 'Sin documentos.',
                                                ),
                                                style: TextStyle(
                                                  color: _textSecondary,
                                                ),
                                              ),
                                            )
                                          else
                                            ...docs.map(
                                              (doc) => _driverDocumentTile(
                                                context,
                                                d,
                                                doc,
                                              ),
                                            ),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _openDocumentEditor(
                                                    context,
                                                    d,
                                                  ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: _gold
                                                    .withOpacity(0.96),
                                                side: BorderSide(
                                                  color: _gold.withOpacity(
                                                    0.38,
                                                  ),
                                                ),
                                                backgroundColor: _panelBg,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                              ),
                                              icon: const Icon(
                                                Icons.add,
                                                size: 18,
                                              ),
                                              label: Text(
                                                _t(
                                                  nl: 'Document toevoegen',
                                                  en: 'Add document',
                                                  fr: 'Ajouter',
                                                  es: 'Agregar',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isCompactLandscape ? 6 : 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      spacing: isCompactLandscape ? 6 : 8,
                                      runSpacing: isCompactLandscape ? 6 : 8,
                                      alignment: WrapAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _rotateDriverCode(context, d),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _gold.withOpacity(
                                              0.98,
                                            ),
                                            side: BorderSide(
                                              color: _gold.withOpacity(0.34),
                                            ),
                                            backgroundColor: _subPanelBg,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isCompactLandscape
                                                  ? 10
                                                  : 12,
                                              vertical: isCompactLandscape
                                                  ? 6
                                                  : 8,
                                            ),
                                            minimumSize: isCompactLandscape
                                                ? const Size(0, 32)
                                                : null,
                                            textStyle: isCompactLandscape
                                                ? const TextStyle(
                                                    fontSize: 11.6,
                                                  )
                                                : null,
                                          ),
                                          icon: Icon(
                                            Icons.key_outlined,
                                            size: isCompactLandscape ? 14 : 16,
                                          ),
                                          label: Text(
                                            isCompactLandscape
                                                ? _t(
                                                    nl: 'Nieuwe code',
                                                    en: 'New code',
                                                    fr: 'Nouveau code',
                                                    es: 'Nuevo código',
                                                  )
                                                : _t(
                                                    nl: 'Nieuwe chauffeurcode genereren',
                                                    en: 'Generate new driver code',
                                                    fr: 'Generer un nouveau code chauffeur',
                                                    es: 'Generar nuevo codigo de conductor',
                                                  ),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openTemporaryDriverLinkQr(
                                                context,
                                                d,
                                              ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _gold.withOpacity(
                                              0.98,
                                            ),
                                            side: BorderSide(
                                              color: _gold.withOpacity(0.34),
                                            ),
                                            backgroundColor: _subPanelBg,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isCompactLandscape
                                                  ? 10
                                                  : 12,
                                              vertical: isCompactLandscape
                                                  ? 6
                                                  : 8,
                                            ),
                                            minimumSize: isCompactLandscape
                                                ? const Size(0, 32)
                                                : null,
                                            textStyle: isCompactLandscape
                                                ? const TextStyle(
                                                    fontSize: 11.6,
                                                  )
                                                : null,
                                          ),
                                          icon: Icon(
                                            Icons.qr_code_2_outlined,
                                            size: isCompactLandscape ? 14 : 16,
                                          ),
                                          label: Text(
                                            isCompactLandscape
                                                ? _t(
                                                    nl: 'Koppel-QR',
                                                    en: 'Pairing QR',
                                                    fr: 'QR liaison',
                                                    es: 'QR vinculación',
                                                  )
                                                : _t(
                                                    nl: 'Tijdelijke koppel-QR',
                                                    en: 'Temporary pairing QR',
                                                    fr: 'QR de liaison temporaire',
                                                    es: 'QR temporal de vinculación',
                                                  ),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openEditDriverDialog(context, d),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _textPrimary,
                                            side: BorderSide(
                                              color: _border.withOpacity(
                                                _isDark ? 0.45 : 0.92,
                                              ),
                                            ),
                                            backgroundColor: _panelBg,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isCompactLandscape
                                                  ? 10
                                                  : 12,
                                              vertical: isCompactLandscape
                                                  ? 6
                                                  : 8,
                                            ),
                                            minimumSize: isCompactLandscape
                                                ? const Size(0, 32)
                                                : null,
                                            textStyle: isCompactLandscape
                                                ? const TextStyle(
                                                    fontSize: 11.6,
                                                  )
                                                : null,
                                          ),
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            size: isCompactLandscape ? 14 : 16,
                                          ),
                                          label: Text(
                                            _t(
                                              nl: 'Bewerken',
                                              en: 'Edit',
                                              fr: 'Modifier',
                                              es: 'Editar',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
