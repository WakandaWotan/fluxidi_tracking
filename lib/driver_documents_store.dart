import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_config.dart'
    show
        deleteAdminDriverDocument,
        listAdminDriverDocuments,
        uploadAdminDriverDocument;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

/// MVP chauffeur compliance documents (local-first).
///
/// TODO(backend): Secure storage, encryption, server-side ownership.
/// TODO(admin): Review workflow, expiry alerts, country-specific templates.
/// TODO(access): Role-based document access; never trust client-side companyId alone.
abstract final class DriverDocumentTypes {
  static const drivingLicense = 'driving_license';
  static const taxiDriverCard = 'taxi_driver_card';
  static const medicalCertificate = 'medical_certificate';
  static const goodConduct = 'good_conduct';
  static const identityDocument = 'identity_document';
  static const workPermit = 'work_permit';
  static const postingDeclaration = 'posting_declaration';
  static const other = 'other';

  static const List<String> all = <String>[
    drivingLicense,
    taxiDriverCard,
    medicalCertificate,
    goodConduct,
    identityDocument,
    workPermit,
    postingDeclaration,
    other,
  ];
}

abstract final class DriverDocumentStatuses {
  static const missing = 'missing';
  static const pendingReview = 'pending_review';
  static const approved = 'approved';
  static const expired = 'expired';
  static const rejected = 'rejected';

  static const List<String> all = <String>[
    missing,
    pendingReview,
    approved,
    expired,
    rejected,
  ];
}

String driverDocumentTypeLabel(String type, AppLanguage lang) {
  switch (type) {
    case DriverDocumentTypes.drivingLicense:
      switch (lang) {
        case AppLanguage.nl:
          return 'Rijbewijs';
        case AppLanguage.en:
          return 'Driving license';
        case AppLanguage.fr:
          return 'Permis de conduire';
        case AppLanguage.es:
          return 'Permiso de conducir';
      }
    case DriverDocumentTypes.taxiDriverCard:
      switch (lang) {
        case AppLanguage.nl:
          return 'Bestuurderspas / chauffeurskaart';
        case AppLanguage.en:
          return 'Taxi driver card';
        case AppLanguage.fr:
          return 'Carte professionnelle de chauffeur';
        case AppLanguage.es:
          return 'Tarjeta de conductor de taxi';
      }
    case DriverDocumentTypes.medicalCertificate:
      switch (lang) {
        case AppLanguage.nl:
          return 'Medische keuring';
        case AppLanguage.en:
          return 'Medical certificate';
        case AppLanguage.fr:
          return 'Certificat médical';
        case AppLanguage.es:
          return 'Certificado médico';
      }
    case DriverDocumentTypes.goodConduct:
      switch (lang) {
        case AppLanguage.nl:
          return 'Goed gedrag / VOG / strafregister';
        case AppLanguage.en:
          return 'Good conduct / criminal record';
        case AppLanguage.fr:
          return 'Extrait de casier judiciaire';
        case AppLanguage.es:
          return 'Antecedentes penales / conducta';
      }
    case DriverDocumentTypes.identityDocument:
      switch (lang) {
        case AppLanguage.nl:
          return 'Identiteitsbewijs';
        case AppLanguage.en:
          return 'Identity document';
        case AppLanguage.fr:
          return 'Pièce d\'identité';
        case AppLanguage.es:
          return 'Documento de identidad';
      }
    case DriverDocumentTypes.workPermit:
      switch (lang) {
        case AppLanguage.nl:
          return 'Werkvergunning';
        case AppLanguage.en:
          return 'Work permit';
        case AppLanguage.fr:
          return 'Permis de travail';
        case AppLanguage.es:
          return 'Permiso de trabajo';
      }
    case DriverDocumentTypes.postingDeclaration:
      switch (lang) {
        case AppLanguage.nl:
          return 'Detachering / grensoverschrijdend document';
        case AppLanguage.en:
          return 'Posting / cross-border declaration';
        case AppLanguage.fr:
          return 'Déclaration de détachement / transfrontalière';
        case AppLanguage.es:
          return 'Desplazamiento / declaración transfronteriza';
      }
    default:
      switch (lang) {
        case AppLanguage.nl:
          return 'Overig';
        case AppLanguage.en:
          return 'Other';
        case AppLanguage.fr:
          return 'Autre';
        case AppLanguage.es:
          return 'Otro';
      }
  }
}

String driverDocumentStatusLabel(String status, AppLanguage lang) {
  switch (status) {
    case DriverDocumentStatuses.missing:
      switch (lang) {
        case AppLanguage.nl:
          return 'Ontbreekt';
        case AppLanguage.en:
          return 'Missing';
        case AppLanguage.fr:
          return 'Manquant';
        case AppLanguage.es:
          return 'Falta';
      }
    case DriverDocumentStatuses.pendingReview:
      switch (lang) {
        case AppLanguage.nl:
          return 'In behandeling';
        case AppLanguage.en:
          return 'Under review';
        case AppLanguage.fr:
          return 'En cours de vérification';
        case AppLanguage.es:
          return 'En revisión';
      }
    case DriverDocumentStatuses.approved:
      switch (lang) {
        case AppLanguage.nl:
          return 'Goedgekeurd';
        case AppLanguage.en:
          return 'Approved';
        case AppLanguage.fr:
          return 'Approuvé';
        case AppLanguage.es:
          return 'Aprobado';
      }
    case DriverDocumentStatuses.expired:
      switch (lang) {
        case AppLanguage.nl:
          return 'Verlopen';
        case AppLanguage.en:
          return 'Expired';
        case AppLanguage.fr:
          return 'Expiré';
        case AppLanguage.es:
          return 'Caducado';
      }
    case DriverDocumentStatuses.rejected:
      switch (lang) {
        case AppLanguage.nl:
          return 'Afgewezen';
        case AppLanguage.en:
          return 'Rejected';
        case AppLanguage.fr:
          return 'Rejeté';
        case AppLanguage.es:
          return 'Rechazado';
      }
    default:
      switch (lang) {
        case AppLanguage.nl:
          return 'Onbekend';
        case AppLanguage.en:
          return 'Unknown';
        case AppLanguage.fr:
          return 'Inconnu';
        case AppLanguage.es:
          return 'Desconocido';
      }
  }
}

