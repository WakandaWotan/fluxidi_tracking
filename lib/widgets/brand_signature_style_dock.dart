import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_color_rail.dart';

const Key kBrandSignatureStyleDockKey = Key('brand_signature_style_dock');
const Key kBrandSignatureStyleEditorAbsorbKey = Key(
  'brand_signature_style_editor_absorb',
);
const Key kBrandSignatureResetDefaultKey = Key(
  'brand_signature_reset_default',
);
const Key kBrandSignatureStyleApplyKey = Key('brand_signature_style_apply');
const Key kBrandSignatureStyleCancelKey = Key('brand_signature_style_cancel');
const Key kBrandSignatureFamilySwatchKey = Key(
  'brand_signature_family_swatch',
);

/// Opens the floating huisstijl dock. No modal scrim — the live dashboard
/// stays at full brightness underneath.
Future<void> showBrandSignatureStyleEditor(BuildContext context) async {
  previewBrandSignaturePalette(brandSignaturePaletteNotifier.value);
  final applied = await Navigator.of(context).push<bool>(
    BrandSignatureStyleEditorRoute(),
  );
  if (applied != true) {
    cancelBrandSignaturePalettePreview();
  }
}

/// Kept so existing call sites keep compiling; the four-row sheet is gone.
Future<void> showBrandSignaturePaletteSheet(BuildContext context) =>
    showBrandSignatureStyleEditor(context);

class BrandSignatureStyleEditorRoute extends PageRoute<bool> {
  BrandSignatureStyleEditorRoute() : super(fullscreenDialog: true);

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const BrandSignatureStyleEditor();
  }
}

class BrandSignatureStyleEditor extends StatelessWidget {
  const BrandSignatureStyleEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        cancelBrandSignaturePalettePreview();
        Navigator.of(context).pop(false);
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned.fill(
              child: AbsorbPointer(
                key: kBrandSignatureStyleEditorAbsorbKey,
                child: SizedBox.expand(),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: BrandSignatureStyleDock(),
            ),
          ],
        ),
      ),
    );
  }
}

class BrandSignatureStyleDock extends StatelessWidget {
  const BrandSignatureStyleDock({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: brandSignaturePaletteNotifier,
      builder: (context, colors, _) {
        final chrome = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Material(
            key: kBrandSignatureStyleDockKey,
            color: chrome.surface.withOpacity(0.96),
            elevation: 10,
            shadowColor: const Color(0x66000000),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    brandSignatureRailTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: chrome.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: kBrandSignatureColorRailMinHeight,
                    width: double.infinity,
                    child: BrandSignatureColorRail(
                      position: colors.position,
                      onChanged: previewBrandSignatureRailPosition,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        key: kBrandSignatureFamilySwatchKey,
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colors.base,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          brandSignatureFamilyLabel(colors.familyId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: chrome.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: kBrandSignatureResetDefaultKey,
                      onPressed: () => previewBrandSignatureRailPosition(
                        kBrandSignatureDefaultPosition,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: kBrandSignatureGoldAccent,
                      ),
                      child: Text(brandSignatureResetDefaultLabel()),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: kBrandSignatureStyleCancelKey,
                          onPressed: () {
                            cancelBrandSignaturePalettePreview();
                            Navigator.of(context).pop(false);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: chrome.textPrimary,
                            side: const BorderSide(
                              color: kBrandSignatureGoldAccent,
                            ),
                          ),
                          child: Text(businessThemeSelectorCancelLabel()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: kBrandSignatureStyleApplyKey,
                          onPressed: () async {
                            await applyBrandSignaturePalette(colors);
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: kBrandSignatureGoldAccent,
                            foregroundColor: const Color(0xFF1A1408),
                          ),
                          child: Text(businessThemeSelectorApplyLabel()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
