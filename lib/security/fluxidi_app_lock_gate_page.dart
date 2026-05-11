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
  bool _storageUnavailable = false;
  bool _storageBypassConfirmed = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'nl') return nl;
    if (code == 'fr') return fr;
    if (code == 'es') return es;
    return en;
  }

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
        _storageUnavailable = false;
        _storageBypassConfirmed = false;
      });
      return;
    }

    final state = await FluxidiAppLockStore.instance.readState();
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (!state.storageAvailable) {
        _needsUnlock = false;
        _setupMode = false;
        _storageUnavailable = true;
      } else if (!state.hasPin) {
        _needsUnlock = true;
        _setupMode = true;
        _storageUnavailable = false;
      } else if (state.enabled) {
        _needsUnlock = true;
        _setupMode = false;
        _storageUnavailable = false;
      } else {
        _needsUnlock = false;
        _setupMode = false;
        _storageUnavailable = false;
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

    if (_storageUnavailable && !_storageBypassConfirmed) {
      const accent = Color(0xFFE5B641);
      return Scaffold(
        backgroundColor: const Color(0xFF07080C),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withOpacity(0.45)),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF101010), Color(0xFF07080C)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withOpacity(0.16),
                              border: Border.all(
                                color: accent.withOpacity(0.55),
                              ),
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _t(
                                nl: 'App-vergrendeling tijdelijk niet beschikbaar',
                                en: 'App lock temporarily unavailable',
                                fr: 'Verrouillage temporairement indisponible',
                                es: 'Bloqueo temporalmente no disponible',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          nl: 'Beveiligde opslag is momenteel niet toegankelijk op dit apparaat. Je kan doorgaan zonder PIN-lock.',
                          en: 'Secure storage is currently unavailable on this device. You can continue without PIN lock.',
                          fr: 'Le stockage sécurisé est actuellement indisponible sur cet appareil. Vous pouvez continuer sans code PIN.',
                          es: 'El almacenamiento seguro no está disponible actualmente en este dispositivo. Puedes continuar sin bloqueo PIN.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 12.8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          if (!mounted) return;
                          setState(() {
                            _storageBypassConfirmed = true;
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: 'Doorgaan',
                            en: 'Continue',
                            fr: 'Continuer',
                            es: 'Continuar',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widget.target;
  }
}
