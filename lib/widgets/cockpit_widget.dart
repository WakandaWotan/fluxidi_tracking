import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class CockpitWidget extends StatelessWidget {
  final Animation<double> activePulse;
  final bool tripActive;
  final bool isWaiting;
  final bool isStartingTrip;
  final bool hasActiveBooking;
  final String? from;
  final String? to;
  final String etaText;
  final String kmRemainingText;
  final String timeText;
  final String priceText;
  final String modeText;
  final VoidCallback onEnterWaitMode;
  final VoidCallback onExitWaitMode;
  final VoidCallback onCenterOnMe;
  final VoidCallback onStopTrip;
  final VoidCallback onNavigate;
  final VoidCallback onStartTrip;

  const CockpitWidget({
    super.key,
    required this.activePulse,
    required this.tripActive,
    required this.isWaiting,
    required this.isStartingTrip,
    required this.hasActiveBooking,
    required this.from,
    required this.to,
    required this.etaText,
    required this.kmRemainingText,
    required this.timeText,
    required this.priceText,
    required this.modeText,
    required this.onEnterWaitMode,
    required this.onExitWaitMode,
    required this.onCenterOnMe,
    required this.onStopTrip,
    required this.onNavigate,
    required this.onStartTrip,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF081126).withOpacity(0.80),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFFFD36A).withOpacity(0.28),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasActiveBooking) ...[
                    Text(
                      '${_labelOrFallback(from, 'Pickup')} → ${_labelOrFallback(to, 'Dropoff')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceText,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            modeText,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    height: 96,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final h = c.maxHeight;
                        const gap = 12.0;
                        final dialSize = math.max(
                          60.0,
                          math.min(84.0, math.min((w - 2 * gap) / 3, h)),
                        );

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _cockpitDial(
                              label: 'ETA',
                              value: etaText,
                              icon: Icons.schedule,
                              size: dialSize,
                              highlight: tripActive,
                            ),
                            SizedBox(width: gap),
                            _cockpitDial(
                              label: 'TIME',
                              value: timeText,
                              icon: Icons.timer_outlined,
                              size: dialSize,
                              highlight: tripActive,
                            ),
                            SizedBox(width: gap),
                            _cockpitDial(
                              label: 'KM',
                              value: kmRemainingText,
                              icon: Icons.route,
                              size: dialSize,
                              highlight: tripActive,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      if (tripActive) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _cockpitPrimaryButton(
                                label: isWaiting ? 'RESUME' : 'WAIT',
                                icon: isWaiting
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_circle_outline,
                                filled: false,
                                onTap: isWaiting ? onExitWaitMode : onEnterWaitMode,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _cockpitPrimaryButton(
                                label: 'CENTER',
                                icon: Icons.my_location_outlined,
                                filled: false,
                                onTap: onCenterOnMe,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          child: _cockpitPrimaryButton(
                            label: 'STOP',
                            icon: Icons.stop_circle_outlined,
                            filled: true,
                            onTap: onStopTrip,
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          height: 52,
                          child: (hasActiveBooking
                              ? _cockpitStartButton()
                              : _cockpitPrimaryButton(
                                  label: 'NAVIGATE',
                                  icon: Icons.navigation_outlined,
                                  filled: false,
                                  onTap: onNavigate,
                                )),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _labelOrFallback(String? raw, String fallback) {
    final s = (raw ?? '').trim();
    return s.isNotEmpty ? s : fallback;
  }

  Widget _cockpitDial({
    required String label,
    required String value,
    required IconData icon,
    required double size,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: activePulse,
      builder: (context, _) {
        final t = highlight ? (0.55 + 0.45 * activePulse.value) : 0.0;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0B1733).withOpacity(0.55),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22 + 0.18 * t),
              width: 1.1,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0x66F5C400).withOpacity(0.18 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: const Color(0xFFFFD36A).withOpacity(0.92),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cockpitPrimaryButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: activePulse,
        builder: (context, _) {
          final t = (0.65 + 0.35 * activePulse.value);

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: filled
                  ? const Color(0xFF3B2230)
                  : const Color(0xFF0B1733).withOpacity(0.45),
              border: Border.all(
                color: filled
                    ? const Color(0xFFFFA7C0).withOpacity(0.55 + 0.25 * t)
                    : const Color(0xFFFFD36A).withOpacity(0.30 + 0.14 * t),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: filled
                      ? const Color(0x66FFA7C0).withOpacity(0.18 * t)
                      : const Color(0x66F5C400).withOpacity(0.14 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1 * t,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: filled
                      ? const Color(0xFFFFA7C0)
                      : const Color(0xFFFFD36A),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cockpitStartButton() {
    return Opacity(
      opacity: isStartingTrip ? 0.75 : 1.0,
      child: IgnorePointer(
        ignoring: isStartingTrip || !hasActiveBooking,
        child: _cockpitPrimaryButton(
          label: isStartingTrip ? 'STARTING…' : 'START',
          icon: Icons.play_circle_outline,
          filled: true,
          onTap: onStartTrip,
        ),
      ),
    );
  }
}
