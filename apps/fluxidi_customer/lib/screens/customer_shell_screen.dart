import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/main.dart' show CustomerSavedBookingsPage;

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import 'customer_home_screen.dart';
import 'customer_profile_screen.dart';

/// The three destinations at the bottom: Home, Bookings, Profile.
///
/// Bookings is the existing saved-bookings page. It refreshes itself from the
/// customer session, so it is mounted here rather than reimplemented.
class CustomerShellScreen extends StatefulWidget {
  const CustomerShellScreen({
    super.key,
    this.config = kCustomerAppConfig,
    this.initialIndex = 0,
  });

  final CustomerAppConfig config;
  final int initialIndex;

  @override
  State<CustomerShellScreen> createState() => _CustomerShellScreenState();
}

class _CustomerShellScreenState extends State<CustomerShellScreen> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, variant, _) {
        return CustomerLanguageBuilder(
          builder: (context, language) {
        final palette = paletteForCustomerTheme(variant);
        return Scaffold(
          backgroundColor: palette.background,
          body: IndexedStack(
            index: _index,
            children: <Widget>[
              CustomerHomeScreen(config: widget.config),
              // Keep the list mounted. Remounting on every tab visit restarted
              // session bootstrap plus a GET per booking before any card
              // appeared.
              const CustomerSavedBookingsPage(),
              CustomerProfileScreen(config: widget.config),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            key: const Key('customer_bottom_nav'),
            selectedIndex: _index,
            backgroundColor: palette.surface,
            surfaceTintColor: Colors.transparent,
            indicatorColor: palette.gold.withValues(
              alpha: palette.isDark ? 0.32 : 0.22,
            ),
            onDestinationSelected: (next) => setState(() => _index = next),
            destinations: <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined, color: palette.textMuted),
                selectedIcon: Icon(Icons.home, color: palette.gold),
                label: CustomerText.home.of(language),
              ),
              NavigationDestination(
                icon: Icon(
                  Icons.receipt_long_outlined,
                  color: palette.textMuted,
                ),
                selectedIcon: Icon(Icons.receipt_long, color: palette.gold),
                label: CustomerText.bookings.of(language),
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline, color: palette.textMuted),
                selectedIcon: Icon(Icons.person, color: palette.gold),
                label: CustomerText.profile.of(language),
              ),
            ],
          ),
        );
          },
        );
      },
    );
  }
}
