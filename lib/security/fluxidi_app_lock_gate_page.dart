import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/security/fluxidi_app_lock_store.dart';
import 'package:fluxidi_tracking/security/fluxidi_pin_unlock_page.dart';

class FluxidiAppLockGatePage extends StatefulWidget {
  const FluxidiAppLockGatePage({
    super.key,
    required this.target,
    required this.shouldGate,
  });

  final Widget target;
  final bool shouldGate;

  @override
  State<FluxidiAppLockGatePage> createState() => _FluxidiAppLockGatePageState();
}

class _FluxidiAppLockGatePageState extends State<FluxidiAppLockGatePage> {
  bool _loading = true;
  bool _needsUnlock = false;
  bool _setupMode = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _resolveGate();
  }

  Future<void> _resolveGate() async {
    if (!widget.shouldGate) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsUnlock = false;
        _setupMode = false;
      });
      return;
    }

    final hasPin = await FluxidiAppLockStore.instance.hasPin();
    final enabled = await FluxidiAppLockStore.instance.isEnabled();
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (!hasPin) {
        _needsUnlock = true;
        _setupMode = true;
      } else if (enabled) {
        _needsUnlock = true;
        _setupMode = false;
      } else {
        _needsUnlock = false;
        _setupMode = false;
      }
    });
  }

  void _onUnlocked() {
    if (!mounted) return;
    setState(() {
      _unlocked = true;
      _needsUnlock = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF07080C),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE5B641)),
        ),
      );
    }

    if (_needsUnlock && !_unlocked) {
      return FluxidiPinUnlockPage(
        setupMode: _setupMode,
        onUnlocked: _onUnlocked,
      );
    }

    return widget.target;
  }
}
