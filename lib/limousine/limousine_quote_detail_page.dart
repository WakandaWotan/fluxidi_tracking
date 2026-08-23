import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_api.dart';
import 'limousine_quote_inbox_labels.dart';
import 'limousine_quote_presentation.dart';
import 'limousine_quote_respond_form.dart';
import 'limousine_quotation_pdf_action.dart';

class LimousineQuoteDetailPage extends StatefulWidget {
  const LimousineQuoteDetailPage({
    super.key,
    required this.quoteRequestId,
    this.initial,
    this.gateway,
    this.embedded = false,
  });

  final String quoteRequestId;
  final LimousineQuoteRequest? initial;
  final LimousineQuoteInboxGateway? gateway;
  final bool embedded;

  @override
  State<LimousineQuoteDetailPage> createState() =>
      _LimousineQuoteDetailPageState();
}

class _LimousineQuoteDetailPageState extends State<LimousineQuoteDetailPage> {
  late final LimousineQuoteInboxGateway _gateway;
  late final LimousineQuoteInboxController _controller;
  bool _loading = true;
  String? _banner;
  int _generation = 0;
  bool _viewedOnce = false;
  bool _viewSettled = false;
  bool _quoteSent = false;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? HttpLimousineQuoteInboxGateway();
    _controller = LimousineQuoteInboxController(gateway: _gateway);
    _controller.detail = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = widget.initial == null;
    });
    try {
      final record = await _gateway.detail(widget.quoteRequestId);
      if (!mounted || gen != _generation) return;
      setState(() {
        _controller.detail = record;
        _loading = false;
      });
      await _ensureViewed(record);
    } on LimousineQuoteInboxException catch (error) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _controller.error = error;
        _loading = false;
      });
    }
  }

  Future<void> _ensureViewed(LimousineQuoteRequest record) async {
    if (_viewedOnce) {
      if (!_viewSettled && mounted) setState(() => _viewSettled = true);
      return;
    }
    _viewedOnce = true;
    final gen = _generation;
    try {
      await _controller.respond(action: 'viewed', record: record);
    } on LimousineQuoteInboxException {
      try {
        final fresh = await _gateway.detail(widget.quoteRequestId);
        if (mounted && gen == _generation) {
          _controller.detail = fresh;
        }
      } catch (_) {}
    } catch (_) {}
    if (!mounted || gen != _generation) return;
    setState(() => _viewSettled = true);
  }

  Future<void> _markViewed(LimousineQuoteRequest record) async {
    final gen = _generation;
    try {
      await _controller.respond(action: 'viewed', record: record);
      if (!mounted || gen != _generation) return;
      setState(() {});
    } on LimousineQuoteInboxException catch (error) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _banner = error.kind == LimousineQuoteInboxErrorKind.staleRevision
            ? _t(kLimousineQuoteStaleRevision)
            : limousineQuoteErrorLabel(error, _lang);
      });
    }
  }

  Future<void> _openQuoteEditor(LimousineQuoteRequest record) async {
    final gen = _generation;
    final draft = await Navigator.of(context).push<LimousineCompanyQuoteDraft>(
      MaterialPageRoute(
        builder: (_) => LimousineQuoteEditorPage(
          record: _controller.detail ?? record,
          onSubmit: (next) async {
            final live = await _controller.liveRecordForRespond(
              _controller.detail ?? record,
            );
            await _controller.respond(
              action: 'quote',
              record: live,
              quote: next.toWorkerQuote(),
            );
          },
        ),
      ),
    );
    if (!mounted || gen != _generation) return;
    if (draft == null) return;
    try {
      final fresh = await _gateway.detail(widget.quoteRequestId);
      if (!mounted || gen != _generation) return;
      setState(() {
        _controller.detail = fresh;
        _quoteSent = fresh.quotationAvailable;
      });
    } on LimousineQuoteInboxException catch (error) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _quoteSent = _controller.detail?.quotationAvailable ?? false;
        _banner = error.kind == LimousineQuoteInboxErrorKind.staleRevision
            ? _t(kLimousineQuoteStaleRevision)
            : limousineQuoteErrorLabel(error, _lang);
      });
    }
  }

  Future<void> _decline(LimousineQuoteRequest record) async {
    final gen = _generation;
    final draft = await showLimousineDeclineDialog(
      context: context,
      language: _lang,
    );
    if (draft == null || !mounted || gen != _generation) return;
    try {
      await _controller.respond(
        action: 'decline',
        record: record,
        decline: draft,
      );
      if (!mounted || gen != _generation) return;
      setState(() {});
    } on LimousineQuoteInboxException catch (error) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _banner = error.kind == LimousineQuoteInboxErrorKind.staleRevision
            ? _t(kLimousineQuoteStaleRevision)
            : limousineQuoteErrorLabel(error, _lang);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForBusinessTheme(variant);
        final record = _controller.detail;
        final body = _buildBody(palette, record);
        if (widget.embedded) {
          return KeyedSubtree(key: kLimousineQuoteDetailPageKey, child: body);
        }
        return Scaffold(
          key: kLimousineQuoteDetailPageKey,
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.textPrimary,
            title: Text(_t(kLimousineQuoteInboxTitle)),
          ),
          body: body,
        );
      },
    );
  }

  Widget _buildBody(
    BusinessThemePalette palette,
    LimousineQuoteRequest? record,
  ) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: kLimousineQuoteInboxLoadingKey),
      );
    }
    final error = _controller.error;
    if (record == null) {
      return _message(
        palette,
        error == null
            ? _t(kLimousineQuoteNotFound)
            : limousineQuoteErrorLabel(error, _lang),
      );
    }
    final actions = limousineQuoteActionsFor(record);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (_banner != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_banner!, style: TextStyle(color: palette.accent)),
          ),
        if (record.companyViewedAt.isNotEmpty)
          Padding(
            key: kLimousineQuoteViewedConfirmationKey,
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_t(kLimousineQuoteViewedConfirmation)} · ${formatLimousineUserDate(record.companyViewedAt, _lang)}',
              style: TextStyle(color: palette.textSecondary, height: 1.35),
            ),
          ),
        if (_quoteSent && record.quotationAvailable)
          _sendSuccessCard(palette, record),
        if (actions.readOnly && !actions.canMarkViewed)
          Container(
            key: kLimousineQuoteReadOnlyBannerKey,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              record.transitionsBlocked || record.isUnknownState
                  ? _t(kLimousineQuoteReadOnlyHistory)
                  : limousineQuoteStateLabel(record.state, _lang),
              style: TextStyle(color: palette.textSecondary, height: 1.35),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(palette, limousineQuoteStateLabel(record.state, _lang)),
            if (record.isUnread) _chip(palette, _t(kLimousineQuoteUnread)),
          ],
        ),
        const SizedBox(height: 16),
        _journeyCard(palette, record),
        const SizedBox(height: 12),
        _termsCard(palette, record),
        const SizedBox(height: 20),
        if (actions.canMarkViewed)
          _actionButton(
            key: kLimousineQuoteMarkViewedKey,
            palette: palette,
            label: _t(kLimousineQuoteMarkViewed),
            onPressed: _controller.submitting
                ? null
                : () => _markViewed(record),
          ),
        if (actions.canQuote) ...[
          const SizedBox(height: 8),
          _actionButton(
            key: kLimousineQuoteSubmitKey,
            palette: palette,
            label: _t(kLimousineQuoteSendQuote),
            onPressed: !_viewSettled || _controller.submitting
                ? null
                : () => _openQuoteEditor(record),
          ),
        ],
        if (actions.canDecline) ...[
          const SizedBox(height: 8),
          _actionButton(
            key: kLimousineQuoteDeclineKey,
            palette: palette,
            label: _t(kLimousineQuoteDecline),
            danger: true,
            onPressed: _controller.submitting ? null : () => _decline(record),
          ),
        ],
        if (record.hasQuotationPdf) ...[
          const SizedBox(height: 8),
          LimousineQuotationPdfAction(
            label: _t(kLimousineQuoteViewQuotation),
            previewTitle: _t(kLimousineQuoteViewQuotationPreviewTitle),
            errorLabel: _t(kLimousineQuoteViewQuotationError),
            loadBytes: () => _gateway.fetchQuotationPdf(
              quoteRequestId: record.quoteRequestId,
              revision: record.quotationRevision!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _journeyCard(
    BusinessThemePalette palette,
    LimousineQuoteRequest record,
  ) {
    final fulfilment = record.fulfilment;
    final rows = <Widget>[];
    void add(LocalizedText label, String? value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return;
      rows.add(_kv(palette, _t(label), text));
    }

    if (record.journeyType.isNotEmpty) {
      final journey =
          kLimousineJourneyTypeLabels[record.journeyType]?.of(_lang) ??
          record.journeyType;
      add(kLimousineQuoteJourneyCard, journey);
    }
    add(kLimousineQuotePickup, fulfilment?.from);
    add(kLimousineQuoteDestination, fulfilment?.to);
    if (fulfilment != null && fulfilment.stops.isNotEmpty) {
      add(kLimousineQuoteStops, fulfilment.stops.join(' · '));
    }
    if (record.scheduledPickupIso.isNotEmpty) {
      add(
        kLimousineQuoteWhen,
        limousineQuoteDisplayOrEmpty(record.scheduledPickupIso, _lang),
      );
    }
    if (record.pax != null) add(kLimousineQuotePassengers, '${record.pax}');
    if (record.bags != null) add(kLimousineQuoteLuggage, '${record.bags}');
    add(kLimousineQuoteCustomerNote, fulfilment?.customerNote);
    final classLabel = limousineQuoteServiceClassDisplay(
      record.serviceClassId,
      _lang,
    );
    if (classLabel.isNotEmpty) {
      rows.add(_kv(palette, _t(kLimousineQuoteServiceClass), classLabel));
    }
    final vehicleLabel = limousineQuoteVehicleDisplay(record, _lang);
    if (vehicleLabel.isNotEmpty) {
      rows.add(_kv(palette, _t(kLimousineQuoteVehicle), vehicleLabel));
    }
    final offerLabel = limousineQuoteOfferDisplay(record, _lang);
    if (offerLabel.isNotEmpty) {
      rows.add(_kv(palette, _t(kLimousineQuoteOffer), offerLabel));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card(
      palette,
      title: _t(kLimousineQuoteJourneyCard),
      children: rows,
    );
  }

  Widget _termsCard(
    BusinessThemePalette palette,
    LimousineQuoteRequest record,
  ) {
    final quote = record.quote;
    final rows = <Widget>[];
    if (quote != null) {
      final money = limousineCanonicalMoneyFromRequest(record);
      if (money != null) {
        for (final line in limousineQuoteMoneyLines(
          money: money,
          language: _lang,
        )) {
          rows.add(
            _kv(palette, line.label, formatLimousineEuroAmount(line.cents)),
          );
        }
      } else {
        rows.add(
          _kv(
            palette,
            _t(kLimousineQuoteGrossAmount),
            formatLimousineEuroAmount(quote.totalInclVatCents),
          ),
        );
      }
      final vatLabel = limousineVatTreatmentLabel(
        money?.vatTreatment.isNotEmpty == true
            ? money!.vatTreatment
            : quote.vatTreatment,
        _lang,
      );
      if (vatLabel.isNotEmpty) {
        rows.add(_kv(palette, _t(kLimousineQuoteVatTreatment), vatLabel));
      }
      if (quote.expiresAt.isNotEmpty) {
        rows.add(
          _kv(
            palette,
            _t(kLimousineQuoteExpires),
            formatLimousineUserDate(quote.expiresAt, _lang),
          ),
        );
      }
      final note = localizedLimousineText(
        quote.publicText,
        languageCode: _lang.name,
      );
      if (note.isNotEmpty) {
        rows.add(_kv(palette, _t(kLimousineQuoteImportantInfo), note));
      }
      final mobilisation = localizedLimousineText(
        quote.mobilisationDisclosure,
        languageCode: _lang.name,
      );
      if (mobilisation.isNotEmpty) {
        rows.add(_kv(palette, _t(kLimousineQuoteMobilisation), mobilisation));
      }
      if (quote.includedServices.isNotEmpty) {
        rows.add(
          _kv(
            palette,
            _t(kLimousineQuoteIncludedServices),
            '${quote.includedServices.length}',
          ),
        );
      }
      if (quote.separatelyPricedExtras.isNotEmpty) {
        rows.add(
          _kv(
            palette,
            _t(kLimousineQuotePaidExtras),
            '${quote.separatelyPricedExtras.length}',
          ),
        );
      }
      final terms = quote.terms;
      if (terms != null) {
        void addTerm(String key, String display) {
          if (display.trim().isEmpty) return;
          final label = kLimousineQuoteFieldLabels[key]?.of(_lang) ?? key;
          rows.add(_kv(palette, label, display));
        }

        final hours = terms['cancellation_deadline_hours'];
        if (hours is num && hours > 0) {
          addTerm('cancellation_deadline_hours', '$hours');
        }
        final cancelPct = terms['cancellation_penalty_percent'];
        if (cancelPct is num && cancelPct > 0) {
          addTerm('cancellation_penalty_percent', '$cancelPct');
        }
        final waitMin = terms['waiting_time_included_minutes'];
        if (waitMin is num && waitMin > 0) {
          addTerm('waiting_time_included_minutes', '$waitMin');
        }
        final waitOver = terms['waiting_time_overage_cents_per_minute'];
        if (waitOver is num && waitOver > 0) {
          addTerm(
            'waiting_time_overage_cents_per_minute',
            formatLimousineEuroAmount(waitOver.toInt()),
          );
        }
        final noShow = terms['no_show_penalty_percent'];
        if (noShow is num && noShow > 0) {
          addTerm('no_show_penalty_percent', '$noShow');
        }
        final overtime = terms['overtime_cents_per_hour'];
        if (overtime is num && overtime > 0) {
          addTerm(
            'overtime_cents_per_hour',
            formatLimousineEuroAmount(overtime.toInt()),
          );
        }
      }
    }
    if (record.decline != null) {
      final reason = localizedLimousineText(
        record.decline!.publicText,
        languageCode: _lang.name,
      );
      if (reason.isNotEmpty) {
        rows.add(_kv(palette, _t(kLimousineQuoteDecline), reason));
      }
    }
    if (record.bookingReference.isNotEmpty) {
      rows.add(
        _kv(palette, _t(kLimousineQuoteBookingRef), record.bookingReference),
      );
    }
    if (record.updatedAt.isNotEmpty) {
      rows.add(
        _kv(
          palette,
          _t(kLimousineQuoteUpdated),
          limousineQuoteDisplayOrEmpty(record.updatedAt, _lang),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card(palette, title: _t(kLimousineQuoteTermsCard), children: rows);
  }

  Widget _card(
    BusinessThemePalette palette, {
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(BusinessThemePalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: palette.textMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: palette.textPrimary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _sendSuccessCard(
    BusinessThemePalette palette,
    LimousineQuoteRequest record,
  ) {
    final money = limousineCanonicalMoneyFromRequest(record);
    final total =
        money?.grossCents ??
        record.quotationTotalInclVatCents ??
        record.quote?.totalInclVatCents;
    final sent = record.quotationSentAt.isNotEmpty
        ? record.quotationSentAt
        : (record.quote?.quotedAt ?? '');
    final expires = record.quotationExpiresAt.isNotEmpty
        ? record.quotationExpiresAt
        : (record.quote?.expiresAt ?? '');
    return Container(
      key: kLimousineQuoteSendSuccessKey,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(kLimousineQuoteSendSuccessTitle),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (money != null)
            ...limousineQuoteMoneyLines(money: money, language: _lang).map(
              (line) => Text(
                '${line.label}: ${formatLimousineEuroAmount(line.cents)}',
              ),
            )
          else if (total != null)
            Text(
              formatLimousineMoney(
                total,
                record.quotationCurrency.isNotEmpty
                    ? record.quotationCurrency
                    : (record.quote?.currency ?? ''),
              ),
            ),
          if (record.quotationRevision != null)
            Text(
              '${_t(kLimousineQuoteSendRevision)} ${record.quotationRevision}',
            ),
          if (sent.isNotEmpty)
            Text(
              '${_t(kLimousineQuoteSendSentAt)}: ${formatLimousineUserDate(sent, _lang)}',
            ),
          if (expires.isNotEmpty)
            Text(
              '${kLimousineQuoteExpires.of(_lang)}: ${formatLimousineUserDate(expires, _lang)}',
            ),
        ],
      ),
    );
  }

  Widget _chip(BusinessThemePalette palette, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.accent.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.accent,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _actionButton({
    required Key key,
    required BusinessThemePalette palette,
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: danger ? palette.danger : palette.accent,
          foregroundColor: palette.textOnAccent,
        ),
        child: Text(label),
      ),
    );
  }

  Widget _message(BusinessThemePalette palette, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, height: 1.4),
        ),
      ),
    );
  }
}
