// FLUXIDI-CANONICAL-DOCUMENT-AND-EMAIL-BRANDING-SOURCE-OF-TRUTH-P0-1

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/branding/company_logo_bytes.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uploadedFile =
      '/data/user/0/com.fluxidi.tracking/app_flutter/tenant_state/company_logo/logo.png';
  const companyMediaUrl =
      'https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/t/c/company/logo.png';
  const themeArt =
      'https://cdn.example.com/themes/hero-banner.png';

  group('canonical document branding owner', () {
    test('1) Branding & support local path is authoritative', () {
      final resolved = resolveDocumentCompanyLogoRef(
        localPath: uploadedFile,
        companyLogoUrl: companyMediaUrl,
        fileExists: (_) => true,
      );
      expect(resolved.source, CompanyLogoSource.localBranding);
      expect(resolved.ref, uploadedFile);
    });

    test('2) company media URL is used when local branding is empty', () {
      final resolved = resolveDocumentCompanyLogoRef(
        localPath: '',
        companyLogoUrl: companyMediaUrl,
      );
      expect(resolved.isCompanyOwned, isTrue);
      expect(resolved.kind, CompanyLogoRefKind.network);
      expect(resolved.ref, companyMediaUrl);
    });

    test('3) theme/gallery artwork host cannot become document logo', () async {
      final client = MockClient((request) async {
        fail('theme artwork must not be fetched: ${request.url}');
      });
      final loaded = await resolveAndLoadDocumentCompanyLogoBytes(
        localPath: themeArt,
        companyLogoUrl: '',
        httpClient: client,
      );
      // Unapproved host → network loader rejects → Fluxidi fallback asset.
      expect(loaded.resolved.source, CompanyLogoSource.fluxidiFallback);
      expect(loaded.resolved.ref, kPackagedFluxidiLogoAsset);
    });

    test('5) invalid branding falls back to Fluxidi monogram asset', () {
      final resolved = resolveDocumentCompanyLogoRef(
        localPath: '',
        companyLogoUrl: '',
      );
      expect(resolved.source, CompanyLogoSource.fluxidiFallback);
      expect(isDefaultFluxidiLogoRef(resolved.ref), isTrue);
    });

    test('6) no INELIVIA / blank / broken-owner claims', () {
      final resolved = resolveDocumentCompanyLogoRef(
        localPath: '',
        companyLogoUrl: '',
      );
      expect(resolved.ref.toLowerCase().contains('inelivia'), isFalse);
      expect(resolved.isRenderable, isTrue);
    });
  });

  group('network logo load for receipts', () {
    test('7) https company logo bytes load for DIRECT receipt path', () async {
      final png = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
      ]);
      final client = MockClient((request) async {
        expect(request.url.toString(), companyMediaUrl);
        return http.Response.bytes(png, 200, headers: {
          'content-type': 'image/png',
        });
      });
      final loaded = await resolveAndLoadDocumentCompanyLogoBytes(
        localPath: companyMediaUrl,
        companyLogoUrl: '',
        httpClient: client,
      );
      expect(loaded.resolved.source, CompanyLogoSource.localBranding);
      expect(loaded.bytes, isNotNull);
      expect(loaded.bytes!.first, 0x89);
    });

    test('HTML error body is rejected as logo bytes', () async {
      final client = MockClient((request) async {
        return http.Response('<!doctype html><html>nope</html>', 200, headers: {
          'content-type': 'text/html',
        });
      });
      final bytes = await loadCompanyLogoBytes(
        const CompanyLogoRef(
          ref: companyMediaUrl,
          kind: CompanyLogoRefKind.network,
          source: CompanyLogoSource.localBranding,
        ),
        httpClient: client,
      );
      expect(bytes, isNull);
    });
  });
}
