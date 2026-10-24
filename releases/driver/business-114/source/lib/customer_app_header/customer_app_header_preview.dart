import 'package:flutter/material.dart';

import 'customer_app_header_branding.dart';
import 'customer_app_header_layout.dart';
import 'customer_app_header_view.dart';

/// Phone and tablet previews that reuse [CustomerAppHeaderView].
class CustomerAppHeaderDevicePreviews extends StatelessWidget {
  const CustomerAppHeaderDevicePreviews({
    super.key,
    required this.branding,
    required this.gold,
    required this.surface,
    required this.background,
    required this.textPrimary,
    required this.border,
    this.phoneLabel = 'Gsm',
    this.tabletLabel = 'Tablet',
    this.logoImage,
    this.coverImage,
    this.coverAspectRatio,
  });

  final CustomerAppHeaderBranding branding;
  final Color gold;
  final Color surface;
  final Color background;
  final Color textPrimary;
  final Color border;
  final String phoneLabel;
  final String tabletLabel;
  final ImageProvider? logoImage;
  final ImageProvider? coverImage;
  final double? coverAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        final children = <Widget>[
          Expanded(
            child: _DeviceFrame(
              label: phoneLabel,
              device: const Size(390, 844),
              branding: branding,
              gold: gold,
              surface: surface,
              background: background,
              textPrimary: textPrimary,
              border: border,
              logoImage: logoImage,
              coverImage: coverImage,
              coverAspectRatio: coverAspectRatio,
            ),
          ),
          SizedBox(width: stacked ? 0 : 12, height: stacked ? 12 : 0),
          Expanded(
            child: _DeviceFrame(
              label: tabletLabel,
              device: const Size(800, 1280),
              branding: branding,
              gold: gold,
              surface: surface,
              background: background,
              textPrimary: textPrimary,
              border: border,
              logoImage: logoImage,
              coverImage: coverImage,
              coverAspectRatio: coverAspectRatio,
            ),
          ),
        ];
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({
    required this.label,
    required this.device,
    required this.branding,
    required this.gold,
    required this.surface,
    required this.background,
    required this.textPrimary,
    required this.border,
    this.logoImage,
    this.coverImage,
    this.coverAspectRatio,
  });

  final String label;
  final Size device;
  final CustomerAppHeaderBranding branding;
  final Color gold;
  final Color surface;
  final Color background;
  final Color textPrimary;
  final Color border;
  final ImageProvider? logoImage;
  final ImageProvider? coverImage;
  final double? coverAspectRatio;

  @override
  Widget build(BuildContext context) {
    final metrics = customerAppHeaderMetrics(
      screen: device,
      mode: branding.effectiveMode,
      coverAspectRatio: coverAspectRatio ?? 8 / 3,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: gold,
            fontWeight: FontWeight.w700,
            fontSize: 12.3,
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(10),
            color: background,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FittedBox(
              alignment: Alignment.topCenter,
              fit: BoxFit.contain,
              child: SizedBox(
                width: device.width,
                height: metrics.height,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(size: device),
                  child: CustomerAppHeaderView(
                    branding: branding,
                    gold: gold,
                    surface: surface,
                    background: background,
                    textPrimary: textPrimary,
                    logoImage: logoImage,
                    coverImage: coverImage,
                    coverAspectRatio: coverAspectRatio,
                    trailing: _PreviewChips(surface: surface, border: border),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewChips extends StatelessWidget {
  const _PreviewChips({required this.surface, required this.border});

  final Color surface;
  final Color border;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon) {
      return Container(
        width: kCustomerAppHeaderChipSize.width,
        height: kCustomerAppHeaderChipSize.height,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Icon(icon, size: 20),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        chip(Icons.language),
        const SizedBox(width: 6),
        chip(Icons.palette_outlined),
      ],
    );
  }
}
