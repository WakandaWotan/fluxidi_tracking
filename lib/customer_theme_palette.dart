import 'package:flutter/material.dart';

enum CustomerThemeVariant {
  premiumLight,
  nightGold,
  ivoryGold,
  champagneSand,
  urbanSlate,
  midnightPlatinum,
  royalBlueGold,
  emeraldGarden,
  roseQuartz,
  lavenderMist,
  emeraldNoir,
}

@immutable
class CustomerThemePalette {
  const CustomerThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.gold,
    required this.bronze,
    required this.border,
    required this.danger,
    required this.success,
    required this.shadow,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;
  final Color gold;
  final Color bronze;
  final Color border;
  final Color danger;
  final Color success;
  final Color shadow;
  final bool isDark;
}

@immutable
class CustomerThemeLocalizedText {
  const CustomerThemeLocalizedText({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
  });

  final String nl;
  final String en;
  final String fr;
  final String es;

  String resolve(String languageCode) {
    switch (languageCode.toLowerCase()) {
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
}

@immutable
class CustomerThemeMetadata {
  const CustomerThemeMetadata({
    required this.variant,
    required this.title,
    required this.description,
  });

  final CustomerThemeVariant variant;
  final CustomerThemeLocalizedText title;
  final CustomerThemeLocalizedText description;
}

const CustomerThemePalette _premiumLightPalette = CustomerThemePalette(
  background: Color(0xFFFFFBF4),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFFFF5E8),
  textPrimary: Color(0xFF182028),
  textMuted: Color(0xFF5F6670),
  gold: Color(0xFFC49A45),
  bronze: Color(0xFFB88735),
  border: Color(0xFFE7DECF),
  danger: Color(0xFFCD5C6C),
  success: Color(0xFF34D29A),
  shadow: Color(0x33000000),
  isDark: false,
);

const CustomerThemePalette _nightGoldPalette = CustomerThemePalette(
  background: Color(0xFF07080C),
  surface: Color(0xFF101010),
  surfaceAlt: Color(0xFF16120A),
  textPrimary: Color(0xFFFFFFFF),
  textMuted: Color(0xB3FFFFFF),
  gold: Color(0xFFE5B641),
  bronze: Color(0xFFC8943F),
  border: Color(0xFF3B2C14),
  danger: Color(0xFFCD5C6C),
  success: Color(0xFF34D29A),
  shadow: Color(0x66000000),
  isDark: true,
);

const CustomerThemePalette _ivoryGoldPalette = CustomerThemePalette(
  background: Color(0xFFFFFCF6),
  surface: Color(0xFFFFFEFA),
  surfaceAlt: Color(0xFFF7EEDC),
  textPrimary: Color(0xFF202834),
  textMuted: Color(0xFF64707E),
  gold: Color(0xFFC8A056),
  bronze: Color(0xFFB9873E),
  border: Color(0xFFE4D8C3),
  danger: Color(0xFFCD5C6C),
  success: Color(0xFF34D29A),
  shadow: Color(0x26000000),
  isDark: false,
);

const CustomerThemePalette _champagneSandPalette = CustomerThemePalette(
  background: Color(0xFFF3E6D4),
  surface: Color(0xFFFFF6EA),
  surfaceAlt: Color(0xFFEED9BC),
  textPrimary: Color(0xFF34281F),
  textMuted: Color(0xFF736253),
  gold: Color(0xFFC89444),
  bronze: Color(0xFF9B6630),
  border: Color(0xFFDABF9E),
  danger: Color(0xFFC65E6F),
  success: Color(0xFF33BE8D),
  shadow: Color(0x30000000),
  isDark: false,
);

const CustomerThemePalette _urbanSlatePalette = CustomerThemePalette(
  background: Color(0xFFEAEFF4),
  surface: Color(0xFFF8FAFC),
  surfaceAlt: Color(0xFFDDE4EC),
  textPrimary: Color(0xFF263341),
  textMuted: Color(0xFF5F7184),
  gold: Color(0xFFAF9160),
  bronze: Color(0xFF7C8796),
  border: Color(0xFFC7D2DF),
  danger: Color(0xFFBE5C6B),
  success: Color(0xFF32B989),
  shadow: Color(0x24000000),
  isDark: false,
);

const CustomerThemePalette _midnightPlatinumPalette = CustomerThemePalette(
  background: Color(0xFF0B1018),
  surface: Color(0xFF141B25),
  surfaceAlt: Color(0xFF1D2734),
  textPrimary: Color(0xFFF3F6FC),
  textMuted: Color(0xFFBAC6D8),
  gold: Color(0xFFD7B774),
  bronze: Color(0xFF9DA8BA),
  border: Color(0xFF3A4A60),
  danger: Color(0xFFD26B7C),
  success: Color(0xFF45C997),
  shadow: Color(0x7F000000),
  isDark: true,
);

const CustomerThemePalette _royalBlueGoldPalette = CustomerThemePalette(
  background: Color(0xFF07162C),
  surface: Color(0xFF10294A),
  surfaceAlt: Color(0xFF183A67),
  textPrimary: Color(0xFFF4F8FF),
  textMuted: Color(0xFFB7CBE9),
  gold: Color(0xFFE2B95D),
  bronze: Color(0xFFB78E44),
  border: Color(0xFF345887),
  danger: Color(0xFFD46A7B),
  success: Color(0xFF47CC99),
  shadow: Color(0x85000000),
  isDark: true,
);

const CustomerThemePalette _emeraldGardenPalette = CustomerThemePalette(
  background: Color(0xFFF2F7F0),
  surface: Color(0xFFECF4E8),
  surfaceAlt: Color(0xFFDDECDC),
  textPrimary: Color(0xFF1F2E28),
  textMuted: Color(0xFF5F726A),
  gold: Color(0xFFC9A45A),
  bronze: Color(0xFF8EA784),
  border: Color(0xFFC7D8C4),
  danger: Color(0xFFC96572),
  success: Color(0xFF2FAE7B),
  shadow: Color(0x24000000),
  isDark: false,
);

const CustomerThemePalette _roseQuartzPalette = CustomerThemePalette(
  background: Color(0xFFFBF0F2),
  surface: Color(0xFFFFF7F8),
  surfaceAlt: Color(0xFFF3E1E6),
  textPrimary: Color(0xFF31252A),
  textMuted: Color(0xFF756068),
  gold: Color(0xFFD1A06A),
  bronze: Color(0xFFB88275),
  border: Color(0xFFE6CBD3),
  danger: Color(0xFFCA5D6E),
  success: Color(0xFF39B488),
  shadow: Color(0x29000000),
  isDark: false,
);

const CustomerThemePalette _lavenderMistPalette = CustomerThemePalette(
  background: Color(0xFFF3F1F8),
  surface: Color(0xFFFBFAFF),
  surfaceAlt: Color(0xFFE7E2F2),
  textPrimary: Color(0xFF2A2740),
  textMuted: Color(0xFF655F82),
  gold: Color(0xFFC5A96A),
  bronze: Color(0xFF7D6FA2),
  border: Color(0xFFD4CDE6),
  danger: Color(0xFFC55D72),
  success: Color(0xFF3CB88D),
  shadow: Color(0x25000000),
  isDark: false,
);

const CustomerThemePalette _emeraldNoirPalette = CustomerThemePalette(
  background: Color(0xFF081712),
  surface: Color(0xFF10211B),
  surfaceAlt: Color(0xFF173028),
  textPrimary: Color(0xFFF6F3EA),
  textMuted: Color(0xFFD4CCBB),
  gold: Color(0xFFD9B46A),
  bronze: Color(0xFF8AA596),
  border: Color(0xFF3E5247),
  danger: Color(0xFFD46A79),
  success: Color(0xFF3DBA88),
  shadow: Color(0x8A000000),
  isDark: true,
);

const CustomerThemeMetadata _premiumLightMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.premiumLight,
  title: CustomerThemeLocalizedText(
    nl: 'Premium licht',
    en: 'Premium light',
    fr: 'Premium clair',
    es: 'Premium claro',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Licht, warm en premium.',
    en: 'Light, warm and premium.',
    fr: 'Clair, chaleureux et premium.',
    es: 'Claro, cálido y premium.',
  ),
);

