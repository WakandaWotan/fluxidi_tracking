import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import 'limousine_quote_detail_page.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_api.dart';
import 'limousine_quote_inbox_labels.dart';

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
  });

  final LimousineQuoteInboxGateway? gateway;
  final bool entitled;
  final LimousineQuoteInboxFilter initialFilter;

  @override
  State<LimousineQuoteInboxPage> createState() =>
      _LimousineQuoteInboxPageState();
}

class _LimousineQuoteInboxPageState extends State<LimousineQuoteInboxPage> {
  late final LimousineQuoteInboxController _controller;
  final _scroll = ScrollController();
  String? _selectedId;

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
      _refresh();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
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
    await _controller.refresh();
    if (!mounted) return;
    setState(() {
      if (_selectedId != null &&
          _controller.items.every(
            (item) => item.quoteRequestId != _selectedId,
          )) {
        _selectedId = _controller.items.isEmpty
            ? null
            : _controller.items.first.quoteRequestId;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_controller.loadingMore || !_controller.hasMore) return;
    await _controller.loadMore();
    if (mounted) setState(() {});
  }

  void _openDetail(LimousineQuoteRequest record, {required bool tablet}) {
    if (tablet) {
      setState(() => _selectedId = record.quoteRequestId);
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<BusinessThemeVariant>(
          valueListenable: businessThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForBusinessTheme(variant);
            final shortest = MediaQuery.sizeOf(context).shortestSide;
            final tablet = limousineQuoteInboxIsTablet(shortest);
            return Scaffold(
              key: kLimousineQuoteInboxPageKey,
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.background,
                foregroundColor: palette.textPrimary,
                title: Text(_t(kLimousineQuoteInboxTitle)),
              ),
              body: !widget.entitled
                  ? _status(palette, _t(kLimousineQuoteGateOff))
                  : _body(palette, tablet: tablet),
            );
          },
        );
      },
    );
  }

  Widget _body(BusinessThemePalette palette, {required bool tablet}) {
    return Column(
      key: tablet
          ? kLimousineQuoteInboxTabletLayoutKey
          : kLimousineQuoteInboxPhoneLayoutKey,
      children: [
        _filters(palette),
        Expanded(
          child: tablet
              ? Row(
                  children: [
                    Expanded(flex: 5, child: _listPane(palette, tablet: true)),
                    VerticalDivider(width: 1, color: palette.border),
                    Expanded(flex: 7, child: _detailPane(palette)),
                  ],
                )
              : _listPane(palette, tablet: false),
        ),
      ],
    );
  }

  Widget _filters(BusinessThemePalette palette) {
    return SingleChildScrollView(
      key: kLimousineQuoteInboxFilterBarKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          for (final filter in LimousineQuoteInboxFilter.values) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                key: ValueKey<String>('limousine_inbox_filter_${filter.name}'),
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
                onSelected: (_) async {
                  _controller.filter = filter;
                  setState(() {});
                  await _refresh();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _listPane(BusinessThemePalette palette, {required bool tablet}) {
    if (_controller.loading && _controller.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(key: kLimousineQuoteInboxLoadingKey),
      );
    }
    final error = _controller.error;
    if (error != null && _controller.items.isEmpty) {
      return _status(
        palette,
        limousineQuoteErrorLabel(error, _lang),
        retry: true,
      );
    }
    final visible = _controller.visibleItems;
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            _status(
              palette,
              _controller.filter == LimousineQuoteInboxFilter.all
                  ? _t(kLimousineQuoteInboxEmpty)
                  : _t(kLimousineQuoteInboxEmptyFiltered),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        key: kLimousineQuoteInboxListKey,
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: visible.length + (_controller.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visible.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  _t(kLimousineQuoteInboxLoadingMore),
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            );
          }
          final item = visible[index];
          return _row(
            palette,
            item,
            selected: tablet && item.quoteRequestId == _selectedId,
          );
        },
      ),
    );
  }

  Widget _row(
    BusinessThemePalette palette,
    LimousineQuoteRequest item, {
    required bool selected,
  }) {
    final quote = item.quote;
    final fulfilment = item.fulfilment;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? palette.surfaceAlt : palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey<String>('limousine_inbox_row_${item.quoteRequestId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(
            item,
            tablet: limousineQuoteInboxIsTablet(
              MediaQuery.sizeOf(context).shortestSide,
            ),
          ),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? palette.accent : palette.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.offerId.isNotEmpty
                            ? item.offerId
                            : limousineQuoteStateLabel(item.state, _lang),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _stateChip(palette, item),
                  ],
                ),
                if (item.journeyType.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    kLimousineJourneyTypeLabels[item.journeyType]?.of(_lang) ??
                        item.journeyType,
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ],
                if (item.scheduledPickupIso.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.scheduledPickupIso,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
                if (fulfilment != null && fulfilment.hasJourney) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (fulfilment.from.isNotEmpty) fulfilment.from,
                      if (fulfilment.to.isNotEmpty) fulfilment.to,
                    ].join(' → '),
                    style: TextStyle(color: palette.textSecondary, height: 1.3),
                  ),
                ],
                if (item.serviceClassId.isNotEmpty || item.vehicleId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (item.serviceClassId.isNotEmpty) item.serviceClassId,
                        if (item.vehicleId.isNotEmpty) item.vehicleId,
                      ].join(' · '),
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                  ),
                if (quote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formatLimousineMoney(
                        quote.totalInclVatCents,
                        quote.currency,
                      ),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                if (item.updatedAt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_t(kLimousineQuoteUpdated)} ${item.updatedAt}',
                      style: TextStyle(color: palette.textMuted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateChip(BusinessThemePalette palette, LimousineQuoteRequest item) {
    final label = item.isUnknownState
        ? _t(kLimousineQuoteUnknownState)
        : limousineQuoteStateLabel(item.state, _lang);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: item.isUnread
            ? palette.accent.withOpacity(0.16)
            : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        item.isUnread ? _t(kLimousineQuoteUnread) : label,
        style: TextStyle(
          color: item.isUnread ? palette.accent : palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detailPane(BusinessThemePalette palette) {
    final id = _selectedId;
    if (id == null) {
      return _status(palette, _t(kLimousineQuoteInboxEmpty));
    }
    final initial = _controller.items
        .where((item) => item.quoteRequestId == id)
        .cast<LimousineQuoteRequest?>()
        .firstWhere((item) => item != null, orElse: () => null);
    return LimousineQuoteDetailPage(
      quoteRequestId: id,
      initial: initial,
      gateway: _controller.gateway,
      embedded: true,
    );
  }

  Widget _status(
    BusinessThemePalette palette,
    String text, {
    bool retry = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              key:
                  text == _t(kLimousineQuoteInboxEmpty) ||
                      text == _t(kLimousineQuoteInboxEmptyFiltered)
                  ? kLimousineQuoteInboxEmptyKey
                  : null,
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            ),
            if (retry) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: kLimousineQuoteInboxRetryKey,
                  onPressed: _refresh,
                  child: Text(_t(kLimousineQuoteInboxRetry)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
