import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

const double kCustomerHomeDesktopMinWidth = 1100;
const Color kCustomerHomeDesktopAccentLight = Color(0xFFFFD400);

Color customerHomeDesktopAccent(CustomerThemePalette palette) =>
    palette.isDark ? palette.gold : kCustomerHomeDesktopAccentLight;

const Key kCustomerHomeDesktopShellKey = Key('customer_home_desktop_shell');
const Key kCustomerHomeDesktopSidebarKey = Key('customer_home_desktop_sidebar');
const Key kCustomerHomeDesktopBookingPanelKey = Key(
  'customer_home_desktop_booking_panel',
);
const Key kCustomerHomeDesktopDiscoverKey = Key('customer_home_desktop_discover');
const Key kCustomerHomeDesktopScrollKey = Key('customer_home_desktop_scroll');
const Key kCustomerHomeSearchRideKey = Key('customer_home_search_ride');
const Key kCustomerHomePickupKey = Key('customer_home_pickup');
const Key kCustomerHomeDropoffKey = Key('customer_home_dropoff');
const Key kCustomerHomeWhenNowKey = Key('customer_home_when_now');
const Key kCustomerHomeWhenLaterKey = Key('customer_home_when_later');
const Key kCustomerHomeNavHomeKey = Key('customer_home_nav_home');
const Key kCustomerHomeNavTaxiKey = Key('customer_home_nav_taxi');
const Key kCustomerHomeNavBookingsKey = Key('customer_home_nav_bookings');
const Key kCustomerHomeNavProfileKey = Key('customer_home_nav_profile');
const Key kCustomerHomeNavThemeKey = Key('customer_home_nav_theme');
const Key kCustomerHomeNavStartKey = Key('customer_home_nav_start');
const Key kCustomerHomeGreetingKey = Key('customer_home_greeting');
const Key kCustomerHomeTaglineKey = Key('customer_home_tagline');
const Key kCustomerHomeProfileAvatarKey = Key('customer_home_profile_avatar');
const Key kCustomerHomeNearbyKey = Key('customer_home_nearby');
const Key kCustomerHomeRadarKey = Key('customer_home_radar');
const Key kCustomerHomePrivacyKey = Key('customer_home_privacy');
const Key kCustomerHomeCompanyKey = Key('customer_home_company');

bool customerHomeUsesDesktopLayout(double width) =>
    width >= kCustomerHomeDesktopMinWidth;

class CustomerHomeSidebarItem extends StatelessWidget {
  const CustomerHomeSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.palette,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final CustomerThemePalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? const Color(0xFF1A1A1A) : const Color(0xFFF4F1EA);
    final bg = selected ? customerHomeDesktopAccent(palette) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          focusColor: selected
              ? const Color(0x33111111)
              : const Color(0x33FFFFFF),
          hoverColor: selected
              ? const Color(0x22111111)
              : const Color(0x1AFFFFFF),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class CustomerHomeDiscoverCard extends StatelessWidget {
  const CustomerHomeDiscoverCard({
    super.key,
    required this.title,
    required this.asset,
    required this.icon,
    required this.onTap,
    required this.palette,
    this.alignment = Alignment.center,
  });

  final String title;
  final String asset;
  final IconData icon;
  final VoidCallback onTap;
  final CustomerThemePalette palette;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        focusColor: palette.gold.withValues(alpha: 0.18),
        hoverColor: palette.gold.withValues(alpha: 0.08),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border.withValues(alpha: 0.7)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ColoredBox(
                    color: palette.surfaceAlt,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      alignment: alignment,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => Icon(
                        icon,
                        color: palette.gold,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border(
                      top: BorderSide(color: palette.border.withValues(alpha: 0.55)),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: palette.textPrimary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.2,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: palette.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerHomeUtilityLink extends StatelessWidget {
  const CustomerHomeUtilityLink({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final CustomerThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: palette.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.2,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
