import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/main.dart'
    show
        kFluxidiLocalizationsDelegates,
        kFluxidiSupportedLocales,
        resolveFluxidiAppLocale;

import '../bridge/customer_flows.dart';
import '../deeplinks/customer_deep_link.dart';
import '../deeplinks/customer_deep_link_source.dart';
import '../screens/customer_payment_return_screen.dart';
import '../screens/customer_shell_screen.dart';
import '../security/customer_session_lock.dart';
import '../security/customer_session_lock_gate.dart';
import 'customer_app_config.dart';
import 'customer_routes.dart';
import 'customer_theme.dart';

/// Root of the standalone Fluxidi customer app.
///
/// Rebuilds on the customer theme and the app language, so the existing theme
/// picker and the language choice apply to this shell and to every bridged
/// screen opened from it.
class FluxidiCustomerApp extends StatefulWidget {
  const FluxidiCustomerApp({
    super.key,
    this.config = kCustomerAppConfig,
    this.deepLinkSource,
    this.sessionLock,
    this.lockAfterBackground = const Duration(seconds: 1),
    this.now,
  });

  final CustomerAppConfig config;

  /// When null, no link source is attached at all.
  final CustomerDeepLinkSource? deepLinkSource;

  /// Test override. Production uses [CustomerSessionLock.instance].
  final CustomerSessionLock? sessionLock;

  /// How long the app must stay in the background before a lock is requested.
  final Duration lockAfterBackground;

  /// Clock for the background grace period. Tests advance this without waiting.
  final DateTime Function()? now;

  @override
  State<FluxidiCustomerApp> createState() => _FluxidiCustomerAppState();
}

class _FluxidiCustomerAppState extends State<FluxidiCustomerApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _CustomerLockNavigatorObserver _lockObserver =
      _CustomerLockNavigatorObserver(_syncNavigationBusy);
  StreamSubscription<Uri>? _linkSub;

  /// First moment the app left the foreground. The return path also emits
  /// [AppLifecycleState.hidden] before [AppLifecycleState.resumed]; that event
  /// must not replace this timestamp or every reopen looks shorter than the
  /// grace period and the lock is skipped.
  DateTime? _backgroundSince;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  CustomerSessionLock get _lock =>
      widget.sessionLock ?? CustomerSessionLock.instance;

  /// Shown above the current screen after an own-scheme return link.
  ///
  /// Held as state instead of a pushed route: an imperative push from the link
  /// listener landed on the navigator stack but never became visible on device,
  /// so the screen is rendered declaratively and cannot be lost that way.
  bool _paymentReturnVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lock.attach());
    // The bridged flows offer a "back to start" action. Point it at this app's
    // own start page instead of the combined app's customer home.
    registerCustomerStartPage(
      (_) => CustomerShellScreen(config: widget.config),
    );
    final source = widget.deepLinkSource;
    if (source == null) return;
    _linkSub = source.linkStream().listen(
      (uri) => _handleIncomingLink(uri, source: 'stream'),
      onError: (Object error) =>
          debugPrint('[CUSTOMER_DEEP_LINK][STREAM_ERROR] $error'),
    );
    unawaited(_handleColdStartLink(source));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundSince ??= _now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final backgroundSince = _backgroundSince;
    _backgroundSince = null;
    _lock.paymentReturnActive = _paymentReturnVisible;
    _syncNavigationBusy();
    if (backgroundSince == null) return;
    final elapsed = _now().difference(backgroundSince);
    if (elapsed < widget.lockAfterBackground) {
      debugPrint(
        '[CUSTOMER_LOCK] resume skipped elapsedMs=${elapsed.inMilliseconds} '
        'graceMs=${widget.lockAfterBackground.inMilliseconds}',
      );
      return;
    }
    _lock.markLockPending();
    debugPrint(
      '[CUSTOMER_LOCK] resume request elapsedMs=${elapsed.inMilliseconds} '
      'defer=${_lock.shouldDeferLock} enabled=${_lock.isEnabled}',
    );
    unawaited(_lock.applyPendingLockIfSafe());
  }

  void _syncNavigationBusy() {
    _lock.navigationBusy = _navigatorKey.currentState?.canPop() == true;
  }

  Future<void> _handleColdStartLink(CustomerDeepLinkSource source) async {
    try {
      final initial = await source.initialLink();
      if (initial != null) {
        _handleIncomingLink(initial, source: 'cold_start');
      }
    } catch (error) {
      debugPrint('[CUSTOMER_DEEP_LINK][COLD_START_ERROR] $error');
    }
  }

  void _handleIncomingLink(Uri uri, {required String source}) {
    final result = resolveCustomerDeepLink(uri, config: widget.config);
    debugPrint(
      '[CUSTOMER_DEEP_LINK] source=$source kind=${result.kind.name} '
      'reason=${result.reason}',
    );
    if (!result.opensPaymentReturnScreen) return;
    // Leave any deeper flow first, so closing the return screen lands on start.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (!mounted) return;
    _lock.paymentReturnActive = true;
    setState(() => _paymentReturnVisible = true);
  }

  void _closePaymentReturn() {
    if (!_paymentReturnVisible) return;
    setState(() => _paymentReturnVisible = false);
    _lock.paymentReturnActive = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, variant, _) {
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: appLanguageNotifier,
          builder: (context, _, __) {
            final palette = paletteForCustomerTheme(variant);
            final theme = buildCustomerTheme(widget.config, variant: variant);
            applyCustomerThemeSystemUiOverlay(palette);
            return MaterialApp(
              title: widget.config.appName,
              debugShowCheckedModeBanner: false,
              navigatorKey: _navigatorKey,
              navigatorObservers: <NavigatorObserver>[_lockObserver],
              theme: theme,
              darkTheme: theme,
              // The palette already encodes light vs dark. Pinning the mode
              // stops the OS dark setting from substituting a default dark
              // Material 3 theme that would ignore the customer's choice.
              themeMode: palette.isDark ? ThemeMode.dark : ThemeMode.light,
              // The chosen app language wins over the device locale, and the
              // framework delegates must cover every language in the list or
              // MaterialLocalizations.of() throws under nl/fr/es/de.
              locale: resolveFluxidiAppLocale(),
              supportedLocales: kFluxidiSupportedLocales,
              localizationsDelegates: kFluxidiLocalizationsDelegates,
              localeResolutionCallback: (deviceLocale, supported) =>
                  resolveFluxidiAppLocale(supported),
              initialRoute: CustomerRoutes.home,
              onGenerateRoute: (settings) =>
                  generateCustomerRoute(settings, config: widget.config),
              builder: (context, child) {
                return ListenableBuilder(
                  listenable: _lock,
                  builder: (context, _) {
                    final page = !_paymentReturnVisible
                        ? (child ?? const SizedBox.shrink())
                        : Stack(
                            children: <Widget>[
                              child ?? const SizedBox.shrink(),
                              CustomerPaymentReturnScreen(
                                config: widget.config,
                                onClose: _closePaymentReturn,
                              ),
                            ],
                          );
                    final locked = _lock.isLocked
                        ? Stack(
                            children: <Widget>[
                              page,
                              CustomerSessionLockGate(lock: _lock),
                            ],
                          )
                        : page;
                    return AnnotatedRegion<SystemUiOverlayStyle>(
                      value: systemUiOverlayStyleForCustomerTheme(palette),
                      child: locked,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CustomerLockNavigatorObserver extends NavigatorObserver {
  _CustomerLockNavigatorObserver(this._onStackChanged);

  final VoidCallback _onStackChanged;

  void _notify() => _onStackChanged();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _notify();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}