const CustomerThemeMetadata _nightGoldMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.nightGold,
  title: CustomerThemeLocalizedText(
    nl: 'Nacht goud',
    en: 'Night gold',
    fr: 'Nuit dorée',
    es: 'Noche dorada',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Donker met Fluxidi-goud.',
    en: 'Dark with Fluxidi gold.',
    fr: 'Sombre avec l’or Fluxidi.',
    es: 'Oscuro con oro Fluxidi.',
  ),
);

const CustomerThemeMetadata _ivoryGoldMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.ivoryGold,
  title: CustomerThemeLocalizedText(
    nl: 'Ivory goud',
    en: 'Ivory gold',
    fr: 'Ivoire doré',
    es: 'Marfil dorado',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Zacht ivoor met verfijnde gouden accenten.',
    en: 'Soft ivory with refined gold accents.',
    fr: 'Ivoire doux avec des accents dorés raffinés.',
    es: 'Marfil suave con acentos dorados refinados.',
  ),
);

const CustomerThemeMetadata _champagneSandMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.champagneSand,
  title: CustomerThemeLocalizedText(
    nl: 'Champagne zand',
    en: 'Champagne sand',
    fr: 'Champagne sable',
    es: 'Champán arena',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Warme champagnebasis met bronzen elegantie.',
    en: 'Warm champagne base with bronze elegance.',
    fr: 'Base champagne chaleureuse avec élégance bronze.',
    es: 'Base champán cálida con elegancia bronce.',
  ),
);

