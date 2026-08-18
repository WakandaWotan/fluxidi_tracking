// LIMOUSINE-MARKETPLACE-P2D4C1B — dashboard Limousine quotes tile.
// Visibility follows subscription entitlement. Unread count is shown only
// when an authoritative loaded count is supplied.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';
import 'limousine_service_capability.dart';

class LimousineQuoteInboxDashboardTile extends StatelessWidget {
  const LimousineQuoteInboxDashboardTile({
    super.key,
    required this.entitled,
    this.unreadCount,
    this.onOpen,
    this.language,
    this.compact = false,
  });

  final bool? entitled;
  final int? unreadCount;
  final VoidCallback? onOpen;
  final AppLanguage? language;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!limousineQuoteInboxEntryVisible(entitled: entitled)) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, appLanguage, _) {
        final lang = language ?? appLanguage;
        return ValueListenableBuilder<BusinessThemeVariant>(
          valueListenable: businessThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForBusinessTheme(variant);
            final badge = unreadCount != null && unreadCount! > 0
                ? unreadCount
                : null;
            return Material(
              key: kLimousineQuoteInboxEntryKey,
              color: palette.surface,
              elevation: 2,
              shadowColor: palette.shadow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.border),
                    color: palette.surface,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: palette.surfaceAlt),
                        Image.asset(
                          kLimousineMarketplaceHeroAsset,
                          key: kLimousineQuoteInboxTileVisualKey,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) {
                            return ColoredBox(
                              color: palette.surfaceAlt,
                              child: Icon(
                                Icons.request_quote_outlined,
                                color: palette.accent,
                                size: compact ? 28 : 36,
                              ),
                            );
                          },
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                palette.background.withOpacity(
                                  palette.isDark ? 0.18 : 0.08,
                                ),
                                palette.background.withOpacity(
                                  palette.isDark ? 0.78 : 0.62,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(compact ? 10 : 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.request_quote_outlined,
                                    color: palette.accent,
                                    size: compact ? 18 : 22,
                                  ),
                                  const Spacer(),
                                  if (badge != null)
                                    Semantics(
                                      label:
                                          '${kLimousineQuoteInboxKpiNew.of(lang)} $badge',
                                      child: Container(
                                        key: kLimousineQuoteInboxTileBadgeKey,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.accent,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '$badge',
                                          style: TextStyle(
                                            color: palette.textOnAccent,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                kLimousineQuoteInboxEntryTitle.of(lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 13 : 15,
                                ),
                              ),
                              Text(
                                kLimousineQuoteInboxEntrySubtitle.of(lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: compact ? 11 : 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