/// Local JSON row for one chauffeur document.
/// Legacy rows may have empty [companyId].
class DriverDocument {
  const DriverDocument({
    required this.documentId,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.documentType,
    required this.title,
    required this.filePath,
    required this.expiryDate,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.storageState = '',
    this.backendFileName = '',
    this.backendContentType = '',
    this.backendSizeBytes = 0,
    this.backendSyncedAt = '',
    this.backendSyncError = '',
  });

  final String documentId;
  final String tenantId;
  final String companyId;
  final String driverId;
  final String documentType;
  final String title;
  final String filePath;

  /// yyyy-MM-dd or ISO date portion; empty if unknown / none.
  final String expiryDate;
  final String status;
  final String notes;
  final String createdAt;
  final String updatedAt;
  final String storageState;
  final String backendFileName;
  final String backendContentType;
  final int backendSizeBytes;
  final String backendSyncedAt;
  final String backendSyncError;

  static const Set<String> allowedStatusValues = <String>{
    DriverDocumentStatuses.missing,
    DriverDocumentStatuses.pendingReview,
    DriverDocumentStatuses.approved,
    DriverDocumentStatuses.expired,
    DriverDocumentStatuses.rejected,
    'active',
    'verified',
    'archived',
    'pending',
  };

  bool get isExpiredByDate {
    final e = expiryDate.trim();
    if (e.isEmpty) return false;
    final d = DateTime.tryParse(e.length >= 10 ? e.substring(0, 10) : e);
    if (d == null) return false;
    final exp = DateTime(d.year, d.month, d.day);
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return exp.isBefore(today);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'documentId': documentId,
    'tenantId': tenantId,
    'tenant_id': tenantId,
    'companyId': companyId,
    'company_id': companyId,
    'driverId': driverId,
    'driver_id': driverId,
    'documentType': documentType,
    'title': title,
    'filePath': filePath,
    'expiryDate': expiryDate,
    'status': status,
    'notes': notes,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'storageState': storageState,
    'storage_state': storageState,
    'backendFileName': backendFileName,
    'backend_file_name': backendFileName,
    'backendContentType': backendContentType,
    'backend_content_type': backendContentType,
    'backendSizeBytes': backendSizeBytes,
    'backend_size_bytes': backendSizeBytes,
    'backendSyncedAt': backendSyncedAt,
    'backend_synced_at': backendSyncedAt,
    'backendSyncError': backendSyncError,
    'backend_sync_error': backendSyncError,
  };

