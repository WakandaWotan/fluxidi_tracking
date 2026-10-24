import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_branding.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_media.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_mode.dart';

void main() {
  test('companies without a stored choice keep logo only', () {
    expect(parseCustomerAppHeaderMode(null), CustomerAppHeaderMode.logoOnly);
    expect(parseCustomerAppHeaderMode(''), CustomerAppHeaderMode.logoOnly);
    expect(
      CustomerAppHeaderBranding.fromJson(const <String, dynamic>{}).mode,
      CustomerAppHeaderMode.logoOnly,
    );
  });

  test('parses the three settings choices', () {
    expect(
      parseCustomerAppHeaderMode('header_image'),
      CustomerAppHeaderMode.coverOnly,
    );
    expect(
      parseCustomerAppHeaderMode('header_and_logo'),
      CustomerAppHeaderMode.coverAndLogo,
    );
    expect(parseCustomerAppHeaderMode('logo'), CustomerAppHeaderMode.logoOnly);
    expect(
      parseCustomerAppHeaderLogoPosition(null),
      CustomerAppHeaderLogoPosition.topLeft,
    );
    expect(
      parseCustomerAppHeaderLogoPosition('top_right'),
      CustomerAppHeaderLogoPosition.topRight,
    );
  });

  test('cover-only falls back to logo when the cover is unusable', () {
    expect(
      effectiveCustomerAppHeaderMode(
        requested: CustomerAppHeaderMode.coverOnly,
        hasLogo: true,
        hasCover: false,
      ),
      CustomerAppHeaderMode.logoOnly,
    );
    expect(
      effectiveCustomerAppHeaderMode(
        requested: CustomerAppHeaderMode.coverAndLogo,
        hasLogo: false,
        hasCover: true,
      ),
      CustomerAppHeaderMode.coverOnly,
    );
  });

  test('reads saved logo and cover without a second upload field', () {
    final branding = CustomerAppHeaderBranding.fromJson(const <String, dynamic>{
      'public_logo_url': 'https://cdn.example/logo.png',
      'public_hero_photo_url': 'https://cdn.example/cover.png',
      'customer_app_header_mode': 'header_image',
      'display_name': 'Other Taxi',
      'customer_app_header_media_revision': '9',
    });
    expect(branding.hasLogo, isTrue);
    expect(branding.hasCover, isTrue);
    expect(branding.mode, CustomerAppHeaderMode.coverOnly);
    expect(branding.companyName, 'Other Taxi');
    expect(branding.displayCoverUrl.contains('v=9'), isTrue);
  });

  test('rejects platform and non-https images', () {
    expect(customerAppHeaderImageIsUsable('http://cdn.example/a.png'), isFalse);
    expect(
      customerAppHeaderImageIsUsable('https://cdn.example/fluxidi_logo.png'),
      isFalse,
    );
    expect(
      customerAppHeaderImageIsUsable('https://cdn.example/cover.png'),
      isTrue,
    );
  });

  test('replaced images change the cache key', () {
    const url = 'https://cdn.example/cover.png';
    expect(
      customerAppHeaderCacheBustedUrl(url, revision: '1'),
      isNot(customerAppHeaderCacheBustedUrl(url, revision: '2')),
    );
  });
}
