import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/company/brand_signature_gold_windows_layout.dart';
import 'package:fluxidi_tracking/company/company_dashboard_layout.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_action_card.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_header.dart';

void main() {
  test('compact Gold grid applies only on Windows Brand Signature Gold', () {
    expect(
      brandSignatureGoldWindowsCompactApplies(
        platform: TargetPlatform.windows,
        isWeb: false,
        variant: BusinessThemeVariant.brandSignatureGold,
      ),
      isTrue,
    );
    expect(
      brandSignatureGoldWindowsCompactApplies(
        platform: TargetPlatform.windows,
        isWeb: false,
        variant: BusinessThemeVariant.cleanProfessional,
      ),
      isFalse,
    );
    expect(
      brandSignatureGoldWindowsCompactApplies(
        platform: TargetPlatform.android,
        isWeb: false,
        variant: BusinessThemeVariant.brandSignatureGold,
      ),
      isFalse,
    );
    expect(
      brandSignatureGoldWindowsCompactApplies(
        platform: TargetPlatform.android,
        isWeb: false,
        variant: BusinessThemeVariant.brandSignatureGold,
        ioWindows: true,
      ),
      isTrue,
    );
    expect(
      brandSignatureGoldWindowsCompactApplies(
        platform: TargetPlatform.windows,
        isWeb: true,
        variant: BusinessThemeVariant.brandSignatureGold,
      ),
      isFalse,
    );
  });

  test('other themes and phone/tablet keep the existing Gold column helper', () {
    expect(
      companyDashboardGoldTileColumns(
        screenClass: FluxidiScreenClass.desktop,
        isTabletLandscape: true,
      ),
      4,
    );
    expect(
      companyDashboardGoldTileColumns(
        screenClass: FluxidiScreenClass.tablet,
        isTabletLandscape: true,
      ),
      3,
    );
    expect(
      companyDashboardGoldTileColumns(
        screenClass: FluxidiScreenClass.phone,
        isTabletLandscape: false,
      ),
      2,
    );
  });

  test('visible columns stay at five on a Christophe-wide body', () {
    expect(brandSignatureGoldWindowsVisibleColumns(1268), 5);
    expect(brandSignatureGoldWindowsVisibleColumns(900), 5);
    expect(brandSignatureGoldWindowsVisibleColumns(880), 4);
    expect(
      (1268 - kBrandSignatureGoldWindowsTileSpacing * 4) / 5,
      greaterThanOrEqualTo(kBrandSignatureGoldWindowsMinReadableTileWidth),
    );
  });

  test('Gold home width uses the tightest client, never a wider MediaQuery', () {
    expect(
      brandSignatureGoldWindowsAvailableWidth(
        constraintWidth: 1648,
        mediaWidth: 2100,
        viewWidth: 1680,
      ),
      1648,
    );
    expect(
      brandSignatureGoldWindowsAvailableWidth(
        constraintWidth: double.infinity,
        mediaWidth: 1680,
        viewWidth: 1344,
      ),
      1344,
    );
    expect(
      brandSignatureGoldWindowsTileWidth(availableWidth: 1648, columns: 5),
      closeTo((1648 - 32) / 5, 0.01),
    );
  });

  test('a normal-wide Windows window fills height with five by two tiles', () {
    const viewport = Size(1440, 900);
    final metrics = brandSignatureGoldWindowsDashboardMetrics(
      viewport: viewport,
      headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
    );
    expect(metrics.columns, 5);
    expect(metrics.fitsWithoutScroll, isTrue);
    expect(
      metrics.tileHeight,
      greaterThan(kBrandSignatureGoldWindowsMinTileHeight),
    );
    expect(
      metrics.tileHeight,
      lessThanOrEqualTo(kBrandSignatureGoldWindowsMaxTileHeight),
    );
    expect(
      metrics.iconExtent,
      greaterThan(kBrandSignatureGoldWindowsMinIconExtent),
    );
    expect(
      metrics.iconExtent,
      lessThanOrEqualTo(kBrandSignatureGoldWindowsMaxIconExtent),
    );
    final grid = metrics.tileHeight * 2 + metrics.spacing;
    final chrome = brandSignatureGoldWindowsChromeHeight(
      headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
      textScale: 1,
    );
    expect(chrome + grid, lessThanOrEqualTo(viewport.height));
    expect(
      viewport.height - (chrome + grid),
      lessThanOrEqualTo(kBrandSignatureGoldWindowsChromeSlack + 8),
    );
  });

  test(
    'a 1280x720-class Windows body keeps header, KPIs, ten tiles and back',
    () {
      final inner = brandSignatureGoldWindowsDashboardMetrics(
        viewport: const Size(1236, 676),
        headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
        contentWidthOverride: 1236 - kBrandSignatureGoldWindowsListHorizontalPadding,
      );
      expect(inner.columns, 5);
      expect(inner.fitsWithoutScroll, isTrue);
      final chrome = brandSignatureGoldWindowsChromeHeight(
        headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
        textScale: 1,
      );
      expect(
        chrome + inner.tileHeight * 2 + inner.spacing,
        lessThanOrEqualTo(676),
      );
      expect(inner.tileHeight, greaterThan(132));
      expect(676 - (chrome + inner.tileHeight * 2 + inner.spacing),
          lessThanOrEqualTo(kBrandSignatureGoldWindowsChromeSlack + 8));

      final tightDpi = brandSignatureGoldWindowsDashboardMetrics(
        viewport: const Size(1000, 532),
        headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
      );
      expect(tightDpi.columns, 5);
      expect(tightDpi.fitsWithoutScroll, isTrue);
      expect(
        brandSignatureGoldWindowsChromeHeight(
              headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
              textScale: 1,
            ) +
            tightDpi.tileHeight * 2 +
            tightDpi.spacing,
        lessThanOrEqualTo(532),
      );
    },
  );

  test('small window or large text keeps a readable minimum and can scroll', () {
    final small = brandSignatureGoldWindowsDashboardMetrics(
      viewport: const Size(1100, 460),
      headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
    );
    expect(small.columns, 5);
    expect(
      small.tileHeight,
      greaterThanOrEqualTo(kBrandSignatureGoldWindowsMinTileHeight),
    );
    expect(small.fitsWithoutScroll, isFalse);

    final scaled = brandSignatureGoldWindowsDashboardMetrics(
      viewport: const Size(1440, 560),
      headerHeight: kBrandSignatureGoldHeaderHeightDesktopWide,
      textScale: 1.6,
    );
    expect(scaled.columns, 5);
    expect(scaled.fitsWithoutScroll, isFalse);
    expect(
      scaled.tileHeight,
      greaterThanOrEqualTo(kBrandSignatureGoldWindowsMinTileHeight),
    );
    expect(
      scaled.titleFontSize,
      greaterThan(kBrandSignatureGoldWindowsTitleFontSize),
    );
  });

  test('icon plus one-line labels fit the reserved tile height', () {
    const tileWidth = 218.0;
    const tileHeight = 118.0;
    final icon = brandSignatureGoldWindowsIconExtent(
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      textScale: 1,
    );
    final labels = brandSignatureGoldWindowsReservedLabelHeight(textScale: 1);
    expect(
      kBrandSignatureGoldWindowsTilePadding.vertical + icon + labels,
      lessThanOrEqualTo(tileHeight),
    );
  });

  testWidgets('compact Gold card binds the icon instead of expanding it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 128,
            child: BrandSignatureGoldActionCard(
              actionKey: 'settings',
              title: 'Instellingen',
              subtitle: 'Profiel & branding',
              padding: kBrandSignatureGoldWindowsTilePadding,
              iconExtent: 56,
              iconGap: kBrandSignatureGoldWindowsIconGap,
              titleFontSize: kBrandSignatureGoldWindowsTitleFontSize,
              subtitleFontSize: kBrandSignatureGoldWindowsSubtitleFontSize,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Instellingen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a live-sized compact Gold tile keeps a long subtitle inside the card',
    (tester) async {
      const tileWidth = 217.9;
      const tileHeight = 118.0;
      final icon = brandSignatureGoldWindowsIconExtent(
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        textScale: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: BrandSignatureGoldActionCard(
                  actionKey: 'drivers',
                  title: 'Driver view',
                  subtitle:
                      'open the existing driver cockpit without signing out',
                  padding: kBrandSignatureGoldWindowsTilePadding,
                  iconExtent: icon,
                  iconGap: kBrandSignatureGoldWindowsIconGap,
                  titleFontSize: kBrandSignatureGoldWindowsTitleFontSize,
                  subtitleFontSize: kBrandSignatureGoldWindowsSubtitleFontSize,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.text('Driver view'), findsOneWidget);
    },
  );

  testWidgets(
    'a five-by-two Gold grid keeps all ten tiles inside a wide window',
    (tester) async {
      const size = Size(1268, 520);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: BrandSignatureGoldWindowsActionGrid(
                columns: 5,
                spacing: kBrandSignatureGoldWindowsTileSpacing,
                tileHeight: 160,
                expandToParent: true,
                children: [
                  for (final entry in <(String, String)>[
                    ('settings', 'Instellingen'),
                    ('payments', 'Abonnement'),
                    ('vehicles', 'Voertuigen'),
                    ('chiron', 'Chiron'),
                    ('documents', 'Chauffeurs'),
                    ('ai_dispatch', 'Klantenbeheer'),
                    ('drivers', 'Chauffeur weergave'),
                    ('demand_radar', 'Vraagradar'),
                    ('booking_link', 'Deel boekingslink'),
                    ('planning', 'Boekingen'),
                  ])
                    BrandSignatureGoldActionCard(
                      actionKey: entry.$1,
                      title: entry.$2,
                      subtitle: 'Leesbare tekst',
                      padding: kBrandSignatureGoldWindowsTilePadding,
                      iconExtent: 48,
                      iconGap: kBrandSignatureGoldWindowsIconGap,
                      titleFontSize: kBrandSignatureGoldWindowsTitleFontSize,
                      subtitleFontSize:
                          kBrandSignatureGoldWindowsSubtitleFontSize,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.text('Boekingen'), findsOneWidget);
      expect(find.text('Chauffeurs'), findsOneWidget);
      expect(find.byType(BrandSignatureGoldActionCard), findsNWidgets(10));
      final grid = tester.getRect(
        find.byKey(kBrandSignatureGoldWindowsActionGridKey),
      );
      expect(grid.width, lessThanOrEqualTo(size.width + 0.5));
      expect(
        tester.getRect(find.text('Boekingen')).right,
        lessThanOrEqualTo(grid.right + 1),
      );
    },
  );

  testWidgets(
    'compact Windows Gold keeps Terug naar startpagina pinned and focused',
    (tester) async {
      const size = Size(1100, 700);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var openedStart = 0;
      var clearedCompany = 0;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: BrandSignatureGoldWindowsPinnedHome(
                pinColor: const Color(0xFF07080C),
                children: [
                  const SizedBox(height: 220, child: Text('header')),
                  for (var i = 0; i < 10; i++)
                    SizedBox(
                      height: 140,
                      child: Text('tile $i'),
                    ),
                ],
                backToStart: Semantics(
                  button: true,
                  enabled: true,
                  label: 'Terug naar startpagina',
                  child: Tooltip(
                    message: 'Terug naar startpagina',
                    child: OutlinedButton.icon(
                      key: const Key('fluxidi_back_to_start'),
                      focusNode: focusNode,
                      onPressed: () {
                        openedStart += 1;
                      },
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Terug naar startpagina'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final back = find.byKey(const Key('fluxidi_back_to_start'));
      expect(back, findsOneWidget);
      expect(find.byKey(kBrandSignatureGoldWindowsPinnedBackSlotKey), findsOneWidget);
      final backRect = tester.getRect(back);
      expect(backRect.top, greaterThanOrEqualTo(0));
      expect(backRect.bottom, lessThanOrEqualTo(size.height + 0.5));
      expect(backRect.height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(back),
        matchesSemantics(
          label: 'Terug naar startpagina',
          isButton: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasEnabledState: true,
          hasFocusAction: true,
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(openedStart, 1);
      expect(clearedCompany, 0);

      await tester.tap(back);
      await tester.pump();
      expect(openedStart, 2);
      expect(clearedCompany, 0);
    },
  );

  test('business home start navigation never clears the company session', () {
    final source = File(
      '${Directory.current.path}/lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    expect(source.contains('_openRoleEntryKeepCompanySession'), isTrue);
    final backFn = source.split('void _openRoleEntryKeepCompanySession()')[1];
    final body = backFn.split('Widget _businessBackToStartButton()')[0];
    expect(body.contains('clearLocalCompanyState'), isFalse);
    expect(body.contains('RoleEntryPage'), isTrue);
    expect(
      source.contains('onPressed: _openRoleEntryKeepCompanySession'),
      isTrue,
    );
    expect(
      source.contains("value == 'switch'") &&
          source.contains('_switchCompany(context)'),
      isTrue,
    );
  });
}
