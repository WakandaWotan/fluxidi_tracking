import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_customer_request_history.dart';
import 'limousine_customer_status_page.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_quote_presentation.dart';

class LimousineCustomerRequestsSection extends StatefulWidget {
  const LimousineCustomerRequestsSection({
    super.key,
    this.history,
    this.gateway,
    this.quoteEnabled,
  });

  final LimousineCustomerRequestHistoryRepository? history;
  final LimousineCustomerQuoteGateway? gateway;
  final bool? quoteEnabled;

  @override
  State<LimousineCustomerRequestsSection> createState() =>
      _LimousineCustomerRequestsSectionState();
}

class _LimousineCustomerRequestsSectionState
    extends State<LimousineCustomerRequestsSection> {
  late final LimousineCustomerRequestHistoryRepository _history;
  late final LimousineCustomerQuoteGateway _gateway;
  List<LimousineCustomerRequestRecord> _items =
      const <LimousineCustomerRequestRecord>[];
  bool _loading = true;

  AppLanguage get _lang => appLanguageNotifier.value;

  bool get _gateOn => widget.quoteEnabled ?? kLimousineCustomerQuoteGateEnabled;

  @override
  void initState() {
    super.initState();
    _history = widget.history ?? LimousineCustomerRequestHistoryRepository();
    _gateway = widget.gateway ?? HttpLimousineCustomerQuoteGateway();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final items = await _history.list();
      final refreshed = <LimousineCustomerRequestRecord>[];
      for (final item in items) {
        if (!looksLikeLimousineStatusRef(item.statusRef)) {
          refreshed.add(item);
          continue;
        }
        try {
          final live = await _gateway.pollStatus(item.statusRef);
          final next = item.copyWith(
            state: live.state,
            from: live.fulfilment?.from ?? item.from,
            to: live.fulfilment?.to ?? item.to,
            scheduledPickupIso: live.scheduledPickupIso.isNotEmpty
                ? live.scheduledPickupIso
                : item.scheduledPickupIso,
            request: live,
            updatedAt: live.updatedAt,
          );
          await _history.upsert(next);
          refreshed.add(next);
        } catch (_) {
          refreshed.add(item);
        }
      }
      if (!mounted) return;
      setState(() {
        _items = refreshed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_gateOn && _items.isEmpty) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, _, __) {
        final palette = paletteForCustomerTheme(customerThemeNotifier.value);
        return Column(
          key: kLimousineCustomerRequestsSectionKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kLimousineCustomerRequestsTitle.of(_lang),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kLimousineCustomerRequestsHint.of(_lang),
              style: TextStyle(color: palette.textMuted, height: 1.35),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Text(
                kLimousineCustomerRequestsEmpty.of(_lang),
                style: TextStyle(color: palette.textMuted, height: 1.35),
              )
            else
              Column(
                key: kLimousineCustomerRequestsListKey,
                children: [
                  for (final item in _items)
                    _LimousineCustomerRequestCard(
                      record: item,
                      language: _lang,
                      palette: palette,
                      onOpen: () => _open(item),
                    ),
                ],
              ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }

  Future<void> _open(LimousineCustomerRequestRecord record) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LimousineCustomerRequestDetailPage(
          record: record,
          gateway: _gateway,
          history: _history,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }
}

class _LimousineCustomerRequestCard extends StatelessWidget {
  const _LimousineCustomerRequestCard({
    required this.record,
    required this.language,
    required this.palette,
    required this.onOpen,
  });

  final LimousineCustomerRequestRecord record;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final live = record.request;
    final vehicle = record.vehicleDisplayName.isNotEmpty
        ? record.vehicleDisplayName
        : (live == null ? '' : limousineQuoteVehicleDisplay(live, language));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  limousineCustomerStateLabel(
                    record.state,
                    language,
                    companyName: record.companyName,
                    request: live,
                  ),
                  style: TextStyle(
                    color: palette.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                if (record.companyName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    record.companyName,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
                if (vehicle.isNotEmpty)
                  Text(vehicle, style: TextStyle(color: palette.textMuted)),
                if (record.scheduledPickupIso.isNotEmpty)
                  Text(
                    limousineQuoteDisplayOrEmpty(
                      record.scheduledPickupIso,
                      language,
                    ),
                    style: TextStyle(color: palette.textMuted),
                  ),
                if (record.from.isNotEmpty || record.to.isNotEmpty)
                  Text(
                    [
                      record.from,
                      record.to,
                    ].where((part) => part.trim().isNotEmpty).join(' → '),
                    style: TextStyle(color: palette.textMuted),
                  ),
                const SizedBox(height: 4),
                Text(
                  record.quoteRequestId,
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LimousineCustomerRequestDetailPage extends StatefulWidget {
  const LimousineCustomerRequestDetailPage({
    super.key,
    required this.record,
    required this.gateway,
    required this.history,
  });

  final LimousineCustomerRequestRecord record;
  final LimousineCustomerQuoteGateway gateway;
  final LimousineCustomerRequestHistoryRepository history;

  @override
  State<LimousineCustomerRequestDetailPage> createState() =>
      _LimousineCustomerRequestDetailPageState();
}

class _LimousineCustomerRequestDetailPageState
    extends State<LimousineCustomerRequestDetailPage>
    with WidgetsBindingObserver {
  late final LimousineCustomerQuoteController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = LimousineCustomerQuoteController(
      gateway: widget.gateway,
      historyRepository: widget.history,
    )..restorePersistedRequest(widget.record);
    _controller.addListener(_onChanged);
    if (looksLikeLimousineStatusRef(widget.record.statusRef)) {
      _controller.refreshStatus();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resumePolling();
    } else {
      _controller.pausePolling();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = appLanguageNotifier.value;
    final palette = paletteForCustomerTheme(customerThemeNotifier.value);
    return Scaffold(
      key: kLimousineCustomerRequestDetailKey,
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(kLimousineCustomerStatusTitle.of(language)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LimousineCustomerStatusView(
            controller: _controller,
            language: language,
            palette: palette,
          ),
        ],
      ),
    );
  }
}
