import 'package:fluxidi_tracking/business_theme_palette.dart';

/// Product cycle order for the business-view theme shortcut.
///
/// Canonical identifiers are preserved. Product copy lists "Emerald" and
/// "Ivory" as adjacent names; the shipped enum combines them as
/// [BusinessThemeVariant.emeraldIvory] (settings label: "Emerald Ivory").
const List<BusinessThemeVariant> kBusinessThemeCycleOrder =
    <BusinessThemeVariant>[
      BusinessThemeVariant.executiveGold,
      BusinessThemeVariant.corporateBlue,
      BusinessThemeVariant.cleanProfessional,
      BusinessThemeVariant.emeraldIvory,
      BusinessThemeVariant.fluxidiNeonRush,
      BusinessThemeVariant.brandSignatureGold,
    ];

/// Accessible label for the one-tap business theme cycle control.
const String kBusinessThemeCycleSemanticLabel = 'Volgend bedrijfsthema';

/// Advances one step in [kBusinessThemeCycleOrder], wrapping after the last.
///
/// Unknown/legacy values fall back to the first cycle entry's successor
/// (Corporate Blue) only when [current] is absent from the ordered list —
/// callers should normally pass a value already normalized by the store.
BusinessThemeVariant nextBusinessThemeVariant(BusinessThemeVariant current) {
  final index = kBusinessThemeCycleOrder.indexOf(current);
  if (index < 0) {
    return kBusinessThemeCycleOrder.first;
  }
  return kBusinessThemeCycleOrder[(index + 1) %
      kBusinessThemeCycleOrder.length];
}

/// Human-readable product name for the active business theme.
String businessThemeProductLabel(BusinessThemeVariant variant) {
  switch (variant) {
    case BusinessThemeVariant.executiveGold:
      return 'Executive Gold';
    case BusinessThemeVariant.corporateBlue:
      return 'Corporate Blue';
    case BusinessThemeVariant.cleanProfessional:
      return 'Clean Professional';
    case BusinessThemeVariant.emeraldIvory:
      return 'Emerald Ivory';
    case BusinessThemeVariant.fluxidiNeonRush:
      return 'Fluxy Neon Rush';
    case BusinessThemeVariant.brandSignatureGold:
      return 'Brand Signature Gold';
  }
}
