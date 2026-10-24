import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';

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
}

const LocalizedText kPublicCompanyExampleBadge = LocalizedText(
  nl: 'Voorbeeldbedrijf',
  en: 'Example company',
  fr: 'Entreprise exemple',
  es: 'Empresa de ejemplo',
);

const LocalizedText kPublicCompanyExampleNotice = LocalizedText(
  nl: 'Dit is het voorbeeldbedrijf van Fluxidi. Dit profiel laat zien hoe een taxibedrijf zich op het platform kan presenteren.',
  en: "This is Fluxidi's example company. This profile shows how a taxi company can present itself on the platform.",
  fr: 'Ceci est l’entreprise exemple de Fluxidi. Ce profil montre comment une société de taxi peut se présenter sur la plateforme.',
  es: 'Esta es la empresa de ejemplo de Fluxidi. Este perfil muestra cómo una empresa de taxi puede presentarse en la plataforma.',
);

const LocalizedText kPublicCompanyReviewBadge = LocalizedText(
  nl: 'Reviewomgeving',
  en: 'Review environment',
  fr: 'Environnement de review',
  es: 'Entorno de review',
);

String _localizedMapText(Object? raw, AppLanguage language) {
  if (raw is String) return raw.trim();
  if (raw is! Map) return '';
  final map = raw.map((key, value) => MapEntry(key.toString(), value));
  final code = switch (language) {
    AppLanguage.en => 'en',
    AppLanguage.fr => 'fr',
    AppLanguage.es => 'es',
    _ => 'nl',
  };
  for (final key in [code, 'nl', 'en']) {
    final value = (map[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

PublicCompanyPresentation publicCompanyPresentationFrom(
  Map<String, dynamic> source, {
  required AppLanguage language,
}) {
  final presentation = source['public_presentation'] is Map
      ? Map<String, dynamic>.from(source['public_presentation'] as Map)
      : const <String, dynamic>{};
  var role = (presentation['role'] ?? '').toString().trim();
  if (role.isEmpty && source['example_company'] == true) role = 'example';
  if (role.isEmpty && source['review_environment'] == true) role = 'review';
  var badge = _localizedMapText(presentation['badge'], language);
  var notice = _localizedMapText(presentation['notice'], language);
  if (role == 'example') {
    if (badge.isEmpty) badge = kPublicCompanyExampleBadge.of(language);
    if (notice.isEmpty) notice = kPublicCompanyExampleNotice.of(language);
  }
  if (role == 'review' && badge.isEmpty) {
    badge = kPublicCompanyReviewBadge.of(language);
  }
  return PublicCompanyPresentation(role: role, badge: badge, notice: notice);
}

class PublicCompanyPresentationBanner extends StatelessWidget {
  const PublicCompanyPresentationBanner({
    super.key,
    required this.presentation,
    this.compact = false,
    this.onInfo,
  });

  final PublicCompanyPresentation presentation;
  final bool compact;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    if (!presentation.hasBadge && !presentation.hasNotice) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (presentation.hasBadge)
            Flexible(
              child: Text(
                presentation.badge,
                key: kCustomerBookingExampleBadgeKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (presentation.hasNotice && onInfo != null)
            IconButton(
              key: kCustomerBookingCompanyInfoKey,
              tooltip: presentation.badge,
              onPressed: onInfo,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.info_outline, size: 18),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (presentation.hasBadge)
            Text(
              presentation.badge,
              key: kCustomerBookingExampleBadgeKey,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          if (presentation.hasNotice) ...[
            const SizedBox(height: 4),
            Text(
              presentation.notice,
              key: kCustomerBookingExampleNoticeKey,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
