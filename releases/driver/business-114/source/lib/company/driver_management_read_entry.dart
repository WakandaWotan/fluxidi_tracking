import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'driver_management_host_entry.dart';

// The entry remains discoverable; only a validated company session can open it.
const driverManagementReadVerified = bool.fromEnvironment(
  'DRIVER_MANAGEMENT_READ_VERIFIED',
  defaultValue: false,
);

enum DriverManagementAccess {
  ready,
  signIn,
  forbidden,
  sourceUnavailable,
  hostUnavailable,
  invalidContract,
  sessionChanged,
}

Future<DriverManagementAccess> driverManagementReadAccess({
  required DriverManagementHostEntry entry,
  required String companyId,
  required Future<({int status, String body})> Function(Uri uri) get,
  required Future<bool> Function() sessionUnchanged,
}) async {
  try {
    final response = await get(
      entry.origin.resolve('/driver-management/readiness'),
    );
    if (response.status == 401) return DriverManagementAccess.signIn;
    if (response.status == 403) return DriverManagementAccess.forbidden;
    if (response.status == 409) return DriverManagementAccess.sourceUnavailable;
    if (response.status != 200) return DriverManagementAccess.hostUnavailable;
    final data = jsonDecode(response.body);
    if (data is! Map ||
        data['ok'] != true ||
        data['ready'] != true ||
        data['read_only'] != true ||
        data['contract'] != 'fluxidi-driver-management-read-v1')
      return DriverManagementAccess.invalidContract;
    final operator = data['operator'];
    final capabilities = data['capabilities'];
    if (operator is! Map ||
        operator['company_id'] != companyId ||
        operator['tenant_id'] is! String ||
        (operator['tenant_id'] as String).trim().isEmpty ||
        capabilities is! Map ||
        capabilities['drivers_read'] != true ||
        capabilities['export_csv'] != true ||
        [
          'partner_write',
          'settlement_write',
          'import_write',
          'bulk_assign',
        ].any((key) => capabilities[key] != false))
      return DriverManagementAccess.invalidContract;
    return await sessionUnchanged()
        ? DriverManagementAccess.ready
        : DriverManagementAccess.sessionChanged;
  } catch (_) {
    return DriverManagementAccess.hostUnavailable;
  }
}

Future<bool> driverManagementReadReady({
  required DriverManagementHostEntry entry,
  required String companyId,
  required Future<({int status, String body})> Function(Uri uri) get,
  required Future<bool> Function() sessionUnchanged,
}) async =>
    await driverManagementReadAccess(
      entry: entry,
      companyId: companyId,
      get: get,
      sessionUnchanged: sessionUnchanged,
    ) ==
    DriverManagementAccess.ready;

class DriverManagementReadEntryButton extends StatefulWidget {
  const DriverManagementReadEntryButton({
    super.key,
    required this.session,
    required this.probe,
    required this.open,
    required this.tooltip,
    this.color,
    this.label,
    this.enabled = driverManagementReadVerified,
    this.accessProbe,
    this.recoverSession,
  });

  final ValueListenable<Object?> session;
  final Future<bool> Function() probe;
  final Future<void> Function() open;
  final String tooltip;
  final Color? color;
  final String? label;
  final bool enabled;
  final Future<DriverManagementAccess> Function()? accessProbe;
  final Future<void> Function()? recoverSession;

  @override
  State<DriverManagementReadEntryButton> createState() => _ReadEntryState();
}

