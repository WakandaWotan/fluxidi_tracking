import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/security/fluxidi_app_lock_store.dart';

class FluxidiPinUnlockPage extends StatefulWidget {
  const FluxidiPinUnlockPage({
    super.key,
    required this.onUnlocked,
    required this.setupMode,
  });

  final VoidCallback onUnlocked;
  final bool setupMode;

  @override
  State<FluxidiPinUnlockPage> createState() => _FluxidiPinUnlockPageState();
}

class _FluxidiPinUnlockPageState extends State<FluxidiPinUnlockPage> {
  final TextEditingController _pinController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _firstPin;
  bool _confirmStep = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    final code = currentLanguageCode;
    if (code == 'nl') return nl;
    if (code == 'fr') return fr;
    if (code == 'es') return es;
    return en;
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pinController.text.trim();
    if (!FluxidiAppLockStore.instance.isValidPinFormat(pin)) {
      setState(() {
        _error = _t(
          nl: 'PIN moet 4 tot 6 cijfers zijn.',
          en: 'PIN must be 4 to 6 digits.',
          fr: 'Le code PIN doit contenir 4 à 6 chiffres.',
          es: 'El PIN debe tener entre 4 y 6 dígitos.',
        );
      });
      return;
    }

    if (widget.setupMode) {
      if (!_confirmStep) {
        setState(() {
          _firstPin = pin;
          _confirmStep = true;
          _error = null;
          _pinController.clear();
        });
        return;
      }
      if (_firstPin != pin) {
        setState(() {
          _error = _t(
            nl: 'PIN komt niet overeen. Probeer opnieuw.',
            en: 'PIN does not match. Try again.',
            fr: 'Le code PIN ne correspond pas. Réessayez.',
            es: 'El PIN no coincide. Inténtalo de nuevo.',
          );
          _confirmStep = false;
          _firstPin = null;
          _pinController.clear();
        });
        return;
      }

      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await FluxidiAppLockStore.instance.setPin(pin);
        if (!mounted) return;
        widget.onUnlocked();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = _t(
            nl: 'PIN opslaan mislukt. Probeer opnieuw.',
            en: 'Failed to save PIN. Try again.',
            fr: 'Enregistrement du PIN échoué. Réessayez.',
            es: 'No se pudo guardar el PIN. Inténtalo de nuevo.',
          );
        });
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await FluxidiAppLockStore.instance.verifyPin(pin);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error = _t(
            nl: 'Onjuiste PIN.',
            en: 'Invalid PIN.',
            fr: 'PIN incorrect.',
            es: 'PIN incorrecto.',
          );
        });
        return;
      }
      widget.onUnlocked();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFE5B641);
    final setupTitle = _confirmStep
        ? _t(
            nl: 'Bevestig PIN',
            en: 'Confirm PIN',
            fr: 'Confirmer le PIN',
            es: 'Confirmar PIN',
          )
        : _t(
            nl: 'Stel je PIN in',
            en: 'Set your PIN',
            fr: 'Définir votre PIN',
            es: 'Configura tu PIN',
          );
    final unlockTitle = _t(
      nl: 'Ontgrendel Fluxidi',
      en: 'Unlock Fluxidi',
      fr: 'Déverrouiller Fluxidi',
      es: 'Desbloquear Fluxidi',
    );

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
                            border: Border.all(color: accent.withOpacity(0.55)),
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            color: Color(0xFFE5B641),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.setupMode ? setupTitle : unlockTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.setupMode
                          ? _t(
                              nl: _confirmStep
                                  ? 'Voer dezelfde PIN opnieuw in.'
                                  : 'Kies een PIN van 4 tot 6 cijfers.',
                              en: _confirmStep
                                  ? 'Enter the same PIN again.'
                                  : 'Choose a 4 to 6 digit PIN.',
                              fr: _confirmStep
                                  ? 'Entrez à nouveau le même PIN.'
                                  : 'Choisissez un PIN de 4 à 6 chiffres.',
                              es: _confirmStep
                                  ? 'Introduce el mismo PIN otra vez.'
                                  : 'Elige un PIN de 4 a 6 dígitos.',
                            )
                          : _t(
                              nl: 'Voer je PIN in om verder te gaan.',
                              en: 'Enter your PIN to continue.',
                              fr: 'Entrez votre PIN pour continuer.',
                              es: 'Introduce tu PIN para continuar.',
                            ),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 12.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pinController,
                      autofocus: true,
                      obscureText: true,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _t(
                          nl: 'PIN',
                          en: 'PIN',
                          fr: 'PIN',
                          es: 'PIN',
                        ),
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF111111),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: accent.withOpacity(0.75),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
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
                        _busy
                            ? _t(
                                nl: 'Even geduld...',
                                en: 'Please wait...',
                                fr: 'Veuillez patienter...',
                                es: 'Espera...',
                              )
                            : _t(
                                nl: 'Ontgrendelen',
                                en: 'Unlock',
                                fr: 'Déverrouiller',
                                es: 'Desbloquear',
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
}
