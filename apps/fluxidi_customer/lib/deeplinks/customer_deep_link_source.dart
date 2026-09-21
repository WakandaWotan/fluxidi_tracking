import 'package:app_links/app_links.dart';

/// Where incoming links come from.
///
/// Abstracted so the app root can be driven in tests without touching a
/// platform channel.
abstract class CustomerDeepLinkSource {
  /// Link that started the app from cold, if any.
  Future<Uri?> initialLink();

  /// Links that arrive while the app is already running.
  Stream<Uri> linkStream();
}

/// Production source backed by `app_links`.
class AppLinksCustomerDeepLinkSource implements CustomerDeepLinkSource {
  AppLinksCustomerDeepLinkSource([AppLinks? appLinks])
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> linkStream() => _appLinks.uriLinkStream;
}
