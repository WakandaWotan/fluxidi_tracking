import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';

String _ddT(
  AppLanguage lang, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (lang) {
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

bool _ddIsLikelyImagePath(String path) {
  final lower = path.toLowerCase().trim();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.bmp');
}

bool _ddIsLikelyPdfPath(String path) {
  return path.toLowerCase().trim().endsWith('.pdf');
}

bool _isLocalFilesystemPath(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return false;
  final normalized = raw.replaceAll('\\', '/').toLowerCase();
  if (normalized.startsWith('/data/user/')) return true;
  if (normalized.contains('/app_flutter/')) return true;
  if (normalized.contains('/driver_documents/files/')) return true;
  if (normalized.startsWith('file://')) return true;
  if (normalized.startsWith('content://')) return true;
  if (RegExp(r'^[a-z]:[\\/]', caseSensitive: false).hasMatch(raw)) {
    return true;
  }
  if (raw.contains('\\')) return true;
  return false;
}

/// Shared attachment preview (admin + driver UI).
Widget driverDocAttachmentPreview(String rawPath, AppLanguage lang) {
  final path = rawPath.trim();
  if (path.isEmpty) return const SizedBox.shrink();
  if (!kIsWeb && !File(path).existsSync()) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        _ddT(
          lang,
          nl: 'Lokale kopie niet gevonden',
          en: 'Local copy not found',
          fr: 'Copie locale introuvable',
          es: 'Copia local no encontrada',
        ),
        style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  final showThumb = !kIsWeb && _ddIsLikelyImagePath(path);

  Widget leading;
  if (showThumb) {
    leading = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            width: 56,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.broken_image_outlined,
                color: Colors.white38,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  } else if (_ddIsLikelyPdfPath(path)) {
    leading = SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.red.shade900.withOpacity(0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.picture_as_pdf,
          color: Colors.white70,
          size: 32,
        ),
      ),
    );
  } else {
    leading = SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.insert_drive_file_outlined,
          color: Colors.white54,
          size: 30,
        ),
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _ddT(
              lang,
              nl: 'Lokale bijlage beschikbaar',
              en: 'Local attachment available',
              fr: 'Pièce jointe locale disponible',
              es: 'Adjunto local disponible',
            ),
            style: const TextStyle(fontSize: 11, color: Colors.white60),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

Future<void> openDriverDocumentFile(
  BuildContext context,
  String rawPath,
  AppLanguage lang,
) async {
  final p = rawPath.trim();
  if (p.isEmpty) return;
  if (!await File(p).exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _ddT(
            lang,
            nl: 'Bestand niet gevonden op dit toestel',
            en: 'File not found on this device',
            fr: 'Fichier introuvable sur cet appareil',
            es: 'Archivo no encontrado en este dispositivo',
          ),
        ),
      ),
    );
    return;
  }
  final result = await OpenFilex.open(p);
  if (!context.mounted) return;
  if (result.type != ResultType.done) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _ddT(
            lang,
            nl: 'Kon bestand niet openen.',
            en: 'Could not open the file.',
            fr: 'Impossible d’ouvrir le fichier.',
            es: 'No se pudo abrir el archivo.',
          ),
        ),
      ),
    );
  }
}

Widget _sheetField(
  TextEditingController ctrl,
  String label, {
  VoidCallback? onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: ctrl,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF0B0B0B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
    ),
  );
}

Future<void> _pickCamera(
  ImagePicker picker,
  BuildContext sheetCtx,
  void Function(VoidCallback fn) setLocal,
  void Function(String path) onPicked,
) async {
  try {
    final x = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    if (!sheetCtx.mounted) return;
    if (x == null) return;
    setLocal(() => onPicked(x.path));
  } catch (_) {}
}

Future<void> _pickGallery(
  ImagePicker picker,
  BuildContext sheetCtx,
  void Function(VoidCallback fn) setLocal,
  void Function(String path) onPicked,
) async {
  try {
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (!sheetCtx.mounted) return;
    if (x == null) return;
    setLocal(() => onPicked(x.path));
  } catch (_) {}
}

Future<void> _pickFile(
  BuildContext sheetCtx,
  void Function(VoidCallback fn) setLocal,
  void Function(String path) onPicked,
) async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'bmp',
      ],
    );
    if (!sheetCtx.mounted) return;
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path != null && path.trim().isNotEmpty) {
      setLocal(() => onPicked(path));
    }
  } catch (_) {}
}

