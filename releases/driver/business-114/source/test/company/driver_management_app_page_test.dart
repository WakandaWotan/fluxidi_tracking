import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_management_app_page.dart';
import 'package:fluxidi_tracking/company/driver_management_app_session.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const origin = 'https://fluxidi-booking-api.fluxidi.workers.dev';

class HostSession extends DriverManagementAppSession {
  HostSession()
    : super(
        companyId: 'own-company',
        authorization: 'Bearer existing-session',
        expiresAt: null,
        sessionUnchanged: () async => true,
      );
  @override
  Future<Uri> connect() async => Uri.parse(
    '$origin/driver-management/handoff#${List.filled(64, 'a').join()}',
  );
}

class TestPlatform extends WebViewPlatform {
  final views = <TestController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final view = TestController(params);
    views.add(view);
    return view;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => TestNavigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => TestView(params);
}

class TestController extends PlatformWebViewController {
  TestController(super.params) : super.implementation();
  TestNavigation? navigation;
  JavaScriptChannelParams? channel;
  final requests = <LoadRequestParams>[], scripts = <String>[];
  bool blanked = false;
  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest) callback,
  ) async {}
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {
    navigation = delegate as TestNavigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams request) async {
    requests.add(request);
    navigation?.finished?.call('$origin/driver-management/');
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    blanked = true;
  }
}

class TestNavigation extends PlatformNavigationDelegate {
  TestNavigation(super.params) : super.implementation();
  NavigationRequestCallback? request;
  PageEventCallback? finished;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    request = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {}
}

class TestView extends PlatformWebViewWidget {
  TestView(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('original-ui-inside-app'));
}

void main() {
  late TestPlatform platform;
  late ValueNotifier<Object?> session;
  var connections = 0, legacy = 0;
  final managed = <String>[];
  Widget app() => MaterialApp(
    home: DriverManagementAppPage(
      connect: () async {
        connections++;
        return HostSession();
      },
      session: session,
      openLegacy: () async {
        legacy++;
      },
      manageDriver: (id) async {
        managed.add(id);
      },
    ),
  );
  setUp(() {
    platform = TestPlatform();
    WebViewPlatform.instance = platform;
    session = ValueNotifier<Object?>('existing-company-session');
    connections = 0;
    legacy = 0;
    managed.clear();
  });
  tearDown(() => session.dispose());
  for (final format in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(844, 390),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'original host is embedded without login/external launch at $format',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = format;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(connections, 1);
        expect(
          find.byKey(const ValueKey('original-ui-inside-app')),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Inloggen'), findsNothing);
        final view = platform.views.single;
        expect(view.requests.single.uri.path, '/driver-management/handoff');
        expect(view.requests.single.headers, isEmpty);
        expect(view.scripts.any((s) => s.contains('partners-tab')), isTrue);
        expect(
          view.scripts.any((s) => s.contains('FluxidiManagementTheme')),
          isTrue,
        );
        expect(
          await view.navigation!.request!(
            const NavigationRequest(
              url: 'https://attacker.invalid/',
              isMainFrame: true,
            ),
          ),
          NavigationDecision.prevent,
        );
        expect(
          await view.navigation!.request!(
            const NavigationRequest(
              url: '$origin/driver-management/',
              isMainFrame: true,
            ),
          ),
          NavigationDecision.navigate,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'company-session change removes old view before automatic reconnect',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final old = platform.views.single;
      session.value = 'next-company-session';
      expect(old.blanked, true);
      await tester.pumpAndSettle();
      expect(connections, 2);
      expect(
        find.byKey(const ValueKey('original-ui-inside-app')),
        findsOneWidget,
      );
      expect(find.text('Inloggen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pause removes management data; resume reuses company login', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final old = platform.views.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(old.blanked, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(connections, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('existing native docs/codes/QR/vehicles stay reachable', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Documenten, codes, QR en voertuigbeheer'));
    expect(legacy, 1);
    platform.views.single.channel!.onMessageReceived(
      const JavaScriptMessage(
        message: '{"type":"manageDriver","driver_id":"own-driver"}',
      ),
    );
    await tester.pumpAndSettle();
    expect(managed, ['own-driver']);
    await tester.pumpWidget(const SizedBox());
  });
}
