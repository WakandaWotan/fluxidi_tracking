import 'dart:async';

import 'package:flutter/material.dart';
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
  static const int _maxFailedAttempts = 5;
  static const Duration _retryBlockDuration = Duration(seconds: 30);

  static const int _maxPinLength = 6;
  static const Color _lockBg = Color(0xFFFFFCF6);
  static const Color _lockBgSoft = Color(0xFFFAF7F1);
  static const Color _lockPanel = Color(0xFFFFFEFA);
  static const Color _lockGold = Color(0xFFC9A968);
  static const Color _lockGoldSoft = Color(0xFFF5ECDD);
  static const Color _lockText = Color(0xFF1F2933);
  static const Color _lockMuted = Color(0xFF7B766D);
  static const Color _lockBorder = Color(0xFFECE3D2);
  static const Color _lockDanger = Color(0xFFA43E4A);
  static const Color _lockDangerBg = Color(0xFFFFF5F6);
  static const Color _lockDangerBorder = Color(0xFFEED4D8);
  static const Color _lockKey = Color(0xFFFFFEFC);
  static const Color _lockKeyAccent = Color(0xFFF7F2E7);
  static const Color _lockKeyBorder = Color(0xFFE8E0D2);
  static const Color _lockFingerprintDisabled = Color(0xFFA8A29A);
  static const Color _lockFingerprintEnabled = Color(0xFF7A7058);
  static const Color _lockOverlayTop = Color(0x24FFFCF8);
  static const Color _lockOverlayMid = Color(0x3CFFFCF8);
  static const Color _lockOverlayBottom = Color(0x66FFFBF7);
  static const List<Shadow> _foregroundTextShadows = [
    Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 1)),
  ];
  static const List<Shadow> _keypadDigitShadows = [
    Shadow(color: Color(0x8A000000), blurRadius: 5, offset: Offset(0, 1.2)),
  ];

  String _enteredPin = '';
  bool _busy = false;
  String? _error;
  String? _firstPin;
  bool _confirmStep = false;
  int _failedAttempts = 0;
  DateTime? _blockedUntilUtc;
  Timer? _retryBlockTimer;

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
    _retryBlockTimer?.cancel();
    super.dispose();
  }

  int _retryBlockSecondsRemaining() {
    final blockedUntil = _blockedUntilUtc;
    if (blockedUntil == null) return 0;
    final diff = blockedUntil.difference(DateTime.now().toUtc()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get _isRetryBlocked => _retryBlockSecondsRemaining() > 0;

  String _retryBlockedMessage() {
    final seconds = _retryBlockSecondsRemaining();
    return _t(
      nl: 'Te veel foutieve pogingen. Probeer opnieuw over ${seconds}s.',
      en: 'Too many failed attempts. Try again in ${seconds}s.',
      fr: 'Trop de tentatives échouées. Réessayez dans ${seconds}s.',
      es: 'Demasiados intentos fallidos. Inténtalo de nuevo en ${seconds}s.',
    );
  }

  void _startRetryBlockTicker() {
    _retryBlockTimer?.cancel();
    _retryBlockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryBlockSecondsRemaining() <= 0) {
        timer.cancel();
        setState(() {
          _blockedUntilUtc = null;
          _error = null;
        });
        return;
      }
      setState(() {
        _error = _retryBlockedMessage();
      });
    });
  }

  void _registerFailedUnlockAttempt() {
    _failedAttempts += 1;
    _enteredPin = '';
    if (_failedAttempts >= _maxFailedAttempts) {
      _failedAttempts = 0;
      _blockedUntilUtc = DateTime.now().toUtc().add(_retryBlockDuration);
      _error = _retryBlockedMessage();
      _startRetryBlockTicker();
      return;
    }
    _error = _t(
      nl: 'Onjuiste PIN-code',
      en: 'Incorrect PIN',
      fr: 'Code PIN incorrect',
      es: 'PIN incorrecto',
    );
  }

  void _clearFailedUnlockState() {
    _failedAttempts = 0;
    _blockedUntilUtc = null;
    _retryBlockTimer?.cancel();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!widget.setupMode && _isRetryBlocked) {
      setState(() {
        _error = _retryBlockedMessage();
      });
      return;
    }
    final pin = _enteredPin.trim();
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
          _enteredPin = '';
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
          _enteredPin = '';
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
      } on FluxidiAppLockStorageUnavailableException {
        if (!mounted) return;
        setState(() {
          _error = _t(
            nl: 'Beveiligde opslag is niet beschikbaar. PIN-lock kan nu niet worden ingesteld.',
            en: 'Secure storage is unavailable. PIN lock cannot be set right now.',
            fr: 'Le stockage sécurisé est indisponible. Le verrou PIN ne peut pas être configuré maintenant.',
            es: 'El almacenamiento seguro no está disponible. El bloqueo PIN no se puede configurar ahora.',
          );
        });
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
      final result = await FluxidiAppLockStore.instance.verifyPinDetailed(pin);
      if (!mounted) return;
      if (!result.storageAvailable) {
        setState(() {
          _error = _t(
            nl: 'Beveiligde opslag is niet beschikbaar. Sluit de app niet af en probeer later opnieuw.',
            en: 'Secure storage is unavailable. Do not close the app and try again later.',
            fr: 'Le stockage sécurisé est indisponible. Ne fermez pas l’application et réessayez plus tard.',
            es: 'El almacenamiento seguro no está disponible. No cierres la app e inténtalo de nuevo más tarde.',
          );
        });
        return;
      }
      if (!result.ok) {
        setState(_registerFailedUnlockAttempt);
        return;
      }
      _clearFailedUnlockState();
      widget.onUnlocked();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _appendDigit(String digit) {
    if (_busy || _enteredPin.length >= _maxPinLength) return;
    setState(() {
      _enteredPin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _error = null;
    });
  }

  bool _isBiometricSupported() {
    return false;
  }

  int _pinDotSlots() {
    if (widget.setupMode) return _maxPinLength;
    if (_enteredPin.length <= 4) return 4;
    return _enteredPin.length.clamp(4, _maxPinLength);
  }

  String _backgroundAssetForSize(Size size) {
    if (size.height > size.width && size.width < 600) {
      return 'assets/fluxidi/background_sign_in_page_phone.png';
    }
    return 'assets/fluxidi/background_sign_in_page.png';
  }

  Widget _pinDot({required bool filled}) {
    const Color emptyBorder = Color(0xFFE7DFD0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? _lockGold : Colors.transparent,
        border: Border.all(
          color: filled ? _lockGold : emptyBorder.withOpacity(0.95),
          width: 1.8,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: _lockGold.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _keypadButton({
    required Widget child,
    required VoidCallback? onPressed,
    required double numericFillOpacity,
    required double sideFillOpacity,
    required double borderOpacity,
    required double glowOpacity,
    required double glowBlur,
    required double glowSpread,
    bool isAccent = false,
    bool isNumeric = false,
  }) {
    final backgroundColor = Colors.white.withOpacity(
      isNumeric ? numericFillOpacity : sideFillOpacity,
    );
    final foregroundColor = isNumeric ? Colors.white : const Color(0xFFF4F4F4);
    final disabledBackgroundColor = isNumeric
        ? Colors.white.withOpacity((numericFillOpacity * 0.5).clamp(0.10, 0.16))
        : Colors.white.withOpacity((sideFillOpacity * 0.62).clamp(0.10, 0.17));
    final disabledForegroundColor = isNumeric
        ? Colors.white.withOpacity(0.55)
        : Colors.white.withOpacity(0.60);
    final borderColor = _lockGold.withOpacity(
      isNumeric ? borderOpacity : (borderOpacity * 0.92).clamp(0.45, 0.74),
    );
    return SizedBox(
      width: 74,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: _lockGold.withOpacity(
                isNumeric
                    ? glowOpacity
                    : (glowOpacity * 0.86).clamp(0.14, 0.28),
              ),
              blurRadius: glowBlur,
              spreadRadius: glowSpread,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            elevation: isAccent ? 1 : 0,
            shadowColor: Colors.transparent,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            disabledBackgroundColor: disabledBackgroundColor,
            disabledForegroundColor: disabledForegroundColor,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _iconWithShadow({
    required IconData icon,
    required double size,
    required Color color,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, 1),
          child: Icon(icon, size: size, color: Colors.black.withOpacity(0.45)),
        ),
        Icon(icon, size: size, color: color),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final keypadScale = (viewportSize.shortestSide / 390).clamp(0.88, 1.24);
    final numericFillOpacity = (0.24 + (keypadScale - 1.0) * 0.03).clamp(
      0.21,
      0.30,
    );
    final sideFillOpacity = (0.20 + (keypadScale - 1.0) * 0.03).clamp(
      0.17,
      0.27,
    );
    final keypadBorderOpacity = (0.62 + (keypadScale - 1.0) * 0.08).clamp(
      0.56,
      0.74,
    );
    final keypadGlowOpacity = (0.24 + (keypadScale - 1.0) * 0.07).clamp(
      0.18,
      0.32,
    );
    final keypadGlowBlur = (9.5 * keypadScale).clamp(8.0, 12.5);
    final keypadGlowSpread = (0.38 * keypadScale).clamp(0.22, 0.72);
    final keypadDigitTextStyle = const TextStyle(
      color: Color(0xFFF8F8F8),
      fontSize: 24,
      fontWeight: FontWeight.w700,
      shadows: _keypadDigitShadows,
    );
    final keypadIconEnabledColor = const Color(0xFFF8F8F8);
    final keypadIconDisabledColor = const Color(0xFFF8F8F8).withOpacity(0.64);

    final backgroundAsset = _backgroundAssetForSize(MediaQuery.sizeOf(context));
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
      fr: 'Déverrouillez Fluxidi',
      es: 'Desbloquea Fluxidi',
    );
    final welcomeBack = _t(
      nl: 'Welkom terug',
      en: 'Welcome back',
      fr: 'Bon retour',
      es: 'Bienvenido de nuevo',
    );
    final useFingerprintLabel = _t(
      nl: 'Gebruik vingerafdruk',
      en: 'Use fingerprint',
      fr: 'Utiliser l’empreinte digitale',
      es: 'Usar huella digital',
    );
    final fingerprintUnavailableLabel = _t(
      nl: 'Vingerafdruk nog niet beschikbaar',
      en: 'Fingerprint not available yet',
      fr: 'Empreinte digitale pas encore disponible',
      es: 'Huella digital aún no disponible',
    );
    final tryAgain = _t(
      nl: 'Probeer opnieuw',
      en: 'Try again',
      fr: 'Réessayez',
      es: 'Inténtalo de nuevo',
    );
    final securitySubtitle = _t(
      nl: 'Veilig ontgrendelen',
      en: 'Secure unlock',
      fr: 'Déverrouillage sécurisé',
      es: 'Desbloqueo seguro',
    );
    final backspaceLabel = _t(
      nl: 'Wissen',
      en: 'Delete',
      fr: 'Supprimer',
      es: 'Borrar',
    );
    final biometricAvailable = _isBiometricSupported();
    Widget glassKeypadButton({
      required Widget child,
      required VoidCallback? onPressed,
      bool isAccent = false,
      bool isNumeric = false,
    }) {
      return _keypadButton(
        child: child,
        onPressed: onPressed,
        isAccent: isAccent,
        isNumeric: isNumeric,
        numericFillOpacity: numericFillOpacity,
        sideFillOpacity: sideFillOpacity,
        borderOpacity: keypadBorderOpacity,
        glowOpacity: keypadGlowOpacity,
        glowBlur: keypadGlowBlur,
        glowSpread: keypadGlowSpread,
      );
    }

    Widget keypad = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('1'),
              child: Text('1', style: keypadDigitTextStyle),
            ),
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('2'),
              child: Text('2', style: keypadDigitTextStyle),
            ),
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('3'),
              child: Text('3', style: keypadDigitTextStyle),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('4'),
              child: Text('4', style: keypadDigitTextStyle),
            ),
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('5'),
              child: Text('5', style: keypadDigitTextStyle),
            ),
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('6'),
              child: Text('6', style: keypadDigitTextStyle),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('7'),
              child: Text('7', style: keypadDigitTextStyle),
            ),
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('8'),
              child: Text('8', style: keypadDigitTextStyle),
            ),
            glassKeypadButton(
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('9'),
              child: Text('9', style: keypadDigitTextStyle),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Tooltip(
              message: useFingerprintLabel,
              child: glassKeypadButton(
                onPressed: biometricAvailable && !_busy ? () {} : null,
                child: _iconWithShadow(
                  icon: Icons.fingerprint_rounded,
                  size: 25,
                  color: biometricAvailable
                      ? keypadIconEnabledColor
                      : keypadIconDisabledColor,
                ),
              ),
            ),
            glassKeypadButton(
              isAccent: true,
              isNumeric: true,
              onPressed: _busy ? null : () => _appendDigit('0'),
              child: Text('0', style: keypadDigitTextStyle),
            ),
            Tooltip(
              message: backspaceLabel,
              child: glassKeypadButton(
                onPressed: _busy || _enteredPin.isEmpty ? null : _backspace,
                child: _iconWithShadow(
                  icon: Icons.backspace_rounded,
                  size: 23,
                  color: keypadIconEnabledColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: _lockBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactLayout = constraints.maxHeight < 760;
                final isPhonePortrait =
                    constraints.maxHeight > constraints.maxWidth &&
                    constraints.maxWidth < 600;
                final panelTopBottomPadding = compactLayout ? 2.0 : 4.0;
                final heroHeight = (constraints.maxHeight * 0.42).clamp(
                  340.0,
                  430.0,
                );
                final foregroundVerticalShift = isPhonePortrait
                    ? (compactLayout ? 44.0 : 62.0)
                    : (compactLayout ? 20.0 : 30.0);
                final heroLeadSpace =
                    (heroHeight -
                            (compactLayout ? 174 : 192) +
                            foregroundVerticalShift)
                        .clamp(86.0, 206.0);
                final brandBarWidth = (constraints.maxWidth * 0.56).clamp(
                  190.0,
                  258.0,
                );
                final buttonTopSpacing = isPhonePortrait
                    ? (compactLayout ? 26.0 : 36.0)
                    : 14.0;
                final buttonBottomSpacing = isPhonePortrait
                    ? (compactLayout ? 20.0 : 24.0)
                    : 14.0;

                final headerCard = Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: SizedBox(
                          width: brandBarWidth,
                          height: compactLayout ? 38.0 : 44.0,
                          child: Image.asset(
                            'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                final contentCard = Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.setupMode ? setupTitle : welcomeBack,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          shadows: _foregroundTextShadows,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                                fr: 'Saisissez votre code PIN pour continuer.',
                                es: 'Introduce tu PIN para continuar.',
                              ),
                        style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: _foregroundTextShadows,
                        ),
                      ),
                      if (!widget.setupMode) ...[
                        const SizedBox(height: 2),
                        Text(
                          unlockTitle,
                          style: const TextStyle(
                            color: Color(0xFFF8F8F8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            shadows: _foregroundTextShadows,
                          ),
                        ),
                      ],
                      SizedBox(height: compactLayout ? 12 : 14),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 140),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List<Widget>.generate(
                            _pinDotSlots(),
                            (index) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: _pinDot(
                                filled: index < _enteredPin.length,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compactLayout ? 8 : 12),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: _lockDangerBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _lockDangerBorder),
                          ),
                          child: Text(
                            _error ==
                                    _t(
                                      nl: 'Onjuiste PIN-code',
                                      en: 'Incorrect PIN',
                                      fr: 'Code PIN incorrect',
                                      es: 'PIN incorrecto',
                                    )
                                ? '${_error!}. $tryAgain.'
                                : _error!,
                            style: const TextStyle(
                              color: _lockDanger,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: compactLayout ? 10 : 12),
                      ] else
                        SizedBox(height: compactLayout ? 6 : 10),
                      keypad,
                      SizedBox(height: compactLayout ? 8 : 10),
                      Text(
                        biometricAvailable
                            ? useFingerprintLabel
                            : fingerprintUnavailableLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFF5F5F5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: _foregroundTextShadows,
                        ),
                      ),
                      SizedBox(height: buttonTopSpacing),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _lockGold,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _lockGold.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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
                      SizedBox(height: buttonBottomSpacing),
                    ],
                  ),
                );

                final panel = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      headerCard,
                      SizedBox(height: heroLeadSpace),
                      contentCard,
                    ],
                  ),
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: panelTopBottomPadding,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: panel,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
