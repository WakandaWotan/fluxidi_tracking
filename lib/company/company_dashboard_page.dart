// COMPANY-CUSTOMER-OPS-P0 — existing company dashboard in the local browser.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_booking_link_page.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_bookings_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_dashboard_layout.dart';
import 'package:fluxidi_tracking/company/company_dashboard_tiles.dart';
import 'package:fluxidi_tracking/company/company_dashboard_unavailable_page.dart';
import 'package:fluxidi_tracking/company/company_drivers_admin_page.dart';
import 'package:fluxidi_tracking/company/company_fleet_page.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_ops_theme_sync.dart';
import 'package:fluxidi_tracking/company/company_settings_page.dart';
import 'package:fluxidi_tracking/company/company_subscription_status_page.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_action_card.dart';

const Key kCompanyDashboardPageKey = Key('company_dashboard_page');
const Key kCompanyDashboardHeaderKey = Key('company_dashboard_header');
const Key kCompanyDashboardLogoKey = Key('company_dashboard_logo');
const Key kCompanyDashboardNameKey = Key('company_dashboard_company_name');
const Key kCompanyDashboardTileGridKey = Key('company_dashboard_tile_grid');
const Key kCompanyDashboardSwitchKey = Key('company_dashboard_switch_company');
const Key kCompanyDashboardSignOutKey = Key('company_dashboard_sign_out');
const Key kCompanyDashboardPickerKey = Key('company_dashboard_picker');

class CompanyDashboardPage extends StatefulWidget {
  const CompanyDashboardPage({
    super.key,
    this.language,
    this.directory,
    this.identityLoader,
    this.onOpenCustomers,
    this.onOpenBooking,
    this.bookingsPageLoader,
    this.bookingDetailLoader,
    this.driversLoader,
    this.vehiclesLoader,
    this.settingsProfileLoader,
    this.settingsProfileSaver,
  });

  final AppLanguage? language;
  final Future<List<CompanyOpsDirectoryEntry>> Function()? directory;
  final Future<Map<String, dynamic>> Function()? identityLoader;
  final void Function(BuildContext context, CompanyOpsIdentity identity)?
      onOpenCustomers;
  final void Function(String bookingId)? onOpenBooking;
  final Future<BookingListPageResult> Function({
    String cursor,
    bool forceRefresh,
  })?
  bookingsPageLoader;
  final Future<Map<String, dynamic>> Function(String bookingId)?
      bookingDetailLoader;
  final Future<List<Map<String, dynamic>>> Function()? driversLoader;
  final Future<List<Map<String, dynamic>>> Function()? vehiclesLoader;
  final Future<Map<String, dynamic>> Function()? settingsProfileLoader;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> profile)?
      settingsProfileSaver;

  @override
  State<CompanyDashboardPage> createState() => CompanyDashboardPageState();
}

