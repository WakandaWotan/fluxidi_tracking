import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';

void main() {
  test('public introduction and story survive save/reload and unrelated edits', () {
    final p = BackendBusinessProfile.defaults().copyWith(
      publicAboutShort: 'Persoonlijke chauffeur.', publicAboutLong: 'Mijn verhaal.');
    final reloaded = BackendBusinessProfile.fromJson(p.toJson()).copyWith(companyName: 'Team');
    expect(reloaded.publicAboutShort, 'Persoonlijke chauffeur.');
    expect(reloaded.publicAboutLong, 'Mijn verhaal.');
    expect(BackendBusinessProfile.fromJson(reloaded.copyWith(publicAboutLong: '').toJson()).publicAboutLong, '');
    expect(BackendBusinessProfile.fromJson({'public_about_short': 'Kort', 'public_about_long': 'Lang'}).publicAboutLong, 'Lang');
  });
  test('driver story survives copy and can be cleared', () {
    const driver = DriverProfile(id: 'd', fullName: 'Chauffeur', employeeNumber: '1', phone: '', isActive: true, publicBio: 'Mijn verhaal.');
    expect(driver.copyWith(publicDisplayName: 'Chris').publicBio, 'Mijn verhaal.');
    expect(driver.copyWith(publicBio: '').publicBio, '');
  });
}
