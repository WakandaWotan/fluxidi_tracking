// COMPANY-CUSTOMER-OPS-P0 — Windows-only compact Brand Signature Gold home.
//
// Other business themes and phone/tablet hosts keep their existing grids.
// This helper never applies a page-wide scale factor.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';

const Key kBrandSignatureGoldWindowsActionGridKey = Key(
  'brand_signature_gold_windows_action_grid',
);

const int kBrandSignatureGoldWindowsTileCount = 11;
const int kBrandSignatureGoldWindowsPreferredColumns = 5;
const int kBrandSignatureGoldWindowsPreferredRows = 2;
const double kBrandSignatureGoldWindowsFiveColumnMinWidth = 900;
const double kBrandSignatureGoldWindowsMinReadableTileWidth = 148;
const double kBrandSignatureGoldWindowsMinTileHeight = 96;
const double kBrandSignatureGoldWindowsMaxTileHeight = 320;
const double kBrandSignatureGoldWindowsMinIconExtent = 36;
const double kBrandSignatureGoldWindowsMaxIconExtent = 200;
const double kBrandSignatureGoldWindowsTileSpacing = 8;
const double kBrandSignatureGoldWindowsFrameInset = 22;
const double kBrandSignatureGoldWindowsListHorizontalPadding = 32;
const double kBrandSignatureGoldWindowsKpiStatusHeight = 48;
const double kBrandSignatureGoldWindowsKpiRowHeight = 56;
const double kBrandSignatureGoldWindowsBackButtonHeight = 48;
const double kBrandSignatureGoldWindowsChromeSlack = 8;
const EdgeInsets kBrandSignatureGoldWindowsTilePadding = EdgeInsets.fromLTRB(
  8,
  6,
  8,
  6,
);
const double kBrandSignatureGoldWindowsIconGap = 4;
const double kBrandSignatureGoldWindowsTitleFontSize = 12.5;
const double kBrandSignatureGoldWindowsSubtitleFontSize = 10.5;
const double kBrandSignatureGoldWindowsLabelLineHeight = 1.25;
const double kBrandSignatureGoldWindowsSubtitleGap = 2;
const double kBrandSignatureGoldWindowsLabelSlack = 3;

double brandSignatureGoldWindowsReservedLabelHeight({
  required double textScale,
  double iconGap = kBrandSignatureGoldWindowsIconGap,
  double titleFontSize = kBrandSignatureGoldWindowsTitleFontSize,
  double subtitleFontSize = kBrandSignatureGoldWindowsSubtitleFontSize,
}) {
  final scale = textScale <= 0 ? 1.0 : textScale;
  return iconGap +
      titleFontSize * scale * kBrandSignatureGoldWindowsLabelLineHeight +
      kBrandSignatureGoldWindowsSubtitleGap +
      subtitleFontSize * scale * kBrandSignatureGoldWindowsLabelLineHeight +
      kBrandSignatureGoldWindowsLabelSlack;
}

/// True only for Brand Signature Gold on the Flutter Windows desktop host.
bool brandSignatureGoldWindowsCompactApplies({
  required TargetPlatform platform,
  required bool isWeb,
  required BusinessThemeVariant variant,
  bool? ioWindows,
}) {
  final windows = platform == TargetPlatform.windows || ioWindows == true;
  return !isWeb &&
      windows &&
      variant == BusinessThemeVariant.brandSignatureGold;
}

int brandSignatureGoldWindowsTileColumns(double contentWidth) {
  if (contentWidth >= kBrandSignatureGoldWindowsFiveColumnMinWidth) {
    return kBrandSignatureGoldWindowsPreferredColumns;
  }
  if (contentWidth >= 720) return 4;
  if (contentWidth >= 520) return 3;
  return 2;
}

/// Drops columns only when a five-across tile would be too narrow to read.
int brandSignatureGoldWindowsVisibleColumns(double availableWidth) {
  if (availableWidth <= 0) return 2;
  var columns = brandSignatureGoldWindowsTileColumns(availableWidth);
  while (columns > 2) {
    final tileWidth =
        (availableWidth -
            kBrandSignatureGoldWindowsTileSpacing * (columns - 1)) /
        columns;
    if (tileWidth >= kBrandSignatureGoldWindowsMinReadableTileWidth) {
      break;
    }
    columns -= 1;
  }
  return columns;
}

