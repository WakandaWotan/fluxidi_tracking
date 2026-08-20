import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_setup_media_pick.dart';
import 'package:http/http.dart' as http;

final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

bool get _hasLiveBookingEnv {
  final base = Platform.environment['BOOKING_BASE_URL'] ?? '';
  final token = Platform.environment['ADMIN_TOKEN'] ?? '';
  return base.trim().isNotEmpty && token.trim().isNotEmpty;
}

Future<Map<String, dynamic>> _upload({
  required String mediaType,
  String? entityId,
}) async {
  final base = (Platform.environment['BOOKING_BASE_URL'] ?? '').replaceAll(
    RegExp(r'/$'),
    '',
  );
  final token = (Platform.environment['ADMIN_TOKEN'] ?? '').trim();
  final tenant =
      Platform.environment['FLUXIDI_TEST_TENANT_ID'] ?? 'fluxidi_fluxidi_ddmh9g';
  final company = Platform.environment['FLUXIDI_TEST_COMPANY_ID'] ?? tenant;
  final uri = Uri.parse('$base/admin/partners/media/upload').replace(
    queryParameters: <String, String>{
      'tenant_id': tenant,
      'company_id': company,
    },
  );
  final request = http.MultipartRequest('POST', uri);
  request.headers['Authorization'] = 'Bearer $token';
  request.fields['tenant_id'] = tenant;
  request.fields['company_id'] = company;
  request.fields['media_type'] = mediaType;
  if (entityId != null && entityId.isNotEmpty) {
    request.fields['entity_id'] = entityId;
  }
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      _kTinyPng,
      filename: 'probe.png',
    ),
  );
  final streamed = await request.send().timeout(const Duration(seconds: 20));
  final body = await streamed.stream.bytesToString();
  Map<String, dynamic> decoded = <String, dynamic>{};
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map) {
      decoded = Map<String, dynamic>.from(parsed);
    }
  } catch (_) {
    decoded = <String, dynamic>{'raw': body.length};
  }
  return <String, dynamic>{
    'status': streamed.statusCode,
    'media_type': mediaType,
    'entity_id': entityId ?? '',
    'error': (decoded['error'] ?? '').toString(),
    'url': (decoded['url'] ?? '').toString(),
    'has_https': (decoded['url'] ?? '').toString().startsWith('https://'),
  };
}

void main() {
  test(
    'live reserved-entity vehicle_photo upload returns a durable https URL',
    () async {
      final fallback = await _upload(
        mediaType: kLimousineSetupMediaFallbackType,
        entityId: kLimousineSetupCoverFallbackEntityId,
      );
      expect(fallback['status'], 200, reason: '${fallback['error']}');
      expect(fallback['has_https'], isTrue);
      expect(fallback['url'].toString(), contains('/public/media/'));

      final dedicated = await _upload(
        mediaType: kLimousineProfileCoverMediaType,
      );
      final dedicatedLogo = await _upload(
        mediaType: kLimousineProfileLogoMediaType,
      );
      // Live worker currently rejects dedicated purposes. Either outcome is
      // acceptable: 400 proves why fallback exists; 200 means the worker
      // caught up. Never treat taxi company_hero as the cover path here.
      expect(dedicated['status'], anyOf(200, 400));
      expect(dedicatedLogo['status'], anyOf(200, 400));
      if (dedicated['status'] == 400) {
        expect(
          dedicated['error'].toString().toLowerCase(),
          contains('unsupported media'),
        );
      }
    },
    skip: _hasLiveBookingEnv
        ? false
        : 'BOOKING_BASE_URL and ADMIN_TOKEN are required for live media e2e',
  );
}
