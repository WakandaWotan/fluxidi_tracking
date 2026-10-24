import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

/// Shared map + draggable booking sheet for phone and tablet.
class CustomerBookingMapSheetShell extends StatelessWidget {
  const CustomerBookingMapSheetShell({
    super.key,
    required this.palette,
    required this.sizes,
    required this.controller,
    required this.map,
    required this.handle,
    required this.formChildren,
    required this.confirm,
    required this.onExtent,
    required this.onAssignScroll,
    this.contentMaxWidth,
    this.formPadding,
  });

  final CustomerThemePalette palette;
  final CustomerBookingSheetSizes sizes;
  final DraggableScrollableController controller;
  final Widget map;
  final Widget handle;
  final List<Widget> formChildren;
  final Widget confirm;
  final ValueChanged<double> onExtent;
  final ValueChanged<ScrollController> onAssignScroll;
  final double? contentMaxWidth;
  final EdgeInsets? formPadding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth =
        contentMaxWidth ?? customerBookingSheetContentMaxWidth(width);
    final padding = formPadding ?? customerBookingSheetFormPadding(width);
    return KeyedSubtree(
      key: kCustomerBookingMapSheetShellKey,
      child: Stack(
        key: kCustomerBookingNarrowStackKey,
        children: [
          Positioned.fill(child: map),
          Positioned.fill(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                onExtent(notification.extent);
                return false;
              },
              child: DraggableScrollableSheet(
                key: const ValueKey('customer_booking_phone_sheet'),
                controller: controller,
                minChildSize: sizes.min,
                maxChildSize: sizes.max,
                initialChildSize: sizes.initial.clamp(sizes.min, sizes.max),
                snap: true,
                snapSizes: sizes.snaps,
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) {
                  onAssignScroll(scrollController);
                  return Material(
                    key: kCustomerBookingSheetKey,
                    color: palette.background,
                    elevation: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        handle,
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: maxWidth),
                              child: ListView(
                                key: kCustomerBookingFormKey,
                                controller: scrollController,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                cacheExtent: 2400,
                                padding: padding,
                                children: formChildren,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: confirm,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
