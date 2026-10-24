import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/discovery/customer_contained_photo.dart';

void main() {
  test('detail photo URL upgrades a small maxwidth without adding crop', () {
    final next = customerPreferredDetailPhotoUrl(
      'https://places.example/photo?maxwidth=400&photo_reference=abc',
    );
    final uri = Uri.parse(next);
    expect(uri.queryParameters['maxwidth'], '1600');
    expect(uri.queryParameters.containsKey('crop'), isFalse);
    expect(uri.queryParameters['photo_reference'], 'abc');
  });

  test('detail photo URL drops a bounding maxheight so the source is not cropped', () {
    final next = customerPreferredDetailPhotoUrl(
      'https://places.example/photo?maxwidth=800&maxheight=400',
    );
    final uri = Uri.parse(next);
    expect(uri.queryParameters['maxwidth'], '1600');
    expect(uri.queryParameters.containsKey('maxheight'), isFalse);
  });

  test('googleusercontent size suffix becomes a larger uncropped variant', () {
    expect(
      customerPreferredDetailPhotoUrl(
        'https://lh3.googleusercontent.com/p/AF1QipExample=w800-h400-k-no',
      ),
      'https://lh3.googleusercontent.com/p/AF1QipExample=s1600',
    );
  });

  test('already large photos are left as-is', () {
    const url = 'https://cdn.example/hotel.jpg';
    expect(customerPreferredDetailPhotoUrl(url), url);
  });

  test('event detail prefers hero over thumbnail', () {
    expect(
      preferredCustomerDetailPhotoUrl(
        hero: 'https://cdn.example/hero.jpg',
        image: 'https://cdn.example/image.jpg',
        thumbnail: 'https://cdn.example/thumb.jpg',
      ),
      'https://cdn.example/hero.jpg',
    );
    expect(
      preferredCustomerDetailPhotoUrl(
        image: 'https://cdn.example/image.jpg',
        thumbnail: 'https://cdn.example/thumb.jpg',
      ),
      'https://cdn.example/image.jpg',
    );
  });

  test('technical discovery copy is recognized in the offered languages', () {
    expect(isCustomerTechnicalDiscoveryCopy('Live place discovery - Hotel'), isTrue);
    expect(isCustomerTechnicalDiscoveryCopy('Real place discovery'), isTrue);
    expect(isCustomerTechnicalDiscoveryCopy('Echte plaatsvermelding'), isTrue);
    expect(
      isCustomerTechnicalDiscoveryCopy(
        'Deze kaarten zijn uitgelichte inspiratie. Live prijzen en beschikbaarheid openen bij Stay22-partners.',
      ),
      isTrue,
    );
    expect(isCustomerTechnicalDiscoveryCopy('Centraal hotel bij de Grote Markt.'), isFalse);
  });
}