/// Tightest finite width the Gold home may use. Never take the max of
/// MediaQuery and the parent — that sizes five tiles past the client.
double brandSignatureGoldWindowsAvailableWidth({
  required double constraintWidth,
  required double mediaWidth,
  double viewWidth = 0,
}) {
  var width = 0.0;
  void consider(double value) {
    if (!value.isFinite || value <= 0) return;
    width = width <= 0 ? value : math.min(width, value);
  }

  consider(constraintWidth);
  consider(mediaWidth);
  consider(viewWidth);
  return width;
}

double brandSignatureGoldWindowsTileWidth({
  required double availableWidth,
  required int columns,
  double spacing = kBrandSignatureGoldWindowsTileSpacing,
}) {
  final count = columns < 1 ? 1 : columns;
  if (count <= 1) return math.max(0.0, availableWidth);
  return math.max(0.0, (availableWidth - spacing * (count - 1)) / count);
}

double brandSignatureGoldWindowsIconExtent({
  required double tileWidth,
  required double tileHeight,
  required double textScale,
  EdgeInsets padding = kBrandSignatureGoldWindowsTilePadding,
  double iconGap = kBrandSignatureGoldWindowsIconGap,
  double titleFontSize = kBrandSignatureGoldWindowsTitleFontSize,
  double subtitleFontSize = kBrandSignatureGoldWindowsSubtitleFontSize,
}) {
  final labelBlock = brandSignatureGoldWindowsReservedLabelHeight(
    textScale: textScale,
    iconGap: iconGap,
    titleFontSize: titleFontSize,
    subtitleFontSize: subtitleFontSize,
  );
  final innerWidth = math.max(0.0, tileWidth - padding.horizontal);
  final innerHeight = math.max(0.0, tileHeight - padding.vertical - labelBlock);
  final raw = math.min(innerWidth, innerHeight);
  if (raw <= 0) return kBrandSignatureGoldWindowsMinIconExtent;
  return raw.clamp(
    kBrandSignatureGoldWindowsMinIconExtent,
    kBrandSignatureGoldWindowsMaxIconExtent,
  );
}

/// Reserved chrome above/below the 5×2 Gold action grid on Business Home.
///
/// [viewport] passed to [brandSignatureGoldWindowsDashboardMetrics] is the
/// home body inside [FluxidiFrame], so this does not subtract the frame again.
double brandSignatureGoldWindowsChromeHeight({
  required double headerHeight,
  required double textScale,
}) {
  final scale = textScale < 1 ? 1.0 : textScale;
  const listPadding = 10.0 + 12.0;
  const sectionGap = 8.0;
  final kpiStatus = kBrandSignatureGoldWindowsKpiStatusHeight * scale;
  final kpi = kBrandSignatureGoldWindowsKpiRowHeight * scale;
  const titleGap = 8.0;
  final title = 16.0 * scale;
  const gridTopGap = 8.0;
  const backGap = 10.0;
  final back = kBrandSignatureGoldWindowsBackButtonHeight * scale;
  return listPadding +
      headerHeight +
      sectionGap +
      kpiStatus +
      kpi +
      titleGap +
      title +
      gridTopGap +
      backGap +
      back +
      kBrandSignatureGoldWindowsChromeSlack;
}

@immutable
class BrandSignatureGoldWindowsDashboardMetrics {
  const BrandSignatureGoldWindowsDashboardMetrics({
    required this.columns,
    required this.tileWidth,
    required this.tileHeight,
    required this.iconExtent,
    required this.spacing,
    required this.tilePadding,
    required this.titleFontSize,
    required this.subtitleFontSize,
    required this.iconGap,
    required this.sectionGap,
    required this.titleGap,
    required this.gridTopGap,
    required this.backGap,
    required this.listPaddingTop,
    required this.listPaddingBottom,
    required this.fitsWithoutScroll,
  });

