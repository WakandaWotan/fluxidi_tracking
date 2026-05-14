import 'package:flutter/material.dart';

enum FluxidiScreenClass { compactPhone, phone, largePhone, tablet, desktop }

class FluxidiBreakpoints {
  static const double compactPhoneMax = 359;
  static const double phoneMax = 479;
  static const double largePhoneMax = 767;
  static const double tabletMax = 1199;

  static FluxidiScreenClass classifyWidth(double width) {
    if (width <= compactPhoneMax) return FluxidiScreenClass.compactPhone;
    if (width <= phoneMax) return FluxidiScreenClass.phone;
    if (width <= largePhoneMax) return FluxidiScreenClass.largePhone;
    if (width <= tabletMax) return FluxidiScreenClass.tablet;
    return FluxidiScreenClass.desktop;
  }
}

class FluxidiResponsiveInfo {
  final double width;
  final double height;
  final Orientation orientation;
  final EdgeInsets padding;
  final FluxidiScreenClass screenClass;

  const FluxidiResponsiveInfo({
    required this.width,
    required this.height,
    required this.orientation,
    required this.padding,
    required this.screenClass,
  });

  factory FluxidiResponsiveInfo.of(BuildContext context) {
    final media = MediaQuery.of(context);
    return FluxidiResponsiveInfo(
      width: media.size.width,
      height: media.size.height,
      orientation: media.orientation,
      padding: media.padding,
      screenClass: FluxidiBreakpoints.classifyWidth(media.size.width),
    );
  }

  bool get isCompactPhone => screenClass == FluxidiScreenClass.compactPhone;
  bool get isPhoneLike =>
      screenClass == FluxidiScreenClass.compactPhone ||
      screenClass == FluxidiScreenClass.phone ||
      screenClass == FluxidiScreenClass.largePhone;
  bool get isTabletUp =>
      screenClass == FluxidiScreenClass.tablet ||
      screenClass == FluxidiScreenClass.desktop;
  bool get isLandscape => orientation == Orientation.landscape;
}

class FluxidiSpacing {
  final double pageHorizontal;
  final double pageVertical;
  final double sectionGap;
  final double cardGap;

  const FluxidiSpacing({
    required this.pageHorizontal,
    required this.pageVertical,
    required this.sectionGap,
    required this.cardGap,
  });

  factory FluxidiSpacing.of(FluxidiResponsiveInfo info) {
    if (info.isCompactPhone) {
      return const FluxidiSpacing(
        pageHorizontal: 12,
        pageVertical: 10,
        sectionGap: 10,
        cardGap: 8,
      );
    }
    if (info.isPhoneLike) {
      return const FluxidiSpacing(
        pageHorizontal: 14,
        pageVertical: 12,
        sectionGap: 12,
        cardGap: 10,
      );
    }
    return const FluxidiSpacing(
      pageHorizontal: 18,
      pageVertical: 14,
      sectionGap: 14,
      cardGap: 12,
    );
  }
}

class FluxidiPageShell extends StatelessWidget {
  final Widget child;
  final double maxContentWidth;
  final bool includeSafeArea;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  const FluxidiPageShell({
    super.key,
    required this.child,
    this.maxContentWidth = 980,
    this.includeSafeArea = true,
    this.scrollable = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final info = FluxidiResponsiveInfo.of(context);
    final spacing = FluxidiSpacing.of(info);
    final resolvedPadding =
        padding ??
        EdgeInsets.symmetric(
          horizontal: spacing.pageHorizontal,
          vertical: spacing.pageVertical,
        );

    Widget content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(padding: resolvedPadding, child: child),
      ),
    );

    if (scrollable) {
      content = SingleChildScrollView(child: content);
    }
    if (includeSafeArea) {
      content = SafeArea(child: content);
    }
    return content;
  }
}

class FluxidiResponsiveDialog extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const FluxidiResponsiveDialog({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.padding,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    double maxWidth = 560,
    EdgeInsetsGeometry? padding,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => FluxidiResponsiveDialog(
        maxWidth: maxWidth,
        padding: padding,
        child: builder(dialogContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = FluxidiResponsiveInfo.of(context);
    final horizontalInset = info.isCompactPhone ? 10.0 : 18.0;
    final verticalInset = info.isLandscape ? 12.0 : 20.0;
    final resolvedPadding =
        padding ??
        EdgeInsets.fromLTRB(
          horizontalInset,
          verticalInset,
          horizontalInset,
          verticalInset,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedWidth = constraints.maxWidth - (horizontalInset * 2);
        final effectiveMaxWidth = constrainedWidth < maxWidth
            ? constrainedWidth
            : maxWidth;
        return Align(
          alignment: Alignment.center,
          child: SingleChildScrollView(
            padding: resolvedPadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

typedef FluxidiIndexedWidgetBuilder =
    Widget Function(BuildContext context, int index);

class FluxidiAdaptiveGrid extends StatelessWidget {
  final int itemCount;
  final FluxidiIndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;
  final int? maxColumns;

  const FluxidiAdaptiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 220,
    this.spacing = 10,
    this.runSpacing = 10,
    this.maxColumns,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final roughColumns =
            ((availableWidth + spacing) / (minItemWidth + spacing)).floor();
        final resolvedColumns = roughColumns < 1 ? 1 : roughColumns;
        final columns = maxColumns == null
            ? resolvedColumns
            : resolvedColumns.clamp(1, maxColumns!);
        final totalSpacing = spacing * (columns - 1);
        final itemWidth = (availableWidth - totalSpacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: List<Widget>.generate(itemCount, (index) {
            return SizedBox(
              width: itemWidth,
              child: itemBuilder(context, index),
            );
          }),
        );
      },
    );
  }
}
