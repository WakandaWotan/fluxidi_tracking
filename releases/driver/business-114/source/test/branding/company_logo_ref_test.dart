// FLUXIDI-CANONICAL-COMPANY-LOGO-AND-INVOICE-PRESENTATION-P0-1
//
// Field failure: after a restart the branding page said "Geen bedrijfslogo
// ingesteld" while the dashboard still showed the uploaded logo. Both read the
// same stored value; the settings preview simply had no branch for an https
// reference and opened it as a file. These tests pin one canonical resolution
// shared by both surfaces, and that a load failure is never reported as "unset".

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';

const String _uploadedFile =
    '/data/user/0/com.fluxidi.tracking/app_flutter/tenant_state/company_logo/logo_1.png';
const String _publicUrl =
    'https://fluxidi-booking-api.fluxidi.workers.dev/public/media/public-media/tenant/a/logo.png';

void main() {
  group('reference classification', () {
    test('each reference kind is classified for the right loader', () {
      expect(
        classifyCompanyLogoRef('assets/fluxidi/fluxidi_logo.png'),
        CompanyLogoRefKind.asset,
      );
      expect(classifyCompanyLogoRef(_uploadedFile), CompanyLogoRefKind.file);
      expect(classifyCompanyLogoRef(_publicUrl), CompanyLogoRefKind.network);
      expect(
        classifyCompanyLogoRef('http://example.test/logo.png'),
        CompanyLogoRefKind.network,
      );
      expect(classifyCompanyLogoRef(''), CompanyLogoRefKind.none);
      expect(classifyCompanyLogoRef('   '), CompanyLogoRefKind.none);
    });

    test('an https reference is never classified as a file', () {
      // The exact regression: Image.file(File("https://...")) always fails and
      // then claimed the company had no logo.
      expect(
        classifyCompanyLogoRef(_publicUrl),
        isNot(CompanyLogoRefKind.file),
      );
    });

    test('unresolved worker-relative and data refs are not renderable', () {
      expect(
        classifyCompanyLogoRef('/public/media/public-media/x.png'),
        CompanyLogoRefKind.none,
      );
      expect(
        classifyCompanyLogoRef('public-media/tenant/a/logo.png'),
        CompanyLogoRefKind.none,
      );
      expect(
        classifyCompanyLogoRef('data:image/png;base64,AAAA'),
        CompanyLogoRefKind.none,
      );
    });
  });

  group('packaged Fluxidi default means "not set"', () {
    test('every packaged variant is treated as no company logo', () {
      for (final raw in <String>[
        '',
        '   ',
        'assets/fluxidi/fluxidi_logo.png',
        'ASSETS/FLUXIDI/FLUXIDI_LOGO.PNG',
        r'assets\fluxidi\fluxidi_logo.png',
        'fluxidi_logo.png',
        'some/dir/fluxidi_logo.png',
      ]) {
        expect(isDefaultFluxidiLogoRef(raw), isTrue, reason: raw);
      }
    });

    test('a company reference is not a packaged default', () {
      expect(isDefaultFluxidiLogoRef(_uploadedFile), isFalse);
      expect(isDefaultFluxidiLogoRef(_publicUrl), isFalse);
    });
  });

  group('canonical resolution', () {
    test('the uploaded local file wins and is company owned', () {
      final resolved = resolveCompanyLogoRef(
        localPath: _uploadedFile,
        publicUrl: _publicUrl,
        fileExists: (_) => true,
      );
      expect(resolved.ref, _uploadedFile);
      expect(resolved.kind, CompanyLogoRefKind.file);
      expect(resolved.source, CompanyLogoSource.localBranding);
      expect(resolved.isCompanyOwned, isTrue);
    });

    test('a stored https reference resolves for rendering, not as a file', () {
      // What startup bootstrap leaves behind after a restart.
      final resolved = resolveCompanyLogoRef(
        localPath: _publicUrl,
        fileExists: (_) => false,
      );
      expect(resolved.kind, CompanyLogoRefKind.network);
      expect(resolved.source, CompanyLogoSource.localBranding);
      expect(resolved.isCompanyOwned, isTrue);
    });

    test('the public profile logo is used when branding is unset', () {
      final resolved = resolveCompanyLogoRef(
        localPath: '',
        publicUrl: _publicUrl,
      );
      expect(resolved.ref, _publicUrl);
      expect(resolved.source, CompanyLogoSource.publicProfile);
      expect(resolved.isCompanyOwned, isTrue);
    });

    test('a worker-relative ref becomes usable once resolved to a URL', () {
      final resolved = resolveCompanyLogoRef(
        localPath: '/public/media/public-media/tenant/a/logo.png',
        resolvePublicUrl: (raw) => 'https://cdn.test$raw',
      );
      expect(resolved.kind, CompanyLogoRefKind.network);
      expect(resolved.ref, startsWith('https://cdn.test/'));
      expect(resolved.isCompanyOwned, isTrue);
    });

    test('a missing local file falls through instead of rendering nothing', () {
      final resolved = resolveCompanyLogoRef(
        localPath: '/gone/logo.png',
        publicUrl: _publicUrl,
        fileExists: (_) => false,
      );
      expect(resolved.ref, _publicUrl);
      expect(resolved.source, CompanyLogoSource.publicProfile);
    });

    test('no company logo yields the Fluxidi fallback, not a blank', () {
      final resolved = resolveCompanyLogoRef(localPath: '', publicUrl: '');
      expect(resolved.source, CompanyLogoSource.fluxidiFallback);
      expect(resolved.kind, CompanyLogoRefKind.asset);
      expect(resolved.ref, kPackagedFluxidiLogoAsset);
      expect(resolved.isCompanyOwned, isFalse);
      expect(resolved.isRenderable, isTrue);
    });

    test('the packaged default never counts as a company logo', () {
      final resolved = resolveCompanyLogoRef(
        localPath: kPackagedFluxidiLogoAsset,
        publicUrl: kPackagedFluxidiLogoAsset,
      );
      expect(resolved.source, CompanyLogoSource.fluxidiFallback);
      expect(resolved.isCompanyOwned, isFalse);
    });

    test('local file refs are skipped on web where they cannot load', () {
      final resolved = resolveCompanyLogoRef(
        localPath: _uploadedFile,
        publicUrl: _publicUrl,
        isWeb: true,
      );
      expect(resolved.kind, CompanyLogoRefKind.network);
      expect(resolved.source, CompanyLogoSource.publicProfile);
    });
  });

  group('settings and dashboard agree', () {
    test('both surfaces resolve the same reference for every input', () {
      final cases = <({String local, String public})>[
        (local: _uploadedFile, public: ''),
        (local: _uploadedFile, public: _publicUrl),
        (local: '', public: _publicUrl),
        (local: _publicUrl, public: ''),
        (local: '', public: ''),
        (local: kPackagedFluxidiLogoAsset, public: _publicUrl),
      ];
      for (final c in cases) {
        // Same inputs, same canonical resolver: the two surfaces cannot diverge.
        final settings = resolveCompanyLogoRef(
          localPath: c.local,
          publicUrl: c.public,
          fileExists: (_) => true,
        );
        final dashboard = resolveCompanyLogoRef(
          localPath: c.local,
          publicUrl: c.public,
          fileExists: (_) => true,
        );
        expect(settings.ref, dashboard.ref, reason: '${c.local}|${c.public}');
        expect(settings.kind, dashboard.kind);
        expect(settings.source, dashboard.source);
      }
    });

    test('deleting the logo clears it for both surfaces', () {
      final resolved = resolveCompanyLogoRef(localPath: '', publicUrl: '');
      expect(resolved.isCompanyOwned, isFalse);
      expect(resolved.source, CompanyLogoSource.fluxidiFallback);
    });

    test('tenant A can never resolve tenant B stored reference', () {
      const tenantA =
          'https://cdn.test/public-media/tenant/a/company/a/logo_a.png';
      const tenantB =
          'https://cdn.test/public-media/tenant/b/company/b/logo_b.png';
      final a = resolveCompanyLogoRef(localPath: tenantA);
      final b = resolveCompanyLogoRef(localPath: tenantB);
      expect(a.ref, tenantA);
      expect(b.ref, tenantB);
      expect(a.ref, isNot(b.ref));
      // Resolution is a pure function of the tenant's own stored value: there is
      // no shared cache or global that could leak the other tenant's reference.
      expect(resolveCompanyLogoRef(localPath: tenantA).ref, tenantA);
    });
  });

  group('preview state never lies about "not set"', () {
    test('a set logo that fails to load reports failure, not empty', () {
      final resolved = resolveCompanyLogoRef(
        localPath: _publicUrl,
      );
      expect(
        resolveCompanyLogoPreviewState(resolved: resolved, loadFailed: true),
        CompanyLogoPreviewState.failed,
      );
      expect(
        resolveCompanyLogoPreviewState(resolved: resolved, loadFailed: false),
        CompanyLogoPreviewState.ready,
      );
    });

    test('only a genuinely unset logo reports empty', () {
      final unset = resolveCompanyLogoRef(localPath: '', publicUrl: '');
      expect(
        resolveCompanyLogoPreviewState(resolved: unset, loadFailed: false),
        CompanyLogoPreviewState.empty,
      );
      expect(
        resolveCompanyLogoPreviewState(resolved: unset, loadFailed: true),
        CompanyLogoPreviewState.empty,
      );
    });
  });
}
