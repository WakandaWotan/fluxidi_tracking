// DRIVER-DELETE-AUTH-P0 — Flutter source contracts for company-session delete.
//
// Run:
//   flutter test test/company/driver_delete_auth_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Missing $relativePath');
  return file.readAsStringSync();
}

void main() {
  group('DRIVER-DELETE-AUTH-P0 Flutter contracts', () {
    test('delete uses company bearer, not empty _adminHeaders', () {
      final src = _read(
        'lib/main_parts/company_driver_management_page_body.dart',
      );
      final start = src.indexOf('Future<void> _deleteDriverFromBackendAndLocal');
      expect(start, greaterThan(0));
      final chunk = src.substring(start, start + 4500);
      expect(chunk.contains('companyBearerHeaders'), isTrue);
      expect(chunk.contains('companySessionToken'), isTrue);
      expect(chunk.contains('..._adminHeaders()'), isFalse);
      expect(
        chunk.contains('/admin/company/drivers/index/delete'),
        isTrue,
      );
      // After the remote POST succeeds, local tombstone is applied (never on
      // failed backend delete). Placeholder local-only delete is a separate path.
      final postIdx = chunk.indexOf('.post(endpoint, headers: headers');
      final okBranch = chunk.indexOf('response.statusCode >= 200', postIdx);
      final localIdx = chunk.indexOf(
        'removeDriverLocallyAfterBackendDelete',
        okBranch,
      );
      final okIdx = chunk.indexOf('[DRIVER_DELETE][OK]', localIdx);
      expect(postIdx, greaterThan(0));
      expect(okBranch, greaterThan(postIdx));
      expect(localIdx, greaterThan(okBranch));
      expect(okIdx, greaterThan(localIdx));
    });

    test('delete failure surfaces mapped backend error codes', () {
      final src = _read(
        'lib/main_parts/company_driver_management_page_body.dart',
      );
      expect(src.contains('_driverDeleteFailureMessage'), isTrue);
      expect(src.contains("code == 'unauthorized'"), isTrue);
      expect(src.contains("code == 'forbidden'"), isTrue);
      expect(src.contains('missing_company_session'), isTrue);
    });

    test('seed predicate no longer treats id vh_1 alone as demo', () {
      final src = _read('lib/company/company_fleet_operational.dart');
      expect(src.contains("if (id == 'vh_1') return true;"), isFalse);
      expect(src.contains("hasRealPlate"), isTrue);
      expect(src.contains("1-ABC-123"), isTrue);
    });
  });
}