  final int columns;
  final double tileWidth;
  final double tileHeight;
  final double iconExtent;
  final double spacing;
  final EdgeInsets tilePadding;
  final double titleFontSize;
  final double subtitleFontSize;
  final double iconGap;
  final double sectionGap;
  final double titleGap;
  final double gridTopGap;
  final double backGap;
  final double listPaddingTop;
  final double listPaddingBottom;
  final bool fitsWithoutScroll;

  BrandSignatureGoldWindowsDashboardMetrics copyWith({
    int? columns,
    double? tileWidth,
    double? tileHeight,
    double? iconExtent,
    bool? fitsWithoutScroll,
  }) {
    return BrandSignatureGoldWindowsDashboardMetrics(
      columns: columns ?? this.columns,
      tileWidth: tileWidth ?? this.tileWidth,
      tileHeight: tileHeight ?? this.tileHeight,
      iconExtent: iconExtent ?? this.iconExtent,
      spacing: spacing,
      tilePadding: tilePadding,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
      iconGap: iconGap,
      sectionGap: sectionGap,
      titleGap: titleGap,
      gridTopGap: gridTopGap,
      backGap: backGap,
      listPaddingTop: listPaddingTop,
      listPaddingBottom: listPaddingBottom,
      fitsWithoutScroll: fitsWithoutScroll ?? this.fitsWithoutScroll,
    );
  }
}

BrandSignatureGoldWindowsDashboardMetrics
brandSignatureGoldWindowsDashboardMetrics({
  required Size viewport,
  required double headerHeight,
  double textScale = 1.0,
  double contentWidthOverride = 0,
}) {
  final scale = textScale <= 0 ? 1.0 : textScale;
  final contentWidth = contentWidthOverride > 0
      ? contentWidthOverride
      : math.max(
          0.0,
          viewport.width - kBrandSignatureGoldWindowsListHorizontalPadding,
        );
  final columns = brandSignatureGoldWindowsVisibleColumns(contentWidth);
  const spacing = kBrandSignatureGoldWindowsTileSpacing;
  final tileWidth = columns <= 1
      ? contentWidth
      : (contentWidth - spacing * (columns - 1)) / columns;
  final chrome = brandSignatureGoldWindowsChromeHeight(
    headerHeight: headerHeight,
    textScale: scale,
  );
  final availableForGrid = viewport.height - chrome;
  final rows = columns >= kBrandSignatureGoldWindowsPreferredColumns
      ? kBrandSignatureGoldWindowsPreferredRows
      : (kBrandSignatureGoldWindowsTileCount / columns).ceil();
  final rawTileHeight = rows <= 1
      ? availableForGrid
      : (availableForGrid - spacing * (rows - 1)) / rows;
  final tileHeight = rawTileHeight
      .clamp(
        kBrandSignatureGoldWindowsMinTileHeight,
        kBrandSignatureGoldWindowsMaxTileHeight,
      )
      .toDouble();
  final neededHeight =
      chrome + tileHeight * rows + spacing * math.max(0, rows - 1);
  final fits =
      neededHeight <= viewport.height &&
      columns >= kBrandSignatureGoldWindowsPreferredColumns &&
      rawTileHeight >= kBrandSignatureGoldWindowsMinTileHeight;
  final titleFontSize = kBrandSignatureGoldWindowsTitleFontSize * scale;
  final subtitleFontSize = kBrandSignatureGoldWindowsSubtitleFontSize * scale;
  final iconExtent = brandSignatureGoldWindowsIconExtent(
    tileWidth: tileWidth,
    tileHeight: tileHeight,
    textScale: scale,
    titleFontSize: kBrandSignatureGoldWindowsTitleFontSize,
    subtitleFontSize: kBrandSignatureGoldWindowsSubtitleFontSize,
  );
  return BrandSignatureGoldWindowsDashboardMetrics(
    columns: columns,
    tileWidth: tileWidth,
    tileHeight: tileHeight,
    iconExtent: iconExtent,
    spacing: spacing,
    tilePadding: kBrandSignatureGoldWindowsTilePadding,
    titleFontSize: titleFontSize,
    subtitleFontSize: subtitleFontSize,
    iconGap: kBrandSignatureGoldWindowsIconGap,
    sectionGap: 8,
    titleGap: 8,
    gridTopGap: 8,
    backGap: 10,
    listPaddingTop: 10,
    listPaddingBottom: 12,
    fitsWithoutScroll: fits,
  );
}

