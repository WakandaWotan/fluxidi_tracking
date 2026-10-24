import 'package:fluxidi_tracking/app_config.dart';

/// Publishing changes the receipt, not the company's saved settings.
BackendBusinessProfile businessProfileAfterPublication(
  BackendBusinessProfile profile, {
  required String publishedAt,
}) => profile.copyWith(
  publicPartnerProfilePublishedAt: publishedAt,
  publicPartnerProfilePublishStatus: 'published',
);