const CustomerThemeMetadata _urbanSlateMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.urbanSlate,
  title: CustomerThemeLocalizedText(
    nl: 'Urban slate',
    en: 'Urban slate',
    fr: 'Ardoise urbaine',
    es: 'Pizarra urbana',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Strak stedelijk met subtiele staal-goud tonen.',
    en: 'Clean urban style with subtle steel-gold tones.',
    fr: 'Style urbain épuré avec des tons acier-or subtils.',
    es: 'Estilo urbano limpio con tonos acero-oro sutiles.',
  ),
);

const CustomerThemeMetadata _midnightPlatinumMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.midnightPlatinum,
  title: CustomerThemeLocalizedText(
    nl: 'Midnight platinum',
    en: 'Midnight platinum',
    fr: 'Minuit platine',
    es: 'Medianoche platino',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Diepe nachttoon met premium platina-contrast.',
    en: 'Deep night tone with premium platinum contrast.',
    fr: 'Ton nuit profond avec contraste platine premium.',
    es: 'Tono nocturno profundo con contraste platino premium.',
  ),
);

const CustomerThemeMetadata _royalBlueGoldMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.royalBlueGold,
  title: CustomerThemeLocalizedText(
    nl: 'Royal blue goud',
    en: 'Royal blue gold',
    fr: 'Bleu royal or',
    es: 'Azul real dorado',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Koningsblauw oppervlak met krachtige gouden highlights.',
    en: 'Royal blue surfaces with bold gold highlights.',
    fr: 'Surfaces bleu royal avec des touches dorées marquées.',
    es: 'Superficies azul real con acentos dorados intensos.',
  ),
);

const CustomerThemeMetadata _emeraldGardenMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.emeraldGarden,
  title: CustomerThemeLocalizedText(
    nl: 'Smaragd tuin',
    en: 'Emerald garden',
    fr: 'Jardin émeraude',
    es: 'Jardín esmeralda',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Groen, rustig en premium.',
    en: 'Green, calm and premium.',
    fr: 'Vert, apaisant et premium.',
    es: 'Verde, tranquilo y premium.',
  ),
);

const CustomerThemeMetadata _roseQuartzMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.roseQuartz,
  title: CustomerThemeLocalizedText(
    nl: 'Rozenkwarts',
    en: 'Rose quartz',
    fr: 'Quartz rose',
    es: 'Cuarzo rosa',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Zacht, vrouwelijk en elegant.',
    en: 'Soft, feminine and elegant.',
    fr: 'Doux, féminin et élégant.',
    es: 'Suave, femenino y elegante.',
  ),
);

