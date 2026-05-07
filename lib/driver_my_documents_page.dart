import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
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

class _DriverMyDocumentsPageState extends State<DriverMyDocumentsPage> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    DriverDocumentsStore.instance.load();
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

  DriverProfile? _driverForSession(ActiveDriverSession session) {
    for (final d in driversNotifier.value) {
      if (d.id == session.driverId) return d;
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

  String _profilePhotoActionLabel(DriverProfile driver) {
    final hasPhoto = _driverPhotoExists(driver.profilePhotoPath);
    if (hasPhoto) {
      return _tr(
        nl: 'Pasfoto wijzigen',
        en: 'Change profile photo',
        fr: 'Modifier la photo',
        es: 'Cambiar foto',
      );
    }
    return _tr(
      nl: 'Pasfoto toevoegen',
      en: 'Add profile photo',
      fr: 'Ajouter une photo',
      es: 'Añadir foto',
    );
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

  Widget _profilePhotoActionCard(DriverProfile driver) {
    final path = driver.profilePhotoPath?.trim() ?? '';
    final hasPhoto = _driverPhotoExists(path);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1A223A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: ClipOval(
              child: hasPhoto
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
                  : Center(
                      child: Text(
                        _driverInitials(driver),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _profilePhotoActionLabel(driver),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _onProfilePhotoActionTap(driver),
            child: Text(
              _tr(nl: 'Kies', en: 'Choose', fr: 'Choisir', es: 'Elegir'),
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
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
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

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                    children: [
                      Text(
                        _tr(
                          nl: 'Je documenten zijn gekoppeld aan je chauffeurprofiel. Gevoelige documenten moeten in productie veilig worden opgeslagen.',
                          en: 'Your documents are linked to your driver profile. In production, sensitive documents must be stored securely.',
                          fr: 'Vos documents sont liés à votre profil chauffeur. En production, les documents sensibles doivent être stockés de manière sécurisée.',
                          es: 'Tus documentos están vinculados a tu perfil de conductor. En producción, los documentos sensibles deben almacenarse de forma segura.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _profilePhotoActionCard(driver),
                      if (docs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _tr(
                              nl: 'Je hebt nog geen documenten opgeladen. Voeg je rijbewijs, bestuurderspas of andere vereiste documenten toe.',
                              en: 'You have not uploaded any documents yet. Add your driving license, taxi driver card, or other required documents.',
                              fr: 'Vous n\'avez pas encore téléversé de documents. Ajoutez votre permis de conduire, votre carte de chauffeur ou d\'autres documents requis.',
                              es: 'Aún no has subido documentos. Añade tu permiso de conducir, tarjeta de conductor de taxi u otros documentos requeridos.',
                            ),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      if (docs.isNotEmpty && pending > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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
                      ...docs.map(
                        (doc) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _driverSelfDocTile(context, doc),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
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
    final typeLabel = driverDocumentTypeLabel(doc.documentType, _lang);
    final expiredVisual =
        doc.isExpiredByDate || doc.status == DriverDocumentStatuses.expired;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expiredVisual
              ? Colors.orange.withOpacity(0.55)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.title.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                doc.title,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${_tr(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: ${driverDocumentStatusLabel(doc.status, _lang)}'
            '${doc.isExpiredByDate && doc.status != DriverDocumentStatuses.expired ? ' (${_tr(nl: 'datum verlopen', en: 'date expired', fr: 'date expirée', es: 'fecha caducada')})' : ''}',
            style: TextStyle(
              color: expiredVisual ? Colors.orangeAccent : Colors.white70,
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
            SizedBox(
              width: double.infinity,
              child: Text(
                doc.filePath,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
              ),
              onPressed: doc.filePath.trim().isEmpty
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
