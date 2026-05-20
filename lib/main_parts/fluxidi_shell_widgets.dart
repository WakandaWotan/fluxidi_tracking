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
    // Hard Frame A: a visible yellow HUD border that *contains* the whole UI.
    // Target: visually ~2–3mm on phone screens.
    return Container(
      color: kFluxidiBlack,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kFluxidiBlack,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: kFluxidiYellow.withOpacity(0.98),
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
                  color: kFluxidiBlack,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: kFluxidiYellow.withOpacity(0.55),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
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
