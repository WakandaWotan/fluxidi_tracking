// FLUXIDI-CANONICAL-DOCUMENT-AND-EMAIL-BRANDING-SOURCE-OF-TRUTH-P0-1
//
// Loads bytes for the Branding & support company logo for document PDFs.
// Field bug: receipt PDF loaders only understood file/asset paths, so after
// bootstrap stored an https company logo URL they fell through to the packaged
// Fluxidi mark.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'company_logo_ref.dart';

/// Max bytes accepted when fetching a company logo for a document PDF.
const int kDocumentCompanyLogoMaxBytes = 2 * 1024 * 1024;

/// Resolve the logo used on operational documents (receipts / credit / refund).
///
/// Branding & support (`localPath`) wins. The company media URL (same Branding
/// upload mirrored on the business profile) is the only secondary source.
/// Theme/gallery artwork must never be passed here.
CompanyLogoRef resolveDocumentCompanyLogoRef({
  String localPath = '',
  String companyLogoUrl = '',
  String? configuredFluxidiAsset,
  String fluxidiFallbackAsset = kPackagedFluxidiLogoAsset,
  bool Function(String path)? fileExists,
  String Function(String raw)? resolvePublicUrl,
  bool isWeb = kIsWeb,
}) {
  return resolveCompanyLogoRef(
    localPath: localPath,
    publicUrl: companyLogoUrl,
    configuredFluxidiAsset: configuredFluxidiAsset,
    fluxidiFallbackAsset: fluxidiFallbackAsset,
    fileExists: fileExists,
    resolvePublicUrl: resolvePublicUrl,
    isWeb: isWeb,
  );
}

/// Load renderer-safe logo bytes for [resolved]. Never throws.
Future<Uint8List?> loadCompanyLogoBytes(
  CompanyLogoRef resolved, {
  http.Client? httpClient,
  int maxBytes = kDocumentCompanyLogoMaxBytes,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (!resolved.isRenderable) return null;
  try {
    switch (resolved.kind) {
      case CompanyLogoRefKind.asset:
        final data = await rootBundle.load(resolved.ref);
        final bytes = data.buffer.asUint8List();
        if (bytes.isEmpty || bytes.length > maxBytes) return null;
        return bytes;
      case CompanyLogoRefKind.file:
        if (kIsWeb) return null;
        final file = File(resolved.ref);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > maxBytes) return null;
        return Uint8List.fromList(bytes);
      case CompanyLogoRefKind.network:
        return _fetchNetworkLogoBytes(
          resolved.ref,
          httpClient: httpClient,
          maxBytes: maxBytes,
          timeout: timeout,
        );
      case CompanyLogoRefKind.none:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// Resolve Branding & support + load bytes in one call (documents).
Future<({CompanyLogoRef resolved, Uint8List? bytes})>
    resolveAndLoadDocumentCompanyLogoBytes({
  String localPath = '',
  String companyLogoUrl = '',
  String? configuredFluxidiAsset,
  bool Function(String path)? fileExists,
  String Function(String raw)? resolvePublicUrl,
  http.Client? httpClient,
}) async {
  final resolved = resolveDocumentCompanyLogoRef(
    localPath: localPath,
    companyLogoUrl: companyLogoUrl,
    configuredFluxidiAsset: configuredFluxidiAsset,
    fileExists: fileExists ?? (path) => File(path).existsSync(),
    resolvePublicUrl: resolvePublicUrl,
  );
  final bytes = await loadCompanyLogoBytes(resolved, httpClient: httpClient);
  // If the company-owned ref failed to load, fall back to packaged Fluxidi.
  if (bytes == null && resolved.source != CompanyLogoSource.fluxidiFallback) {
    final fallback = resolveDocumentCompanyLogoRef(
      localPath: '',
      companyLogoUrl: '',
      configuredFluxidiAsset: configuredFluxidiAsset,
    );
    return (
      resolved: fallback,
      bytes: await loadCompanyLogoBytes(fallback, httpClient: httpClient),
    );
  }
  return (resolved: resolved, bytes: bytes);
}

Future<Uint8List?> _fetchNetworkLogoBytes(
  String url, {
  http.Client? httpClient,
  required int maxBytes,
  required Duration timeout,
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return null;
  }
  // Documents only accept Fluxidi media / known company logo hosts — reject
  // arbitrary third-party URLs at the loader boundary.
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final approvedHost = host.contains('fluxidi') || host.endsWith('workers.dev');
  final approvedPath =
      path.contains('/public/media/') || path.contains('company/logo');
  if (!approvedHost && !approvedPath) return null;

  final client = httpClient ?? http.Client();
  final owned = httpClient == null;
  try {
    final response = await client.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
      return null;
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    // Reject obvious HTML/error bodies masquerading as images.
    if (bytes.length >= 15) {
      final head = String.fromCharCodes(bytes.take(15)).toLowerCase();
      if (head.contains('<!doctype') || head.contains('<html')) return null;
    }
    return Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  } finally {
    if (owned) client.close();
  }
}
