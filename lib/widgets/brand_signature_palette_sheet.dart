import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';

const Key kBrandSignaturePaletteSheetKey = Key('brand_signature_palette_sheet');

Future<void> showBrandSignaturePaletteSheet(BuildContext context) async {
  previewBrandSignaturePalette(brandSignaturePaletteNotifier.value);
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const BrandSignaturePaletteSheet(),
  );
  if (applied != true) {
    cancelBrandSignaturePalettePreview();
  }
}

class BrandSignaturePaletteSheet extends StatelessWidget {
  const BrandSignaturePaletteSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: brandSignaturePaletteNotifier,
      builder: (context, colors, _) {
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              key: kBrandSignaturePaletteSheetKey,
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      brandSignatureCustomizeStyleLabel(),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ColorRow(
                      label: brandSignatureGoldL10n(
                        nl: 'Header',
                        en: 'Header',
                        fr: 'En-tête',
                        es: 'Encabezado',
                      ),
                      color: colors.header,
                      swatches: _headerChoices,
                      onSelected: (color) => previewBrandSignaturePalette(
                        colors.copyWith(header: color),
                      ),
                    ),
                    _ColorRow(
                      label: brandSignatureGoldL10n(
                        nl: 'Pagina',
                        en: 'Page',
                        fr: 'Page',
                        es: 'Página',
                      ),
                      color: colors.page,
                      swatches: _pageChoices,
                      onSelected: (color) => previewBrandSignaturePalette(
                        colors.copyWith(page: color),
                      ),
                    ),
                    _ColorRow(
                      label: brandSignatureGoldL10n(
                        nl: 'Kaarten',
                        en: 'Cards',
                        fr: 'Cartes',
                        es: 'Tarjetas',
                      ),
                      color: colors.card,
                      swatches: _cardChoices,
                      onSelected: (color) => previewBrandSignaturePalette(
                        colors.copyWith(card: color),
                      ),
                    ),
                    _ColorRow(
                      label: brandSignatureGoldL10n(
                        nl: 'Accent',
                        en: 'Accent',
                        fr: 'Accent',
                        es: 'Acento',
                      ),
                      color: colors.accent,
                      swatches: _accentChoices,
                      onSelected: (color) => previewBrandSignaturePalette(
                        colors.copyWith(accent: color),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(businessThemeSelectorCancelLabel()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              await applyBrandSignaturePalette(colors);
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

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.swatches,
    required this.onSelected,
  });

  final String label;
  final Color color;
  final List<Color> swatches;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = paletteForBusinessTheme(
      BusinessThemeVariant.brandSignatureGold,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final swatch in swatches)
                GestureDetector(
                  onTap: () => onSelected(swatch),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: swatch == color
                            ? palette.accent
                            : palette.border,
                        width: swatch == color ? 2.4 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

const List<Color> _headerChoices = <Color>[
  Color(0xFF1A1408),
  Color(0xFF2A1C0A),
  Color(0xFF0F1720),
  Color(0xFF3D2A10),
];

const List<Color> _pageChoices = <Color>[
  Color(0xFF0C0A07),
  Color(0xFF14110C),
  Color(0xFF0A0C10),
  Color(0xFF1A140C),
];

const List<Color> _cardChoices = <Color>[
  Color(0xFF1C160C),
  Color(0xFF241C10),
  Color(0xFF16120C),
  Color(0xFF2A2214),
];

const List<Color> _accentChoices = <Color>[
  Color(0xFFD4AF37),
  Color(0xFFE5B641),
  Color(0xFFC9A227),
  Color(0xFFF0C14B),
];