  factory DriverDocument.fromJson(Map<String, dynamic> m) {
    String readAny(List<String> keys) {
      for (final key in keys) {
        final text = (m[key] ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    int readIntAny(List<String> keys) {
      for (final key in keys) {
        final value = m[key];
        if (value == null) continue;
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value.toString().trim());
        if (parsed != null) return parsed;
      }
      return 0;
    }

    final tenant = readAny(const ['tenantId', 'tenant_id']);
    final company = readAny(const ['companyId', 'company_id']);
    final driver = readAny(const ['driverId', 'driver_id']);
    var type = readAny(const ['documentType', 'document_type']);
    if (type.isEmpty || !DriverDocumentTypes.all.contains(type)) {
      type = DriverDocumentTypes.other;
    }
    var st = readAny(const ['status']).toLowerCase();
    if (st.isEmpty || !allowedStatusValues.contains(st)) {
      st = DriverDocumentStatuses.pendingReview;
    }
    return DriverDocument(
      documentId: () {
        final x = readAny(const ['documentId', 'document_id']);
        if (x.isNotEmpty) return x;
        final dr = driver;
        final tl = readAny(const ['title']);
        return 'ddoc_legacy_${dr.hashCode}_${tl.hashCode}';
      }(),
      tenantId: tenant,
      companyId: company,
      driverId: driver,
      documentType: type,
      title: readAny(const ['title']),
      filePath: readAny(const ['filePath', 'file_path']),
      expiryDate: readAny(const ['expiryDate', 'expiry_date']),
      status: st,
      notes: readAny(const ['notes']),
      createdAt: readAny(const ['createdAt', 'created_at']),
      updatedAt: readAny(const ['updatedAt', 'updated_at']),
      storageState: readAny(const ['storageState', 'storage_state']),
      backendFileName: readAny(const [
        'backendFileName',
        'backend_file_name',
        'file_name',
        'fileName',
      ]),
      backendContentType: readAny(const [
        'backendContentType',
        'backend_content_type',
        'content_type',
        'contentType',
      ]),
      backendSizeBytes: readIntAny(const [
        'backendSizeBytes',
        'backend_size_bytes',
        'size_bytes',
        'sizeBytes',
        'size',
      ]),
      backendSyncedAt: readAny(const ['backendSyncedAt', 'backend_synced_at']),
      backendSyncError: readAny(const [
        'backendSyncError',
        'backend_sync_error',
      ]),
    );
  }

  DriverDocument copyWith({
    String? documentId,
    String? tenantId,
    String? companyId,
    String? driverId,
    String? documentType,
    String? title,
    String? filePath,
    String? expiryDate,
    String? status,
    String? notes,
    String? createdAt,
    String? updatedAt,
    String? storageState,
    String? backendFileName,
    String? backendContentType,
    int? backendSizeBytes,
    String? backendSyncedAt,
    String? backendSyncError,
  }) {
    return DriverDocument(
      documentId: documentId ?? this.documentId,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      driverId: driverId ?? this.driverId,
      documentType: documentType ?? this.documentType,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      storageState: storageState ?? this.storageState,
      backendFileName: backendFileName ?? this.backendFileName,
      backendContentType: backendContentType ?? this.backendContentType,
      backendSizeBytes: backendSizeBytes ?? this.backendSizeBytes,
      backendSyncedAt: backendSyncedAt ?? this.backendSyncedAt,
      backendSyncError: backendSyncError ?? this.backendSyncError,
    );
  }
}

final ValueNotifier<List<DriverDocument>> driverDocumentsNotifier =
    ValueNotifier<List<DriverDocument>>(<DriverDocument>[]);

/// Persists [driverDocumentsNotifier] under app documents.
///
/// TODO: Encrypt at rest; integrate with backend secure vault.
class DriverDocumentsStore {
  DriverDocumentsStore._();
  static final DriverDocumentsStore instance = DriverDocumentsStore._();

  static const String _fileName = 'driver_documents_v1.json';
  static const String _folderName = 'driver_documents';
  static const String _attachmentsFolderName = 'files';

  List<DriverDocument>? _memory;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}$_folderName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _basename(String path) {
    final s = path.replaceAll('\\', '/');
    final i = s.lastIndexOf('/');
    return i >= 0 ? s.substring(i + 1) : s;
  }

  /// Safe folder/file segment for persisted attachment paths.
  static String sanitizePathSegment(String input, {String fallback = '_'}) {
    final t = input.trim();
    if (t.isEmpty) return fallback;
    final b = StringBuffer();
    for (final c in t.split('')) {
      if (RegExp(r'[a-zA-Z0-9._-]').hasMatch(c)) {
        b.write(c);
      } else {
        b.write('_');
      }
    }
    var s = b.toString();
    if (s.length > 96) s = s.substring(0, 96);
    return s.isEmpty ? fallback : s;
  }

  static String _safeOriginalFilename(String sourcePath) {
    final base = _basename(sourcePath);
    final s = sanitizePathSegment(base, fallback: 'file');
    return s.isEmpty ? 'file' : s;
  }

  /// True when [absolutePath] is already under managed storage for [documentId].
  static bool isPersistedManagedPath(String absolutePath, String documentId) {
    final norm = absolutePath.replaceAll('\\', '/');
    if (!norm.contains('/$_folderName/$_attachmentsFolderName/')) return false;
    final fn = _basename(norm);
    final prefix = '${documentId.trim()}_';
    return fn.startsWith(prefix);
  }

  /// Copies a picked or manual file into app documents storage:
  /// `<appDocuments>/driver_documents/files/<company>/<driver>/<documentId>_<safe_name>`
  ///
  /// Returns [sourcePath] when already persisted for [documentId] and the file exists.
  /// Returns the new absolute path after a successful copy.
  /// Returns [null] when the source file does not exist (caller keeps [sourcePath] as-is),
  /// when ids are invalid, or when a copy was attempted but failed.
  Future<String?> persistPickedFileIfNeeded({
    required String sourcePath,
    required String documentId,
    required String driverId,
    required String companyId,
  }) async {
    final srcRaw = sourcePath.trim();
    if (srcRaw.isEmpty) return '';

    final docId = documentId.trim();
    final drvId = driverId.trim();
    if (docId.isEmpty || drvId.isEmpty) return null;

    final existing = File(srcRaw);
    final exists = await existing.exists();

    if (isPersistedManagedPath(srcRaw, docId)) {
      if (exists) return srcRaw;
      return null;
    }

    if (!exists) return null;

    final base = await getApplicationDocumentsDirectory();
    final companySeg = sanitizePathSegment(
      companyId.trim().isEmpty ? '_legacy' : companyId.trim(),
    );
    final driverSeg = sanitizePathSegment(drvId);

    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_folderName${Platform.pathSeparator}$_attachmentsFolderName${Platform.pathSeparator}$companySeg${Platform.pathSeparator}$driverSeg',
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final destName = '${docId}_${_safeOriginalFilename(srcRaw)}';
    final destPath = '${dir.path}${Platform.pathSeparator}$destName';

    try {
      await existing.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// Generates a new stable document id (same as [buildNew] when id omitted).
  static String newDocumentId() => _newDocumentId();

  Future<File> _file() async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}$_fileName');
  }

  static String _newDocumentId() {
    final r = math.Random();
    return 'ddoc_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(999999)}';
  }

  /// Empty/missing file loads as [] without error.
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        driverDocumentsNotifier.value = <DriverDocument>[];
        _memory = driverDocumentsNotifier.value;
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        driverDocumentsNotifier.value = <DriverDocument>[];
        _memory = driverDocumentsNotifier.value;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        driverDocumentsNotifier.value = <DriverDocument>[];
        _memory = driverDocumentsNotifier.value;
        return;
      }
      final list = decoded['documents'];
      if (list is! List) {
        driverDocumentsNotifier.value = <DriverDocument>[];
        _memory = driverDocumentsNotifier.value;
        return;
      }
      final out = <DriverDocument>[];
      var migratedAny = false;
      for (final e in list) {
        if (e is! Map) continue;
        try {
          final parsed = DriverDocument.fromJson(Map<String, dynamic>.from(e));
          final doc = _migrateLegacyScopeIfSafe(parsed);
          if (doc.tenantId != parsed.tenantId ||
              doc.companyId != parsed.companyId) {
            migratedAny = true;
          }
          if (doc.driverId.trim().isEmpty) continue;
          out.add(doc);
        } catch (_) {}
      }
      _memory = out;
      driverDocumentsNotifier.value = List<DriverDocument>.from(out);
      if (migratedAny) {
        await _persist();
      }
    } catch (_) {
      driverDocumentsNotifier.value = <DriverDocument>[];
      _memory = driverDocumentsNotifier.value;
    }
  }

  /// Reload from disk (drops memory snapshot).
  Future<void> reload() async {
    _memory = null;
    await load();
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      final payload = <String, dynamic>{
        'version': 1,
        'documents': driverDocumentsNotifier.value
            .map((e) => e.toJson())
            .toList(),
      };
      await file.writeAsString(jsonEncode(payload));
      _memory = List<DriverDocument>.from(driverDocumentsNotifier.value);
      debugPrint(
        '[DRIVER_DOCS][SAVE] count=${driverDocumentsNotifier.value.length}',
      );
    } catch (_) {}
  }

  ({String tenantId, String companyId}) _activeTenantCompanyScope() {
    final sessionTenant = (activeDriverSessionNotifier.value?.tenantId ?? '')
        .trim();
    final sessionCompany = (activeDriverSessionNotifier.value?.companyId ?? '')
        .trim();
    if (sessionTenant.isNotEmpty && sessionCompany.isNotEmpty) {
      return (tenantId: sessionTenant, companyId: sessionCompany);
    }
    final company = _activeCompanyIdForDocuments().trim();
    if (company.isNotEmpty) {
      return (tenantId: company, companyId: company);
    }
    return (tenantId: '', companyId: '');
  }

  String _activeDriverIdForScope() {
    return (activeDriverSessionNotifier.value?.driverId ?? '').trim();
  }

  DriverDocument _copyWithScope(
    DriverDocument doc, {
    required String tenantId,
    required String companyId,
    String? driverId,
  }) {
    return DriverDocument(
      documentId: doc.documentId,
      tenantId: tenantId.trim(),
      companyId: companyId.trim(),
      driverId: (driverId ?? doc.driverId).trim(),
      documentType: doc.documentType,
      title: doc.title,
      filePath: doc.filePath,
      expiryDate: doc.expiryDate,
      status: doc.status,
      notes: doc.notes,
      createdAt: doc.createdAt,
      updatedAt: doc.updatedAt,
      storageState: doc.storageState,
      backendFileName: doc.backendFileName,
      backendContentType: doc.backendContentType,
      backendSizeBytes: doc.backendSizeBytes,
      backendSyncedAt: doc.backendSyncedAt,
      backendSyncError: doc.backendSyncError,
    );
  }

  String _safeBackendText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.toLowerCase() == 'null') return '';
    return text;
  }

  int _safeBackendInt(dynamic value) {
    if (value is num) return value.toInt();
    final parsed = int.tryParse((value ?? '').toString().trim());
    if (parsed == null) return 0;
    return parsed < 0 ? 0 : parsed;
  }

  String _normalizeBackendStatus(dynamic value) {
    final status = _safeBackendText(value).toLowerCase();
    if (status.isEmpty) return DriverDocumentStatuses.pendingReview;
    if (DriverDocument.allowedStatusValues.contains(status)) return status;
    return DriverDocumentStatuses.pendingReview;
  }

  String _documentScopeKey({
    required String tenantId,
    required String companyId,
    required String driverId,
    required String documentId,
  }) {
    final tenant = tenantId.trim();
    final company = companyId.trim();
    final driver = driverId.trim();
    final doc = documentId.trim();
    if (tenant.isEmpty || company.isEmpty || driver.isEmpty || doc.isEmpty) {
      return '';
    }
    return '$tenant::$company::$driver::$doc';
  }

  DriverDocument? _findByDocumentScope({
    required String tenantId,
    required String companyId,
    required String driverId,
    required String documentId,
  }) {
    final key = _documentScopeKey(
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
      documentId: documentId,
    );
    if (key.isEmpty) return null;
    for (final entry in driverDocumentsNotifier.value) {
      final entryKey = _documentScopeKey(
        tenantId: entry.tenantId,
        companyId: entry.companyId,
        driverId: entry.driverId,
        documentId: entry.documentId,
      );
      if (entryKey == key) return entry;
    }
    return null;
  }

  Future<void> _upsertDocumentAndPersist(DriverDocument doc) async {
    final key = _documentScopeKey(
      tenantId: doc.tenantId,
      companyId: doc.companyId,
      driverId: doc.driverId,
      documentId: doc.documentId,
    );
    if (key.isEmpty) return;
    final out = <DriverDocument>[];
    var replaced = false;
    for (final existing in driverDocumentsNotifier.value) {
      final existingKey = _documentScopeKey(
        tenantId: existing.tenantId,
        companyId: existing.companyId,
        driverId: existing.driverId,
        documentId: existing.documentId,
      );
      if (existingKey == key) {
        out.add(doc);
        replaced = true;
      } else {
        out.add(existing);
      }
    }
    if (!replaced) out.add(doc);
    driverDocumentsNotifier.value = out;
    await _persist();
  }

  DriverDocument _mergeBackendDocumentMetadata({
    required Map<String, dynamic> backend,
    required String tenantId,
    required String companyId,
    required String driverId,
    DriverDocument? existing,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final backendDocumentId = _safeBackendText(
      backend['document_id'] ?? backend['documentId'],
    );
    final resolvedDocumentId = backendDocumentId.isNotEmpty
        ? backendDocumentId
        : (existing?.documentId.trim() ?? '');
    final backendTenant = _safeBackendText(
      backend['tenant_id'] ?? backend['tenantId'],
    );
    final backendCompany = _safeBackendText(
      backend['company_id'] ?? backend['companyId'],
    );
    final backendDriver = _safeBackendText(
      backend['driver_id'] ?? backend['driverId'],
    );
    final backendType = _safeBackendText(
      backend['document_type'] ?? backend['documentType'],
    );
    final backendTitle = _safeBackendText(backend['title']);
    final backendExpiry = _safeBackendText(
      backend['expiry_date'] ?? backend['expiryDate'],
    );
    final backendNotes = _safeBackendText(backend['notes']);
    final backendCreated = _safeBackendText(
      backend['created_at'] ?? backend['createdAt'],
    );
    final backendUpdated = _safeBackendText(
      backend['updated_at'] ?? backend['updatedAt'],
    );
    final backendStorageState = _safeBackendText(
      backend['storage_state'] ?? backend['storageState'],
    );
    final backendFileName = _safeBackendText(
      backend['file_name'] ??
          backend['fileName'] ??
          backend['backend_file_name'],
    );
    final backendContentType = _safeBackendText(
      backend['content_type'] ??
          backend['contentType'] ??
          backend['backend_content_type'],
    );
    final backendSizeBytes = _safeBackendInt(
      backend['size_bytes'] ??
          backend['sizeBytes'] ??
          backend['size'] ??
          backend['backend_size_bytes'] ??
          backend['backendSizeBytes'],
    );

    return DriverDocument(
      documentId: resolvedDocumentId,
      tenantId: backendTenant.isNotEmpty ? backendTenant : tenantId.trim(),
      companyId: backendCompany.isNotEmpty ? backendCompany : companyId.trim(),
      driverId: backendDriver.isNotEmpty ? backendDriver : driverId.trim(),
      documentType: backendType.isNotEmpty
          ? backendType
          : (existing?.documentType ?? DriverDocumentTypes.other),
      title: backendTitle.isNotEmpty ? backendTitle : (existing?.title ?? ''),
      filePath: (existing?.filePath ?? '').trim(),
      expiryDate: backendExpiry.isNotEmpty
          ? backendExpiry
          : (existing?.expiryDate ?? ''),
      status: _normalizeBackendStatus(
        backend['status'] ??
            existing?.status ??
            DriverDocumentStatuses.pendingReview,
      ),
      notes: backendNotes.isNotEmpty ? backendNotes : (existing?.notes ?? ''),
      createdAt: backendCreated.isNotEmpty
          ? backendCreated
          : ((existing?.createdAt ?? '').trim().isNotEmpty
                ? existing!.createdAt
                : nowIso),
      updatedAt: backendUpdated.isNotEmpty
          ? backendUpdated
          : ((existing?.updatedAt ?? '').trim().isNotEmpty
                ? existing!.updatedAt
                : nowIso),
      storageState: backendStorageState.isNotEmpty
          ? backendStorageState
          : (existing?.storageState ?? ''),
      backendFileName: backendFileName.isNotEmpty
          ? backendFileName
          : (existing?.backendFileName ?? ''),
      backendContentType: backendContentType.isNotEmpty
          ? backendContentType
          : (existing?.backendContentType ?? ''),
      backendSizeBytes: backendSizeBytes > 0
          ? backendSizeBytes
          : (existing?.backendSizeBytes ?? 0),
      backendSyncedAt: nowIso,
      backendSyncError: '',
    );
  }

  DriverDocument _withBackendSyncError(DriverDocument doc, String errorCode) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return doc.copyWith(
      backendSyncedAt: nowIso,
      backendSyncError: errorCode.trim().isEmpty
          ? 'sync_failed'
          : errorCode.trim(),
    );
  }

  DriverDocument _migrateLegacyScopeIfSafe(DriverDocument doc) {
    var tenant = doc.tenantId.trim();
    var company = doc.companyId.trim();
    final driver = doc.driverId.trim();
    final activeScope = _activeTenantCompanyScope();
    final activeDriverId = _activeDriverIdForScope();
    var changed = false;

    if (tenant.isEmpty && company.isNotEmpty) {
      tenant = company;
      changed = true;
    }
    if (company.isEmpty && tenant.isNotEmpty) {
      company = tenant;
      changed = true;
    }
    if (tenant.isEmpty &&
        company.isEmpty &&
        activeScope.tenantId.isNotEmpty &&
        activeScope.companyId.isNotEmpty &&
        (activeDriverId.isEmpty || activeDriverId == driver)) {
      tenant = activeScope.tenantId;
      company = activeScope.companyId;
      changed = true;
    }

    if (!changed) return doc;
    return _copyWithScope(doc, tenantId: tenant, companyId: company);
  }

  String _activeCompanyIdForDocuments() {
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    if (profileCompanyId.isNotEmpty) return profileCompanyId;
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompanyId.isNotEmpty) return sessionCompanyId;
    final hasExplicitContext =
        companyProfileNotifier.value != null ||
        activeCompanySessionNotifier.value != null;
    if (hasExplicitContext) {
      final resolved = resolvedCompanyId.trim();
      if (resolved.isNotEmpty) return resolved;
    }
    return '';
  }

  DriverDocument _copyWithCompanyId(DriverDocument doc, String companyId) {
    final cid = companyId.trim();
    if (doc.companyId.trim() == cid) return doc;
    return _copyWithScope(doc, tenantId: cid, companyId: cid);
  }

  /// Exposed for UI-level pre-save guards.
  String resolvedActiveCompanyIdForDocuments() =>
      _activeCompanyIdForDocuments();

  List<DriverDocument> documentsVisibleForDriver(String driverId) {
    final did = driverId.trim();
    final activeScope = _activeTenantCompanyScope();
    final activeDriverId = _activeDriverIdForScope();
    debugPrint(
      '[DRIVER_DOCS][SCOPE] op=visible tenant=${activeScope.tenantId.isNotEmpty} company=${activeScope.companyId.isNotEmpty} activeDriver=${activeDriverId.isNotEmpty}',
    );
    return driverDocumentsNotifier.value
        .where((d) {
          if (d.driverId.trim() != did) return false;
          if (activeDriverId.isNotEmpty &&
              d.driverId.trim() != activeDriverId) {
            return false;
          }
          final tenant = d.tenantId.trim();
          final company = d.companyId.trim();
          if (activeScope.tenantId.isNotEmpty &&
              activeScope.companyId.isNotEmpty) {
            final scopeMatch =
                tenant == activeScope.tenantId &&
                company == activeScope.companyId;
            if (!scopeMatch) {
              debugPrint('[DRIVER_DOCS][LEGACY_HIDDEN] reason=scope_mismatch');
            }
            return scopeMatch;
          }
          if (tenant.isEmpty || company.isEmpty) {
            debugPrint('[DRIVER_DOCS][LEGACY_HIDDEN] reason=missing_scope');
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  /// Driving licence + identity recommended for a simple compliance hint.
  bool hasCoreDocumentGapForDriver(String driverId) {
    final docs = documentsVisibleForDriver(driverId);
    final types = docs.map((e) => e.documentType.trim()).toSet();
    return !types.contains(DriverDocumentTypes.drivingLicense) ||
        !types.contains(DriverDocumentTypes.identityDocument);
  }

  Future<void> addDocument(DriverDocument doc) async {
    final activeScope = _activeTenantCompanyScope();
    final activeDriverId = _activeDriverIdForScope();
    final driverId = doc.driverId.trim();
    final tenantId = doc.tenantId.trim();
    final companyId = doc.companyId.trim();
    debugPrint(
      '[DRIVER_DOCS][SCOPE] op=add hasTenant=${tenantId.isNotEmpty} hasCompany=${companyId.isNotEmpty} hasDriver=${driverId.isNotEmpty}',
    );
    if (driverId.isEmpty || tenantId.isEmpty || companyId.isEmpty) return;
    if (activeScope.tenantId.isNotEmpty &&
        activeScope.companyId.isNotEmpty &&
        (tenantId != activeScope.tenantId ||
            companyId != activeScope.companyId)) {
      return;
    }
    if (activeDriverId.isNotEmpty && driverId != activeDriverId) return;
    final candidate = doc;
    final next = <DriverDocument>[...driverDocumentsNotifier.value, candidate];
    driverDocumentsNotifier.value = next;
    await _persist();
  }

  Future<void> updateDocument(DriverDocument doc) async {
    final activeScope = _activeTenantCompanyScope();
    final activeDriverId = _activeDriverIdForScope();
    final tenantId = doc.tenantId.trim();
    final companyId = doc.companyId.trim();
    final driverId = doc.driverId.trim();
    debugPrint(
      '[DRIVER_DOCS][SCOPE] op=update hasTenant=${tenantId.isNotEmpty} hasCompany=${companyId.isNotEmpty} hasDriver=${driverId.isNotEmpty}',
    );
    if (tenantId.isEmpty || companyId.isEmpty || driverId.isEmpty) return;
    DriverDocument? existing;
    for (final entry in driverDocumentsNotifier.value) {
      if (entry.documentId == doc.documentId) {
        existing = entry;
        break;
      }
    }
    if (existing == null) return;
    if (existing.tenantId.trim() != tenantId ||
        existing.companyId.trim() != companyId ||
        existing.driverId.trim() != driverId) {
      return;
    }
    if (activeScope.tenantId.isNotEmpty &&
        activeScope.companyId.isNotEmpty &&
        (existing.tenantId.trim() != activeScope.tenantId ||
            existing.companyId.trim() != activeScope.companyId)) {
      return;
    }
    if (activeDriverId.isNotEmpty &&
        existing.driverId.trim() != activeDriverId) {
      return;
    }
    final candidate = doc;
    final next = driverDocumentsNotifier.value
        .map((d) => d.documentId == candidate.documentId ? candidate : d)
        .toList(growable: false);
    driverDocumentsNotifier.value = next;
    await _persist();
  }

  Future<void> deleteDocument(String documentId) async {
    final id = documentId.trim();
    final activeScope = _activeTenantCompanyScope();
    final activeDriverId = _activeDriverIdForScope();
    debugPrint('[DRIVER_DOCS][SCOPE] op=delete requested=${id.isNotEmpty}');
    DriverDocument? target;
    for (final entry in driverDocumentsNotifier.value) {
      if (entry.documentId == id) {
        target = entry;
        break;
      }
    }
    if (target == null) return;
    if (activeScope.tenantId.isNotEmpty &&
        activeScope.companyId.isNotEmpty &&
        (target.tenantId.trim() != activeScope.tenantId ||
            target.companyId.trim() != activeScope.companyId)) {
      return;
    }
    if (activeDriverId.isNotEmpty && target.driverId.trim() != activeDriverId) {
      return;
    }
    final next = driverDocumentsNotifier.value
        .where((d) => d.documentId != id)
        .toList(growable: false);
    driverDocumentsNotifier.value = next;
    await _persist();
  }

  Future<DriverDocument?> syncDocumentUpsertToBackend({
    required DriverDocument doc,
    required String bookingBaseUrl,
    required String companySessionToken,
  }) async {
    final tenantId = doc.tenantId.trim();
    final companyId = doc.companyId.trim();
    final driverId = doc.driverId.trim();
    final documentId = doc.documentId.trim();
    final path = doc.filePath.trim();
    debugPrint(
      '[DRIVER_DOCS][BACKEND_UPLOAD_START] hasScope=${tenantId.isNotEmpty && companyId.isNotEmpty && driverId.isNotEmpty} hasDoc=${documentId.isNotEmpty}',
    );

    DriverDocument target =
        _findByDocumentScope(
          tenantId: tenantId,
          companyId: companyId,
          driverId: driverId,
          documentId: documentId,
        ) ??
        doc;

    if (companySessionToken.trim().isEmpty) {
      final withError = _withBackendSyncError(
        target,
        'missing_company_session_token',
      );
      await _upsertDocumentAndPersist(withError);
      debugPrint(
        '[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=missing_company_session_token',
      );
      return null;
    }
    if (tenantId.isEmpty ||
        companyId.isEmpty ||
        driverId.isEmpty ||
        documentId.isEmpty) {
      final withError = _withBackendSyncError(
        target,
        'invalid_scope_or_document_id',
      );
      await _upsertDocumentAndPersist(withError);
      debugPrint(
        '[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=invalid_scope_or_document_id',
      );
      return null;
    }
    if (path.isEmpty || !await File(path).exists()) {
      final withError = _withBackendSyncError(target, 'missing_local_file');
      await _upsertDocumentAndPersist(withError);
      debugPrint(
        '[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=missing_local_file',
      );
      return null;
    }

    try {
      final response = await uploadAdminDriverDocument(
        bookingBaseUrl: bookingBaseUrl,
        companySessionToken: companySessionToken,
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        documentId: documentId,
        documentType: doc.documentType,
        title: doc.title,
        expiryDate: doc.expiryDate,
        status: doc.status,
        notes: doc.notes,
        filePath: path,
      );
      final source = response['document'];
      final metadata = source is Map
          ? Map<String, dynamic>.from(source)
          : Map<String, dynamic>.from(response);
      final merged = _mergeBackendDocumentMetadata(
        backend: metadata,
        tenantId: tenantId,
        companyId: companyId,
        driverId: driverId,
        existing: target,
      );
      await _upsertDocumentAndPersist(merged);
      debugPrint('[DRIVER_DOCS][BACKEND_UPLOAD_OK] ok=true');
      return merged;
    } catch (e) {
      final withError = _withBackendSyncError(target, e.toString());
      await _upsertDocumentAndPersist(withError);
      debugPrint('[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=exception');
      return null;
    }
  }

  Future<void> refreshDriverDocumentsFromBackend({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String tenantId,
    required String companyId,
    required String driverId,
  }) async {
    final scopedTenant = tenantId.trim();
    final scopedCompany = companyId.trim();
    final scopedDriver = driverId.trim();
    debugPrint(
      '[DRIVER_DOCS][BACKEND_REFRESH_START] hasScope=${scopedTenant.isNotEmpty && scopedCompany.isNotEmpty && scopedDriver.isNotEmpty}',
    );
    if (companySessionToken.trim().isEmpty ||
        scopedTenant.isEmpty ||
        scopedCompany.isEmpty ||
        scopedDriver.isEmpty) {
      debugPrint(
        '[DRIVER_DOCS][BACKEND_REFRESH_FAIL] reason=missing_scope_or_token',
      );
      return;
    }

    try {
      final response = await listAdminDriverDocuments(
        bookingBaseUrl: bookingBaseUrl,
        companySessionToken: companySessionToken,
        tenantId: scopedTenant,
        companyId: scopedCompany,
        driverId: scopedDriver,
      );
      final rawItems = response['items'];
      final items = rawItems is List ? rawItems : const <dynamic>[];
      final current = List<DriverDocument>.from(driverDocumentsNotifier.value);
      final byScopedKey = <String, DriverDocument>{};
      for (final entry in current) {
        final scopedKey = _documentScopeKey(
          tenantId: entry.tenantId,
          companyId: entry.companyId,
          driverId: entry.driverId,
          documentId: entry.documentId,
        );
        if (scopedKey.isEmpty) continue;
        byScopedKey[scopedKey] = entry;
      }
      final remoteByScopedKey = <String, DriverDocument>{};
      for (final raw in items) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = _safeBackendText(map['document_id'] ?? map['documentId']);
        if (id.isEmpty) continue;
        final backendTenant = _safeBackendText(
          map['tenant_id'] ?? map['tenantId'],
        );
        final backendCompany = _safeBackendText(
          map['company_id'] ?? map['companyId'],
        );
        final backendDriver = _safeBackendText(
          map['driver_id'] ?? map['driverId'],
        );
        final resolvedTenant = backendTenant.isNotEmpty
            ? backendTenant
            : scopedTenant;
        final resolvedCompany = backendCompany.isNotEmpty
            ? backendCompany
            : scopedCompany;
        final resolvedDriver = backendDriver.isNotEmpty
            ? backendDriver
            : scopedDriver;
        final scopedKey = _documentScopeKey(
          tenantId: resolvedTenant,
          companyId: resolvedCompany,
          driverId: resolvedDriver,
          documentId: id,
        );
        if (scopedKey.isEmpty) continue;
        final merged = _mergeBackendDocumentMetadata(
          backend: map,
          tenantId: scopedTenant,
          companyId: scopedCompany,
          driverId: scopedDriver,
          existing: byScopedKey[scopedKey],
        );
        remoteByScopedKey[scopedKey] = merged;
      }

      final next = <DriverDocument>[];
      final consumed = <String>{};
      for (final local in current) {
        final localScopedKey = _documentScopeKey(
          tenantId: local.tenantId,
          companyId: local.companyId,
          driverId: local.driverId,
          documentId: local.documentId,
        );
        if (localScopedKey.isEmpty) {
          next.add(local);
          continue;
        }
        final remote = remoteByScopedKey[localScopedKey];
        if (remote != null) {
          next.add(remote);
          consumed.add(localScopedKey);
        } else {
          next.add(local);
        }
      }
      for (final entry in remoteByScopedKey.entries) {
        if (consumed.contains(entry.key)) continue;
        next.add(entry.value);
      }

      driverDocumentsNotifier.value = next;
      await _persist();
      debugPrint(
        '[DRIVER_DOCS][BACKEND_REFRESH_OK] remote=${remoteByScopedKey.length} local=${next.length}',
      );
    } catch (_) {
      debugPrint('[DRIVER_DOCS][BACKEND_REFRESH_FAIL] reason=exception');
    }
  }

  bool _matchesExactScope(
    DriverDocument doc, {
    required String tenantId,
    required String companyId,
    required String driverId,
  }) {
    return doc.tenantId.trim() == tenantId.trim() &&
        doc.companyId.trim() == companyId.trim() &&
        doc.driverId.trim() == driverId.trim();
  }

  Future<bool> deleteDocumentInBackendThenLocal({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String tenantId,
    required String companyId,
    required String driverId,
    required String documentId,
  }) async {
    final scopedTenant = tenantId.trim();
    final scopedCompany = companyId.trim();
    final scopedDriver = driverId.trim();
    final id = documentId.trim();
    debugPrint(
      '[DRIVER_DOCS][BACKEND_DELETE_START] hasScope=${scopedTenant.isNotEmpty && scopedCompany.isNotEmpty && scopedDriver.isNotEmpty} hasDoc=${id.isNotEmpty}',
    );
    if (companySessionToken.trim().isEmpty ||
        scopedTenant.isEmpty ||
        scopedCompany.isEmpty ||
        scopedDriver.isEmpty ||
        id.isEmpty) {
      debugPrint(
        '[DRIVER_DOCS][BACKEND_DELETE_FAIL] reason=missing_scope_or_token',
      );
      return false;
    }

    final before = _findByDocumentScope(
      tenantId: scopedTenant,
      companyId: scopedCompany,
      driverId: scopedDriver,
      documentId: id,
    );
    try {
      final out = await deleteAdminDriverDocument(
        bookingBaseUrl: bookingBaseUrl,
        companySessionToken: companySessionToken,
        tenantId: scopedTenant,
        companyId: scopedCompany,
        driverId: scopedDriver,
        documentId: id,
      );
      final ok = out['ok'] == true;
      if (!ok) {
        debugPrint('[DRIVER_DOCS][BACKEND_DELETE_FAIL] reason=backend_not_ok');
        return false;
      }
      await deleteDocument(id);
      final after = _findByDocumentScope(
        tenantId: scopedTenant,
        companyId: scopedCompany,
        driverId: scopedDriver,
        documentId: id,
      );
      final removedLocally = after == null;
      debugPrint('[DRIVER_DOCS][BACKEND_DELETE_OK] ok=$removedLocally');
      return removedLocally || before == null;
    } catch (e) {
      final reason = e.toString();
      if (reason.contains('not_found')) {
        final local = _findByDocumentScope(
          tenantId: scopedTenant,
          companyId: scopedCompany,
          driverId: scopedDriver,
          documentId: id,
        );
        if (local != null &&
            _matchesExactScope(
              local,
              tenantId: scopedTenant,
              companyId: scopedCompany,
              driverId: scopedDriver,
            )) {
          await deleteDocument(id);
          final after = _findByDocumentScope(
            tenantId: scopedTenant,
            companyId: scopedCompany,
            driverId: scopedDriver,
            documentId: id,
          );
          final removed = after == null;
          debugPrint('[DRIVER_DOCS][BACKEND_DELETE_OK] ok=$removed');
          return removed;
        }
      }
      debugPrint('[DRIVER_DOCS][BACKEND_DELETE_FAIL] reason=exception');
      return false;
    }
  }

  /// Default [companyId] when saving new docs under an active local tenant.
  String resolvedCompanyIdForNewDoc() {
    final activeCompanyId = _activeCompanyIdForDocuments();
    if (activeCompanyId.isNotEmpty) return activeCompanyId;
    return companyProfileNotifier.value != null ? resolvedCompanyId : '';
  }

  String resolvedTenantIdForNewDoc() {
    final scope = _activeTenantCompanyScope();
    if (scope.tenantId.isNotEmpty) return scope.tenantId;
    final company = resolvedCompanyIdForNewDoc().trim();
    return company;
  }

  static DriverDocument buildNew({
    required String tenantId,
    required String driverId,
    required String documentType,
    required String title,
    required String filePath,
    required String expiryDate,
    required String status,
    required String notes,
    required String companyId,
    String? documentId,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = documentId?.trim();
    return DriverDocument(
      documentId: (id != null && id.isNotEmpty) ? id : _newDocumentId(),
      tenantId: tenantId.trim(),
      companyId: companyId.trim(),
      driverId: driverId.trim(),
      documentType: documentType.trim().isEmpty
          ? DriverDocumentTypes.other
          : documentType.trim(),
      title: title.trim(),
      filePath: filePath.trim(),
      expiryDate: expiryDate.trim(),
      status: status.trim().isEmpty
          ? DriverDocumentStatuses.pendingReview
          : status.trim(),
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
      storageState: '',
      backendFileName: '',
      backendContentType: '',
      backendSizeBytes: 0,
      backendSyncedAt: '',
      backendSyncError: '',
    );
  }

  static DriverDocument mergeEdit({
    required DriverDocument existing,
    required String documentType,
    required String title,
    required String filePath,
    required String expiryDate,
    required String status,
    required String notes,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return DriverDocument(
      documentId: existing.documentId,
      tenantId: existing.tenantId,
      companyId: existing.companyId,
      driverId: existing.driverId,
      documentType: documentType.trim().isEmpty
          ? DriverDocumentTypes.other
          : documentType.trim(),
      title: title.trim(),
      filePath: filePath.trim(),
      expiryDate: expiryDate.trim(),
      status: status.trim().isEmpty
          ? DriverDocumentStatuses.pendingReview
          : status.trim(),
      notes: notes.trim(),
      createdAt: existing.createdAt,
      updatedAt: now,
      storageState: existing.storageState,
      backendFileName: existing.backendFileName,
      backendContentType: existing.backendContentType,
      backendSizeBytes: existing.backendSizeBytes,
      backendSyncedAt: existing.backendSyncedAt,
      backendSyncError: existing.backendSyncError,
    );
  }
}
