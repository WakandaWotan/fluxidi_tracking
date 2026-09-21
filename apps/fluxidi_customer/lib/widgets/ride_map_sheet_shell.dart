import 'package:flutter/material.dart';

import '../app/customer_app_config.dart';

/// Large map area with a draggable sheet on top.
///
/// This is the booking layout the existing app settled on: one shell for phone,
/// tablet portrait and tablet landscape, never a two-column planner split. The
/// map surface itself is not connected yet, so it shows the chosen addresses
/// instead of a drawn route.
class RideMapSheetShell extends StatelessWidget {
  const RideMapSheetShell({
    super.key,
    required this.sheetBuilder,
    this.map,
    this.mapOverlay,
    this.onMapInsets,
    this.config = kCustomerAppConfig,
  });

  final Widget Function(BuildContext context, ScrollController controller)
  sheetBuilder;

  /// The map itself. Without it the surface says the map is not connected.
  final Widget? map;

  final Widget? mapOverlay;

  /// Area the sheet covers, so the map can fit the route in what stays visible.
  final ValueChanged<EdgeInsets>? onMapInsets;

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        // Landscape leaves less room, so the sheet starts higher and may cover
        // more of the map. The map is never replaced by a second column.
        final isShort = height < 520;
        final initial = isShort ? 0.72 : 0.58;
        final minSize = isShort ? 0.5 : 0.34;
        if (onMapInsets != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onMapInsets!(EdgeInsets.only(bottom: height * initial));
          });
        }

        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: _MapSurface(
                config: config,
                map: map,
                child: mapOverlay,
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: initial,
              minChildSize: minSize,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: config.brand.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      const _SheetGrip(),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            // Wide tablets cap the content width instead of
                            // switching to a side-by-side form.
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: sheetBuilder(context, scrollController),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _MapSurface extends StatelessWidget {
  const _MapSurface({required this.config, this.map, this.child});

  final CustomerAppConfig config;
  final Widget? map;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            config.brand.surface,
            config.brand.card,
            config.brand.primary.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (map != null)
            Positioned.fill(key: const Key('ride_map_surface'), child: map!)
          else
            Positioned(
              top: 14,
              left: 16,
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.map_outlined,
                    size: 16,
                    color: config.brand.textSoft,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Kaart niet beschikbaar in deze build',
                    key: const Key('ride_map_not_connected'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: config.brand.textSoft,
                    ),
                  ),
                ],
              ),
            ),
          if (child != null) Positioned.fill(child: child!),
        ],
      ),
    );
  }
}
