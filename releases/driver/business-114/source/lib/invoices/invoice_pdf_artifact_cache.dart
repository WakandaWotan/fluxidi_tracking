/// FLUXIDI-HISTORICAL-INVOICE-PDF-STALE-ARTIFACT-REFRESH-P0-1
///
/// Local cache naming for downloaded business-invoice PDFs.
///
/// A downloaded artifact is written under a name that carries the server
/// artifact revision, so bytes produced by an older PDF projection can never
/// collide with — or be mistaken for — the refreshed artifact.
library;

/// Header the booking worker sets on `GET /bookings/{id}/invoice/pdf`.
const String kInvoicePdfArtifactRevisionHeader =
    'x-fluxidi-invoice-artifact-revision';

const String _kInvoicePdfCacheSuffix = '_invoice_';

String _sanitize(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');

/// Deterministic, dependency-free content signature used only for cache keying.
///
/// Two 32-bit lanes keep every intermediate below 2^53 so the result is
/// identical on the VM and on the web.
String _contentSignatureHex(List<int> bytes) {
  var hi = 0xcbf29ce4;
  var lo = 0x84222325;
  for (final byte in bytes) {
    lo ^= byte & 0xff;
    final scaled = lo * 0x1b3;
    final nextLo = scaled & 0xffffffff;
    hi = (hi * 0x1b3 + lo + (scaled ~/ 0x100000000)) & 0xffffffff;
    lo = nextLo;
  }
  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}

/// Revision tag for a freshly downloaded invoice PDF.
///
/// Prefers the explicit worker revision header, then the ETag, and otherwise
/// falls back to a digest of the bytes so the tag still changes whenever the
/// server artifact changes.
String resolveInvoicePdfArtifactRevision({
  String? artifactRevisionHeader,
  String? etag,
  List<int> bytes = const <int>[],
}) {
  final header = (artifactRevisionHeader ?? '').trim();
  if (header.isNotEmpty) return _sanitize(header);

  final tag = (etag ?? '').trim().replaceAll(RegExp(r'^W/'), '').replaceAll(
    '"',
    '',
  );
  if (tag.trim().isNotEmpty) return _sanitize(tag.trim());

  if (bytes.isEmpty) return 'unknown';
  return 'sig${_contentSignatureHex(bytes)}';
}

/// Shared prefix of every cached invoice PDF for one booking reference.
String invoicePdfCacheFilePrefix(String reference) {
  final base = _sanitize(reference.trim());
  return '${base.isEmpty ? 'receipt' : base}$_kInvoicePdfCacheSuffix';
}

/// Revision-scoped cache file name, e.g. `R-2026-0042_invoice_street_pdf_proj_v2.ab12.pdf`.
String invoicePdfCacheFileName({
  required String reference,
  required String artifactRevision,
}) {
  final revision = _sanitize(artifactRevision.trim());
  return '${invoicePdfCacheFilePrefix(reference)}'
      '${revision.isEmpty ? 'unknown' : revision}.pdf';
}

/// Whether [fileName] is an older cache entry for the same invoice that the
/// caller should delete after writing [currentFileName].
bool isSupersededInvoicePdfCacheFile({
  required String fileName,
  required String reference,
  required String currentFileName,
}) {
  if (fileName == currentFileName) return false;
  if (!fileName.endsWith('.pdf')) return false;
  return fileName.startsWith(invoicePdfCacheFilePrefix(reference));
}
