import 'dart:async';

import 'package:flutter/widgets.dart';

/// Owns the role-entry background index in [State] so a parent rebuild cannot
/// recreate `Stream.periodic` and snap the carousel back to frame 0.
///
/// Horizontal swipes are applied by the host's caller, only from the
/// decorative background layer — never from the role cards.
class RoleEntryCarouselHost extends StatefulWidget {
  const RoleEntryCarouselHost({
    super.key,
    required this.assetCount,
    required this.builder,
    this.autoAdvance = true,
    this.interval = const Duration(milliseconds: 3200),
  });

  final int assetCount;
  final bool autoAdvance;
  final Duration interval;
  final Widget Function(
    BuildContext context,
    int index,
    void Function(int delta) advanceBy,
  )
  builder;

  @override
  State<RoleEntryCarouselHost> createState() => RoleEntryCarouselHostState();
}

class RoleEntryCarouselHostState extends State<RoleEntryCarouselHost> {
  int _index = 0;
  Timer? _timer;

  int get index => _index;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(RoleEntryCarouselHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoAdvance != widget.autoAdvance ||
        oldWidget.interval != widget.interval ||
        oldWidget.assetCount != widget.assetCount) {
      if (widget.assetCount > 0) {
        _index = _index % widget.assetCount;
      } else {
        _index = 0;
      }
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.autoAdvance || widget.assetCount <= 1) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.assetCount);
    });
  }

  void advanceBy(int delta) {
    if (widget.assetCount <= 0) return;
    setState(() {
      _index = (_index + delta) % widget.assetCount;
      if (_index < 0) _index += widget.assetCount;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _index, advanceBy);
  }
}