/// Sizes Gold home tiles from the painted grid width so a fifth column
/// cannot overflow the window. Vertical scroll stays available when the
/// preferred two rows do not fit.
class BrandSignatureGoldWindowsActionGrid extends StatelessWidget {
  const BrandSignatureGoldWindowsActionGrid({
    super.key,
    required this.columns,
    required this.spacing,
    required this.tileHeight,
    required this.children,
    this.scrollable = false,
    this.expandToParent = false,
  });

  final int columns;
  final double spacing;
  final double tileHeight;
  final List<Widget> children;
  final bool scrollable;

  /// When true the grid uses the parent box instead of shrinking to the
  /// Gold artwork's intrinsic width, which would clip the fifth column.
  final bool expandToParent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = View.of(context);
        final viewWidth = view.devicePixelRatio > 0
            ? view.physicalSize.width / view.devicePixelRatio
            : 0.0;
        final width = brandSignatureGoldWindowsAvailableWidth(
          constraintWidth: constraints.maxWidth,
          mediaWidth: MediaQuery.sizeOf(context).width,
          viewWidth: viewWidth,
        );
        final count = columns < 1 ? 1 : columns;
        final tileWidth = brandSignatureGoldWindowsTileWidth(
          availableWidth: width,
          columns: count,
          spacing: spacing,
        );
        final rows = math.max(1, (children.length / count).ceil());
        final neededHeight =
            tileHeight * rows + spacing * math.max(0, rows - 1);
        final hostHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : neededHeight;
        final rowWidgets = <Widget>[];
        for (var start = 0; start < children.length; start += count) {
          final end = math.min(start + count, children.length);
          rowWidgets.add(
            Row(
              children: [
                for (var i = start; i < end; i += 1) ...[
                  if (i > start) SizedBox(width: spacing),
                  SizedBox(
                    width: tileWidth,
                    height: tileHeight,
                    child: ClipRect(child: children[i]),
                  ),
                ],
              ],
            ),
          );
        }
        Widget grid = Column(
          key: kBrandSignatureGoldWindowsActionGridKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < rowWidgets.length; r += 1) ...[
              if (r > 0) SizedBox(height: spacing),
              rowWidgets[r],
            ],
          ],
        );
        final mustScroll =
            scrollable ||
            (constraints.maxHeight.isFinite && neededHeight > hostHeight + 0.5);
        if (mustScroll) {
          grid = SingleChildScrollView(
            child: SizedBox(width: width, child: grid),
          );
        }
        return SizedBox(
          width: width,
          height: expandToParent && constraints.maxHeight.isFinite
              ? hostHeight
              : (mustScroll ? hostHeight : neededHeight),
          child: ClipRect(child: grid),
        );
      },
    );
  }
}

const Key kBrandSignatureGoldWindowsPinnedHomeKey = Key(
  'brand_signature_gold_windows_pinned_home',
);
const Key kBrandSignatureGoldWindowsPinnedBackSlotKey = Key(
  'brand_signature_gold_windows_pinned_back_slot',
);

/// Gold compact home: tiles may scroll, the start-page action stays pinned.
///
/// Never clip the back control under the tile grid. This only changes
/// overflow handling; it does not restyle the dashboard.
class BrandSignatureGoldWindowsPinnedHome extends StatelessWidget {
  const BrandSignatureGoldWindowsPinnedHome({
    super.key,
    required this.children,
    required this.backToStart,
    required this.pinColor,
    this.listPadding = EdgeInsets.zero,
    this.backGap = 10,
    this.listBottom = 12,
  });

  final List<Widget> children;
  final Widget backToStart;
  final Color pinColor;
  final EdgeInsets listPadding;
  final double backGap;
  final double listBottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: kBrandSignatureGoldWindowsPinnedHomeKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: listPadding.copyWith(bottom: 8),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: children,
          ),
        ),
        ColoredBox(
          key: kBrandSignatureGoldWindowsPinnedBackSlotKey,
          color: pinColor,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, backGap, 16, listBottom),
            child: backToStart,
          ),
        ),
      ],
    );
  }
}