class _ReadEntryState extends State<DriverManagementReadEntryButton>
    with WidgetsBindingObserver {
  bool ready = false;
  bool opening = false;
  bool checking = false;
  DriverManagementAccess access = DriverManagementAccess.signIn;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(refresh);
    refresh();
  }

  @override
  void didUpdateWidget(DriverManagementReadEntryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(refresh);
      widget.session.addListener(refresh);
    }
    if (oldWidget.session != widget.session ||
        oldWidget.enabled != widget.enabled)
      refresh();
  }

  Future<void> refresh() async {
    final current = ++generation;
    if (mounted)
      setState(() {
        ready = false;
        checking = widget.enabled && widget.session.value != null;
        access = DriverManagementAccess.signIn;
      });
    if (!checking) return;
    DriverManagementAccess result;
    try {
      result = widget.accessProbe != null
          ? await widget.accessProbe!()
          : await widget.probe()
          ? DriverManagementAccess.ready
          : DriverManagementAccess.hostUnavailable;
    } catch (_) {
      result = DriverManagementAccess.hostUnavailable;
    }
    if (mounted && generation == current)
      setState(() {
        access = result;
        ready = result == DriverManagementAccess.ready;
        checking = false;
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      generation++;
      if (mounted)
        setState(() {
          ready = false;
          checking = false;
          access = DriverManagementAccess.sessionChanged;
        });
    }
  }

  @override
  void dispose() {
    generation++;
    widget.session.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final onPressed = opening || checking || !ready
        ? null
        : () async {
            setState(() => opening = true);
            try {
              await widget.open();
            } finally {
              if (mounted) setState(() => opening = false);
            }
          };
    if (widget.label != null || !ready) {
      final language = Localizations.localeOf(context).languageCode;
      final nl = language == 'nl';
      final message = checking
          ? (nl ? 'Bedrijfstoegang controleren…' : 'Checking company access…')
          : switch (access) {
              DriverManagementAccess.ready =>
                nl
                    ? 'Zoeken, filters, details en CSV-export'
                    : 'Search, filters, details and CSV export',
              DriverManagementAccess.signIn =>
                nl
                    ? 'Meld je opnieuw aan met je bedrijfslogin.'
                    : 'Sign in again with your company login.',
              DriverManagementAccess.forbidden =>
                nl
                    ? 'Je bedrijfssessie heeft geen chauffeurleesrecht.'
                    : 'Your company session has no driver read permission.',
              DriverManagementAccess.sourceUnavailable =>
                nl
                    ? 'De host kan je bedrijfsgegevens nog niet veilig laden (409).'
                    : 'The host cannot safely load your company data yet (409).',
              DriverManagementAccess.invalidContract =>
                nl
                    ? 'De host gaf geen geldige, geïsoleerde leesomgeving terug.'
                    : 'The host did not return a valid isolated read environment.',
              DriverManagementAccess.sessionChanged =>
                nl
                    ? 'Je bedrijfssessie is gewijzigd. Controleer opnieuw.'
                    : 'Your company session changed. Check again.',
              DriverManagementAccess.hostUnavailable =>
                nl
                    ? 'De beheerhost is niet bereikbaar. Probeer opnieuw.'
                    : 'The management host is unavailable. Try again.',
            };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label ?? widget.tooltip,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(message, key: const ValueKey('driver-management-access-status')),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('driver-management-read-entry'),
                style: TextButton.styleFrom(foregroundColor: widget.color),
                onPressed: onPressed,
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  nl ? 'Open chauffeurbeheer' : 'Open driver management',
                ),
              ),
              if (!ready)
                TextButton.icon(
                  key: const ValueKey('driver-management-access-retry'),
                  onPressed: checking || opening
                      ? null
                      : () async {
                          if (access == DriverManagementAccess.signIn &&
                              widget.recoverSession != null)
                            await widget.recoverSession!();
                          if (mounted) await refresh();
                        },
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    access == DriverManagementAccess.signIn &&
                            widget.recoverSession != null
                        ? (nl ? 'Bedrijfslogin' : 'Company login')
                        : (nl ? 'Opnieuw controleren' : 'Check again'),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    return IconButton(
      key: const ValueKey('driver-management-read-entry'),
      tooltip: widget.tooltip,
      color: widget.color,
      icon: const Icon(Icons.open_in_new),
      onPressed: onPressed,
    );
  }
}
