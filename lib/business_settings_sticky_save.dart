// Sticky primary save/publish bar for Business settings.
//
// Rendered as Scaffold.bottomNavigationBar so the control stays in the
// visible app chrome. Bottom inset uses viewPadding (edge-to-edge Android)
// plus a fixed 12px gap — never a device-specific pixel height.

import 'dart:math' as math;

import 'package:flutter/material.dart';

const Key kBusinessSettingsStickySaveBarKey = ValueKey<String>(
  'business_settings_sticky_save_bar',
);
const Key kBusinessSettingsPublishEverythingButtonKey = ValueKey<String>(
  'business_settings_publish_everything_button',
);
const Key kBusinessSettingsSaveAndContinueButtonKey = ValueKey<String>(
  'business_settings_save_and_continue_button',
);

const double kBusinessSettingsStickyButtonMinHeight = 54;
const double kBusinessSettingsStickyGapAboveSystemInset = 12;

/// System nav/gesture inset plus the required 12px gap above it.
///
/// Uses the larger of [viewPadding] and [padding] so edge-to-edge
/// (padding == 0, viewPadding > 0) and classic insets both work, without
/// adding both and creating a double inset.
double businessSettingsStickyBottomInset(BuildContext context) {
  final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
  final padding = MediaQuery.paddingOf(context).bottom;
  return math.max(viewPadding, padding) +
      kBusinessSettingsStickyGapAboveSystemInset;
}

/// Extra ListView padding when the sticky bar overlays the body.
///
/// With [Scaffold.bottomNavigationBar] and [Scaffold.extendBody] == false
/// the body is already laid out above the bar, so callers should not add
/// this reserve on top of the Scaffold slot (that would double the gap).
double businessSettingsListBottomReserve({
  required double viewPaddingBottom,
  required double stickyBarHeight,
}) {
  return stickyBarHeight +
      viewPaddingBottom +
      kBusinessSettingsStickyGapAboveSystemInset;
}

class BusinessSettingsStickySaveBar extends StatelessWidget {
  const BusinessSettingsStickySaveBar({
    super.key,
    required this.label,
    required this.onPressed,
    required this.busy,
    this.continueMode = false,
    this.background,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool continueMode;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final bottom = businessSettingsStickyBottomInset(context);
    return Material(
      key: kBusinessSettingsStickySaveBarKey,
      color: background ?? Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      clipBehavior: Clip.none,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, bottom),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: continueMode
                  ? kBusinessSettingsSaveAndContinueButtonKey
                  : kBusinessSettingsPublishEverythingButtonKey,
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size(
                  double.infinity,
                  kBusinessSettingsStickyButtonMinHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                alignment: Alignment.center,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(continueMode ? Icons.save_outlined : Icons.save),
              label: Text(label, textAlign: TextAlign.center, maxLines: 2),
            ),
          ),
        ),
      ),
    );
  }
}
