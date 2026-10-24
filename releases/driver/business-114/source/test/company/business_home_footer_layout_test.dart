import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/business_theme_root_canvas.dart';

void main() {
  test('tall portrait tablet keeps dashboard footer inline', () {
    expect(businessHomeUsesInlineTabletPortraitFooter(const Size(800, 1280)), isTrue);
    expect(businessHomeUsesInlineTabletPortraitFooter(const Size(1200, 1920)), isTrue);
  });

  test('phone and landscape retain normal footer placement', () {
    expect(businessHomeUsesInlineTabletPortraitFooter(const Size(390, 844)), isFalse);
    expect(businessHomeUsesInlineTabletPortraitFooter(const Size(1280, 800)), isFalse);
  });
}
