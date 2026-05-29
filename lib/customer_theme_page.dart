import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';

class CustomerThemePage extends StatefulWidget {
  const CustomerThemePage({super.key});

  @override
  State<CustomerThemePage> createState() => _CustomerThemePageState();
}

class _CustomerThemePageState extends State<CustomerThemePage> {
  @override
  void initState() {
    super.initState();
    // T2: load persisted selection when opening the theme selector.
    unawaited(loadCustomerThemePreference());
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (currentLanguageCode.toLowerCase()) {
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      case 'es':
        return es;
      case 'en':
      default:
        return en;
    }
  }

  Future<void> _selectTheme(CustomerThemeVariant variant) async {
    await saveCustomerThemePreference(variant);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Widget _paletteDot(Color color, {required bool darkBackground}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: darkBackground
              ? Colors.white.withOpacity(0.3)
              : Colors.black.withOpacity(0.16),
        ),
      ),
    );
  }

  Widget _themeCard({
    required CustomerThemeVariant variant,
    required CustomerThemeVariant current,
    required String title,
    required String description,
  }) {
    final previewPalette = paletteForCustomerTheme(variant);
    final selected = current == variant;
    final cardBorderColor = selected
        ? previewPalette.gold.withOpacity(previewPalette.isDark ? 0.86 : 0.95)
        : previewPalette.border.withOpacity(
            previewPalette.isDark ? 0.92 : 0.98,
          );
    final badgeBackground = previewPalette.isDark
        ? previewPalette.gold.withOpacity(0.24)
        : previewPalette.gold.withOpacity(0.16);
    final badgeBorder = previewPalette.gold.withOpacity(
      previewPalette.isDark ? 0.58 : 0.48,
    );
    final badgeText = previewPalette.isDark
        ? previewPalette.gold
        : previewPalette.bronze;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: selected ? null : () => _selectTheme(variant),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                previewPalette.surface,
                previewPalette.surfaceAlt.withOpacity(
                  previewPalette.isDark ? 0.95 : 0.88,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cardBorderColor,
              width: selected ? 1.35 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: previewPalette.shadow.withOpacity(
                  previewPalette.isDark ? 0.45 : 0.22,
                ),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: previewPalette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: badgeBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, size: 14, color: badgeText),
                          const SizedBox(width: 4),
                          Text(
                            _t(
                              nl: 'Actief',
                              en: 'Active',
                              fr: 'Actif',
                              es: 'Activo',
                            ),
                            style: TextStyle(
                              color: badgeText,
                              fontSize: 11.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                description,
                style: TextStyle(
                  color: previewPalette.textMuted,
                  fontSize: 12.8,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _paletteDot(
                    previewPalette.background,
                    darkBackground: previewPalette.isDark,
                  ),
                  const SizedBox(width: 8),
                  _paletteDot(
                    previewPalette.surface,
                    darkBackground: previewPalette.isDark,
                  ),
                  const SizedBox(width: 8),
                  _paletteDot(
                    previewPalette.textPrimary,
                    darkBackground: previewPalette.isDark,
                  ),
                  const SizedBox(width: 8),
                  _paletteDot(
                    previewPalette.gold,
                    darkBackground: previewPalette.isDark,
                  ),
                  const SizedBox(width: 8),
                  _paletteDot(
                    previewPalette.bronze,
                    darkBackground: previewPalette.isDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, currentVariant, _) {
        final palette = paletteForCustomerTheme(currentVariant);
        final variants = CustomerThemeVariant.values;
        final locale = currentLanguageCode.toLowerCase();
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.textPrimary,
            elevation: 0,
            title: Text(_t(nl: 'Thema', en: 'Theme', fr: 'Thème', es: 'Tema')),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              children: [
                for (var i = 0; i < variants.length; i++) ...[
                  _themeCard(
                    variant: variants[i],
                    current: currentVariant,
                    title: customerThemeMetadata(
                      variants[i],
                    ).title.resolve(locale),
                    description: customerThemeMetadata(
                      variants[i],
                    ).description.resolve(locale),
                  ),
                  if (i < variants.length - 1) const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    _t(
                      nl: 'Dit thema wordt lokaal opgeslagen. Later koppelen we dit aan je klantprofiel.',
                      en: 'This theme is saved locally. Later we’ll connect it to your customer profile.',
                      fr: 'Ce thème est enregistré localement. Il sera ensuite lié à votre profil client.',
                      es: 'Este tema se guarda localmente. Más adelante se conectará a tu perfil de cliente.',
                    ),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.3,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
