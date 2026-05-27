import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fluxidi_tracking/app_config.dart'
    show
        deleteAdminDriverDocument,
        listAdminDriverDocuments,
        updateAdminDriverDocumentMetadata,
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

abstract final class DriverDocumentComplianceTypes {
  static const drivingLicense = 'driving_license';
  static const driverCard = 'driver_card';
  static const medicalCheck = 'medical_check';
  static const conductCertificate = 'conduct_certificate';
  static const identityDocument = 'identity_document';
  static const workPermit = 'work_permit';
  static const crossBorderDetachment = 'cross_border_detachment';
  static const other = 'other';

  static const List<String> required = <String>[
    drivingLicense,
    driverCard,
    medicalCheck,
    conductCertificate,
    identityDocument,
    workPermit,
    crossBorderDetachment,
  ];
}

class DriverDocumentComplianceSummary {
  const DriverDocumentComplianceSummary({
    this.requiredTotal = 7,
    required this.validRequiredCount,
    required this.uploadedRequiredCount,
    required this.missingRequiredTypeIds,
    required this.expiredRequiredTypeIds,
    required this.pendingRequiredTypeIds,
    required this.rejectedRequiredTypeIds,
    required this.missingAttachmentRequiredTypeIds,
  });

  final int requiredTotal;
  final int validRequiredCount;
  final int uploadedRequiredCount;
  final List<String> missingRequiredTypeIds;
  final List<String> expiredRequiredTypeIds;
  final List<String> pendingRequiredTypeIds;
  final List<String> rejectedRequiredTypeIds;
  final List<String> missingAttachmentRequiredTypeIds;

  bool get hasAllRequiredDocuments => validRequiredCount >= requiredTotal;

  bool get needsAction =>
      !hasAllRequiredDocuments ||
      missingRequiredTypeIds.isNotEmpty ||
      expiredRequiredTypeIds.isNotEmpty ||
      pendingRequiredTypeIds.isNotEmpty ||
      rejectedRequiredTypeIds.isNotEmpty ||
      missingAttachmentRequiredTypeIds.isNotEmpty;
}

class DriverDocumentsRefreshResult {
  const DriverDocumentsRefreshResult({
    required this.ok,
    required this.backendCount,
    required this.localBeforeCount,
    required this.localAfterCount,
    required this.errorCode,
  });

  final bool ok;
  final int backendCount;
  final int localBeforeCount;
  final int localAfterCount;
  final String errorCode;
}

class DriverDocumentsBackfillResult {
  const DriverDocumentsBackfillResult({
    required this.localOnlyCount,
    required this.uploadedCount,
    required this.skippedCount,
    required this.failedCount,
  });

  final int localOnlyCount;
  final int uploadedCount;
  final int skippedCount;
  final int failedCount;
}

