// FLUXIDI-HISTORICAL-INVOICE-PDF-STALE-ARTIFACT-REFRESH-P0-1
//
// Proves the local invoice-PDF cache name follows the server artifact
// revision, so bytes from a superseded PDF projection can never be reused.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/invoices/invoice_pdf_artifact_cache.dart';

const String _v1Revision = 'street_pdf_proj_v1.aa11bb22cc33dd44';
const String _v2Revision = 'street_pdf_proj_v2.99ff88ee77dd66cc';

void main() {
  group('artifact revision resolution', () {
    test('prefers the worker revision header', () {
      expect(
        resolveInvoicePdfArtifactRevision(
          artifactRevisionHeader: _v2Revision,
          etag: '"something-else"',
          bytes: const <int>[1, 2, 3],
        ),
        _v2Revision,
      );
    });

    test('falls back to the ETag, stripping quotes and weak markers', () {
      expect(
        resolveInvoicePdfArtifactRevision(
          etag: 'W/"$_v2Revision"',
          bytes: const <int>[1, 2, 3],
        ),
        _v2Revision,
      );
    });

    test('falls back to a deterministic content signature', () {
      final a = resolveInvoicePdfArtifactRevision(
        bytes: const <int>[1, 2, 3, 4],
      );
      final b = resolveInvoicePdfArtifactRevision(
        bytes: const <int>[1, 2, 3, 4],
      );
      final c = resolveInvoicePdfArtifactRevision(
        bytes: const <int>[1, 2, 3, 5],
      );

      expect(a, b, reason: 'identical bytes must produce an identical tag');
      expect(a, isNot(c), reason: 'different bytes must produce a new tag');
      expect(a, startsWith('sig'));
      expect(resolveInvoicePdfArtifactRevision(), 'unknown');
    });

    test('never leaks path separators into a file name', () {
      final revision = resolveInvoicePdfArtifactRevision(
        artifactRevisionHeader: '../../etc/passwd rev',
      );
      expect(revision, isNot(contains('/')));
      expect(revision, isNot(contains(' ')));
      expect(revision, isNot(contains(r'\')));
    });
  });

  group('cache file naming', () {
    test('cache key changes when the artifact revision changes', () {
      final stale = invoicePdfCacheFileName(
        reference: 'R-2026-0042',
        artifactRevision: _v1Revision,
      );
      final fresh = invoicePdfCacheFileName(
        reference: 'R-2026-0042',
        artifactRevision: _v2Revision,
      );

      expect(stale, isNot(fresh));
      expect(stale, contains('street_pdf_proj_v1'));
      expect(fresh, contains('street_pdf_proj_v2'));
      expect(fresh, endsWith('.pdf'));
    });

    test('projection versions never collide on one file name', () {
      final names = <String>{
        invoicePdfCacheFileName(
          reference: 'R-2026-0042',
          artifactRevision: _v1Revision,
        ),
        invoicePdfCacheFileName(
          reference: 'R-2026-0042',
          artifactRevision: _v2Revision,
        ),
      };
      expect(names.length, 2);
    });

    test('is stable for the same reference and revision', () {
      expect(
        invoicePdfCacheFileName(
          reference: 'R-2026-0042',
          artifactRevision: _v2Revision,
        ),
        invoicePdfCacheFileName(
          reference: 'R-2026-0042',
          artifactRevision: _v2Revision,
        ),
      );
    });

    test('different bookings stay in separate cache entries', () {
      expect(
        invoicePdfCacheFileName(
          reference: 'R-2026-0042',
          artifactRevision: _v2Revision,
        ),
        isNot(
          invoicePdfCacheFileName(
            reference: 'R-2026-0043',
            artifactRevision: _v2Revision,
          ),
        ),
      );
    });

    test('sanitizes hostile references and empty input', () {
      final name = invoicePdfCacheFileName(
        reference: '../../R 2026/0042',
        artifactRevision: _v2Revision,
      );
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(' ')));
      expect(
        invoicePdfCacheFileName(reference: '', artifactRevision: ''),
        'receipt_invoice_unknown.pdf',
      );
    });
  });

  group('superseded cache pruning', () {
    const reference = 'R-2026-0042';
    final current = invoicePdfCacheFileName(
      reference: reference,
      artifactRevision: _v2Revision,
    );
    final previous = invoicePdfCacheFileName(
      reference: reference,
      artifactRevision: _v1Revision,
    );

    test('an older revision for the same invoice is superseded', () {
      expect(
        isSupersededInvoicePdfCacheFile(
          fileName: previous,
          reference: reference,
          currentFileName: current,
        ),
        isTrue,
      );
    });

    test('the freshly written file is never deleted', () {
      expect(
        isSupersededInvoicePdfCacheFile(
          fileName: current,
          reference: reference,
          currentFileName: current,
        ),
        isFalse,
      );
    });

    test('other bookings and the ride receipt PDF are left alone', () {
      for (final other in <String>[
        invoicePdfCacheFileName(
          reference: 'R-2026-0043',
          artifactRevision: _v1Revision,
        ),
        '$reference.pdf',
        'fluxidi-preview.pdf',
        '${reference}_invoice_$_v1Revision.txt',
      ]) {
        expect(
          isSupersededInvoicePdfCacheFile(
            fileName: other,
            reference: reference,
            currentFileName: current,
          ),
          isFalse,
          reason: 'must not delete $other',
        );
      }
    });
  });
}
