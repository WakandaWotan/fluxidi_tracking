import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import '../bridge/customer_flows.dart';
import '../bridge/customer_language.dart';
import '../bridge/customer_runtime.dart';
import '../security/customer_device_unlock.dart';
import '../security/customer_session_lock.dart';
import '../widgets/customer_header_bar.dart';
import '../widgets/customer_language_sheet.dart';

/// Profile page: personal details, bookings, language, theme, and the data and
/// account-deletion page. Every entry opens the existing screen behind it.
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key, this.config = kCustomerAppConfig});

  final CustomerAppConfig config;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  bool _loading = true;
  bool _signedIn = false;
  CustomerProfile? _profile;

  @override
  void initState() {
    super.initState();
    CustomerSessionLock.instance.addListener(_onLockChanged);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    CustomerSessionLock.instance.removeListener(_onLockChanged);
    super.dispose();
  }

  void _onLockChanged() {
    if (!mounted || CustomerSessionLock.instance.isLocked) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final signedIn = await hasValidCustomerSession();
    final profile = signedIn ? await loadLocalCustomerProfile() : null;
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _profile = profile;
      _loading = false;
    });
    if (signedIn) scheduleCustomerProfileSync(reason: 'profile_screen');
  }

  Future<void> _signIn() async {
    await signInCustomer(context);
    await _refresh();
  }

  Future<void> _signOut() async {
    await signOutCustomer();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, variant, _) {
        return CustomerLanguageBuilder(
          builder: (context, language) {
        final palette = paletteForCustomerTheme(variant);
        final theme = Theme.of(context);
        return ColoredBox(
          color: palette.background,
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: <Widget>[
                  CustomerHeaderBar(config: widget.config),
                  const SizedBox(height: 20),
                  Text(
                    CustomerText.profile.of(language),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AccountCard(
                    palette: palette,
                    loading: _loading,
                    signedIn: _signedIn,
                    profile: _profile,
                    onSignIn: _signIn,
                    onSignOut: _signOut,
                  ),
                  if (_signedIn && !_loading) ...<Widget>[
                    const SizedBox(height: 10),
                    _DeviceUnlockTile(palette: palette, language: language),
                  ],
                  const SizedBox(height: 18),
                  _ProfileTile(
                    palette: palette,
                    tileKey: const Key('customer_profile_my_details'),
                    icon: Icons.badge_outlined,
                    label: CustomerText.myDetails.of(language),
                    onTap: () async {
                      await openMyDetails(context);
                      await _refresh();
                    },
                  ),
                  _ProfileTile(
                    palette: palette,
                    tileKey: const Key('customer_profile_my_bookings'),
                    icon: Icons.receipt_long_outlined,
                    label: CustomerText.myBookings.of(language),
                    onTap: () => unawaited(openMyBookings(context)),
                  ),
                  _ProfileTile(
                    palette: palette,
                    tileKey: const Key('customer_profile_companies'),
                    icon: Icons.store_outlined,
                    label: CustomerText.companies.of(language),
                    onTap: () => unawaited(openCompanySearch(context)),
                  ),
                  _ProfileTile(
                    palette: palette,
                    tileKey: const Key('customer_profile_language'),
                    icon: Icons.translate_outlined,
                    label: CustomerText.language.of(language),
                    trailingText: kCustomerLanguageLabels[language],
                    onTap: () async {
                      await showCustomerLanguageSheet(context);
                      if (mounted) setState(() {});
                    },
                  ),
                  _ProfileTile(
                    palette: palette,
                    tileKey: const Key('customer_profile_theme'),
                    icon: Icons.palette_outlined,
                    label: CustomerText.chooseTheme.of(language),
                    onTap: () => unawaited(openThemePicker(context)),
                  ),
                  const SizedBox(height: 10),
                  _ProfileTile(
                    palette: palette,
                    tileKey: const Key('customer_profile_privacy'),
                    icon: Icons.privacy_tip_outlined,
                    label: CustomerText.dataAndAccount.of(language),
                    onTap: () => openPrivacyAndAccount(context),
                  ),
                ],
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.palette,
    required this.loading,
    required this.signedIn,
    required this.profile,
    required this.onSignIn,
    required this.onSignOut,
  });

  final CustomerThemePalette palette;
  final bool loading;
  final bool signedIn;
  final CustomerProfile? profile;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final name = (profile?.name ?? '').trim();
    final phone = (profile?.phone ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: palette.gold.withValues(alpha: 0.18),
            child: Icon(Icons.person_outline, color: palette.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  signedIn && name.isNotEmpty
                      ? name
                      : CustomerText.signedOutHint.current,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                if (signedIn && phone.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          signedIn
              ? TextButton(
                  key: const Key('customer_profile_sign_out'),
                  onPressed: () => unawaited(onSignOut()),
                  child: Text(CustomerText.signOut.current),
                )
              : FilledButton(
                  key: const Key('customer_profile_sign_in'),
                  onPressed: () => unawaited(onSignIn()),
                  child: Text(CustomerText.signIn.current),
                ),
        ],
      ),
    );
  }
}

class _DeviceUnlockTile extends StatefulWidget {
  const _DeviceUnlockTile({
    required this.palette,
    required this.language,
  });

  final CustomerThemePalette palette;
  final AppLanguage language;

  @override
  State<_DeviceUnlockTile> createState() => _DeviceUnlockTileState();
}

class _DeviceUnlockTileState extends State<_DeviceUnlockTile> {
  bool _ready = false;
  bool _available = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final lock = CustomerSessionLock.instance;
    final available = await lock.canProtectDevice();
    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = lock.isEnabled;
      _ready = true;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final lock = CustomerSessionLock.instance;
    final language = widget.language;
    final result = value
        ? await lock.enableAfterAuthentication(
            reason: CustomerText.unlockReasonEnable.of(language),
          )
        : await lock.disableAfterAuthentication(
            reason: CustomerText.unlockReasonDisable.of(language),
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enabled = lock.isEnabled;
    });
    if (result == CustomerUnlockResult.unavailable) {
      setState(() => _available = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !_available) return const SizedBox.shrink();
    return Container(
      key: const Key('customer_profile_device_unlock'),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: widget.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.palette.border),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _enabled,
        onChanged: _busy ? null : (value) => unawaited(_toggle(value)),
        title: Text(
          CustomerText.unlockSwitchTitle.of(widget.language),
          style: TextStyle(
            color: widget.palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          CustomerText.unlockSwitchSubtitle.of(widget.language),
          style: TextStyle(color: widget.palette.textMuted),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tileKey,
    this.trailingText,
  });

  final CustomerThemePalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Key? tileKey;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: tileKey,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, color: palette.gold),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if ((trailingText ?? '').isNotEmpty) ...<Widget>[
                  Text(
                    trailingText!,
                    style: TextStyle(color: palette.textMuted),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.chevron_right, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
