import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/main.dart' show CustomerSavedBookingsPage;

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import '../app/customer_theme.dart';
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
    final palette = activeCustomerPalette();
    return Scaffold(
      backgroundColor: palette.background,
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          CustomerHomeScreen(config: widget.config),
          // Keyed on the tab index so leaving and returning reloads the list
          // instead of showing a stale one.
          _index == 1
              ? const CustomerSavedBookingsPage()
              : const SizedBox.shrink(),
          CustomerProfileScreen(config: widget.config),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('customer_bottom_nav'),
        selectedIndex: _index,
        onDestinationSelected: (next) => setState(() => _index = next),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: CustomerText.home.current,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: CustomerText.bookings.current,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: CustomerText.profile.current,
          ),
        ],
      ),
    );
  }
}
