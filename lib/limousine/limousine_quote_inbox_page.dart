import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_quote_detail_page.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_presentation.dart';
import 'limousine_quote_inbox_api.dart';
import 'limousine_quote_inbox_labels.dart';
import 'limousine_operational_handoff.dart';
import 'limousine_quote_inbox_presentation.dart';
import 'limousine_external_quote.dart';
import 'limousine_external_quote_labels.dart';
import 'limousine_external_quote_page.dart';
import 'limousine_quote_respond_form.dart';
import 'limousine_service_capability.dart';

class LimousineQuoteGateOffPanel extends StatelessWidget {
  const LimousineQuoteGateOffPanel({
    super.key,
    this.embedded = true,
    this.language,
    this.palette,
  });

  final bool embedded;
  final AppLanguage? language;
  final BusinessThemePalette? palette;

  @override
  Widget build(BuildContext context) {
    final lang = language ?? appLanguageNotifier.value;
    final colors =
        palette ?? paletteForBusinessTheme(businessThemeNotifier.value);
    return Padding(
      key: kLimousineQuoteInboxGateOffKey,
      padding: EdgeInsets.all(embedded ? 4 : 24),
      child: Align(
        alignment: embedded ? Alignment.topCenter : Alignment.center,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: embedded ? 12 : 16,
            vertical: embedded ? 10 : 16,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            kLimousineQuoteGateOff.of(lang),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              height: 1.4,
              fontSize: embedded ? 13.5 : 16,
              fontWeight: embedded ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class LimousineQuoteInboxNavEntry extends StatelessWidget {
  const LimousineQuoteInboxNavEntry({
    super.key,
    required this.entitled,
    this.onOpen,
    this.language = AppLanguage.en,
  });

  final bool? entitled;
  final VoidCallback? onOpen;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (!limousineQuoteInboxEntryVisible(entitled: entitled)) {
      return const SizedBox.shrink();
    }
    return Material(
      child: ListTile(
        key: kLimousineQuoteInboxEntryKey,
        leading: const Icon(Icons.request_quote_outlined),
        title: Text(kLimousineQuoteInboxEntryTitle.of(language)),
        subtitle: Text(kLimousineQuoteInboxEntrySubtitle.of(language)),
        onTap: onOpen,
      ),
    );
  }
}

class LimousineQuoteInboxPage extends StatefulWidget {
  const LimousineQuoteInboxPage({
    super.key,
    this.gateway,
    this.entitled = true,
    this.initialFilter = LimousineQuoteInboxFilter.all,
    this.embedded = false,
    this.onUnreadCount,
  });

  final LimousineQuoteInboxGateway? gateway;
  final bool entitled;
  final LimousineQuoteInboxFilter initialFilter;
  final bool embedded;
  final ValueChanged<int?>? onUnreadCount;

  @override
  State<LimousineQuoteInboxPage> createState() =>
      _LimousineQuoteInboxPageState();
}

class _LimousineQuoteInboxPageState extends State<LimousineQuoteInboxPage> {
  late final LimousineQuoteInboxController _controller;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String _query = '';
  bool _refreshing = false;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    _controller = LimousineQuoteInboxController(
      gateway: widget.gateway ?? HttpLimousineQuoteInboxGateway(),
    );
    _controller.filter = widget.initialFilter;
    _scroll.addListener(_onScroll);
    if (widget.entitled) {
      _controller.loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LimousineQuoteInboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entitled && !oldWidget.entitled) {
      _controller.loading = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    setState(() {});
    try {
      await _controller.refresh();
    } finally {
      _refreshing = false;
      if (mounted) {
        setState(() {});
        _emitUnreadCount();
      }
    }
  }

  void _emitUnreadCount() {
    widget.onUnreadCount?.call(
      _controller.items.isEmpty
          ? null
          : limousineQuoteInboxUnreadBadge(_controller.items),
    );
  }

  Future<void> _loadMore() async {
    if (_controller.loadingMore || !_controller.hasMore) return;
    await _controller.loadMore();
    if (mounted) {
      setState(() {});
      _emitUnreadCount();
    }
  }

  bool get _isGateOff {
    if (!widget.entitled) return true;
    return _controller.error?.kind == LimousineQuoteInboxErrorKind.gateOff;
  }

  List<LimousineQuoteRequest> get _visible {
    return limousineQuoteInboxSearch(
      _controller.visibleItems,
      _query,
      language: _lang,
    );
  }

  void _openDetail(LimousineQuoteRequest record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LimousineQuoteDetailPage(
          quoteRequestId: record.quoteRequestId,
          initial: record,
          gateway: _controller.gateway,
        ),
      ),
    );
  }

  Future<void> _openExternalQuote() async {
    final gateway = asLimousineExternalQuoteGateway(_controller.gateway);
    if (gateway == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LimousineExternalQuoteCreatePage(gateway: gateway),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openEditor(LimousineQuoteRequest record) async {
    await Navigator.of(context).push<LimousineCompanyQuoteDraft>(
      MaterialPageRoute(
        builder: (_) => LimousineQuoteEditorPage(
          record: record,
          onSubmit: (next) async {
            final live = await _controller.liveRecordForRespond(record);
            await _controller.respond(
              action: 'quote',
              record: live,
              quote: next.toWorkerQuote(),
            );
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _closeRequest(LimousineQuoteRequest record) async {
    final draft = await showLimousineDeclineDialog(
      context: context,
      language: _lang,
    );
    if (draft == null || !mounted) return;
    try {
      await _controller.respond(
        action: 'decline',
        record: record,
        decline: draft,
      );
    } on LimousineQuoteInboxException {
      // Friendly mapping stays on the existing detail/error path.
    }
    if (mounted) setState(() {});
  }

  Future<void> _runAction(
    LimousineQuoteInboxCardAction action,
    LimousineQuoteRequest record,
  ) async {
    switch (action) {
      case LimousineQuoteInboxCardAction.createQuote:
      case LimousineQuoteInboxCardAction.editQuote:
        await _openEditor(record);
        return;
      case LimousineQuoteInboxCardAction.close:
        await _closeRequest(record);
        return;
      case LimousineQuoteInboxCardAction.view:
      case LimousineQuoteInboxCardAction.viewQuote:
      case LimousineQuoteInboxCardAction.openAcceptedHandoff:
      case LimousineQuoteInboxCardAction.viewBooking:
        _openDetail(record);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<BusinessThemeVariant>(
          valueListenable: businessThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForBusinessTheme(variant);
            final tokens = LimousineUxTokens.fromBusiness(palette);
            final shortest = MediaQuery.sizeOf(context).shortestSide;
            final tablet = limousineQuoteInboxIsTablet(shortest);
            final body = LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: limousineQuoteInboxContentWidth(
                        constraints.maxWidth,
                      ),
                      maxHeight: constraints.maxHeight,
                    ),
                    child: KeyedSubtree(
                      key: tablet
                          ? kLimousineQuoteInboxTabletLayoutKey
                          : kLimousineQuoteInboxPhoneLayoutKey,
                      child: Column(
                        children: [
                          if (widget.embedded && widget.entitled && !_isGateOff)
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                key: kLimousineQuoteInboxRefreshKey,
                                tooltip: _t(kLimousineQuoteInboxRefresh),
                                onPressed: _refreshing ? null : _refresh,
                                icon:
                                    _refreshing && _controller.items.isNotEmpty
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: palette.accent,
                                        ),
                                      )
                                    : Icon(
                                        Icons.refresh,
                                        color: palette.textPrimary,
                                      ),
                              ),
                            ),
                          Expanded(child: _body(palette, tablet: tablet)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
            return Theme(
              data: limousineUxThemeData(tokens),
              child: widget.embedded
                  ? KeyedSubtree(key: kLimousineQuoteInboxPageKey, child: body)
                  : Scaffold(
                      key: kLimousineQuoteInboxPageKey,
                      backgroundColor: palette.background,
                      appBar: AppBar(
                        backgroundColor: palette.surface,
                        foregroundColor: palette.textPrimary,
                        title: Text(_t(kLimousineQuoteInboxTitle)),
                        actions: [
                          if (widget.entitled)
                            IconButton(
                              key: kLimousineQuoteInboxRefreshKey,
                              tooltip: _t(kLimousineQuoteInboxRefresh),
                              onPressed: _refreshing ? null : _refresh,
                              icon: _refreshing && _controller.items.isNotEmpty
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: palette.accent,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                            ),
                        ],
                      ),
                      body: SafeArea(child: body),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _body(BusinessThemePalette palette, {required bool tablet}) {
    if (!widget.entitled) {
      return _gate(palette);
    }
    final error = _controller.error;
    final gateOff = error?.kind == LimousineQuoteInboxErrorKind.gateOff;
    if (gateOff && _controller.items.isEmpty) {
      return _gate(palette);
    }
    return RefreshIndicator(
      color: palette.accent,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        cacheExtent: 4000,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(palette, tablet: tablet),
                  if (_controller.loading && _controller.items.isEmpty)
                    _skeleton(palette)
                  else if (error != null && _controller.items.isEmpty)
                    _error(palette, error)
                  else ...[
                    const SizedBox(height: 12),
                    _kpis(palette, tablet: tablet),
                    const SizedBox(height: 12),
                    _searchAndFilters(palette),
                    const SizedBox(height: 12),
                    if (_visible.isEmpty)
                      _empty(palette)
                    else
                      Column(
                        key: kLimousineQuoteInboxListKey,
                        children: [
                          for (final item in _visible)
                            _card(palette, item, tablet: tablet),
                          if (_controller.loadingMore)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  _t(kLimousineQuoteInboxLoadingMore),
                                  style: TextStyle(color: palette.textMuted),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BusinessThemePalette palette, {required bool tablet}) {
    return Semantics(
      header: true,
      child: Container(
        key: kLimousineQuoteInboxHeroKey,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    // Keep Testomgeving until Worker listingMode and
                    // LIMOUSINE_TEST_COMPANY_ALLOWLIST leave test_preview.
                    // Do not derive this chip from dart-defines.
                    child: Chip(
                      key: kLimousineQuoteInboxTestBadgeKey,
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        Icons.science_outlined,
                        color: palette.accent,
                        size: 16,
                      ),
                      label: Text(_t(kLimousineQuoteInboxTestBadge)),
                      side: BorderSide(color: palette.accent),
                      backgroundColor: palette.surfaceAlt,
                      labelStyle: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(kLimousineQuoteInboxHeroTitle),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(kLimousineQuoteInboxHeroBody),
                    style: TextStyle(
                      color: palette.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (_scroll.hasClients) {
                        _scroll.animateTo(
                          180,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    icon: Icon(
                      Icons.description_outlined,
                      color: palette.accent,
                    ),
                    label: Text(_t(kLimousineQuoteInboxManualQuotes)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.accent),
                      minimumSize: const Size(48, 44),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: kLimousineExternalQuoteCreateActionKey,
                    onPressed: _openExternalQuote,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(_t(kLimousineExternalQuoteCreateAction)),
                  ),
                ],
              ),
            ),
            if (tablet) ...[
              const SizedBox(width: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 168,
                  height: 110,
                  child: Image.asset(
                    kLimousineMarketplaceHeroAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: palette.surfaceAlt,
                      child: Icon(
                        Icons.directions_car_filled,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpis(BusinessThemePalette palette, {required bool tablet}) {
    final kpis = limousineQuoteInboxKpis(_controller.items);
    final codes = LimousineQuoteInboxKpiCode.values;
    return Semantics(
      label: _t(kLimousineQuoteInboxHeroTitle),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = tablet
              ? ((constraints.maxWidth - 30) / 4).clamp(140.0, 240.0)
              : ((constraints.maxWidth - 10) / 2).clamp(140.0, 280.0);
          return Wrap(
            key: kLimousineQuoteInboxKpiRowKey,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final code in codes)
                SizedBox(
                  width: width,
                  child: _kpiCard(palette, code, kpis.of(code), tablet: tablet),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _kpiCard(
    BusinessThemePalette palette,
    LimousineQuoteInboxKpiCode code,
    int value, {
    required bool tablet,
  }) {
    final label = _t(limousineQuoteInboxKpiLabel(code));
    return Semantics(
      label: '$label $value',
      child: Container(
        key: limousineQuoteInboxKpiKey(code.name),
        constraints: BoxConstraints(minHeight: tablet ? 88 : 68),
        padding: EdgeInsets.all(tablet ? 14 : 10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_kpiIcon(code), color: palette.accent, size: tablet ? 20 : 18),
            SizedBox(height: tablet ? 8 : 6),
            Text(
              '$value',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: tablet ? 26 : 22,
              ),
            ),
            Text(
              label,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: tablet ? 14 : 13,
                height: 1.2,
              ),
            ),
            if (tablet)
              Text(
                _t(limousineQuoteInboxKpiHint(code)),
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  IconData _kpiIcon(LimousineQuoteInboxKpiCode code) {
    switch (code) {
      case LimousineQuoteInboxKpiCode.neu:
        return Icons.note_add_outlined;
      case LimousineQuoteInboxKpiCode.toAnswer:
        return Icons.schedule_outlined;
      case LimousineQuoteInboxKpiCode.waitingCustomer:
        return Icons.send_outlined;
      case LimousineQuoteInboxKpiCode.accepted:
        return Icons.check_circle_outline;
    }
  }

  Widget _searchAndFilters(BusinessThemePalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: kLimousineQuoteInboxSearchKey,
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: _t(kLimousineQuoteInboxSearchHint),
            hintStyle: TextStyle(color: palette.textMuted),
            prefixIcon: Icon(Icons.search, color: palette.textMuted),
            filled: true,
            fillColor: palette.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.accent),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          key: kLimousineQuoteInboxFilterBarKey,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in kLimousineQuoteInboxPrimaryFilters) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: ValueKey<String>(
                      'limousine_inbox_filter_${filter.name}',
                    ),
                    selected: _controller.filter == filter,
                    label: Text(
                      kLimousineQuoteInboxFilterLabels[filter]!.of(_lang),
                    ),
                    selectedColor: palette.accent.withOpacity(0.16),
                    backgroundColor: palette.surfaceAlt,
                    labelStyle: TextStyle(
                      color: _controller.filter == filter
                          ? palette.accent
                          : palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: _controller.filter == filter
                          ? palette.accent
                          : palette.border,
                    ),
                    onSelected: (_) => _selectFilter(filter),
                  ),
                ),
              ],
              PopupMenuButton<LimousineQuoteInboxFilter>(
                tooltip: _t(kLimousineQuoteInboxMoreFilters),
                color: palette.surface,
                onSelected: _selectFilter,
                itemBuilder: (context) => [
                  for (final filter in kLimousineQuoteInboxOverflowFilters)
                    PopupMenuItem(
                      value: filter,
                      child: Text(
                        kLimousineQuoteInboxFilterLabels[filter]!.of(_lang),
                        style: TextStyle(color: palette.textPrimary),
                      ),
                    ),
                ],
                child: Chip(
                  label: Text(_t(kLimousineQuoteInboxMoreFilters)),
                  backgroundColor: palette.surfaceAlt,
                  labelStyle: TextStyle(color: palette.textMuted),
                  side: BorderSide(color: palette.border),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _selectFilter(LimousineQuoteInboxFilter filter) async {
    _controller.filter = filter;
    setState(() {});
    await _refresh();
  }

  Widget _card(
    BusinessThemePalette palette,
    LimousineQuoteRequest item, {
    required bool tablet,
  }) {
    final actions = limousineQuoteInboxCardActions(item);
    final status = limousineQuoteInboxStatusLabel(item, _lang);
    final amount = limousineQuoteInboxAuthoritativeAmount(item, _lang);
    final pickup = limousineQuoteInboxPickupText(item);
    final destination = limousineQuoteInboxDestinationText(item);
    final cardReference = limousineQuoteInboxCardReference(item);
    final extras = item.fulfilment?.customerNote.trim() ?? '';
    final classLabel = item.serviceClassId.isEmpty
        ? ''
        : limousineServiceClassLabel(item.serviceClassId, _lang);
    final title = limousineQuoteInboxCardHeading(item, _lang);
    final vehicleLine =
        item.publicVehicleName.isNotEmpty && item.publicVehicleName != title
        ? item.publicVehicleName
        : '';
    final dateLine = item.scheduledPickupIso.isEmpty
        ? ''
        : limousineQuoteDisplayOrEmpty(item.scheduledPickupIso, _lang);
    final showDuration = limousineQuoteInboxShowsRequestedDuration(
      item.fulfilment?.requestedDurationMinutes,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: tablet ? 12 : 10),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey<String>('limousine_inbox_row_${item.quoteRequestId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(item),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.all(tablet ? 16 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _statusIcon(item),
                      color: _statusColor(palette, item),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Semantics(
                        label: status,
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _statusColor(palette, item),
                            fontWeight: FontWeight.w800,
                            fontSize: tablet ? 12.5 : 12,
                          ),
                        ),
                      ),
                    ),
                    if (limousineQuoteIsExternal(item))
                      LimousineOwnCustomerOriginBadge(compact: !tablet),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: tablet ? 17 : 16,
                    ),
                  ),
                ),
                if (item.quote?.expiresAt.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_t(kLimousineQuoteInboxValidUntil)} ${formatLimousineUserDate(item.quote!.expiresAt, _lang)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                if (item.publicVehiclePhotoUrl.isNotEmpty ||
                    vehicleLine.isNotEmpty ||
                    dateLine.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.publicVehiclePhotoUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item.publicVehiclePhotoUrl,
                                width: tablet ? 72 : 56,
                                height: tablet ? 52 : 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (vehicleLine.isNotEmpty)
                                Text(
                                  vehicleLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              if (dateLine.isNotEmpty)
                                Text(
                                  dateLine,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (cardReference.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      cardReference,
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                  ),
                if (pickup.isNotEmpty || destination.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _structuredRoute(
                      palette,
                      item.quoteRequestId,
                      pickup: pickup,
                      destination: destination,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (item.pax != null)
                      _metaChip(
                        palette,
                        '${item.pax} ${_t(kLimousineQuoteInboxPassengersMeta)}',
                      ),
                    if (item.bags != null)
                      _metaChip(
                        palette,
                        '${item.bags} ${_t(kLimousineQuoteInboxLuggageMeta)}',
                      ),
                    if (classLabel.isNotEmpty) _metaChip(palette, classLabel),
                    if (item.occasion.isNotEmpty)
                      _metaChip(palette, item.occasion),
                    if (item.pricingMode.isNotEmpty)
                      _metaChip(
                        palette,
                        limousinePricingModeLabel(item.pricingMode, _lang),
                      ),
                    if (showDuration)
                      _metaChip(
                        palette,
                        '${item.fulfilment!.requestedDurationMinutes}m',
                      ),
                  ],
                ),
                if (extras.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      extras,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ),
                if (limousineSnapshotFromPriceCents(item.pricingSnapshot) !=
                    null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${kLimousineOperationalFromPriceAudit.of(_lang)} ${limousineMoneyCents(limousineSnapshotFromPriceCents(item.pricingSnapshot))}',
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                  ),
                if (amount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: tablet
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceAlt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: palette.border),
                            ),
                            child: Text(
                              amount,
                              key: limousineQuoteInboxCardAmountKey(
                                item.quoteRequestId,
                              ),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Text(
                            amount,
                            key: limousineQuoteInboxCardAmountKey(
                              item.quoteRequestId,
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                  ),
                if (LimousineQuoteStateId.normalize(item.state) ==
                    LimousineQuoteStateId.accepted)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: palette.success,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _t(kLimousineQuoteInboxAcceptedBanner),
                            style: TextStyle(
                              color: palette.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: tablet ? WrapAlignment.end : WrapAlignment.start,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      _actionButton(palette, item, actions[i], primary: i == 0),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _structuredRoute(
    BusinessThemePalette palette,
    String quoteRequestId, {
    required String pickup,
    required String destination,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pickup.isNotEmpty)
          Text(
            pickup,
            key: limousineQuoteInboxCardPickupKey(quoteRequestId),
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (pickup.isNotEmpty && destination.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Icon(
              Icons.arrow_downward,
              size: 14,
              color: palette.textMuted,
            ),
          ),
        if (destination.isNotEmpty)
          Text(
            destination,
            key: limousineQuoteInboxCardDestinationKey(quoteRequestId),
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _metaChip(BusinessThemePalette palette, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _actionButton(
    BusinessThemePalette palette,
    LimousineQuoteRequest item,
    LimousineQuoteInboxCardAction action, {
    required bool primary,
  }) {
    final label = _t(limousineQuoteInboxActionLabel(action));
    final key = limousineQuoteInboxActionKey(item.quoteRequestId, action.name);
    if (primary) {
      return FilledButton(
        key: key,
        onPressed: () => _runAction(action, item),
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.textOnAccent,
          minimumSize: const Size(48, 44),
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      key: key,
      onPressed: () => _runAction(action, item),
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        minimumSize: const Size(48, 44),
      ),
      child: Text(label),
    );
  }

  Color _statusColor(BusinessThemePalette palette, LimousineQuoteRequest item) {
    final state = LimousineQuoteStateId.normalize(item.state);
    if (state == LimousineQuoteStateId.accepted ||
        state == LimousineQuoteStateId.bookingCreated) {
      return palette.success;
    }
    if (LimousineQuoteStateId.closedGroup.contains(state)) {
      return palette.danger;
    }
    if (LimousineQuoteStateId.waitingForCustomer.contains(state)) {
      return palette.textSecondary;
    }
    return palette.accent;
  }

  IconData _statusIcon(LimousineQuoteRequest item) {
    final state = LimousineQuoteStateId.normalize(item.state);
    if (state == LimousineQuoteStateId.accepted) return Icons.check_circle;
    if (LimousineQuoteStateId.waitingForCustomer.contains(state)) {
      return Icons.send;
    }
    if (state == LimousineQuoteStateId.viewedByCompany) {
      return Icons.schedule;
    }
    return Icons.circle;
  }

  Widget _skeleton(BusinessThemePalette palette) {
    return Padding(
      key: kLimousineQuoteInboxLoadingKey,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: 88,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.border),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(BusinessThemePalette palette) {
    final filtered =
        _controller.filter != LimousineQuoteInboxFilter.all ||
        _query.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
      child: Column(
        children: [
          Text(
            key: kLimousineQuoteInboxEmptyKey,
            filtered
                ? _t(kLimousineQuoteInboxEmptyFiltered)
                : _t(kLimousineQuoteInboxEmpty),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          if (!filtered) ...[
            const SizedBox(height: 8),
            Text(
              _t(kLimousineQuoteInboxEmptyHint),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gate(BusinessThemePalette palette) {
    return LimousineQuoteGateOffPanel(
      embedded: widget.embedded,
      language: _lang,
      palette: palette,
    );
  }

  Widget _error(
    BusinessThemePalette palette,
    LimousineQuoteInboxException error,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
      child: Column(
        children: [
          Text(
            key: kLimousineQuoteInboxErrorKey,
            limousineQuoteErrorLabel(error, _lang),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: kLimousineQuoteInboxRetryKey,
              onPressed: _refresh,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.textOnAccent,
              ),
              child: Text(_t(kLimousineQuoteInboxRetry)),
            ),
          ),
        ],
      ),
    );
  }
}
