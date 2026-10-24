import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'driver_management_app_session.dart';
import '../business_theme_palette.dart';
import 'driver_management_theme.dart';

/// Displays the recovered, original UI inside the app. No browser launcher.
class DriverManagementAppPage extends StatefulWidget {
  const DriverManagementAppPage({
    super.key,
    required this.connect,
    required this.session,
    required this.openLegacy,
    required this.manageDriver,
    this.palette,
  });
  final Future<DriverManagementAppSession> Function() connect;
  final ValueListenable<Object?> session;
  final Future<void> Function() openLegacy;
  final Future<void> Function(String) manageDriver;
  final BusinessThemePalette? palette;
  @override
  State<DriverManagementAppPage> createState() =>
      _DriverManagementAppPageState();
}

class _DriverManagementAppPageState extends State<DriverManagementAppPage>
    with WidgetsBindingObserver {
  BusinessThemePalette get _palette =>
      widget.palette ??
      paletteForBusinessTheme(BusinessThemeVariant.executiveGold);
  Future<void> _applyTheme(WebViewController controller) async {
    final values = jsonEncode(driverManagementThemeValues(_palette));
    await controller.runJavaScript(
      "window.FluxidiManagementTheme?.apply($values);",
    );
  }

  @override
  void didUpdateWidget(covariant DriverManagementAppPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller != null)
      unawaited(_applyTheme(controller).catchError((_) {}));
  }

  WebViewController? _controller;
  DriverManagementAppSession? _connection;
  String? _error;
  int _generation = 0;
  bool _busy = true, _exporting = false, _background = false;
  Timer? _loadTimeout;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    _open();
  }

  void _sessionChanged() {
    _discard();
    if (!_background) _open();
  }

  void _discard({bool notify = true}) {
    _loadTimeout?.cancel();
    _generation++;
    final old = _controller;
    _controller = null;
    _connection?.close();
    _connection = null;
    // Remove the platform view immediately before any async network operation.
    if (notify && mounted) setState(() => _busy = true);
    if (old != null) {
      old.setJavaScriptMode(JavaScriptMode.disabled).catchError((_) {});
      old.loadHtmlString('<html><body></body></html>').catchError((_) {});
    }
  }

  Future<void> _open() async {
    final generation = ++_generation;
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    DriverManagementAppSession? connection;
    try {
      connection = await widget.connect();
      if (!mounted || generation != _generation) {
        connection.close();
        return;
      }
      _connection = connection;
      final location = await connection.connect();
      if (!mounted || generation != _generation) {
        connection.close();
        return;
      }
      final active = connection;
      final controller = WebViewController(
        onPermissionRequest: (request) => request.deny(),
      );
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(_palette.background);
      await controller.addJavaScriptChannel(
        'FluxidiManagement',
        onMessageReceived: (message) =>
            _message(message.message, generation, active),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              generation == _generation && active.allowsNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (url) async {
            if (!mounted || generation != _generation) return;
            if (!await active.sessionUnchanged()) {
              _sessionChanged();
              return;
            }
            if (!mounted || generation != _generation) return;
            if (Uri.tryParse(url)?.path == '/driver-management/') {
              await _applyTheme(controller);
              await controller.runJavaScript(
                "document.getElementById('partners-tab')?.click();document.getElementById('drivers-tab').onclick=()=>window.FluxidiManagement.postMessage(JSON.stringify({type:'drivers'}));",
              );
              _loadTimeout?.cancel();
              if (mounted && generation == _generation)
                setState(() => _busy = false);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true &&
                mounted &&
                generation == _generation)
              setState(() {
                _error =
                    'De beheeromgeving kon niet worden geladen. Probeer opnieuw.';
                _busy = false;
              });
          },
          onHttpError: (error) {
            final uri = error.request?.uri;
            if (uri != null &&
                [
                  '/driver-management/',
                  '/driver-management/handoff',
                ].contains(uri.path) &&
                mounted &&
                generation == _generation) {
              _loadTimeout?.cancel();
              setState(() {
                _error =
                    'Je bedrijfsomgeving is tijdelijk niet beschikbaar. Probeer opnieuw.';
                _busy = false;
              });
            }
          },
        ),
      );
      if (controller.platform is AndroidWebViewController) {
        final android = controller.platform as AndroidWebViewController;
        await android.setMixedContentMode(MixedContentMode.neverAllow);
        await android.setAllowFileAccess(false);
        await android.setAllowContentAccess(false);
        await android.setGeolocationEnabled(false);
      }
      if (!mounted || generation != _generation) return;
      setState(() => _controller = controller);
      _loadTimeout = Timer(const Duration(seconds: 25), () {
        if (mounted && generation == _generation && _busy)
          setState(() {
            _busy = false;
            _error = 'De bedrijfsomgeving antwoordt niet. Probeer opnieuw.';
          });
      });
      await controller.loadRequest(location);
    } catch (_) {
      connection?.close();
      if (mounted && generation == _generation)
        setState(() {
          _controller = null;
          _connection = null;
          _busy = false;
          _error =
              'Chauffeurbeheer is tijdelijk niet bereikbaar of je bedrijfssessie is verlopen. Probeer opnieuw vanuit je bedrijfslogin.';
        });
    }
  }

  Future<void> _message(
    String raw,
    int generation,
    DriverManagementAppSession connection,
  ) async {
    if (raw.length > 16384 ||
        generation != _generation ||
        !identical(connection, _connection))
      return;
    try {
      if (!await connection.sessionUnchanged() ||
          !mounted ||
          generation != _generation)
        return;
      final message = jsonDecode(raw);
      if (message is! Map) return;
      if (message['type'] == 'drivers') {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      } else if (message['type'] == 'manageDriver' &&
          message['driver_id'] is String) {
        final id = message['driver_id'] as String;
        if (id.isEmpty || id.length > 200) return;
        await widget.manageDriver(id);
      } else if (message['type'] == 'export' &&
          message['url'] is String &&
          !_exporting) {
        _exporting = true;
        try {
          final csv = await connection.exportCsv(message['url'] as String);
          if (!mounted ||
              generation != _generation ||
              !await connection.sessionUnchanged())
            return;
          final bytes = Uint8List.fromList(utf8.encode(csv));
          if (!mounted) return;
          final box = context.findRenderObject() as RenderBox?;
          await Share.shareXFiles(
            [
              XFile.fromData(
                bytes,
                mimeType: 'text/csv',
                name: 'fluxidi-chauffeurs.csv',
              ),
            ],
            fileNameOverrides: ['fluxidi-chauffeurs.csv'],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          );
        } finally {
          _exporting = false;
        }
      }
    } catch (_) {
      if (mounted && generation == _generation)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'De beheeractie kon niet veilig worden uitgevoerd. Probeer opnieuw.',
            ),
          ),
        );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _background = true;
      _discard();
    }
    if (state == AppLifecycleState.resumed && _background) {
      _background = false;
      _open();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _discard(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: driverManagementTheme(_palette),
    child: Scaffold(
      key: const ValueKey('driver-management-app-page'),
      backgroundColor: _palette.background,
      appBar: AppBar(
        backgroundColor: _palette.background,
        foregroundColor: _palette.textPrimary,
        title: const Text('Partnerbedrijven'),
        actions: [
          IconButton(
            key: const ValueKey('driver-management-app-legacy'),
            tooltip: 'Documenten, codes, QR en voertuigbeheer',
            onPressed: widget.openLegacy,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            tooltip: 'Vernieuwen',
            onPressed: _busy
                ? null
                : () {
                    _discard();
                    _open();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null && _error == null)
              WebViewWidget(
                key: ValueKey(_generation),
                controller: _controller!,
              ),
            if (_busy)
              Center(child: CircularProgressIndicator(color: _palette.accent)),
            if (_error != null)
              Center(
                key: const ValueKey('driver-management-app-error'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(color: _palette.textPrimary),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _open,
                        child: const Text('Opnieuw proberen'),
                      ),
                      TextButton(
                        onPressed: widget.openLegacy,
                        child: const Text('Bestaand beheer openen'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
