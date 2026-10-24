import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_controller.dart';

/// Repaints the existing outer decoration only. Child, border dimensions,
/// corner radii, padding and hit testing remain owned by FluxidiFrame.
class DriverRideFrameBorder extends StatefulWidget {
  const DriverRideFrameBorder({
    super.key,
    required this.decoration,
    required this.child,
    this.controller,
  });
  final BoxDecoration decoration;
  final Widget child;
  final DriverRideAlertController? controller;
  @override
  State<DriverRideFrameBorder> createState() => _FrameState();
}

class _FrameState extends State<DriverRideFrameBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  DriverRideAlertController get _alerts =>
      widget.controller ?? DriverRideAlertController.instance;
  bool _reduceMotion = false;
  @override
  void initState() {
    super.initState();
    _alerts.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(DriverRideFrameBorder old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? DriverRideAlertController.instance).removeListener(
        _changed,
      );
      _alerts.addListener(_changed);
      _sync();
    }
  }

  void _sync() {
    if (_alerts.active && !_reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _changed() {
    _sync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _alerts.removeListener(_changed);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: widget.child,
    builder: (context, child) {
      final border = widget.decoration.border;
      var decoration = widget.decoration;
      if (_alerts.active && border is Border) {
        final t = _reduceMotion
            ? 0.65
            : Curves.easeInOut.transform(_pulse.value);
        Color shade(Color color) => Color.lerp(
          const Color(0xffb71c1c),
          const Color(0xffff5252),
          t,
        )!;
        decoration = decoration.copyWith(
          border: Border(
            top: border.top.copyWith(color: shade(border.top.color)),
            right: border.right.copyWith(color: shade(border.right.color)),
            bottom: border.bottom.copyWith(color: shade(border.bottom.color)),
            left: border.left.copyWith(color: shade(border.left.color)),
          ),
        );
      }
      return DecoratedBox(decoration: decoration, child: child);
    },
  );
}