String _normalizeDocumentAliasToken(String raw) {
  var out = raw.trim().toLowerCase();
  if (out.isEmpty) return '';
  const replacements = <String, String>{
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  replacements.forEach((k, v) {
    out = out.replaceAll(k, v);
  });
  out = out.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  out = out.replaceAll(RegExp(r'_+'), '_');
  out = out.replaceAll(RegExp(r'^_+|_+$'), '');
  return out;
}

String normalizeDriverDocumentTypeForCompliance({
  required String rawType,
  String? title,
}) {
  final type = _normalizeDocumentAliasToken(rawType);
  final titleKey = _normalizeDocumentAliasToken(title ?? '');
  final keys = <String>[
    if (type.isNotEmpty) type,
    if (titleKey.isNotEmpty) titleKey,
  ];

  bool containsAny(String source, List<String> fragments) {
    for (final fragment in fragments) {
      if (source.contains(fragment)) return true;
    }
    return false;
  }

  for (final key in keys) {
    if (key == DriverDocumentComplianceTypes.drivingLicense ||
        key == DriverDocumentTypes.drivingLicense ||
        containsAny(key, <String>['rijbewijs', 'driving_license', 'permis'])) {
      return DriverDocumentComplianceTypes.drivingLicense;
    }
    if (key == DriverDocumentComplianceTypes.driverCard ||
        key == DriverDocumentTypes.taxiDriverCard ||
        containsAny(key, <String>[
          'driver_card',
          'taxi_driver_card',
          'bestuurderspas',
          'chauffeurskaart',
          'tarjeta_de_conductor',
        ])) {
      return DriverDocumentComplianceTypes.driverCard;
    }
    if (key == DriverDocumentComplianceTypes.medicalCheck ||
        key == DriverDocumentTypes.medicalCertificate ||
        containsAny(key, <String>[
          'medical_check',
          'medical_certificate',
          'medische_keuring',
          'certificat_medical',
        ])) {
      return DriverDocumentComplianceTypes.medicalCheck;
    }
    if (key == DriverDocumentComplianceTypes.conductCertificate ||
        key == DriverDocumentTypes.goodConduct ||
        containsAny(key, <String>[
          'conduct_certificate',
          'good_conduct',
          'vog',
          'strafregister',
          'casier_judiciaire',
          'antecedentes',
        ])) {
      return DriverDocumentComplianceTypes.conductCertificate;
    }
    if (key == DriverDocumentComplianceTypes.identityDocument ||
        key == DriverDocumentTypes.identityDocument ||
        containsAny(key, <String>[
          'identity_document',
          'identiteitsbewijs',
          'identite',
        ])) {
      return DriverDocumentComplianceTypes.identityDocument;
    }
    if (key == DriverDocumentComplianceTypes.workPermit ||
        key == DriverDocumentTypes.workPermit ||
        containsAny(key, <String>[
          'work_permit',
          'werkvergunning',
          'permis_de_travail',
        ])) {
      return DriverDocumentComplianceTypes.workPermit;
    }
    if (key == DriverDocumentComplianceTypes.crossBorderDetachment ||
        key == DriverDocumentTypes.postingDeclaration ||
        containsAny(key, <String>[
          'cross_border_detachment',
          'posting_declaration',
          'detachering',
          'grensoverschrijdend',
          'transfronteriza',
          'detachement',
        ])) {
      return DriverDocumentComplianceTypes.crossBorderDetachment;
    }
    if (key == DriverDocumentComplianceTypes.other ||
        key == DriverDocumentTypes.other ||
        containsAny(key, <String>['overig', 'other', 'autre', 'otro'])) {
      return DriverDocumentComplianceTypes.other;
    }
  }
  return DriverDocumentComplianceTypes.other;
}

bool _driverDocumentExpiryIsPast(String rawDate) {
  final text = rawDate.trim();
  if (text.isEmpty) return false;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return false;
  return parsed.toUtc().isBefore(DateTime.now().toUtc());
}

String driverDocumentArtifactSource(DriverDocument doc) {
  final storageState = doc.storageState.trim().toLowerCase();
  final hasBackendArtifactMetadata =
      storageState == 'stored' &&
      doc.backendFileName.trim().isNotEmpty &&
      doc.backendContentType.trim().isNotEmpty &&
      doc.backendSizeBytes > 0;
  if (hasBackendArtifactMetadata) return 'backend';

  final localPath = doc.filePath.trim();
  if (localPath.isEmpty || kIsWeb) return 'missing';
  try {
    if (File(localPath).existsSync()) return 'local';
  } catch (_) {}
  return 'missing';
}

bool documentHasUsableAttachment(DriverDocument doc) {
  return driverDocumentArtifactSource(doc) != 'missing';
}

DriverDocumentComplianceSummary buildDriverDocumentComplianceSummary(
  Iterable<DriverDocument> documents,
) {
  final grouped = <String, List<DriverDocument>>{};
  for (final doc in documents) {
    final normalizedType = normalizeDriverDocumentTypeForCompliance(
      rawType: doc.documentType,
      title: doc.title,
    );
    if (!DriverDocumentComplianceTypes.required.contains(normalizedType)) {
      continue;
    }
    grouped.putIfAbsent(normalizedType, () => <DriverDocument>[]).add(doc);
  }

  var validRequiredCount = 0;
  var uploadedRequiredCount = 0;
  final missing = <String>[];
  final expired = <String>[];
  final pending = <String>[];
  final rejected = <String>[];
  final missingAttachment = <String>[];

  for (final requiredType in DriverDocumentComplianceTypes.required) {
    final docs = grouped[requiredType] ?? const <DriverDocument>[];
    if (docs.isEmpty) {
      missing.add(requiredType);
      continue;
    }

    uploadedRequiredCount += 1;
    var hasValid = false;
    var hasExpired = false;
    var hasPending = false;
    var hasRejected = false;

    for (final doc in docs) {
      final status = doc.status.trim().toLowerCase();
      final expiryPast = _driverDocumentExpiryIsPast(doc.expiryDate);
      final hasArtifact = documentHasUsableAttachment(doc);
      if (status == DriverDocumentStatuses.approved &&
          !expiryPast &&
          hasArtifact) {
        hasValid = true;
      }
      if (status == DriverDocumentStatuses.approved &&
          !expiryPast &&
          !hasArtifact) {
        missingAttachment.add(requiredType);
      }
      if (status == DriverDocumentStatuses.pendingReview) {
        hasPending = true;
      }
      if (status == DriverDocumentStatuses.rejected) {
        hasRejected = true;
      }
      if (status == DriverDocumentStatuses.expired || expiryPast) {
        hasExpired = true;
      }
    }

    if (hasValid) {
      validRequiredCount += 1;
      continue;
    }
    if (hasExpired) expired.add(requiredType);
    if (hasPending) pending.add(requiredType);
    if (hasRejected) rejected.add(requiredType);
  }

  return DriverDocumentComplianceSummary(
    requiredTotal: DriverDocumentComplianceTypes.required.length,
    validRequiredCount: validRequiredCount,
    uploadedRequiredCount: uploadedRequiredCount,
    missingRequiredTypeIds: missing,
    expiredRequiredTypeIds: expired,
    pendingRequiredTypeIds: pending,
    rejectedRequiredTypeIds: rejected,
    missingAttachmentRequiredTypeIds: missingAttachment.toSet().toList(
      growable: false,
    ),
  );
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
    this.backendPendingDelete = false,
    this.backendPendingUpload = false,
    this.backendLastSyncAttemptAt = '',
    this.backendSyncAttemptCount = 0,
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
  final bool backendPendingDelete;
  final bool backendPendingUpload;
  final String backendLastSyncAttemptAt;
  final int backendSyncAttemptCount;

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
    'backendPendingDelete': backendPendingDelete,
    'backend_pending_delete': backendPendingDelete,
    'backendPendingUpload': backendPendingUpload,
    'backend_pending_upload': backendPendingUpload,
    'backendLastSyncAttemptAt': backendLastSyncAttemptAt,
    'backend_last_sync_attempt_at': backendLastSyncAttemptAt,
    'backendSyncAttemptCount': backendSyncAttemptCount,
    'backend_sync_attempt_count': backendSyncAttemptCount,
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

    bool readBoolAny(List<String> keys) {
      for (final key in keys) {
        final value = m[key];
        if (value == null) continue;
        if (value is bool) return value;
        final text = value.toString().trim().toLowerCase();
        if (text == 'true' || text == '1' || text == 'yes') return true;
        if (text == 'false' || text == '0' || text == 'no') return false;
      }
      return false;
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
      backendPendingDelete: readBoolAny(const [
        'backendPendingDelete',
        'backend_pending_delete',
      ]),
      backendPendingUpload: readBoolAny(const [
        'backendPendingUpload',
        'backend_pending_upload',
      ]),
      backendLastSyncAttemptAt: readAny(const [
        'backendLastSyncAttemptAt',
        'backend_last_sync_attempt_at',
      ]),
      backendSyncAttemptCount: math.max(
        0,
        readIntAny(const [
          'backendSyncAttemptCount',
          'backend_sync_attempt_count',
        ]),
      ),
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
    bool? backendPendingDelete,
    bool? backendPendingUpload,
    String? backendLastSyncAttemptAt,
    int? backendSyncAttemptCount,
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
      backendPendingDelete: backendPendingDelete ?? this.backendPendingDelete,
      backendPendingUpload: backendPendingUpload ?? this.backendPendingUpload,
      backendLastSyncAttemptAt:
          backendLastSyncAttemptAt ?? this.backendLastSyncAttemptAt,
      backendSyncAttemptCount:
          backendSyncAttemptCount ?? this.backendSyncAttemptCount,
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
  final Map<String, ({DriverDocument doc, DateTime atUtc})>
  _recentConfirmedDocumentEditsByScopedKey =
      <String, ({DriverDocument doc, DateTime atUtc})>{};

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

  ({String tenantId, String companyId})?
  _strictActiveTenantCompanyScopeForDocuments() {
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      return null;
    }
    final companyId = profileCompanyId.isNotEmpty
        ? profileCompanyId
        : sessionCompanyId;
    if (companyId.isNotEmpty) {
      return (tenantId: companyId, companyId: companyId);
    }
    final activeDriverSession = activeDriverSessionNotifier.value;
    final driverTenantId = (activeDriverSession?.tenantId ?? '').trim();
    final driverCompanyId = (activeDriverSession?.companyId ?? '').trim();
    final canUseDriverScope =
        driverTenantId.isNotEmpty &&
        driverCompanyId.isNotEmpty &&
        (activeDriverSession?.isVerifiedPairingSession ?? false);
    if (canUseDriverScope) {
      return (tenantId: driverTenantId, companyId: driverCompanyId);
    }
    return null;
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
      backendPendingDelete: doc.backendPendingDelete,
      backendPendingUpload: doc.backendPendingUpload,
      backendLastSyncAttemptAt: doc.backendLastSyncAttemptAt,
      backendSyncAttemptCount: doc.backendSyncAttemptCount,
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

  String _safeSyncErrorCode(String raw, {String fallback = 'sync_failed'}) {
    var out = raw.trim().toLowerCase();
    if (out.isEmpty) return fallback;
    out = out.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    out = out.replaceAll(RegExp(r'_+'), '_');
    out = out.replaceAll(RegExp(r'^_+|_+$'), '');
    if (out.isEmpty) return fallback;
    if (out.length > 64) out = out.substring(0, 64);
    return out;
  }

  String _shortRef(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'unknown';
    if (text.length <= 4) return '…${text.substring(text.length - 1)}';
    return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
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

  void markRecentConfirmedDocumentEdit(DriverDocument doc) {
    final key = _documentScopeKey(
      tenantId: doc.tenantId,
      companyId: doc.companyId,
      driverId: doc.driverId,
      documentId: doc.documentId,
    );
    if (key.isEmpty) return;
    _recentConfirmedDocumentEditsByScopedKey[key] = (
      doc: doc,
      atUtc: DateTime.now().toUtc(),
    );
  }

  List<DriverDocument> _reapplyRecentConfirmedDocumentEdits({
    required List<DriverDocument> docs,
    required String tenantId,
    required String companyId,
    required String driverId,
  }) {
    final now = DateTime.now().toUtc();
    const keepFor = Duration(seconds: 35);
    final staleKeys = <String>[];
    final out = <DriverDocument>[];
    for (final current in docs) {
      final key = _documentScopeKey(
        tenantId: current.tenantId,
        companyId: current.companyId,
        driverId: current.driverId,
        documentId: current.documentId,
      );
      if (key.isEmpty) {
        out.add(current);
        continue;
      }
      final recent = _recentConfirmedDocumentEditsByScopedKey[key];
      if (recent == null) {
        out.add(current);
        continue;
      }
      if (now.difference(recent.atUtc) > keepFor) {
        staleKeys.add(key);
        out.add(current);
        continue;
      }
      final sameScope =
          current.tenantId.trim() == tenantId.trim() &&
          current.companyId.trim() == companyId.trim() &&
          current.driverId.trim() == driverId.trim();
      if (!sameScope) {
        out.add(current);
        continue;
      }
      final backendUpdated = DateTime.tryParse(current.updatedAt.trim());
      if (backendUpdated != null &&
          backendUpdated.toUtc().isAfter(recent.atUtc)) {
        staleKeys.add(key);
        out.add(current);
        continue;
      }
      debugPrint(
        '[DRIVER_DOC_EDIT][STALE_PROTECT] driver=${_shortRef(current.driverId)} doc=${_shortRef(current.documentId)} reason=recent_confirmed_edit',
      );
      out.add(
        current.copyWith(
          documentType: recent.doc.documentType,
          title: recent.doc.title,
          expiryDate: recent.doc.expiryDate,
          status: recent.doc.status,
          notes: recent.doc.notes,
          filePath: recent.doc.filePath,
          updatedAt: recent.doc.updatedAt,
        ),
      );
    }
    for (final key in staleKeys) {
      _recentConfirmedDocumentEditsByScopedKey.remove(key);
    }
    return out;
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
      backend['expiry_date'] ??
          backend['expiryDate'] ??
          backend['expires_at'] ??
          backend['expiresAt'] ??
          backend['valid_until'] ??
          backend['validUntil'],
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
      backendPendingDelete: existing?.backendPendingDelete ?? false,
      backendPendingUpload: false,
      backendLastSyncAttemptAt: existing?.backendLastSyncAttemptAt ?? '',
      backendSyncAttemptCount: existing?.backendSyncAttemptCount ?? 0,
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

  List<DriverDocument> documentsVisibleForCompanyAdminDriver(
    String driverId, {
    required String tenantId,
    required String companyId,
  }) {
    final did = driverId.trim();
    final scopedTenant = tenantId.trim();
    final scopedCompany = companyId.trim();
    if (did.isEmpty || scopedTenant.isEmpty || scopedCompany.isEmpty) {
      return const <DriverDocument>[];
    }
    return driverDocumentsNotifier.value
        .where((d) {
          if (d.driverId.trim() != did) return false;
          return d.tenantId.trim() == scopedTenant &&
              d.companyId.trim() == scopedCompany;
        })
        .toList(growable: false);
  }

  DriverDocumentComplianceSummary complianceSummaryForDocuments(
    Iterable<DriverDocument> docs,
  ) {
    return buildDriverDocumentComplianceSummary(docs);
  }

  DriverDocumentComplianceSummary complianceSummaryForCompanyAdminDriver(
    String driverId, {
    required String tenantId,
    required String companyId,
  }) {
    final docs = documentsVisibleForCompanyAdminDriver(
      driverId,
      tenantId: tenantId,
      companyId: companyId,
    );
    return complianceSummaryForDocuments(docs);
  }

  /// Driving licence + identity recommended for a simple compliance hint.
  bool hasCoreDocumentGapForDriver(String driverId) {
    final docs = documentsVisibleForDriver(driverId);
    final types = docs.map((e) => e.documentType.trim()).toSet();
    return !types.contains(DriverDocumentTypes.drivingLicense) ||
        !types.contains(DriverDocumentTypes.identityDocument);
  }

  bool hasCoreDocumentGapForCompanyAdminDriver(
    String driverId, {
    required String tenantId,
    required String companyId,
  }) {
    final docs = documentsVisibleForCompanyAdminDriver(
      driverId,
      tenantId: tenantId,
      companyId: companyId,
    );
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
    markRecentConfirmedDocumentEdit(candidate);
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
    markRecentConfirmedDocumentEdit(candidate);
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
    final safeDriverRef = _shortRef(driverId);
    final safeDocRef = _shortRef(documentId);
    debugPrint(
      '[DRIVER_DOCS][BACKEND_UPLOAD_START] hasScope=${tenantId.isNotEmpty && companyId.isNotEmpty && driverId.isNotEmpty} hasDoc=${documentId.isNotEmpty}',
    );
    debugPrint(
      '[DRIVER_DOC_EDIT][START] driver=$safeDriverRef doc=$safeDocRef',
    );

    DriverDocument target =
        _findByDocumentScope(
          tenantId: tenantId,
          companyId: companyId,
          driverId: driverId,
          documentId: documentId,
        ) ??
        doc;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    target = target.copyWith(
      backendPendingUpload: true,
      backendLastSyncAttemptAt: nowIso,
      backendSyncAttemptCount: target.backendSyncAttemptCount + 1,
    );
    await _upsertDocumentAndPersist(target);
    final strictScope = _strictActiveTenantCompanyScopeForDocuments();
    final hasStrictScope = strictScope != null;
    final hasMatchingStrictScope =
        hasStrictScope &&
        tenantId.isNotEmpty &&
        companyId.isNotEmpty &&
        tenantId == strictScope.tenantId &&
        companyId == strictScope.companyId;
    if (!hasMatchingStrictScope) {
      final withError = target.copyWith(
        backendPendingUpload: true,
        backendSyncError: 'missing_strict_company_scope',
      );
      await _upsertDocumentAndPersist(withError);
      debugPrint(
        '[DRIVER_DOCUMENT_SCOPE][BLOCK] reason=missing_strict_company_scope action=sync_document_upsert',
      );
      return null;
    }

    if (companySessionToken.trim().isEmpty) {
      final withError = target.copyWith(
        backendPendingUpload: true,
        backendSyncError: 'missing_company_session_token',
      );
      await _upsertDocumentAndPersist(withError);
      debugPrint(
        '[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=missing_company_session_token',
      );
      debugPrint(
        '[DRIVER_DOC_EDIT][FAILED] driver=$safeDriverRef doc=$safeDocRef error=missing_company_session_token',
      );
      return null;
    }
    if (tenantId.isEmpty ||
        companyId.isEmpty ||
        driverId.isEmpty ||
        documentId.isEmpty) {
      final withError = target.copyWith(
        backendPendingUpload: true,
        backendSyncError: 'invalid_scope_or_document_id',
      );
      await _upsertDocumentAndPersist(withError);
      debugPrint(
        '[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=invalid_scope_or_document_id',
      );
      debugPrint(
        '[DRIVER_DOC_EDIT][FAILED] driver=$safeDriverRef doc=$safeDocRef error=invalid_scope_or_document_id',
      );
      return null;
    }
    final hasLocalFile = path.isNotEmpty && await File(path).exists();
    final hasBackendArtifactMetadata =
        target.storageState.trim().toLowerCase() == 'stored' &&
        target.backendFileName.trim().isNotEmpty &&
        target.backendContentType.trim().isNotEmpty &&
        target.backendSizeBytes > 0;

    try {
      late final Map<String, dynamic> response;
      if (hasLocalFile) {
        debugPrint(
          '[DRIVER_DOC_EDIT][BACKEND_REQUEST] driver=$safeDriverRef doc=$safeDocRef endpoint=/admin/driver-documents/upload fields=tenant_id,company_id,driver_id,document_id,document_type,title,expiry_date,status,notes,file',
        );
        response = await uploadAdminDriverDocument(
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
        debugPrint(
          '[DRIVER_DOC_EDIT][BACKEND_RESPONSE] driver=$safeDriverRef doc=$safeDocRef status=200 ok=true',
        );
      } else if (hasBackendArtifactMetadata) {
        debugPrint(
          '[DRIVER_DOC_EDIT][BACKEND_REQUEST] driver=$safeDriverRef doc=$safeDocRef endpoint=/admin/driver-documents/update fields=tenant_id,company_id,driver_id,document_id,document_type,title,expiry_date,status,notes',
        );
        response = await updateAdminDriverDocumentMetadata(
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
        );
        debugPrint(
          '[DRIVER_DOC_EDIT][BACKEND_RESPONSE] driver=$safeDriverRef doc=$safeDocRef status=200 ok=true',
        );
      } else {
        final withError = target.copyWith(
          backendPendingUpload: true,
          backendSyncError: 'missing_local_file',
        );
        await _upsertDocumentAndPersist(withError);
        markRecentConfirmedDocumentEdit(withError);
        debugPrint(
          '[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=missing_local_file',
        );
        debugPrint(
          '[DRIVER_DOC_EDIT][FAILED] driver=$safeDriverRef doc=$safeDocRef error=missing_local_file',
        );
        return null;
      }
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
      final persisted = merged.copyWith(
        backendPendingUpload: false,
        backendSyncError: '',
        backendSyncedAt: DateTime.now().toUtc().toIso8601String(),
        backendLastSyncAttemptAt: nowIso,
        backendSyncAttemptCount: target.backendSyncAttemptCount,
      );
      await _upsertDocumentAndPersist(persisted);
      markRecentConfirmedDocumentEdit(persisted);
      debugPrint('[DRIVER_DOCS][BACKEND_UPLOAD_OK] ok=true');
      return persisted;
    } catch (e) {
      final withError = target.copyWith(
        backendPendingUpload: true,
        backendSyncError: _safeSyncErrorCode(e.toString()),
      );
      await _upsertDocumentAndPersist(withError);
      debugPrint('[DRIVER_DOCS][BACKEND_UPLOAD_FAIL] reason=exception');
      debugPrint(
        '[DRIVER_DOC_EDIT][FAILED] driver=$safeDriverRef doc=$safeDocRef error=${_safeSyncErrorCode(e.toString())}',
      );
      return null;
    }
  }

  Future<DriverDocumentsBackfillResult>
  backfillLocalDriverDocumentsToBackendForDriver({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String tenantId,
    required String companyId,
    required String driverId,
  }) async {
    final scopedTenant = tenantId.trim();
    final scopedCompany = companyId.trim();
    final scopedDriver = driverId.trim();
    final safeDriverRef = _shortRef(scopedDriver);
    debugPrint('[DRIVER_DOCS_BACKFILL][START] driver=$safeDriverRef');

    if (companySessionToken.trim().isEmpty ||
        scopedTenant.isEmpty ||
        scopedCompany.isEmpty ||
        scopedDriver.isEmpty) {
      debugPrint(
        '[DRIVER_DOCS_BACKFILL][DONE] driver=$safeDriverRef uploaded=0 skipped=0 failed=0',
      );
      return const DriverDocumentsBackfillResult(
        localOnlyCount: 0,
        uploadedCount: 0,
        skippedCount: 0,
        failedCount: 0,
      );
    }

    final allForDriver = driverDocumentsNotifier.value
        .where((doc) => doc.driverId.trim() == scopedDriver)
        .toList(growable: false);
    final scopedKeySet = <String>{
      for (final doc in allForDriver)
        _documentScopeKey(
          tenantId: doc.tenantId,
          companyId: doc.companyId,
          driverId: doc.driverId,
          documentId: doc.documentId,
        ),
    };
    for (final doc in allForDriver) {
      final tenant = doc.tenantId.trim();
      final company = doc.companyId.trim();
      final isScoped = tenant == scopedTenant && company == scopedCompany;
      if (isScoped) continue;
      final canMigrate =
          (tenant.isEmpty || company.isEmpty) &&
          doc.documentId.trim().isNotEmpty;
      final safeDocRef = _shortRef(doc.documentId);
      debugPrint(
        '[DRIVER_DOCS_BACKFILL][LEGACY_CANDIDATE] driver=$safeDriverRef doc=$safeDocRef reason=${canMigrate ? 'missing_scope' : 'scope_mismatch'}',
      );
      if (!canMigrate) continue;
      final targetKey = _documentScopeKey(
        tenantId: scopedTenant,
        companyId: scopedCompany,
        driverId: scopedDriver,
        documentId: doc.documentId,
      );
      if (targetKey.isEmpty || scopedKeySet.contains(targetKey)) continue;
      debugPrint(
        '[DRIVER_DOCS_BACKFILL][MIGRATE_START] driver=$safeDriverRef doc=$safeDocRef',
      );
      final migrated = doc.copyWith(
        tenantId: scopedTenant,
        companyId: scopedCompany,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await _upsertDocumentAndPersist(migrated);
      markRecentConfirmedDocumentEdit(migrated);
      scopedKeySet.add(targetKey);
      debugPrint(
        '[DRIVER_DOCS_BACKFILL][MIGRATE_DONE] driver=$safeDriverRef doc=$safeDocRef',
      );
    }

    final scopedDocs = driverDocumentsNotifier.value
        .where(
          (doc) =>
              doc.tenantId.trim() == scopedTenant &&
              doc.companyId.trim() == scopedCompany &&
              doc.driverId.trim() == scopedDriver,
        )
        .toList(growable: false);
    final localOnlyDocs = scopedDocs
        .where((doc) {
          final storage = doc.storageState.trim().toLowerCase();
          final backendArtifact =
              storage == 'stored' &&
              doc.backendFileName.trim().isNotEmpty &&
              doc.backendContentType.trim().isNotEmpty &&
              doc.backendSizeBytes > 0;
          return !backendArtifact;
        })
        .toList(growable: false);
    debugPrint(
      '[DRIVER_DOCS_BACKFILL][LOCAL_ONLY] driver=$safeDriverRef count=${localOnlyDocs.length}',
    );

    var uploaded = 0;
    var skipped = 0;
    var failed = 0;
    var reuploadRequired = 0;
    for (final doc in localOnlyDocs) {
      final safeDocRef = _shortRef(doc.documentId);
      final localPath = doc.filePath.trim();
      final hasLocalFile =
          localPath.isNotEmpty && await File(localPath).exists();
      if (!hasLocalFile) {
        skipped++;
        reuploadRequired++;
        await _upsertDocumentAndPersist(
          doc.copyWith(
            backendPendingUpload: true,
            backendSyncError: 'missing_local_file_for_backfill',
            backendLastSyncAttemptAt: DateTime.now().toUtc().toIso8601String(),
            backendSyncAttemptCount: doc.backendSyncAttemptCount + 1,
          ),
        );
        debugPrint(
          '[DRIVER_DOCS_BACKFILL][SKIP_NO_FILE] driver=$safeDriverRef doc=$safeDocRef',
        );
        debugPrint(
          '[DRIVER_DOCS_BACKFILL][REUPLOAD_REQUIRED] driver=$safeDriverRef doc=$safeDocRef reason=missing_local_file',
        );
        continue;
      }
      debugPrint(
        '[DRIVER_DOCS_BACKFILL][UPLOAD_START] driver=$safeDriverRef doc=$safeDocRef',
      );
      try {
        final out = await syncDocumentUpsertToBackend(
          doc: doc,
          bookingBaseUrl: bookingBaseUrl,
          companySessionToken: companySessionToken,
        );
        if (out == null) {
          failed++;
          debugPrint(
            '[DRIVER_DOCS_BACKFILL][UPLOAD_FAILED] driver=$safeDriverRef doc=$safeDocRef error=upload_not_ok',
          );
        } else {
          uploaded++;
          debugPrint(
            '[DRIVER_DOCS_BACKFILL][UPLOAD_DONE] driver=$safeDriverRef doc=$safeDocRef',
          );
        }
      } catch (e) {
        failed++;
        debugPrint(
          '[DRIVER_DOCS_BACKFILL][UPLOAD_FAILED] driver=$safeDriverRef doc=$safeDocRef error=${_safeSyncErrorCode(e.toString())}',
        );
      }
    }
    if (reuploadRequired > 0) {
      debugPrint(
        '[DRIVER_DOCS_BACKFILL][SOURCE_DEVICE_REQUIRED] driver=$safeDriverRef count=$reuploadRequired',
      );
    }
    debugPrint(
      '[DRIVER_DOCS_BACKFILL][DONE] driver=$safeDriverRef uploaded=$uploaded skipped=$skipped failed=$failed',
    );
    return DriverDocumentsBackfillResult(
      localOnlyCount: localOnlyDocs.length,
      uploadedCount: uploaded,
      skippedCount: skipped,
      failedCount: failed,
    );
  }

  Future<bool> refreshDriverDocumentsFromBackend({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String tenantId,
    required String companyId,
    required String driverId,
  }) async {
    final result = await refreshDriverDocumentsFromBackendDetailed(
      bookingBaseUrl: bookingBaseUrl,
      companySessionToken: companySessionToken,
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
    );
    return result.ok;
  }

  Future<DriverDocumentsRefreshResult>
  refreshDriverDocumentsFromBackendDetailed({
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
    final localBeforeCount = driverDocumentsNotifier.value
        .where(
          (entry) =>
              entry.tenantId.trim() == scopedTenant &&
              entry.companyId.trim() == scopedCompany &&
              entry.driverId.trim() == scopedDriver,
        )
        .length;
    if (companySessionToken.trim().isEmpty ||
        scopedTenant.isEmpty ||
        scopedCompany.isEmpty ||
        scopedDriver.isEmpty) {
      debugPrint(
        '[DRIVER_DOCS][BACKEND_REFRESH_FAIL] reason=missing_scope_or_token',
      );
      return DriverDocumentsRefreshResult(
        ok: false,
        backendCount: 0,
        localBeforeCount: localBeforeCount,
        localAfterCount: localBeforeCount,
        errorCode: 'missing_scope_or_token',
      );
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

      final protectedNext = _reapplyRecentConfirmedDocumentEdits(
        docs: next,
        tenantId: scopedTenant,
        companyId: scopedCompany,
        driverId: scopedDriver,
      );
      driverDocumentsNotifier.value = protectedNext;
      await _persist();
      final localAfterCount = protectedNext
          .where(
            (entry) =>
                entry.tenantId.trim() == scopedTenant &&
                entry.companyId.trim() == scopedCompany &&
                entry.driverId.trim() == scopedDriver,
          )
          .length;
      debugPrint(
        '[DRIVER_DOCS][BACKEND_REFRESH_OK] remote=${remoteByScopedKey.length} local=${next.length}',
      );
      return DriverDocumentsRefreshResult(
        ok: true,
        backendCount: items.length,
        localBeforeCount: localBeforeCount,
        localAfterCount: localAfterCount,
        errorCode: '',
      );
    } catch (_) {
      debugPrint('[DRIVER_DOCS][BACKEND_REFRESH_FAIL] reason=exception');
      return DriverDocumentsRefreshResult(
        ok: false,
        backendCount: 0,
        localBeforeCount: localBeforeCount,
        localAfterCount: localBeforeCount,
        errorCode: 'exception',
      );
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

  Future<void> retryPendingDriverDocumentSync({
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
      '[DRIVER_DOCS][BACKEND_RETRY_START] hasScope=${scopedTenant.isNotEmpty && scopedCompany.isNotEmpty && scopedDriver.isNotEmpty}',
    );
    if (companySessionToken.trim().isEmpty ||
        scopedTenant.isEmpty ||
        scopedCompany.isEmpty ||
        scopedDriver.isEmpty) {
      debugPrint(
        '[DRIVER_DOCS][BACKEND_RETRY_SKIP] reason=missing_scope_or_token',
      );
      return;
    }
    final scopedDocs = driverDocumentsNotifier.value
        .where(
          (doc) => _matchesExactScope(
            doc,
            tenantId: scopedTenant,
            companyId: scopedCompany,
            driverId: scopedDriver,
          ),
        )
        .toList(growable: false);
    for (final doc in scopedDocs) {
      final hasSyncError = doc.backendSyncError.trim().isNotEmpty;
      if (doc.backendPendingDelete) {
        debugPrint('[DRIVER_DOCS][BACKEND_RETRY_DELETE] queued=true');
        try {
          await deleteDocumentInBackendThenLocal(
            bookingBaseUrl: bookingBaseUrl,
            companySessionToken: companySessionToken,
            tenantId: scopedTenant,
            companyId: scopedCompany,
            driverId: scopedDriver,
            documentId: doc.documentId,
          );
        } catch (_) {
          // Best-effort: leave local pending marker.
        }
        continue;
      }
      if (!doc.backendPendingUpload && !hasSyncError) continue;

      final path = doc.filePath.trim();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (path.isEmpty || !await File(path).exists()) {
        final updated = doc.copyWith(
          backendPendingUpload: true,
          backendLastSyncAttemptAt: nowIso,
          backendSyncAttemptCount: doc.backendSyncAttemptCount + 1,
          backendSyncError: 'missing_local_file_for_retry',
        );
        await _upsertDocumentAndPersist(updated);
        debugPrint(
          '[DRIVER_DOCS][BACKEND_RETRY_SKIP] reason=missing_local_file_for_retry',
        );
        continue;
      }
      debugPrint('[DRIVER_DOCS][BACKEND_RETRY_UPLOAD] queued=true');
      try {
        await syncDocumentUpsertToBackend(
          doc: doc,
          bookingBaseUrl: bookingBaseUrl,
          companySessionToken: companySessionToken,
        );
      } catch (_) {
        // Best-effort: upload method persists failure state.
      }
    }
    debugPrint('[DRIVER_DOCS][BACKEND_RETRY_DONE] ok=true');
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
      final outError = _safeBackendText(
        out['error'] ?? out['code'] ?? out['message'],
      ).toLowerCase();
      final backendNotFound =
          outError.contains('not_found') || outError.contains('404');
      if (backendNotFound &&
          before != null &&
          _matchesExactScope(
            before,
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
      if (!ok) {
        if (before != null &&
            _matchesExactScope(
              before,
              tenantId: scopedTenant,
              companyId: scopedCompany,
              driverId: scopedDriver,
            )) {
          final pendingDelete = before.copyWith(
            backendPendingDelete: true,
            backendPendingUpload: false,
            backendLastSyncAttemptAt: DateTime.now().toUtc().toIso8601String(),
            backendSyncAttemptCount: before.backendSyncAttemptCount + 1,
            backendSyncError: 'delete_pending',
          );
          await _upsertDocumentAndPersist(pendingDelete);
        }
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
      if (before != null &&
          _matchesExactScope(
            before,
            tenantId: scopedTenant,
            companyId: scopedCompany,
            driverId: scopedDriver,
          )) {
        final pendingDelete = before.copyWith(
          backendPendingDelete: true,
          backendPendingUpload: false,
          backendLastSyncAttemptAt: DateTime.now().toUtc().toIso8601String(),
          backendSyncAttemptCount: before.backendSyncAttemptCount + 1,
          backendSyncError: 'delete_pending',
        );
        await _upsertDocumentAndPersist(pendingDelete);
      }
      debugPrint('[DRIVER_DOCS][BACKEND_DELETE_FAIL] reason=exception');
      return false;
    }
  }

  /// Default [companyId] when saving new docs under an active local tenant.
  String resolvedCompanyIdForNewDoc() {
    final strictScope = _strictActiveTenantCompanyScopeForDocuments();
    return strictScope?.companyId ?? '';
  }

  String resolvedTenantIdForNewDoc() {
    final strictScope = _strictActiveTenantCompanyScopeForDocuments();
    return strictScope?.tenantId ?? '';
  }

  ({String tenantId, String companyId})? strictActiveScopeForNewDoc() {
    return _strictActiveTenantCompanyScopeForDocuments();
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
      backendPendingDelete: false,
      backendPendingUpload: false,
      backendLastSyncAttemptAt: '',
      backendSyncAttemptCount: 0,
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
      backendPendingDelete: existing.backendPendingDelete,
      backendPendingUpload: existing.backendPendingUpload,
      backendLastSyncAttemptAt: existing.backendLastSyncAttemptAt,
      backendSyncAttemptCount: existing.backendSyncAttemptCount,
    );
  }
}
