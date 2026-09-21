import 'dart:async';

import 'package:flutter/material.dart';

import '../deeplinks/customer_deep_link.dart';
import '../deeplinks/customer_deep_link_source.dart';
import '../screens/customer_payment_return_screen.dart';
import 'customer_app_config.dart';
import 'customer_routes.dart';
import 'customer_theme.dart';

/// Root of the standalone Fluxidi customer app.
///
/// Owns its own startup: no company, driver or planner bootstrap, no session
/// restore and no backend calls in this phase.
class FluxidiCustomerApp extends StatefulWidget {
  const FluxidiCustomerApp({
    super.key,
    this.config = kCustomerAppConfig,
    this.deepLinkSource,
  });

  final CustomerAppConfig config;

  /// When null, no link source is attached at all.
  final CustomerDeepLinkSource? deepLinkSource;

  @override
  State<FluxidiCustomerApp> createState() => _FluxidiCustomerAppState();
}

class _FluxidiCustomerAppState extends State<FluxidiCustomerApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  /// Shown above the current screen after an own-scheme return link.
  ///
  /// Held as state instead of a pushed route: an imperative push from the link
  /// listener landed on the navigator stack but never became visible on device,
  /// so the screen is rendered declaratively and cannot be lost that way.
  bool _paymentReturnVisible = false;

  @override
  void initState() {
    super.initState();
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
    _linkSub?.cancel();
    super.dispose();
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
    setState(() => _paymentReturnVisible = true);
  }

  void _closePaymentReturn() {
    if (!_paymentReturnVisible) return;
    setState(() => _paymentReturnVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.config.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: buildCustomerTheme(widget.config),
      initialRoute: CustomerRoutes.home,
      onGenerateRoute: (settings) =>
          generateCustomerRoute(settings, config: widget.config),
      builder: (context, child) {
        if (!_paymentReturnVisible) return child ?? const SizedBox.shrink();
        return Stack(
          children: <Widget>[
            child ?? const SizedBox.shrink(),
            CustomerPaymentReturnScreen(
              config: widget.config,
              onClose: _closePaymentReturn,
            ),
          ],
        );
      },
    );
  }
}