const CustomerThemeMetadata _lavenderMistMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.lavenderMist,
  title: CustomerThemeLocalizedText(
    nl: 'Lavendel mist',
    en: 'Lavender mist',
    fr: 'Brume lavande',
    es: 'Niebla lavanda',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Fris paars met zachte luxe.',
    en: 'Fresh purple with soft luxury.',
    fr: 'Violet frais avec une douceur luxueuse.',
    es: 'Púrpura fresco con lujo suave.',
  ),
);

const CustomerThemeMetadata _emeraldNoirMetadata = CustomerThemeMetadata(
  variant: CustomerThemeVariant.emeraldNoir,
  title: CustomerThemeLocalizedText(
    nl: 'Emerald noir',
    en: 'Emerald noir',
    fr: 'Émeraude noir',
    es: 'Esmeralda noir',
  ),
  description: CustomerThemeLocalizedText(
    nl: 'Donker smaragdgroen met gouden luxe.',
    en: 'Dark emerald with golden luxury.',
    fr: 'Émeraude sombre avec luxe doré.',
    es: 'Esmeralda oscura con lujo dorado.',
  ),
);

CustomerThemePalette paletteForCustomerTheme(CustomerThemeVariant variant) {
  switch (variant) {
    case CustomerThemeVariant.premiumLight:
      return _premiumLightPalette;
    case CustomerThemeVariant.nightGold:
      return _nightGoldPalette;
    case CustomerThemeVariant.ivoryGold:
      return _ivoryGoldPalette;
    case CustomerThemeVariant.champagneSand:
      return _champagneSandPalette;
    case CustomerThemeVariant.urbanSlate:
      return _urbanSlatePalette;
    case CustomerThemeVariant.midnightPlatinum:
      return _midnightPlatinumPalette;
    case CustomerThemeVariant.royalBlueGold:
      return _royalBlueGoldPalette;
    case CustomerThemeVariant.emeraldGarden:
      return _emeraldGardenPalette;
    case CustomerThemeVariant.roseQuartz:
      return _roseQuartzPalette;
    case CustomerThemeVariant.lavenderMist:
      return _lavenderMistPalette;
    case CustomerThemeVariant.emeraldNoir:
      return _emeraldNoirPalette;
  }
}

ThemeData themeForCustomerPalette(
  ThemeData base,
  CustomerThemePalette palette,
) {
  final brightness = palette.isDark ? Brightness.dark : Brightness.light;
  return base.copyWith(
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    cardColor: palette.surface,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textMuted,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    ),
    disabledColor: palette.textMuted.withOpacity(0.72),
    checkboxTheme: base.checkboxTheme.copyWith(
      side: BorderSide(color: palette.textMuted),
    ),
  );
}

CustomerThemeMetadata customerThemeMetadata(CustomerThemeVariant variant) {
  switch (variant) {
    case CustomerThemeVariant.premiumLight:
      return _premiumLightMetadata;
    case CustomerThemeVariant.nightGold:
      return _nightGoldMetadata;
    case CustomerThemeVariant.ivoryGold:
      return _ivoryGoldMetadata;
    case CustomerThemeVariant.champagneSand:
      return _champagneSandMetadata;
    case CustomerThemeVariant.urbanSlate:
      return _urbanSlateMetadata;
    case CustomerThemeVariant.midnightPlatinum:
      return _midnightPlatinumMetadata;
    case CustomerThemeVariant.royalBlueGold:
      return _royalBlueGoldMetadata;
    case CustomerThemeVariant.emeraldGarden:
      return _emeraldGardenMetadata;
    case CustomerThemeVariant.roseQuartz:
      return _roseQuartzMetadata;
    case CustomerThemeVariant.lavenderMist:
      return _lavenderMistMetadata;
    case CustomerThemeVariant.emeraldNoir:
      return _emeraldNoirMetadata;
  }
}
