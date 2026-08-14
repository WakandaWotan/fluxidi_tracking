import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/business_theme_cycle.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_palette_sheet.dart';

const Key kBusinessThemeSelectorSheetKey = Key('business_theme_selector_sheet');
const Key kBusinessThemeSelectorApplyKey = Key('business_theme_selector_apply');
const Key kBusinessThemeSelectorCancelKey = Key(
  'business_theme_selector_cancel',
);
const Key kBrandSignatureCustomizeStyleKey = Key(
  'brand_signature_customize_style',
);

Future<void> showBusinessThemeSelectorSheet(BuildContext context) async {
  previewBusinessTheme(businessThemeNotifier.value);
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const BusinessThemeSelectorSheet(),
  );
  if (applied != true) {
    cancelBusinessThemePreview();
  }
}

class BusinessThemeSelectorSheet extends StatelessWidget {
  const BusinessThemeSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, current, _) {
        final palette = paletteForBusinessTheme(current);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              key: kBusinessThemeSelectorSheetKey,
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      businessThemeSelectorTitle(),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final variant in BusinessThemeVariant.values)
                            _ThemePreviewTile(
                              variant: variant,
                              selected: variant == current,
                              onTap: () => previewBusinessTheme(variant),
                            ),
                        ],
                      ),
                    ),
                    if (current == BusinessThemeVariant.brandSignatureGold) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        key: kBrandSignatureCustomizeStyleKey,
                        onPressed: () =>
                            showBrandSignaturePaletteSheet(context),
                        child: Text(brandSignatureCustomizeStyleLabel()),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: kBusinessThemeSelectorCancelKey,
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(businessThemeSelectorCancelLabel()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            key: kBusinessThemeSelectorApplyKey,
                            onPressed: () async {
                              await applyBusinessThemePreset(current);
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            },
                            child: Text(businessThemeSelectorApplyLabel()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThemePreviewTile extends StatelessWidget {
  const _ThemePreviewTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final BusinessThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final swatch = paletteForBusinessTheme(variant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: Key('business_theme_selector_tile_${variant.name}'),
        color: selected
            ? swatch.accent.withOpacity(0.16)
            : swatch.surfaceAlt.withOpacity(0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: <Color>[
                        swatch.background,
                        swatch.surface,
                        swatch.accent,
                      ],
                    ),
                    border: Border.all(color: swatch.border),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    businessThemeProductLabel(variant),
                    style: TextStyle(
                      color: swatch.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_off,
                  key: selected
                      ? Key('business_theme_selector_check_${variant.name}')
                      : null,
                  color: selected ? swatch.accent : swatch.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
