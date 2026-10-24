/// Example / review presentation of a public company.
///
/// Mirrors the meaning of `lib/nearby/public_company_presentation.dart` at
/// golden commit 9df7e7b9. Without this, Fluxidi's own example company would
/// look like an ordinary taxi company in the list.
library;

import 'public_partner_models.dart';

const String kExampleBadgeNl = 'Voorbeeldbedrijf';
const String kExampleNoticeNl =
    'Dit is het voorbeeldbedrijf van Fluxidi. Dit profiel laat zien hoe een '
    'taxibedrijf zich op het platform kan presenteren.';
const String kReviewBadgeNl = 'Reviewomgeving';

class PublicCompanyPresentation {
  const PublicCompanyPresentation({
    this.role = '',
    this.badge = '',
    this.notice = '',
  });

  final String role;
  final String badge;
  final String notice;

  bool get isExample => role == 'example';
  bool get isReview => role == 'review';
  bool get hasBadge => badge.trim().isNotEmpty;
  bool get hasNotice => notice.trim().isNotEmpty;
  bool get isPlain => !hasBadge && !hasNotice;
}

/// Reads the presentation block from a nearby entry or a profile.
PublicCompanyPresentation publicCompanyPresentationFrom(
  Map<String, dynamic> source,
) {
  final presentation = asStringKeyedMap(source['public_presentation']);

  var role = readText(presentation, const <String>['role']);
  if (role.isEmpty && source['example_company'] == true) role = 'example';
  if (role.isEmpty && source['review_environment'] == true) role = 'review';

  var badge = _localizedNl(presentation['badge']);
  var notice = _localizedNl(presentation['notice']);

  if (role == 'example') {
    if (badge.isEmpty) badge = kExampleBadgeNl;
    if (notice.isEmpty) notice = kExampleNoticeNl;
  }
  if (role == 'review' && badge.isEmpty) badge = kReviewBadgeNl;

  return PublicCompanyPresentation(role: role, badge: badge, notice: notice);
}

/// Server sends either a plain string or a per-language map.
String _localizedNl(Object? raw) {
  if (raw is String) return raw.trim();
  if (raw is! Map) return '';
  final map = asStringKeyedMap(raw);
  return readText(map, const <String>['nl', 'en']);
}
