import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'customer_app_header_branding.dart';
import 'header_local_cache.dart';
import 'customer_app_header_layout.dart';
import 'customer_app_header_mode.dart';

/// Shared renderer for the white-label header and the settings preview.
///
/// Marketplace Fluxidi screens must not use this widget.
class CustomerAppHeaderView extends StatelessWidget {
  const CustomerAppHeaderView({
    super.key,
    required this.branding,
    required this.trailing,
    required this.gold,
    required this.surface,
    required this.background,
    required this.textPrimary,
    this.logoImage,
    this.coverImage,
    this.coverAspectRatio,
    this.onCoverFailed,
    this.onLogoFailed,
  });

  final CustomerAppHeaderBranding branding;
  final Widget trailing;
  final Color gold;
  final Color surface;
  final Color background;
  final Color textPrimary;
  final ImageProvider? logoImage;
  final ImageProvider? coverImage;
  final double? coverAspectRatio;
  final VoidCallback? onCoverFailed;
  final VoidCallback? onLogoFailed;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final hasLogo = logoImage != null || branding.hasLogo;
    final hasCover = coverImage != null || branding.hasCover;
    final mode = effectiveCustomerAppHeaderMode(
      requested: branding.mode,
      hasLogo: hasLogo,
      hasCover: hasCover,
    );
    final metrics = customerAppHeaderMetrics(
      screen: screen,
      mode: mode,
      coverAspectRatio: coverAspectRatio ?? 8 / 3,
    );
    return KeyedSubtree(
      key: ValueKey<String>(
        'customer_app_header:${mode.name}:${branding.displayLogoUrl}:${branding.displayCoverUrl}',
      ),
      child: SizedBox(
        width: double.infinity,
        child: _HeaderBody(
          branding: branding,
          trailing: trailing,
          gold: gold,
          surface: surface,
          background: background,
          textPrimary: textPrimary,
          logoImage: logoImage,
          coverImage: coverImage,
          mode: mode,
          metrics: metrics,
          hasLogo: hasLogo,
          hasCover: hasCover,
          onCoverFailed: onCoverFailed,
          onLogoFailed: onLogoFailed,
        ),
      ),
    );
  }
}

class _HeaderBody extends StatelessWidget {
  const _HeaderBody({
    required this.branding,
    required this.trailing,
    required this.gold,
    required this.surface,
    required this.background,
    required this.textPrimary,
    required this.logoImage,
    required this.coverImage,
    required this.mode,
    required this.metrics,
    required this.hasLogo,
    required this.hasCover,
    this.onCoverFailed,
    this.onLogoFailed,
  });

  final CustomerAppHeaderBranding branding;
  final Widget trailing;
  final Color gold;
  final Color surface;
  final Color background;
  final Color textPrimary;
  final ImageProvider? logoImage;
  final ImageProvider? coverImage;
  final CustomerAppHeaderMode mode;
  final CustomerAppHeaderMetrics metrics;
  final bool hasLogo;
  final bool hasCover;
  final VoidCallback? onCoverFailed;
  final VoidCallback? onLogoFailed;

