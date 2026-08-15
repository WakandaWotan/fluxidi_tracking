import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/driver_app_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme/driver_theme_selector.dart';
import 'package:fluxidi_tracking/driver_theme_cycle.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_style_dock.dart';
import 'package:fluxidi_tracking/widgets/business_theme_selector_sheet.dart';

const Key kDriverThemeSelectorApplyKey = Key('driver_theme_selector_apply');
const Key kDriverThemeSelectorCancelKey = Key('driver_theme_selector_cancel');

Future<void> showDriverThemeSelectorSheet(
  BuildContext context, {
  required bool companyDriverView,
}) async {
  final current = chauffeurThemeListenable(
    companyDriverView: companyDriverView,
  ).value;
  previewChauffeurTheme(current, companyDriverView: companyDriverView);
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DriverThemeSelectorSheet(
      companyDriverView: companyDriverView,
    ),
  );
  if (result == true) {
    return;
  }
  if (result == 'customize') {
    final persistGold = applyChauffeurTheme(
      DriverThemeVariant.customHuisstijl,
      companyDriverView: companyDriverView,
    );
    if (context.mounted) {
      await showBrandSignatureStyleEditor(
        context,
        controller: chauffeurCustomStyleController(
          companyDriverView: companyDriverView,
        ),
      );
    }
    await persistGold;
    return;
  }
  cancelChauffeurThemePreview(companyDriverView: companyDriverView);
}

class DriverThemeSelectorSheet extends StatelessWidget {
  const DriverThemeSelectorSheet({
    super.key,
    required this.companyDriverView,
  });

  final bool companyDriverView;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: chauffeurThemeListenable(
        companyDriverView: companyDriverView,
      ),
      builder: (context, current, _) {
        final palette = paletteForDriverTheme(current);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              key: kDriverThemeSelectorSheetKey,
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
                          for (final variant in kDriverThemeSelectorVariants)
                            _DriverThemePreviewTile(
                              variant: variant,
                              selected: variant == current,
                              onTap: () => previewChauffeurTheme(
                                variant,
                                companyDriverView: companyDriverView,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (current == DriverThemeVariant.customHuisstijl) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        key: kBrandSignatureCustomizeStyleKey,
                        onPressed: () =>
                            Navigator.of(context).pop('customize'),
                        child: Text(brandSignatureCustomizeStyleLabel()),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: kDriverThemeSelectorCancelKey,
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(businessThemeSelectorCancelLabel()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            key: kDriverThemeSelectorApplyKey,
                            onPressed: () async {
                              await applyChauffeurTheme(
                                current,
                                companyDriverView: companyDriverView,
                              );
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

class _DriverThemePreviewTile extends StatelessWidget {
  const _DriverThemePreviewTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final DriverThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final swatch = paletteForDriverTheme(variant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: driverThemeSelectorTileKey(variant),
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
                    driverThemeProductLabel(variant),
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
                      ? Key('driver_theme_selector_check_${variant.name}')
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
