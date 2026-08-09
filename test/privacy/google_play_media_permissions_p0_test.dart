// GOOGLE-PLAY-MEDIA-PERMISSIONS-P0
//
// Fluxidi must not ship broad photo/video library permissions. Image selection
// uses image_picker (Android Photo Picker). open_filex must not pull
// READ_MEDIA_* / READ_EXTERNAL_STORAGE into the Play release binary.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('GOOGLE-PLAY-MEDIA-PERMISSIONS-P0', () {
    test('app manifest strips open_filex media/library permissions', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(
        manifest.contains('xmlns:tools="http://schemas.android.com/tools"'),
        isTrue,
      );

      for (final permission in <String>[
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
        'android.permission.READ_MEDIA_AUDIO',
        'android.permission.READ_EXTERNAL_STORAGE',
      ]) {
        final removeDecl = RegExp(
          '<uses-permission[^>]*android:name="$permission"[^>]*tools:node="remove"',
        );
        expect(
          removeDecl.hasMatch(manifest),
          isTrue,
          reason: '$permission must be tools:node=remove in app manifest',
        );
      }
    });

    test('image selection remains wired via image_picker gallery/camera', () {
      final pubspec = _read('pubspec.yaml');
      expect(pubspec.contains('image_picker:'), isTrue);

      final vehicle = _read('lib/vehicle_management_page.dart');
      final business = _read('lib/business_settings_page.dart');
      expect(vehicle.contains('ImageSource.gallery'), isTrue);
      expect(business.contains('ImageSource.gallery'), isTrue);
      expect(vehicle.contains('pickImage'), isTrue);
      expect(business.contains('pickImage'), isTrue);
    });

    test('open_filex remains for app-local open only (not media browse)', () {
      final pubspec = _read('pubspec.yaml');
      expect(pubspec.contains('open_filex:'), isTrue);

      final sheet = _read('lib/driver_document_sheet.dart');
      final help = _read('lib/main_parts/business_help_manual_page.dart');
      expect(sheet.contains('OpenFilex.open'), isTrue);
      expect(help.contains('OpenFilex.open'), isTrue);
    });
  });
}
