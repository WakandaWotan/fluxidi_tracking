import 'dart:ui';
import 'package:flutter/material.dart';

/// Fluxidi Driver — Cockpit (compact premium)
class CockpitWidget extends StatefulWidget {
  final String etaText;
  final String kmText;
  final String priceText;

  final bool tripStarted;
  final bool isWaiting;
  final bool navActive;

  final VoidCallback onNav;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onWait;
  final VoidCallback onGo;

  const CockpitWidget({
    super.key,
    required this.etaText,
    required this.kmText,
    required this.priceText,
    required this.tripStarted,
    required this.isWaiting,
    required this.navActive,
    required this.onNav,
    required this.onStart,
    required this.onStop,
    required this.onWait,
    required this.onGo,
  });

  @override
  State<CockpitWidget> createState() => _CockpitWidgetState();
}

class _CockpitWidgetState extends State<CockpitWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.tripStarted) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant CockpitWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.tripStarted && widget.tripStarted) {
      _pulse.repeat(reverse: true);
    } else if (oldWidget.tripStarted && !widget.tripStarted) {
      _pulse.stop();
      _pulse.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eta = (widget.etaText.trim().isEmpty) ? '—' : widget.etaText;
    final km = (widget.kmText.trim().isEmpty) ? '—' : widget.kmText;
    final price = (widget.priceText.trim().isEmpty) ? '—' : widget.priceText;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final panel = AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = widget.tripStarted ? _pulse.value : 0.0;
        final borderOpacity = widget.tripStarted ? (0.74 + 0.08 * t) : 0.34;

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF08142D).withOpacity(0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFFFD54F).withOpacity(borderOpacity * 0.72),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 6,
                    spreadRadius: 0.2,
                  ),
                ],
              ),
              child: isLandscape ? _buildLandscapeStrip(eta: eta, km: km, price: price) : _buildPortraitPanel(eta: eta, km: km, price: price),
            ),
          ),
        );
      },
    );

    return SafeArea(
      bottom: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          child: panel,
        ),
      ),
    );
  }

  Widget _buildPortraitPanel({required String eta, required String km, required String price}) {
    const gap = 4.0;
    const verticalPadding = 3.0;
    return SizedBox(
      height: 108,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, verticalPadding, 8, verticalPadding),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _metric('ETA', eta, verticalPadding: 4, titleSize: 9, valueSize: 15),
                  const SizedBox(width: gap),
                  _metric('KM', km, verticalPadding: 4, titleSize: 9, valueSize: 15),
                  const SizedBox(width: gap),
                  _metric('€', price, verticalPadding: 4, titleSize: 9, valueSize: 15),
                ],
              ),
            ),
            const SizedBox(height: gap),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  _btn(
                    keyId: 'nav',
                    label: widget.navActive ? 'NAV ON' : 'NAV',
                    icon: widget.navActive ? Icons.navigation : Icons.navigation_outlined,
                    onTap: widget.onNav,
                    hot: widget.navActive,
                    height: 0,
                    iconSize: 12,
                    fontSize: 10,
                  ),
                  const SizedBox(width: gap),
                  _btn(
                    keyId: 'primary',
                    label: widget.tripStarted ? 'STOP' : 'START',
                    icon: widget.tripStarted ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                    onTap: widget.tripStarted ? widget.onStop : widget.onStart,
                    hot: widget.tripStarted,
                    height: 0,
                    iconSize: 12,
                    fontSize: 10,
                  ),
                  const SizedBox(width: gap),
                  _btn(
                    keyId: 'wait',
                    label: widget.isWaiting ? 'GA' : 'WACHT',
                    icon: widget.isWaiting ? Icons.play_arrow : Icons.pause,
                    onTap: widget.isWaiting ? widget.onGo : widget.onWait,
                    hot: widget.isWaiting,
                    height: 0,
                    iconSize: 12,
                    fontSize: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeStrip({required String eta, required String km, required String price}) {
    return SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _stripItem('ETA', eta),
            const SizedBox(width: 6),
            _stripItem('KM', km),
            const SizedBox(width: 6),
            _stripItem('€', price),
            const SizedBox(width: 6),
            _btn(
              keyId: 'nav',
              label: widget.navActive ? 'NAV ON' : 'NAV',
              icon: widget.navActive ? Icons.navigation : Icons.navigation_outlined,
              onTap: widget.onNav,
              hot: widget.navActive,
              height: 0,
              iconSize: 12,
              fontSize: 10,
            ),
            const SizedBox(width: 6),
            _btn(
              keyId: 'primary',
              label: widget.tripStarted ? 'STOP' : 'START',
              icon: widget.tripStarted ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              onTap: widget.tripStarted ? widget.onStop : widget.onStart,
              hot: widget.tripStarted,
              height: 0,
              iconSize: 12,
              fontSize: 10,
            ),
            const SizedBox(width: 6),
            _btn(
              keyId: 'wait',
              label: widget.isWaiting ? 'GA' : 'WACHT',
              icon: widget.isWaiting ? Icons.play_arrow : Icons.pause,
              onTap: widget.isWaiting ? widget.onGo : widget.onWait,
              hot: widget.isWaiting,
              height: 0,
              iconSize: 12,
              fontSize: 10,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stripItem(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF101E3A).withOpacity(0.92),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withOpacity(0.055)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    String label,
    String value, {
    required double verticalPadding,
    required double titleSize,
    required double valueSize,
  }) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 0.5),
            decoration: BoxDecoration(
              color: const Color(0xFF101E3A).withOpacity(0.94),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withOpacity(0.055)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: titleSize.clamp(0, 11),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: valueSize.clamp(0, 16),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _btn({
    required String keyId,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool hot,
    required double height,
    required double iconSize,
    required double fontSize,
  }) {
    final isStop = keyId == 'primary' && label == 'STOP';
    final isNavActive = keyId == 'nav' && hot;
    final isWait = keyId == 'wait';
    final accent = isStop ? const Color(0xFFFF6B5F) : const Color(0xFFFFD54F);
    final background = isStop
        ? const Color(0xFF3A1821)
        : (isNavActive ? const Color(0xFF2B260D) : const Color(0xFF101E3A));
    final bgOpacity = isStop ? 0.96 : (hot && !isWait ? 0.92 : 0.86);
    final borderOpacity =
        isStop ? 0.78 : (isNavActive ? 0.62 : (isWait ? 0.18 : 0.28));
    final contentColor =
        hot && !isWait ? accent : Colors.white.withOpacity(isWait ? 0.76 : 0.88);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: height > 0 ? height : null,
            decoration: BoxDecoration(
              color: background.withOpacity(bgOpacity),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withOpacity(borderOpacity),
                width: isStop ? 1.4 : 1.0,
              ),
              boxShadow: hot
                  ? [
                      BoxShadow(
                        color: accent.withOpacity(isStop ? 0.22 : 0.12),
                        blurRadius: isStop ? 8 : 5,
                        spreadRadius: 0.1,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) {
                    return FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: Row(
                    key: ValueKey<String>('${keyId}_$label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: iconSize, color: contentColor),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          color: contentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
