import 'package:flutter/material.dart';

/// Holds the vehicle area's height while capacity is edited. Longer filtered
/// lists scroll inside this slot instead of moving the controls below it.
class CustomerBookingStableVehicleSpace extends StatefulWidget {
  const CustomerBookingStableVehicleSpace({
    super.key,
    required this.retain,
    required this.child,
    this.updating = false,
  });
  final bool retain;
  final Widget child;
  final bool updating;

  @override
  State<CustomerBookingStableVehicleSpace> createState() =>
      _VehicleSpaceState();
}

class _VehicleSpaceState extends State<CustomerBookingStableVehicleSpace> {
  double? _reservedHeight;
  double? _width;
  Widget? _settledChild;

  @override
  void initState() {
    super.initState();
    _settledChild = widget.child;
  }

  @override
  void didUpdateWidget(CustomerBookingStableVehicleSpace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.updating) _settledChild = widget.child;
    if (!widget.retain) {
      _reservedHeight = null;
    } else if (!oldWidget.retain) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size.height > 0) {
        _reservedHeight = box.size.height;
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Rotation/resizing may deliberately lay out the new width afresh.
      if (_width != null && _width != constraints.maxWidth)
        _reservedHeight = null;
      _width = constraints.maxWidth;
      final height = _reservedHeight;
      final waiting = widget.retain && widget.updating;
      final content = Stack(
        children: [
          IgnorePointer(
            ignoring: waiting,
            child: waiting ? (_settledChild ?? widget.child) : widget.child,
          ),
          if (waiting)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                key: ValueKey('vehicle_capacity_refresh_progress'),
                minHeight: 2,
              ),
            ),
        ],
      );
      if (height == null) return content;
      return SizedBox(
        height: height,
        child: SingleChildScrollView(
          key: const ValueKey('booking_vehicle_capacity_scroll'),
          primary: false,
          child: content,
        ),
      );
    },
  );
}
