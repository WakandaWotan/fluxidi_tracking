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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Thema opgeslagen.',
            en: 'Theme saved.',
            fr: 'Thème enregistré.',
            es: 'Tema guardado.',
          ),
        ),
      ),
    );
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
    required CustomerThemePalette pagePalette,
    required String title,
    required String description,
  }) {
    final preview = paletteForCustomerTheme(variant);
    final selected = current == variant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: selected ? null : () => _selectTheme(variant),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: pagePalette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? pagePalette.gold.withOpacity(0.9)
                  : pagePalette.border.withOpacity(0.9),
              width: selected ? 1.35 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: pagePalette.shadow.withOpacity(
                  pagePalette.isDark ? 0.5 : 0.25,
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
                        color: pagePalette.textPrimary,
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
                        color: pagePalette.gold.withOpacity(
                          pagePalette.isDark ? 0.22 : 0.16,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: pagePalette.gold.withOpacity(0.55),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: pagePalette.gold,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _t(
                              nl: 'Actief',
                              en: 'Active',
                              fr: 'Actif',
                              es: 'Activo',
                            ),
                            style: TextStyle(
                              color: pagePalette.gold,
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
                  color: pagePalette.textMuted,
                  fontSize: 12.8,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _paletteDot(
                    preview.background,
                    darkBackground: preview.isDark,
                  ),
                  const SizedBox(width: 8),
                  _paletteDot(preview.surface, darkBackground: preview.isDark),
                  const SizedBox(width: 8),
                  _paletteDot(
                    preview.textPrimary,
                    darkBackground: preview.isDark,
                  ),
                  const SizedBox(width: 8),
                  _paletteDot(preview.gold, darkBackground: preview.isDark),
                  const SizedBox(width: 8),
                  _paletteDot(preview.bronze, darkBackground: preview.isDark),
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
      builder: (context, variant, _) {
        final palette = paletteForCustomerTheme(variant);
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
                _themeCard(
                  variant: CustomerThemeVariant.premiumLight,
                  current: variant,
                  pagePalette: palette,
                  title: _t(
                    nl: 'Premium licht',
                    en: 'Premium light',
                    fr: 'Premium clair',
                    es: 'Premium claro',
                  ),
                  description: _t(
                    nl: 'Licht, warm en premium.',
                    en: 'Light, warm and premium.',
                    fr: 'Clair, chaleureux et premium.',
                    es: 'Claro, cálido y premium.',
                  ),
                ),
                const SizedBox(height: 10),
                _themeCard(
                  variant: CustomerThemeVariant.nightGold,
                  current: variant,
                  pagePalette: palette,
                  title: _t(
                    nl: 'Nacht goud',
                    en: 'Night gold',
                    fr: 'Nuit dorée',
                    es: 'Noche dorada',
                  ),
                  description: _t(
                    nl: 'Donker met Fluxidi-goud.',
                    en: 'Dark with Fluxidi gold.',
                    fr: 'Sombre avec l’or Fluxidi.',
                    es: 'Oscuro con oro Fluxidi.',
                  ),
                ),
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
