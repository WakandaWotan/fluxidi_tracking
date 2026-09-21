import 'dart:async';

import 'package:flutter/material.dart';

import '../deeplinks/customer_deep_link.dart';
import '../deeplinks/customer_deep_link_source.dart';
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
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushNamedAndRemoveUntil(
      CustomerRoutes.paymentReturn,
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.config.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: buildCustomerTheme(widget.config),
      initialRoute: CustomerRoutes.home,
      onGenerateRoute: generateCustomerRoute,
    );
  }
}
