import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_setup_media_pick.dart';

void main() {
  test('HTTP status and unsupported media_type are parsed from live errors', () {
    const error = 'Exception: HTTP 400: {"ok":false,"error":"unsupported media_type"}';
    expect(limousineSetupMediaHttpStatus(error), 400);
    expect(limousineSetupMediaHttpErrorCode(error), 'unsupported media_type');
    expect(limousineSetupMediaTypeUnsupported(error), isTrue);
    expect(
      limousineSetupMediaTypeUnsupported('HTTP 413: {"error":"file_too_large"}'),
      isFalse,
    );
  });

  test('fallback entity ids stay reserved and off the taxi hero/logo keys', () {
    expect(
      limousineSetupFallbackEntityId(LimousineSetupMediaKind.cover),
      kLimousineSetupCoverFallbackEntityId,
    );
    expect(
      limousineSetupFallbackEntityId(LimousineSetupMediaKind.logo),
      kLimousineSetupLogoFallbackEntityId,
    );
    expect(kLimousineSetupMediaFallbackType, 'vehicle_photo');
    expect(kLimousineSetupCoverFallbackEntityId, isNot('company_hero'));
    expect(kLimousineSetupLogoFallbackEntityId, isNot('company_logo'));
    expect(
      limousineSetupMediaTarget(LimousineSetupMediaKind.cover).mediaType,
      kLimousineProfileCoverMediaType,
    );
    expect(
      limousineSetupMediaTarget(LimousineSetupMediaKind.logo).mediaType,
      kLimousineProfileLogoMediaType,
    );
  });

  test('unsupported dedicated type retries vehicle_photo with reserved entity', () async {
    final calls = <Map<String, String?>>[];
    final uploaded = await limousineSendSetupMediaWithFallback(
      kind: LimousineSetupMediaKind.cover,
      dedicatedMediaType: kLimousineProfileCoverMediaType,
      newMediaId: () => 'media_reserved_1',
      send: ({required mediaType, entityId, mediaId}) async {
        calls.add(<String, String?>{
          'mediaType': mediaType,
          'entityId': entityId,
          'mediaId': mediaId,
        });
        if (mediaType == kLimousineProfileCoverMediaType) {
          throw Exception('HTTP 400: {"error":"unsupported media_type"}');
        }
        return <String, dynamic>{
          'ok': true,
          'url':
              'https://fluxidi-booking-api.fluxidi.workers.dev/public/media/gallery/x.png',
        };
      },
    );
    expect(calls, hasLength(2));
    expect(calls.first['mediaType'], kLimousineProfileCoverMediaType);
    expect(calls.first['entityId'], isNull);
    expect(calls.last['mediaType'], 'vehicle_photo');
    expect(calls.last['entityId'], kLimousineSetupCoverFallbackEntityId);
    expect(calls.last['mediaId'], 'media_reserved_1');
    expect(
      uploaded['url'].toString().startsWith('https://'),
      isTrue,
    );
  });

  test('other upload errors do not fall back to vehicle_photo', () async {
    var calls = 0;
    await expectLater(
      limousineSendSetupMediaWithFallback(
        kind: LimousineSetupMediaKind.logo,
        dedicatedMediaType: kLimousineProfileLogoMediaType,
        send: ({required mediaType, entityId, mediaId}) async {
          calls += 1;
          throw Exception('HTTP 401: {"error":"unauthorized"}');
        },
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('HTTP 401') &&
              error.toString().contains('unauthorized'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('failure copy stays concrete instead of one generic sentence', () {
    expect(
      limousineSetupMediaFailureMessage(
        kind: LimousineSetupMediaKind.cover,
        error: const LimousineSetupMediaFailure(
          phase: 'auth',
          kind: LimousineSetupMediaKind.cover,
          code: 'missing_company_session',
        ),
        language: AppLanguage.nl,
      ),
      contains(kLimousineBusinessSetupMediaAuthFailed.nl),
    );
    expect(
      limousineSetupMediaFailureMessage(
        kind: LimousineSetupMediaKind.cover,
        error: const LimousineSetupMediaFailure(
          phase: 'upload',
          kind: LimousineSetupMediaKind.cover,
          code: 'unsupported media_type',
          httpStatus: 400,
        ),
        language: AppLanguage.nl,
      ),
      allOf(
        contains(kLimousineBusinessSetupCoverUploadFailed.nl),
        contains('400'),
        contains('unsupported media_type'),
      ),
    );
    expect(
      limousineSetupMediaFailureMessage(
        kind: LimousineSetupMediaKind.logo,
        error: const LimousineSetupMediaFailure(
          phase: 'persist',
          kind: LimousineSetupMediaKind.logo,
          code: 'draft-persist-failed',
        ),
        language: AppLanguage.nl,
      ),
      contains(kLimousineBusinessSetupLogoPersistFailed.nl),
    );
    expect(
      limousineSetupMediaFailureMessage(
        kind: LimousineSetupMediaKind.cover,
        error: const LimousinePickedMediaException('upload-not-durable'),
        language: AppLanguage.nl,
      ),
      kLimousineBusinessSetupCoverNotDurable.nl,
    );
    expect(
      limousineSetupMediaFailureMessage(
        kind: LimousineSetupMediaKind.cover,
        error: const LimousineSetupMediaFailure(
          phase: 'response',
          kind: LimousineSetupMediaKind.cover,
          code: 'upload-not-durable',
        ),
        language: AppLanguage.nl,
      ),
      contains(kLimousineBusinessSetupCoverNotDurable.nl),
    );
  });
}