  @override
  Widget build(BuildContext context) {
    final logo = _LogoPane(
      branding: branding,
      gold: gold,
      textPrimary: textPrimary,
      logoImage: logoImage,
      frame: metrics.logoFrame,
      compact: mode == CustomerAppHeaderMode.coverAndLogo,
      alignment: mode == CustomerAppHeaderMode.logoOnly
          ? Alignment.center
          : branding.logoPosition == CustomerAppHeaderLogoPosition.topRight
          ? Alignment.centerRight
          : Alignment.centerLeft,
      onFailed: onLogoFailed,
    );
    final cover = hasCover
        ? _CoverPane(
            branding: branding,
            background: background,
            coverImage: coverImage,
            fallbackAspectRatio: metrics.coverSlot.height <= 0
                ? 8 / 3
                : metrics.coverSlot.width / metrics.coverSlot.height,
            maxHeight: customerAppHeaderMaxCoverHeight(
              MediaQuery.sizeOf(context),
            ),
            onFailed: onCoverFailed,
          )
        : const SizedBox.shrink();
    final media = mode == CustomerAppHeaderMode.coverAndLogo && hasCover
        ? _CoverWithOverlayLogo(
            cover: cover,
            logo: logo,
            logoSize: metrics.logoFrame,
            position: branding.logoPosition,
          )
        : mode == CustomerAppHeaderMode.logoOnly
        ? logo
        : cover;

    if (mode != CustomerAppHeaderMode.logoOnly && hasCover) {
      return ClipRect(
        child: Stack(
          children: <Widget>[
            media,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(
                  kCustomerAppHeaderLogoOverlayInset,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: Align(alignment: Alignment.topRight, child: trailing),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kCustomerAppHeaderGutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(alignment: Alignment.centerRight, child: trailing),
          const SizedBox(height: 6),
          media,
        ],
      ),
    );
  }
}

class _CoverWithOverlayLogo extends StatelessWidget {
  const _CoverWithOverlayLogo({
    required this.cover,
    required this.logo,
    required this.logoSize,
    required this.position,
  });

  final Widget cover;
  final Widget logo;
  final Size logoSize;
  final CustomerAppHeaderLogoPosition position;

  @override
  Widget build(BuildContext context) {
    final left = position == CustomerAppHeaderLogoPosition.topLeft;
    return Stack(
      children: <Widget>[
        cover,
        Positioned(
          bottom: kCustomerAppHeaderLogoOverlayInset,
          left: left ? kCustomerAppHeaderLogoOverlayInset : null,
          right: left ? null : kCustomerAppHeaderLogoOverlayInset,
          width: logoSize.width,
          height: logoSize.height,
          child: logo,
        ),
      ],
    );
  }
}

class _LogoPane extends StatelessWidget {
  const _LogoPane({
    required this.branding,
    required this.gold,
    required this.textPrimary,
    required this.logoImage,
    required this.frame,
    required this.compact,
    this.alignment = Alignment.centerLeft,
    this.onFailed,
  });

  final CustomerAppHeaderBranding branding;
  final Color gold;
  final Color textPrimary;
  final ImageProvider? logoImage;
  final Size frame;
  final bool compact;
  final Alignment alignment;
  final VoidCallback? onFailed;

  @override
  Widget build(BuildContext context) {
    final child = _logoChild();
    return Align(
      alignment: alignment,
      child: SizedBox(
        key: const Key('customer_header_logo_slot'),
        width: frame.width,
        height: frame.height,
        child: child,
      ),
    );
  }

  Widget _logoChild() {
    if (logoImage != null) {
      return Image(
        key: const Key('customer_header_logo'),
        image: logoImage!,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.high,
      );
    }
    if (branding.hasLogo) {
      return Image(
        image: headerImageProvider(branding.displayLogoUrl),
        key: const Key('customer_header_logo'),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, synchronous) =>
            synchronous || frame != null
            ? child
            : _NameFallback(
                name: branding.companyName,
                gold: gold,
                compact: compact,
              ),
        errorBuilder: (_, __, ___) {
          final notify = onFailed;
          if (notify != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => notify());
          }
          return _NameFallback(
            name: branding.companyName,
            gold: gold,
            compact: compact,
          );
        },
      );
    }
    return _NameFallback(
      name: branding.companyName,
      gold: gold,
      compact: compact,
    );
  }
}

class _NameFallback extends StatelessWidget {
  const _NameFallback({
    required this.name,
    required this.gold,
    required this.compact,
  });

  final String name;
  final Color gold;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = name.trim().isEmpty ? '' : name.trim();
    if (label.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        key: const Key('customer_header_company_name'),
        maxLines: 1,
        style: TextStyle(
          color: gold,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 22 : 28,
        ),
      ),
    );
  }
}

class _CoverPane extends StatelessWidget {
  const _CoverPane({
    required this.branding,
    required this.background,
    required this.coverImage,
    required this.fallbackAspectRatio,
    required this.maxHeight,
    this.onFailed,
  });

  final CustomerAppHeaderBranding branding;
  final Color background;
  final ImageProvider? coverImage;
  final double fallbackAspectRatio;
  final double maxHeight;
  final VoidCallback? onFailed;

  @override
  Widget build(BuildContext context) {
    final widget = this;
    final aspect = fallbackAspectRatio > 0 ? fallbackAspectRatio : 8 / 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final naturalHeight = width / aspect;
        final height = math.min(naturalHeight, widget.maxHeight);
        return ColoredBox(
          color: widget.background,
          child: SizedBox(
            key: const Key('customer_header_cover_slot'),
            width: width,
            height: height,
            child: widget.coverImage != null
                ? Image(
                    key: const Key('customer_header_cover'),
                    image: widget.coverImage!,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  )
                : Image(
                    image: headerImageProvider(widget.branding.displayCoverUrl),
                    key: const Key('customer_header_cover'),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    frameBuilder: (_, child, frame, synchronous) =>
                        synchronous || frame != null
                        ? child
                        : ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: Center(
                              child: Text(
                                widget.branding.companyName,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                          ),
                    errorBuilder: (_, __, ___) {
                      final notify = widget.onFailed;
                      if (notify != null) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => notify(),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        );
      },
    );
  }
}