class CompanyDashboardPageState extends State<CompanyDashboardPage> {
  List<CompanyOpsDirectoryEntry> _directory = const <CompanyOpsDirectoryEntry>[];
  String? _directoryError;
  bool _loadingIdentity = false;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    registerCompanyOpsThemeRemoteSync();
    _loadDirectory();
    if (companyOpsLocalSessionNotifier.value != null) {
      _refreshIdentity();
    }
  }

  Future<void> _loadDirectory() async {
    try {
      final items = await (widget.directory ?? fetchCompanyOpsLocalDirectory)();
      if (!mounted) return;
      setState(() {
        _directory = items;
        _directoryError = null;
      });
      if (companyOpsLocalSessionNotifier.value == null && items.isNotEmpty) {
        final preferred = items.cast<CompanyOpsDirectoryEntry>().firstWhere(
          (entry) => entry.companyId == kCompanyCustomerOpsLocalDemoCompanyId,
          orElse: () => items.first,
        );
        await _activate(preferred);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _directoryError = kCompanyDashboardPickCompany.of(_lang);
      });
    }
  }

  Future<void> _refreshIdentity() async {
    final session = companyOpsLocalSessionNotifier.value;
    if (session == null) return;
    final generation = companyOpsContextGeneration;
    setState(() => _loadingIdentity = true);
    try {
      final profile = await (widget.identityLoader ??
          fetchCompanyOpsBusinessProfile)();
      if (!shouldApplyCompanyOpsIdentity(
        generation: generation,
        companyId: session.companyId,
        session: companyOpsLocalSessionNotifier.value,
      )) {
        return;
      }
      final identity = identityFromBusinessProfile(
        generation: generation,
        companyId: session.companyId,
        profile: profile,
      );
      companyOpsIdentityNotifier.value = identity;
      bindBusinessThemeCompanyScope(session.companyId);
      await hydrateBusinessThemeFromCompanyProfile(
        companyId: session.companyId,
        profile: profile,
      );
    } catch (_) {
      if (!shouldApplyCompanyOpsIdentity(
        generation: generation,
        companyId: session.companyId,
        session: companyOpsLocalSessionNotifier.value,
      )) {
        return;
      }
      companyOpsIdentityNotifier.value = CompanyOpsIdentity(
        generation: generation,
        companyId: session.companyId,
        companyName: '',
        logo: CompanyLogoRef.unset,
        profileError: kCompanyCustomersMissingScopeHint,
      );
    } finally {
      if (mounted && isCurrentCompanyOpsGeneration(generation)) {
        setState(() => _loadingIdentity = false);
      }
    }
  }

  Future<void> _activate(CompanyOpsDirectoryEntry entry) async {
    beginCompanyOpsContextClear();
    final generation = companyOpsContextGeneration;
    companyOpsLocalSessionNotifier.value = CompanyOpsLocalSession(
      companyId: entry.companyId,
      sessionToken: entry.sessionToken,
    );
    bindBusinessThemeCompanyScope(entry.companyId);
    await _refreshIdentity();
    if (!isCurrentCompanyOpsGeneration(generation)) return;
  }

  void _signOut() {
    beginCompanyOpsContextClear();
    setState(() {});
  }

  void _openTile(CompanyDashboardTileSpec tile) {
    if (tile.webFit == CompanyDashboardTileWebFit.blocked) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CompanyDashboardUnavailablePage(
            tile: tile,
            language: _lang,
          ),
        ),
      );
      return;
    }
    final identity = companyOpsIdentityNotifier.value;
    switch (tile.actionKey) {
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanySettingsPage(
              language: _lang,
              profileLoader: widget.settingsProfileLoader,
              profileSaver: widget.settingsProfileSaver,
              onSaved: _refreshIdentity,
            ),
          ),
        );
        return;
      case 'payments':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanySubscriptionStatusPage(language: _lang),
          ),
        );
        return;
      case 'vehicles':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyFleetPage(language: _lang),
          ),
        );
        return;
      case 'customers':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyDriversAdminPage(language: _lang),
          ),
        );
        return;
      case 'booking_link':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyBookingLinkPage(language: _lang),
          ),
        );
        return;
      case 'planning':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyBookingsPage(
              language: _lang,
              pageLoader: widget.bookingsPageLoader,
              detailLoader: widget.bookingDetailLoader,
              driversLoader: widget.driversLoader,
              vehiclesLoader: widget.vehiclesLoader,
            ),
          ),
        );
        return;
      case 'ai_dispatch':
        if (widget.onOpenCustomers != null) {
          widget.onOpenCustomers!(context, identity);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyCustomersPage(
              language: _lang,
              issuerName: identity.companyName,
              sessionStore: createCompanyCustomerImportSessionStore(),
              onOpenBooking: widget.onOpenBooking ?? _openBookingFromQuote,
            ),
          ),
        );
        return;
      default:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyDashboardUnavailablePage(
              tile: tile,
              language: _lang,
            ),
          ),
        );
    }
  }

  void _openBookingFromQuote(String bookingId) {
    openCompanyBookingDetail(
      context,
      bookingId: bookingId,
      language: _lang,
      openedFrom: CompanyBookingOpenedFrom.quote,
      driversLoader: widget.driversLoader ?? fetchCompanyOpsDrivers,
      vehiclesLoader: widget.vehiclesLoader ?? fetchCompanyOpsVehicles,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: ValueListenableBuilder<CompanyOpsIdentity>(
        valueListenable: companyOpsIdentityNotifier,
        builder: (context, identity, _) {
          final session = companyOpsLocalSessionNotifier.value;
          if (session == null) {
            return _CompanyPicker(
              language: _lang,
              directory: _directory,
              error: _directoryError,
              onRetry: _loadDirectory,
              onPick: _activate,
            );
          }
          return Scaffold(
            key: kCompanyDashboardPageKey,
            body: SafeArea(
              child: DecoratedBox(
                decoration: companyOpsRootBoxDecoration(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final info = FluxidiResponsiveInfo.of(context);
                    final isDesktopWide = companyDashboardIsDesktopWide(
                      constraints.maxWidth,
                    );
                    final isTabletLandscape =
                        info.isTabletUp &&
                        !isDesktopWide &&
                        info.isLandscape &&
                        constraints.maxWidth >= 900;
                    final columns = companyDashboardGoldTileColumns(
                      screenClass: info.screenClass,
                      isTabletLandscape: isTabletLandscape,
                    );
                    final headerHeight = companyDashboardHeaderHeight(
                      isTabletLandscape: isTabletLandscape,
                      useTabletVisualMode: info.isTabletUp && !isDesktopWide,
                      isDesktopWide: isDesktopWide,
                    );
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _CompanyDashboardHeader(
                          height: headerHeight,
                          identity: identity,
                          loading: _loadingIdentity,
                          language: _lang,
                          onSwitch: _signOut,
                          onSignOut: _signOut,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          kCompanyDashboardTitle.of(_lang),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        _TileGrid(
                          columns: columns,
                          tileHeight: isDesktopWide
                              ? kCompanyDashboardDesktopGoldTileHeight
                              : 132 + kBrandSignatureGoldActionCardHeightBoost,
                          language: _lang,
                          onOpen: _openTile,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

const String kCompanyCustomersMissingScopeHint =
    'Bedrijfsprofiel ontbreekt of is niet geladen.';

class _CompanyPicker extends StatelessWidget {
  const _CompanyPicker({
    required this.language,
    required this.directory,
    required this.error,
    required this.onRetry,
    required this.onPick,
  });

  final AppLanguage language;
  final List<CompanyOpsDirectoryEntry> directory;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<CompanyOpsDirectoryEntry> onPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: kCompanyDashboardPickerKey,
      appBar: AppBar(title: Text(kCompanyDashboardPickCompany.of(language))),
      body: directory.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error ?? kCompanyDashboardPickCompany.of(language)),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Opnieuw'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in directory)
                  Card(
                    key: Key('company_dashboard_pick_${entry.companyId}'),
                    child: ListTile(
                      title: Text(
                        entry.companyName.isEmpty
                            ? entry.companyId
                            : entry.companyName,
                      ),
                      subtitle: Text(entry.companyId),
                      onTap: () => onPick(entry),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CompanyDashboardHeader extends StatelessWidget {
  const _CompanyDashboardHeader({
    required this.height,
    required this.identity,
    required this.loading,
    required this.language,
    required this.onSwitch,
    required this.onSignOut,
  });

  final double height;
  final CompanyOpsIdentity identity;
  final bool loading;
  final AppLanguage language;
  final VoidCallback onSwitch;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        return ValueListenableBuilder<BrandSignaturePalette>(
          valueListenable: brandSignaturePaletteNotifier,
          builder: (context, colors, __) {
        final palette = paletteForBusinessTheme(variant);
        final headerColor = variant == BusinessThemeVariant.brandSignatureGold
            ? colors.header
            : palette.surface;
        final borderColor = variant == BusinessThemeVariant.brandSignatureGold
            ? colors.border
            : palette.border;
        final name = identity.companyName.trim();
        return SizedBox(
          key: kCompanyDashboardHeaderKey,
          height: height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: BorderRadius.circular(
                kCompanyDashboardHeaderRadius,
              ),
              border: Border.all(color: borderColor.withOpacity(0.72)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  _HeaderMark(identity: identity, color: palette.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      loading && name.isEmpty
                          ? '…'
                          : name.isEmpty
                          ? identity.companyId
                          : name,
                      key: kCompanyDashboardNameKey,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: height <= kCompanyDashboardDesktopHeaderHeight
                            ? 18
                            : 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    key: kCompanyDashboardSwitchKey,
                    onPressed: onSwitch,
                    child: Text(kCompanyDashboardSwitchCompany.of(language)),
                  ),
                  TextButton(
                    key: kCompanyDashboardSignOutKey,
                    onPressed: onSignOut,
                    child: Text(kCompanyDashboardSignOut.of(language)),
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

class _HeaderMark extends StatelessWidget {
  const _HeaderMark({required this.identity, required this.color});

  final CompanyOpsIdentity identity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (identity.hasCompanyLogo) {
      return Image(
        key: kCompanyDashboardLogoKey,
        image: NetworkImage(identity.logo.ref),
        width: 56,
        height: 56,
        fit: BoxFit.contain,
        gaplessPlayback: false,
        errorBuilder: (_, __, ___) => _NameFallback(
          name: identity.companyName,
          color: color,
        ),
      );
    }
    return _NameFallback(name: identity.companyName, color: color);
  }
}

class _NameFallback extends StatelessWidget {
  const _NameFallback({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    return SizedBox(
      width: 56,
      height: 56,
      child: Center(
        child: Text(
          trimmed.isEmpty
              ? '—'
              : String.fromCharCode(trimmed.runes.first).toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({
    required this.columns,
    required this.tileHeight,
    required this.language,
    required this.onOpen,
  });

  final int columns;
  final double tileHeight;
  final AppLanguage language;
  final ValueChanged<CompanyDashboardTileSpec> onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForBusinessTheme(variant);
        return LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final cardWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            return Wrap(
              key: kCompanyDashboardTileGridKey,
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final tile in kCompanyDashboardTiles)
                  SizedBox(
                    width: cardWidth,
                    height: tileHeight,
                    child: variant == BusinessThemeVariant.brandSignatureGold
                        ? BrandSignatureGoldActionCard(
                            actionKey: tile.actionKey,
                            title: tile.title.of(language),
                            subtitle: tile.subtitle.of(language),
                            onTap: () => onOpen(tile),
                          )
                        : _SharedThemeActionCard(
                            actionKey: tile.actionKey,
                            title: tile.title.of(language),
                            subtitle: tile.subtitle.of(language),
                            palette: palette,
                            onTap: () => onOpen(tile),
                          ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SharedThemeActionCard extends StatelessWidget {
  const _SharedThemeActionCard({
    required this.actionKey,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final String actionKey;
  final String title;
  final String subtitle;
  final BusinessThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key('brand_signature_action_$actionKey'),
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border.withOpacity(0.85)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForAction(actionKey), color: palette.accent, size: 28),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconForAction(String actionKey) {
  switch (actionKey) {
    case 'settings':
      return Icons.settings_outlined;
    case 'payments':
      return Icons.credit_card_outlined;
    case 'vehicles':
      return Icons.directions_car_outlined;
    case 'chiron':
      return Icons.verified_outlined;
    case 'customers':
      return Icons.groups_outlined;
    case 'drivers':
      return Icons.badge_outlined;
    case 'demand_radar':
      return Icons.radar_outlined;
    case 'booking_link':
      return Icons.qr_code_2_outlined;
    case 'planning':
      return Icons.calendar_month_outlined;
    case 'ai_dispatch':
      return Icons.people_alt_outlined;
    default:
      return Icons.grid_view_outlined;
  }
}
