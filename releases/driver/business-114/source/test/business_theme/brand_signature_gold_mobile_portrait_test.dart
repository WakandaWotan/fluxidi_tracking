import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_header.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('phone portrait logo frames stay inside the given widths', () {
    expect(brandSignatureGoldMobilePortraitLogoBox(320), const Size(240, 84));
    expect(brandSignatureGoldMobilePortraitLogoBox(359), const Size(240, 84));
    expect(brandSignatureGoldMobilePortraitLogoBox(360), const Size(280, 94));
    expect(brandSignatureGoldMobilePortraitLogoBox(390), const Size(280, 94));
    expect(brandSignatureGoldMobilePortraitLogoBox(430), const Size(280, 94));
    expect(brandSignatureGoldMobilePortraitLogoBox(480), const Size(320, 104));
    expect(brandSignatureGoldMobilePortraitLogoBox(767), const Size(320, 104));
    expect(
      brandSignatureGoldUsesStackedMobilePortrait(width: 390, height: 844),
      isTrue,
    );
    expect(
      brandSignatureGoldUsesStackedMobilePortrait(width: 844, height: 390),
      isFalse,
    );
    expect(
      brandSignatureGoldUsesStackedMobilePortrait(width: 800, height: 1280),
      isFalse,
    );
    expect(
      brandSignatureGoldUsesStackedMobilePortrait(width: 1280, height: 800),
      isFalse,
    );
  });

  testWidgets('phone portrait stacks controls above a centered logo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_header(name: 'Stadstaxi Noord'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final header = tester.getRect(find.byKey(kBrandSignatureGoldHeaderKey));
    final theme = tester.getRect(
      find.byKey(BusinessThemeCycleButton.buttonKey),
    );
    final logo = tester.getRect(find.byKey(kBrandSignatureGoldLogoKey));
    expect(theme.bottom, lessThan(logo.top));
    expect(logo.width, lessThanOrEqualTo(280));
    expect(logo.height, lessThanOrEqualTo(94));
    expect(header.height, greaterThan(168));
    expect(logo.center.dx, closeTo(header.center.dx, 1));
  });

  testWidgets('a long company name stays inside the phone portrait header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _header(
        name: 'Internationale Luchthavenvervoer Maatschappij Van De Kust',
        hasLogo: false,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Internationale'), findsOneWidget);
  });

  testWidgets('larger text scale does not overflow the phone portrait header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: _header(name: 'Stadstaxi', hasLogo: false),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet portrait keeps the fixed side-by-side height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_header(name: 'Stadstaxi', height: 208));
    await tester.pump();
    expect(tester.getSize(find.byKey(kBrandSignatureGoldHeaderKey)).height, 208);
  });

  testWidgets('wide landscape keeps the fixed desktop height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_header(name: 'Stadstaxi', height: 96));
    await tester.pump();
    expect(tester.getSize(find.byKey(kBrandSignatureGoldHeaderKey)).height, 96);
  });
}

Widget _header({
  required String name,
  bool hasLogo = true,
  double height = 168,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: BrandSignatureGoldHeader(
            height: height,
            logoRef: hasLogo
                ? 'assets/fluxidi/fluxidi_logo_horizontal_gold.png'
                : '',
            hasCompanyLogo: hasLogo,
            companyName: name,
            onOpenThemeSelector: () {},
          ),
      ),
    ),
  );
}
