import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

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
          return 'Certificado medico';
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
          return 'Desplazamiento / declaracion transfronteriza';
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
      return status;
  }
}

/// Local JSON row for one chauffeur document.
/// Legacy rows may have empty [companyId].
class DriverDocument {
  const DriverDocument({
    required this.documentId,
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
  });

  final String documentId;
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
    'companyId': companyId,
    'driverId': driverId,
    'documentType': documentType,
    'title': title,
    'filePath': filePath,
    'expiryDate': expiryDate,
    'status': status,
    'notes': notes,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory DriverDocument.fromJson(Map<String, dynamic> m) {
    String r(String k) => (m[k] ?? '').toString();
    final tid = r('tenantId');
    final cid = r('companyId');
    final company = cid.isNotEmpty ? cid : tid;
    var type = r('documentType').trim();
    if (type.isEmpty || !DriverDocumentTypes.all.contains(type)) {
      type = DriverDocumentTypes.other;
    }
    var st = r('status').trim();
    if (st.isEmpty || !DriverDocumentStatuses.all.contains(st)) {
      st = DriverDocumentStatuses.pendingReview;
    }
    return DriverDocument(
      documentId: () {
        final x = r('documentId').trim();
        if (x.isNotEmpty) return x;
        final dr = r('driverId');
        final tl = r('title');
        return 'ddoc_legacy_${dr.hashCode}_${tl.hashCode}';
      }(),
      companyId: company,
      driverId: r('driverId'),
      documentType: type,
      title: r('title'),
      filePath: r('filePath'),
      expiryDate: r('expiryDate'),
      status: st,
      notes: r('notes'),
      createdAt: r('createdAt'),
      updatedAt: r('updatedAt'),
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
      for (final e in list) {
        if (e is! Map) continue;
        try {
          final doc = DriverDocument.fromJson(Map<String, dynamic>.from(e));
          if (doc.driverId.trim().isEmpty) continue;
          out.add(doc);
        } catch (_) {}
      }
      _memory = out;
      driverDocumentsNotifier.value = List<DriverDocument>.from(out);
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
    } catch (_) {}
  }

  List<DriverDocument> documentsVisibleForDriver(String driverId) {
    final did = driverId.trim();
    final rid = resolvedCompanyId.trim();
    return driverDocumentsNotifier.value
        .where((d) {
          if (d.driverId.trim() != did) return false;
          final c = d.companyId.trim();
          if (c.isEmpty) return true;
          return c == rid;
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
    if (doc.driverId.trim().isEmpty) return;
    final next = <DriverDocument>[...driverDocumentsNotifier.value, doc];
    driverDocumentsNotifier.value = next;
    await _persist();
  }

  Future<void> updateDocument(DriverDocument doc) async {
    if (doc.driverId.trim().isEmpty) return;
    final next = driverDocumentsNotifier.value
        .map((d) => d.documentId == doc.documentId ? doc : d)
        .toList(growable: false);
    driverDocumentsNotifier.value = next;
    await _persist();
  }

  Future<void> deleteDocument(String documentId) async {
    final id = documentId.trim();
    final next = driverDocumentsNotifier.value
        .where((d) => d.documentId != id)
        .toList(growable: false);
    driverDocumentsNotifier.value = next;
    await _persist();
  }

  /// Default [companyId] when saving new docs under an active local tenant.
  String resolvedCompanyIdForNewDoc() =>
      companyProfileNotifier.value != null ? resolvedCompanyId : '';

  static DriverDocument buildNew({
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
    );
  }
}