/// Shared document editor (company admin + chauffeur self-service).
///
/// When [driverSelfService] is true, status is not editable; new docs use
/// [DriverDocumentStatuses.pendingReview]; edits keep the existing status.
Future<void> showDriverDocumentEditorSheet(
  BuildContext context, {
  required DriverProfile driver,
  DriverDocument? existing,
  bool driverSelfService = false,
  String? initialDocumentType,
}) async {
  final picker = ImagePicker();
  final preferredType = initialDocumentType?.trim() ?? '';
  var selectedType =
      existing?.documentType ??
      (DriverDocumentTypes.all.contains(preferredType)
          ? preferredType
          : DriverDocumentTypes.other);
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  final existingPath = (existing?.filePath ?? '').trim();
  var selectedAttachmentPath = existingPath;
  final manualReferenceCtrl = TextEditingController(
    text: _isLocalFilesystemPath(existingPath) ? '' : existingPath,
  );
  final expiryCtrl = TextEditingController(text: existing?.expiryDate ?? '');
  var selectedStatus = existing?.status ?? DriverDocumentStatuses.pendingReview;
  final notesCtrl = TextEditingController(text: existing?.notes ?? '');

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141B2F),
    builder: (ctx) {
      return ValueListenableBuilder<AppLanguage>(
        valueListenable: appLanguageNotifier,
        builder: (context, lang, _) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              String t({
                required String nl,
                required String en,
                required String fr,
                required String es,
              }) => _ddT(lang, nl: nl, en: en, fr: fr, es: es);

              return Padding(
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
                            ? t(
                                nl: 'Document toevoegen',
                                en: 'Add document',
                                fr: 'Ajouter un document',
                                es: 'Añadir documento',
                              )
                            : t(
                                nl: 'Document bewerken',
                                en: 'Edit document',
                                fr: 'Modifier document',
                                es: 'Editar documento',
                              ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        isExpanded: true,
                        items: DriverDocumentTypes.all
                            .map(
                              (ty) => DropdownMenuItem(
                                value: ty,
                                child: Text(
                                  driverDocumentTypeLabel(ty, lang),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => selectedType = v);
                        },
                        decoration: InputDecoration(
                          labelText: t(
                            nl: 'Documenttype',
                            en: 'Document type',
                            fr: 'Type',
                            es: 'Tipo',
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0B0B0B),
                        ),
                        dropdownColor: const Color(0xFF111111),
                      ),
                      const SizedBox(height: 8),
                      _sheetField(
                        titleCtrl,
                        t(nl: 'Titel', en: 'Title', fr: 'Titre', es: 'Titulo'),
                      ),
                      Text(
                        t(
                          nl: 'Bijlage',
                          en: 'Attachment',
                          fr: 'Piece jointe',
                          es: 'Adjunto',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _pickCamera(picker, ctx, setLocal, (path) {
                                    selectedAttachmentPath = path.trim();
                                  }),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                              ),
                              label: Text(
                                t(
                                  nl: 'Foto nemen',
                                  en: 'Take photo',
                                  fr: 'Prendre une photo',
                                  es: 'Tomar foto',
                                ),
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _pickGallery(picker, ctx, setLocal, (path) {
                                    selectedAttachmentPath = path.trim();
                                  }),
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                              label: Text(
                                t(
                                  nl: 'Kies uit galerij',
                                  en: 'Choose from gallery',
                                  fr: 'Choisir dans la galerie',
                                  es: 'Elegir de galeria',
                                ),
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFile(ctx, setLocal, (path) {
                            selectedAttachmentPath = path.trim();
                          }),
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: Text(
                            t(
                              nl: 'Bestand/PDF kiezen',
                              en: 'Choose file/PDF',
                              fr: 'Choisir fichier/PDF',
                              es: 'Elegir archivo/PDF',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      Builder(
                        builder: (_) =>
                            _isLocalFilesystemPath(selectedAttachmentPath)
                            ? driverDocAttachmentPreview(
                                selectedAttachmentPath,
                                lang,
                              )
                            : const SizedBox.shrink(),
                      ),
                      _sheetField(
                        manualReferenceCtrl,
                        t(
                          nl: 'Handmatig pad / referentie (optioneel)',
                          en: 'Manual path / reference (optional)',
                          fr: 'Chemin manuel (optionnel)',
                          es: 'Ruta manual (opcional)',
                        ),
                        onChanged: () => setLocal(() {}),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _sheetField(
                              expiryCtrl,
                              t(
                                nl: 'Vervaldatum (yyyy-mm-dd)',
                                en: 'Expiry (yyyy-mm-dd)',
                                fr: 'Expiration',
                                es: 'Caducidad',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: t(
                              nl: 'Kies datum',
                              en: 'Pick date',
                              fr: 'Date',
                              es: 'Fecha',
                            ),
                            onPressed: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: now.add(const Duration(days: 365)),
                                firstDate: DateTime(now.year - 10),
                                lastDate: DateTime(now.year + 20),
                              );
                              if (d == null) return;
                              if (!ctx.mounted) return;
                              setLocal(
                                () => expiryCtrl.text =
                                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                              );
                            },
                            icon: const Icon(Icons.calendar_today_outlined),
                          ),
                        ],
                      ),
                      if (!driverSelfService)
                        DropdownButtonFormField<String>(
                          value: selectedStatus,
                          isExpanded: true,
                          items: DriverDocumentStatuses.all
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    driverDocumentStatusLabel(s, lang),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() => selectedStatus = v);
                          },
                          decoration: InputDecoration(
                            labelText: t(
                              nl: 'Status',
                              en: 'Status',
                              fr: 'Statut',
                              es: 'Estado',
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0B0B0B),
                          ),
                          dropdownColor: const Color(0xFF111111),
                        ),
                      if (!driverSelfService) const SizedBox(height: 8),
                      _sheetField(
                        notesCtrl,
                        t(
                          nl: 'Notities',
                          en: 'Notes',
                          fr: 'Notes',
                          es: 'Notas',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                t(
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
                                if (driver.id.trim().isEmpty) return;
                                String shortRef(String value) {
                                  final text = value.trim();
                                  if (text.isEmpty) return 'unknown';
                                  if (text.length <= 4) {
                                    return '…${text.substring(text.length - 1)}';
                                  }
                                  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
                                }

                                final activeCompanyId = DriverDocumentsStore
                                    .instance
                                    .resolvedActiveCompanyIdForDocuments();
                                final driverCompanyId =
                                    driver.companyId?.trim() ?? '';
                                if (activeCompanyId.isNotEmpty &&
                                    driverCompanyId.isNotEmpty &&
                                    driverCompanyId != activeCompanyId) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          t(
                                            nl: 'Deze chauffeur hoort niet bij het actieve bedrijf.',
                                            en: 'This driver does not belong to the active company.',
                                            fr: 'Ce chauffeur n appartient pas a l entreprise active.',
                                            es: 'Este conductor no pertenece a la empresa activa.',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (existing != null &&
                                    activeCompanyId.isNotEmpty &&
                                    existing.companyId.trim() !=
                                        activeCompanyId) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          t(
                                            nl: 'Dit document hoort niet bij het actieve bedrijf.',
                                            en: 'This document does not belong to the active company.',
                                            fr: 'Ce document n appartient pas a l entreprise active.',
                                            es: 'Este documento no pertenece a la empresa activa.',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                var company = DriverDocumentsStore.instance
                                    .resolvedCompanyIdForNewDoc();
                                var tenant = DriverDocumentsStore.instance
                                    .resolvedTenantIdForNewDoc();
                                if (activeCompanyId.isNotEmpty) {
                                  company = activeCompanyId;
                                  if (tenant.trim().isEmpty) {
                                    tenant = activeCompanyId;
                                  }
                                }
                                final resolvedDocId =
                                    existing?.documentId ??
                                    DriverDocumentsStore.newDocumentId();
                                final safeDriverRef = shortRef(driver.id);
                                final safeDocRef = shortRef(resolvedDocId);
                                debugPrint(
                                  '[DRIVER_DOC_EDIT][START] driver=$safeDriverRef doc=$safeDocRef',
                                );

                                final effectiveStatus = driverSelfService
                                    ? (existing?.status ??
                                          DriverDocumentStatuses.pendingReview)
                                    : selectedStatus;

                                final manualReference = manualReferenceCtrl.text
                                    .trim();
                                var path = selectedAttachmentPath.trim();
                                if (manualReference.isNotEmpty &&
                                    !_isLocalFilesystemPath(manualReference)) {
                                  path = manualReference;
                                }
                                if (manualReference.isNotEmpty &&
                                    _isLocalFilesystemPath(manualReference)) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          t(
                                            nl: 'Lokale apparaatpaden zijn niet toegestaan als handmatige referentie.',
                                            en: 'Local device paths are not allowed as manual references.',
                                            fr: 'Les chemins locaux de l appareil ne sont pas autorises comme reference manuelle.',
                                            es: 'Las rutas locales del dispositivo no estan permitidas como referencia manual.',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (path.isNotEmpty) {
                                  final beforePath = path;
                                  if (_isLocalFilesystemPath(path)) {
                                    final persisted = await DriverDocumentsStore
                                        .instance
                                        .persistPickedFileIfNeeded(
                                          sourcePath: path,
                                          documentId: resolvedDocId,
                                          driverId: driver.id,
                                          companyId: company,
                                        );
                                    if (persisted != null) {
                                      path = persisted;
                                    } else if (await File(
                                          beforePath,
                                        ).exists() &&
                                        !DriverDocumentsStore.isPersistedManagedPath(
                                          beforePath,
                                          resolvedDocId,
                                        )) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              t(
                                                nl: 'Kon bestand niet naar permanente opslag kopiëren.',
                                                en: 'Could not copy file to persistent storage.',
                                                fr: 'Impossible de copier le fichier vers le stockage permanent.',
                                                es: 'No se pudo copiar el archivo al almacenamiento persistente.',
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                  }
                                }

                                late final DriverDocument targetDoc;
                                if (existing == null) {
                                  final doc = DriverDocumentsStore.buildNew(
                                    tenantId: tenant,
                                    driverId: driver.id,
                                    documentType: selectedType,
                                    title: titleCtrl.text,
                                    filePath: path,
                                    expiryDate: expiryCtrl.text,
                                    status: effectiveStatus,
                                    notes: notesCtrl.text,
                                    companyId: company,
                                    documentId: resolvedDocId,
                                  );
                                  await DriverDocumentsStore.instance
                                      .addDocument(doc);
                                  DriverDocumentsStore.instance
                                      .markRecentConfirmedDocumentEdit(doc);
                                  debugPrint(
                                    '[DRIVER_DOC_EDIT][DATE_CHANGE] driver=$safeDriverRef doc=$safeDocRef old=none new=${doc.expiryDate.trim().isEmpty ? 'none' : doc.expiryDate.trim()}',
                                  );
                                  debugPrint(
                                    '[DRIVER_DOC_EDIT][LOCAL_SAVE] driver=$safeDriverRef doc=$safeDocRef ok=true',
                                  );
                                  targetDoc = doc;
                                } else {
                                  final doc = DriverDocumentsStore.mergeEdit(
                                    existing: existing,
                                    documentType: selectedType,
                                    title: titleCtrl.text,
                                    filePath: path,
                                    expiryDate: expiryCtrl.text,
                                    status: effectiveStatus,
                                    notes: notesCtrl.text,
                                  );
                                  await DriverDocumentsStore.instance
                                      .updateDocument(doc);
                                  DriverDocumentsStore.instance
                                      .markRecentConfirmedDocumentEdit(doc);
                                  final oldExpiry = existing.expiryDate.trim();
                                  final newExpiry = doc.expiryDate.trim();
                                  debugPrint(
                                    '[DRIVER_DOC_EDIT][DATE_CHANGE] driver=$safeDriverRef doc=$safeDocRef old=${oldExpiry.isEmpty ? 'none' : oldExpiry} new=${newExpiry.isEmpty ? 'none' : newExpiry}',
                                  );
                                  debugPrint(
                                    '[DRIVER_DOC_EDIT][LOCAL_SAVE] driver=$safeDriverRef doc=$safeDocRef ok=true',
                                  );
                                  targetDoc = doc;
                                }
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                debugPrint(
                                  '[DRIVER_DOCS][UI_SYNC_AFTER_SAVE_START] hasScope=${targetDoc.tenantId.trim().isNotEmpty && targetDoc.companyId.trim().isNotEmpty && targetDoc.driverId.trim().isNotEmpty}',
                                );
                                final companySessionToken =
                                    (activeCompanySessionNotifier
                                                .value
                                                ?.companySessionToken ??
                                            '')
                                        .trim();
                                if (companySessionToken.isEmpty) {
                                  debugPrint(
                                    '[DRIVER_DOCS][UI_SYNC_AFTER_SAVE_SKIP] reason=missing_company_session_token',
                                  );
                                  return;
                                }
                                if (targetDoc.tenantId.trim().isEmpty ||
                                    targetDoc.companyId.trim().isEmpty ||
                                    targetDoc.driverId.trim().isEmpty) {
                                  debugPrint(
                                    '[DRIVER_DOCS][UI_SYNC_AFTER_SAVE_SKIP] reason=missing_scope',
                                  );
                                  return;
                                }
                                unawaited(
                                  DriverDocumentsStore.instance
                                      .syncDocumentUpsertToBackend(
                                        doc: targetDoc,
                                        bookingBaseUrl:
                                            appConfig.bookingBaseUrl,
                                        companySessionToken:
                                            companySessionToken,
                                      )
                                      .then((_) {
                                        debugPrint(
                                          '[DRIVER_DOCS][UI_SYNC_AFTER_SAVE_DONE] ok=true',
                                        );
                                        debugPrint(
                                          '[DRIVER_DOC_EDIT][PROPAGATE] driver=$safeDriverRef doc=$safeDocRef updated=true',
                                        );
                                      })
                                      .catchError((error) {
                                        debugPrint(
                                          '[DRIVER_DOCS][UI_SYNC_AFTER_SAVE_DONE] ok=false',
                                        );
                                        debugPrint(
                                          '[DRIVER_DOC_EDIT][FAILED] driver=$safeDriverRef doc=$safeDocRef error=sync_failed',
                                        );
                                      }),
                                );
                              },
                              child: Text(
                                t(
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
          );
        },
      );
    },
  );
}
