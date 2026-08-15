import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_action_card.dart';

String _normalize(String s) => s.replaceAll('\r\n', '\n');

String _driverHome() => _normalize(
  File('lib/main_parts/driver_home_page_state.dart').readAsStringSync(),
);

String _businessHome() => _normalize(
  File('lib/main_parts/business_home_page_state.dart').readAsStringSync(),
);

String _quickActionsRegion() {
  final source = _driverHome();
  final start = source.indexOf('Widget _buildDriverQuickActionsGrid({');
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf('Widget _buildPremiumDriverDashboard()', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  test('Gold phone portrait reuses the company two-column token', () {
    expect(kBrandSignatureGoldPhonePortraitColumns, 2);
    expect(kBrandSignatureGoldPhoneActionSpacing, 12);
    expect(kBrandSignatureGoldPhoneCompactCardHeight, 132);
    expect(kBrandSignatureGoldPhoneActionIconBox, 96);
    expect(
      brandSignatureGoldChauffeurPhoneActionColumns(
        isPhoneLandscapeHost: false,
      ),
      2,
    );
    expect(
      brandSignatureGoldChauffeurPhoneActionColumns(isPhoneLandscapeHost: true),
      4,
    );
  });

  test('Gold chauffeur phone portrait source uses two columns', () {
    final qa = _quickActionsRegion();
    expect(qa, contains('} else if (isCustomHuisstijl) {'));
    expect(
      qa,
      contains(
        'columns = brandSignatureGoldChauffeurPhoneActionColumns(\n'
        '            isPhoneLandscapeHost: false,\n'
        '          );',
      ),
    );
    expect(qa, contains('kBrandSignatureGoldPhoneActionSpacing'));
    expect(qa, contains('kBrandSignatureGoldPhoneActionGridKey'));
    expect(qa, contains("goldActionKey: 'street_ride'"));
    expect(qa, contains("goldActionKey: 'fare_calculator'"));
    expect(qa, contains("goldActionKey: 'rides'"));
    expect(qa, contains("goldActionKey: 'history'"));
    expect(qa, contains("goldActionKey: 'receipts'"));
    expect(qa, contains("goldActionKey: 'documents'"));
    expect(qa, contains('onTap: _openDirectRideEntry'));
    expect(qa, contains('onTap: _openCalculatorFromDashboard'));
    expect(qa, contains('_openBookingsHubFromDashboard('));
    expect(qa, contains('onTap: _openTripHistoryFromDashboard'));
    expect(qa, contains('DriverMyDocumentsPage('));
    final street = qa.indexOf("goldActionKey: 'street_ride'");
    final fare = qa.indexOf("goldActionKey: 'fare_calculator'");
    final rides = qa.indexOf("goldActionKey: 'rides'");
    final history = qa.indexOf("goldActionKey: 'history'");
    expect(street, greaterThanOrEqualTo(0));
    expect(fare, greaterThan(street));
    expect(rides, greaterThan(fare));
    expect(history, greaterThan(rides));
  });

  test('non-Gold visual phone keeps one column', () {
    final qa = _quickActionsRegion();
    expect(qa, contains('} else if (isPhoneVisual) {'));
    final visual = qa.indexOf('} else if (isPhoneVisual) {');
    final block = qa.substring(visual, visual + 80);
    expect(block, contains('columns = 1;'));
    expect(qa, contains('} else if (isCustomHuisstijl) {'));
    expect(qa.indexOf('} else if (isCustomHuisstijl) {'), lessThan(visual));
  });

  test('tablet Gold height path stays on tablet tokens', () {
    final qa = _quickActionsRegion();
    expect(qa, contains('tabletPortraitCardMinHeight ?? 120.0'));
    expect(qa, contains('landscapeCardMinHeight ?? 98.0'));
    expect(qa, contains('isTabletPortrait) {'));
    expect(qa, contains('columns = 2;'));
    expect(qa, contains('forcedColumns ?? 3'));
  });

  test('company Gold phone grid stays two columns and unscoped', () {
    final home = _businessHome();
    expect(home, contains('final columns = isTabletLandscape ? 3 : 2;'));
    expect(home, contains('BrandSignatureGoldActionCard('));
    expect(home, isNot(contains('phoneGoldIconBox')));
    expect(home, isNot(contains('kBrandSignatureGoldPhoneActionGridKey')));
    expect(
      home,
      isNot(contains('brandSignatureGoldChauffeurPhoneActionColumns')),
    );
  });

  testWidgets('empty Gold subtitle does not reserve extra height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    const cardHeight =
        kBrandSignatureGoldPhoneCompactCardHeight +
        kBrandSignatureGoldActionCardHeightBoost;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 180,
                height: cardHeight,
                child: BrandSignatureGoldActionCard(
                  actionKey: 'street_ride',
                  title: 'Straatrit',
                  subtitle: '',
                  phoneGoldIconBox: true,
                ),
              ),
              SizedBox(
                width: 180,
                height: cardHeight,
                child: BrandSignatureGoldActionCard(
                  actionKey: 'history',
                  title: 'Historiek',
                  subtitle: 'Vorige ritten',
                  phoneGoldIconBox: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final emptyIcon = tester.getSize(
      find.byKey(kBrandSignatureGoldPhoneActionIconBoxKey).first,
    );
    final filledIcon = tester.getSize(
      find.byKey(kBrandSignatureGoldPhoneActionIconBoxKey).last,
    );
    expect(emptyIcon, const Size(96, 96));
    expect(filledIcon.width, lessThan(emptyIcon.width + 0.01));
    expect(find.text('Vorige ritten'), findsOneWidget);
    expect(find.text('Straatrit'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Gold phone titles wrap two lines without overflow', (
    tester,
  ) async {
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) {
        fail(details.toString());
      }
      FlutterError.presentError(details);
    };
    const titles = <(String, String)>[
      ('street_ride', 'Straatrit'),
      ('fare_calculator', 'Prijs berekenen'),
      ('rides', 'Mijn ritten'),
      ('history', 'Historiek'),
      ('fare_calculator', 'Fare calculator'),
      ('fare_calculator', 'Calcul de tarif'),
      ('fare_calculator', 'Calcular tarifa'),
      ('street_ride', 'Course directe'),
    ];
    for (final width in <double>[360, 390, 406.7]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: Wrap(
                spacing: kBrandSignatureGoldPhoneActionSpacing,
                runSpacing: kBrandSignatureGoldPhoneActionSpacing,
                children: [
                  for (final item in titles)
                    SizedBox(
                      width:
                          (width - kBrandSignatureGoldPhoneActionSpacing) / 2,
                      height:
                          kBrandSignatureGoldPhoneCompactCardHeight +
                          kBrandSignatureGoldActionCardHeightBoost,
                      child: BrandSignatureGoldActionCard(
                        actionKey: item.$1,
                        title: item.$2,
                        subtitle: '',
                        phoneGoldIconBox: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(
        find.byKey(brandSignatureGoldActionTitleKey('fare_calculator')).first,
      );
      expect(title.maxLines, 2);
      expect(
        tester.getSize(
          find.byKey(kBrandSignatureGoldPhoneActionIconBoxKey).first,
        ),
        const Size(
          kBrandSignatureGoldPhoneActionIconBox,
          kBrandSignatureGoldPhoneActionIconBox,
        ),
      );
    }
    await tester.binding.setSurfaceSize(null);
  });

  test('ChauffeurGoldIcon nav size token stays 25 in dashboard source', () {
    final src = _driverHome();
    expect(src, contains('const navIconSize = 25.0;'));
    expect(src, contains('ChauffeurGoldIcon('));
    expect(src, contains('size: navIconSize'));
  });
}
