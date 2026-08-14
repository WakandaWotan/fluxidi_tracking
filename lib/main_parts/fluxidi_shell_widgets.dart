part of '../main.dart';

class FluxidiBackToStartButton extends StatelessWidget {
  const FluxidiBackToStartButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleEntryPage()),
            (route) => false,
          );
        },
        icon: const Icon(Icons.home_outlined),
        label: Text(
          _tr(
            nl: 'Terug naar startpagina',
            en: 'Back to start page',
            fr: 'Retour à l’accueil',
            es: 'Volver a la pantalla inicial',
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE5B641),
          backgroundColor: const Color(0xFF07080C),
          side: BorderSide(
            color: const Color(0xFFE5B641).withOpacity(0.7),
            width: 1.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
      ),
    );
  }
}

class FluxidiFrame extends StatelessWidget {
  final Widget child;
  const FluxidiFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant?>(
      valueListenable: chauffeurShellFrameThemeNotifier,
      builder: (context, chauffeurShellTheme, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: businessShellFrameActiveNotifier,
          builder: (context, businessShellActive, _) {
            return ValueListenableBuilder<BusinessThemeVariant>(
              valueListenable: businessThemeNotifier,
              builder: (context, themeVariant, _) {
                // Frame accent precedence (explicit, no wildcard):
                //   1. when the chauffeur shell is mounted (i.e.
                //      `chauffeurShellFrameThemeNotifier` is non-null because
                //      [_DriverHomePageState] published the effective driver
                //      variant on init), the outer HUD MUST follow the
                //      effective chauffeur theme — even when the business
                //      shell flag is still true underneath because Driver
                //      view was opened from Business Home. This stops the
                //      business accent (e.g. Neon Rush purple) from wrapping
                //      Driver Home / History / Documents / Bookings.
                //   2. otherwise, business shell flag must be active to
                //      consume the business theme accent — else the brand
                //      default kFluxidiYellow is used so PIN/unlock, login,
                //      role entry, customer, and standalone driver screens
                //      never inherit a business theme accent.
                //   3. inside an active business shell, fall through the
                //      exhaustive BusinessThemeVariant switch unchanged.
                final Color frameAccent;
                final String frameSource;
                if (chauffeurShellTheme != null) {
                  frameAccent = switch (chauffeurShellTheme) {
                    DriverThemeVariant.midnightBlue => paletteForDriverTheme(
                      DriverThemeVariant.midnightBlue,
                    ).border,
                    // Soft warm champagne, aligned with the Midday Gold
                    // panelBorder/accent used by `_DriverDocumentsThemeTokens`
                    // and `_BookingsHubThemeTokens` so the outer frame
                    // matches the Documents/Bookings/History highContrast
                    // styling instead of reading as Night Gold.
                    DriverThemeVariant.highContrast => const Color(0xFFFFDFA3),
                    DriverThemeVariant.lightEmerald => paletteForDriverTheme(
                      DriverThemeVariant.lightEmerald,
                    ).accent,
                    // Same value as the legacy `kFluxidiYellow` brand default
                    // (`appConfig.primaryColor` for the chauffeur build),
                    // so Night Gold keeps its existing frame look exactly.
                    DriverThemeVariant.nightGold => paletteForDriverTheme(
                      DriverThemeVariant.nightGold,
                    ).accent,
                  };
                  frameSource = 'driver';
                } else if (!businessShellActive) {
                  frameAccent = kFluxidiYellow;
                  frameSource = 'brand';
                } else {
                  frameAccent = switch (themeVariant) {
                    BusinessThemeVariant.executiveGold => kFluxidiYellow,
                    BusinessThemeVariant.corporateBlue =>
                      paletteForBusinessTheme(
                        BusinessThemeVariant.corporateBlue,
                      ).accent,
                    BusinessThemeVariant.cleanProfessional =>
                      paletteForBusinessTheme(
                        BusinessThemeVariant.cleanProfessional,
                      ).accent,
                    BusinessThemeVariant.emeraldIvory =>
                      paletteForBusinessTheme(
                        BusinessThemeVariant.emeraldIvory,
                      ).accent,
                    BusinessThemeVariant.fluxidiNeonRush =>
                      paletteForBusinessTheme(
                        BusinessThemeVariant.fluxidiNeonRush,
                      ).accent,
                    BusinessThemeVariant.brandSignatureGold =>
                      paletteForBusinessTheme(
                        BusinessThemeVariant.brandSignatureGold,
                      ).accent,
                  };
                  frameSource = 'business';
                }
                // Hard Frame A: a visible HUD border that contains the whole UI.
                // Target: visually ~2–3mm on phone screens.
                // Light Emerald chauffeur shell fills use the mint background so
                // the outer/inner frame does not flash Night Gold black.
                final Color frameFill =
                    chauffeurShellTheme == DriverThemeVariant.lightEmerald
                    ? paletteForDriverTheme(
                        DriverThemeVariant.lightEmerald,
                      ).background
                    : kFluxidiBlack;
                return Container(
                  color: frameFill,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: frameFill,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: frameAccent.withOpacity(0.98),
                            width: 3.0,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 18,
                              spreadRadius: 2,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: frameFill,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: frameAccent.withOpacity(0.55),
                                width: 1.5,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: kFluxidiE2eBuild
                                  ? Column(
                                      children: [
                                        Material(
                                          color: const Color(0xFF8B0000),
                                          child: SafeArea(
                                            bottom: false,
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                      horizontal: 12,
                                                    ),
                                                child: Text(
                                                  kFluxidiE2eBannerText,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(child: child),
                                      ],
                                    )
                                  : child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _GlowIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const _GlowIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: disabled
                ? Colors.white.withOpacity(0.04)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: disabled
                ? const []
                : [
                    BoxShadow(
                      color: kFluxidiYellowSoft,
                      blurRadius: 18,
                      spreadRadius: 0.5,
                    ),
                  ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: disabled
                ? Colors.white.withOpacity(0.35)
                : Colors.white.withOpacity(0.90),
          ),
        ),
      ),
    );

    if ((tooltip ?? '').isEmpty) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
