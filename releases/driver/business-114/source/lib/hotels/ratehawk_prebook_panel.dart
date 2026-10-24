import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

import 'ratehawk_hotelpage.dart';
import 'ratehawk_prebook.dart';

class RatehawkPrebookSection extends StatefulWidget {
  const RatehawkPrebookSection({
    required this.offerRef,
    required this.languageCode,
    required this.palette,
    this.client,
    this.controller,
    this.onBlocked,
    this.onRefreshAvailability,
    this.onOtherRooms,
    super.key,
  });

  final String offerRef;
  final String languageCode;
  final CustomerThemePalette palette;
  final RatehawkPrebookClient? client;
  final RatehawkPrebookController? controller;
  final VoidCallback? onBlocked;
  final VoidCallback? onRefreshAvailability;
  final VoidCallback? onOtherRooms;

  @override
  State<RatehawkPrebookSection> createState() => _RatehawkPrebookSectionState();
}

class _RatehawkPrebookSectionState extends State<RatehawkPrebookSection> {
  late final RatehawkPrebookController _controller;
  late final bool _ownsController;
  bool _notifiedBlocked = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        RatehawkPrebookController(client: widget.client, reduceMotion: false);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_controller.state == RatehawkPrebookLifecycleState.blocked &&
        !_notifiedBlocked) {
      _notifiedBlocked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBlocked?.call();
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        _controller.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final gold = widget.palette.gold;
    final text = widget.palette.textPrimary;
    final muted = widget.palette.textMuted;
    final language = widget.languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          ratehawkPrebookStateLabel(_controller.state, language),
          style: TextStyle(
            color: gold.withOpacity(0.92),
            fontSize: 12.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_controller.state == RatehawkPrebookLifecycleState.checking &&
            !reduceMotion) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            minHeight: 2,
            color: gold,
            backgroundColor: gold.withOpacity(0.16),
          ),
        ],
        if (_controller.state == RatehawkPrebookLifecycleState.idle) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _controller.check(
                offerRef: widget.offerRef,
                locale: language,
              ),
              child: Text(ratehawkPrebookCheckLabel(language)),
            ),
          ),
        ],
        if (_controller.state == RatehawkPrebookLifecycleState.checking) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _controller.cancel,
            child: Text(ratehawkPrebookCancelLabel(language)),
          ),
        ],
        if (_controller.state == RatehawkPrebookLifecycleState.retryable) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                _controller.check(offerRef: widget.offerRef, locale: language),
            child: Text(ratehawkRetryLabel(language)),
          ),
        ],
        if (_controller.response?.currentTerms != null &&
            (_controller.state ==
                    RatehawkPrebookLifecycleState.readyUnchanged ||
                _controller.state ==
                    RatehawkPrebookLifecycleState.readyChanged)) ...[
          const SizedBox(height: 8),
          Text(
            _controller.response!.currentTerms!.customerTotalLabel ??
                _controller.response!.currentTerms!.customerTotal ??
                '',
            style: TextStyle(
              color: text,
              fontSize: 13.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_controller.response!.currentTerms!.roomName != null)
            Text(
              _controller.response!.currentTerms!.roomName!,
              style: TextStyle(color: muted, fontSize: 12.2),
            ),
        ],
        if (_controller.state == RatehawkPrebookLifecycleState.readyChanged)
          for (final change
              in _controller.response?.changes ??
                  const <RatehawkPrebookChange>[])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${change.label ?? change.code}: ${change.before ?? '—'} → ${change.after ?? '—'}',
                style: TextStyle(color: muted, fontSize: 11.6, height: 1.3),
              ),
            ),
        if (_controller.state ==
            RatehawkPrebookLifecycleState.readyUnchanged) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _controller.accept(locale: language),
              child: Text(ratehawkPrebookConfirmLabel(language)),
            ),
          ),
        ],
        if (_controller.state ==
            RatehawkPrebookLifecycleState.readyChanged) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _controller.accept(locale: language),
              child: Text(ratehawkPrebookAcceptChangesLabel(language)),
            ),
          ),
        ],
        if (_controller.state == RatehawkPrebookLifecycleState.blocked) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: widget.onRefreshAvailability,
                child: Text(ratehawkPrebookRefreshLabel(language)),
              ),
              OutlinedButton(
                onPressed: widget.onOtherRooms,
                child: Text(ratehawkPrebookOtherRoomsLabel(language)),
              ),
            ],
          ),
        ],
        if (_controller.state == RatehawkPrebookLifecycleState.accepted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              ratehawkPrebookAcceptedLabel(language),
              style: TextStyle(color: muted, fontSize: 12.2, height: 1.3),
            ),
          ),
      ],
    );
  }
}
