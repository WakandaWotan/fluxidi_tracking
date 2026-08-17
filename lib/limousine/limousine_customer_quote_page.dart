import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_customer_entry.dart';
import 'limousine_customer_quote.dart';
import 'limousine_marketplace_labels.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_customer_status_page.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

class LimousineCustomerQuotePage extends StatefulWidget {
  const LimousineCustomerQuotePage({
    super.key,
    this.controller,
    this.gateway,
    this.entryEnabled,
    this.initialPublicPartnerId,
    this.initialOffer,
    this.initialCompanyName = '',
  });

  final LimousineCustomerQuoteController? controller;
  final LimousineCustomerQuoteGateway? gateway;
  final bool? entryEnabled;
  final String? initialPublicPartnerId;
  final LimousinePublishedOffer? initialOffer;
  final String initialCompanyName;

  @override
  State<LimousineCustomerQuotePage> createState() =>
      _LimousineCustomerQuotePageState();
}

class _LimousineCustomerQuotePageState extends State<LimousineCustomerQuotePage>
    with WidgetsBindingObserver {
  late final LimousineCustomerQuoteController _controller;
  late final bool _ownsController;
  final _postcode = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _note = TextEditingController();
  final _duration = TextEditingController();
  final List<TextEditingController> _stops = <TextEditingController>[];

  bool get _entryEnabled =>
      widget.entryEnabled ?? LimousineCustomerEntryContract.isVisible;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final existing = widget.controller;
    _ownsController = existing == null;
    _controller =
        existing ??
        LimousineCustomerQuoteController(
          gateway: widget.gateway ?? HttpLimousineCustomerQuoteGateway(),
        );
    _controller.addListener(_onChanged);
    final initialOffer = widget.initialOffer;
    final initialPartner = (widget.initialPublicPartnerId ?? '').trim();
    if (initialOffer != null && initialPartner.isNotEmpty) {
      _controller.applyShowroomSelection(
        publicPartnerId: initialPartner,
        offer: initialOffer,
        companyName: widget.initialCompanyName,
      );
    }
    _from.text = _controller.draft.from;
    _to.text = _controller.draft.to;
    _note.text = _controller.draft.customerNote;
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resumePolling();
    } else {
      _controller.pausePolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.stopPolling();
    if (_ownsController) _controller.dispose();
    _postcode.dispose();
    _from.dispose();
    _to.dispose();
    _note.dispose();
    _duration.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    super.dispose();
  }

  CustomerThemePalette get _palette =>
      paletteForCustomerTheme(customerThemeNotifier.value);

  bool get _tablet =>
      limousineQuoteInboxIsTablet(MediaQuery.sizeOf(context).shortestSide);

  @override
  Widget build(BuildContext context) {
    if (!_entryEnabled && widget.controller == null && widget.gateway == null) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      key: kLimousineCustomerQuotePageKey,
      backgroundColor: _palette.background,
      appBar: AppBar(
        backgroundColor: _palette.surface,
        foregroundColor: _palette.textPrimary,
        title: Text(_t(kLimousineCustomerPageTitle)),
      ),
      body: SafeArea(
        child: KeyedSubtree(
          key: _tablet
              ? kLimousineCustomerTabletLayoutKey
              : kLimousineCustomerPhoneLayoutKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _hero(reduceMotion),
              const SizedBox(height: 12),
              _stepChip(),
              const SizedBox(height: 12),
              if (_controller.phase == LimousineCustomerQuotePhase.unavailable)
                LimousineCustomerUnavailableBanner(language: _lang)
              else if (_controller.request != null)
                LimousineCustomerStatusView(
                  controller: _controller,
                  language: _lang,
                  palette: _palette,
                )
              else
                ..._draftSteps(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(bool reduceMotion) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: _tablet ? 180 : 128,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              LimousineCustomerEntryContract.visualAsset,
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.expand(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _palette.background.withOpacity(reduceMotion ? 0.35 : 0.15),
                    _palette.background.withOpacity(0.72),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _t(kLimousineBookLabel),
                  style: TextStyle(
                    color: _palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepChip() {
    final labels = <LimousineCustomerQuoteStep, LocalizedText>{
      LimousineCustomerQuoteStep.journey: kLimousineCustomerStepJourney,
      LimousineCustomerQuoteStep.providerOffer: kLimousineCustomerStepProvider,
      LimousineCustomerQuoteStep.detailsExtras: kLimousineCustomerStepDetails,
      LimousineCustomerQuoteStep.reviewRequest: kLimousineCustomerStepReview,
      LimousineCustomerQuoteStep.waitingCompany: kLimousineCustomerStepWaiting,
      LimousineCustomerQuoteStep.reviewQuote: kLimousineCustomerStepQuote,
      LimousineCustomerQuoteStep.acceptOffer: kLimousineCustomerStepAccept,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        backgroundColor: _palette.surfaceAlt,
        label: Text(
          _t(labels[_controller.step] ?? kLimousineCustomerStepJourney),
        ),
      ),
    );
  }

  List<Widget> _draftSteps() {
    switch (_controller.step) {
      case LimousineCustomerQuoteStep.journey:
        return _journeyStep();
      case LimousineCustomerQuoteStep.providerOffer:
        return _providerStep();
      case LimousineCustomerQuoteStep.detailsExtras:
        return _detailsStep();
      case LimousineCustomerQuoteStep.reviewRequest:
        return _reviewStep();
      default:
        return _reviewStep();
    }
  }

  List<Widget> _journeyStep() {
    return [
      _field(
        _t(kLimousineCustomerFrom),
        _from,
        onChanged: (value) {
          _controller.updateDraft(_controller.draft.copyWith(from: value));
        },
      ),
      _field(
        _t(kLimousineCustomerTo),
        _to,
        onChanged: (value) {
          _controller.updateDraft(_controller.draft.copyWith(to: value));
        },
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final type in const [
            'point_to_point',
            'airport_transfer',
            'hotel_transfer',
            'event_transfer',
            'hourly_package',
          ])
            ChoiceChip(
              label: Text(
                (kLimousineJourneyTypeLabels[type] ??
                        kLimousineCustomerStepJourney)
                    .of(_lang),
              ),
              selected: _controller.draft.journeyType == type,
              onSelected: (_) {
                _controller.updateDraft(
                  _controller.draft.copyWith(journeyType: type),
                );
              },
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_t(kLimousineCustomerRoundtrip)),
        value: _controller.draft.roundtrip,
        onChanged: (value) {
          _controller.updateDraft(_controller.draft.copyWith(roundtrip: value));
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_t(kLimousineCustomerPickupTime)),
        subtitle: Text(
          _controller.draft.scheduledPickupIso.isEmpty
              ? '—'
              : _controller.draft.scheduledPickupIso,
        ),
        onTap: () => _pickSchedule(returnTrip: false),
      ),
      if (_controller.draft.roundtrip)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_t(kLimousineCustomerReturnTime)),
          subtitle: Text(
            _controller.draft.returnPickupIso.isEmpty
                ? '—'
                : _controller.draft.returnPickupIso,
          ),
          onTap: () => _pickSchedule(returnTrip: true),
        ),
      if (_controller.draft.journeyType == 'hourly_package')
        _field(
          _t(kLimousineCustomerDuration),
          _duration,
          onChanged: (value) {
            _controller.updateDraft(
              _controller.draft.copyWith(
                requestedDurationMinutes: int.tryParse(value.trim()),
              ),
            );
          },
        ),
      ..._stopFields(),
      _navRow(
        onNext: () {
          _syncDraft();
          _controller.goTo(LimousineCustomerQuoteStep.providerOffer);
        },
      ),
    ];
  }

  List<Widget> _stopFields() {
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _stops.length >= 8
              ? null
              : () {
                  setState(() => _stops.add(TextEditingController()));
                },
          icon: const Icon(Icons.add),
          label: Text(_t(kLimousineCustomerAddStop)),
        ),
      ),
      for (var i = 0; i < _stops.length; i++)
        _field('${_t(kLimousineCustomerStops)} ${i + 1}', _stops[i]),
    ];
  }

  List<Widget> _providerStep() {
    final locked = _controller.providerOfferLocked;
    return [
      if (!locked) ...[
        _field(_t(kLimousineCustomerSearchHint), _postcode),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _controller.discovering
                ? null
                : () => _controller.discover(postcode: _postcode.text),
            child: Text(_t(kLimousineCustomerSearchAction)),
          ),
        ),
      ],
      if (_controller.discovering) const LinearProgressIndicator(),
      if (!_controller.discovering &&
          _controller.lastDiscoveryCount == 0 &&
          _controller.lastDiscoveryService == 'limousine')
        Padding(
          key: kLimousineCustomerDiscoverEmptyKey,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_t(kLimousineCustomerEmptyDiscovery)),
        ),
      for (final provider in _controller.providers)
        ListTile(
          leading: const Icon(Icons.directions_car_filled_outlined),
          title: Text(provider.companyName),
          subtitle: Text(provider.serviceArea.take(3).join(' · ')),
          selected:
              _controller.selectedProvider?.provider.partnerId ==
              provider.partnerId,
          onTap: locked ? null : () => _controller.selectProvider(provider),
        ),
      if (_controller.selectedProvider != null) ...[
        const SizedBox(height: 8),
        for (final offer in _controller.selectedProvider!.offers)
          RadioListTile<String>(
            value: offer.offerId,
            groupValue: _controller.selectedOffer?.offerId,
            title: Text(
              localizedLimousineText(offer.title, languageCode: _lang.name),
            ),
            subtitle: Text(
              limousineCustomerPresentationLabel(
                offer.pricePresentation,
                _lang,
              ),
            ),
            onChanged: locked ? null : (_) => _controller.selectOffer(offer),
          ),
      ],
      _navRow(
        onBack: () => _controller.goTo(LimousineCustomerQuoteStep.journey),
        onNext: () =>
            _controller.goTo(LimousineCustomerQuoteStep.detailsExtras),
      ),
    ];
  }

  List<Widget> _detailsStep() {
    return [
      _stepper(_t(kLimousineCustomerPax), _controller.draft.pax ?? 1, (value) {
        _controller.updateDraft(_controller.draft.copyWith(pax: value));
      }),
      _stepper(_t(kLimousineCustomerBags), _controller.draft.bags ?? 0, (
        value,
      ) {
        _controller.updateDraft(_controller.draft.copyWith(bags: value));
      }),
      if (_controller.selectedOffer != null)
        ..._controller.selectedOffer!.paidExtras.map((extra) {
          final id = (extra['extra_id'] ?? '').toString();
          final selected = _controller.draft.selectedExtraIds.contains(id);
          return CheckboxListTile(
            value: selected,
            title: Text(
              localizedLimousineText(
                extra['label'] is Map
                    ? Map<String, String>.from(
                        (extra['label'] as Map).map(
                          (key, value) => MapEntry(key.toString(), '$value'),
                        ),
                      )
                    : const <String, String>{},
                languageCode: _lang.name,
              ),
            ),
            onChanged: (value) {
              final next = List<String>.from(
                _controller.draft.selectedExtraIds,
              );
              if (value == true) {
                if (!next.contains(id)) next.add(id);
              } else {
                next.remove(id);
              }
              _controller.updateDraft(
                _controller.draft.copyWith(selectedExtraIds: next),
              );
            },
          );
        }),
      _field(
        _t(kLimousineCustomerNote),
        _note,
        maxLines: 3,
        onChanged: (value) {
          _controller.updateDraft(
            _controller.draft.copyWith(customerNote: value),
          );
        },
      ),
      _navRow(
        onBack: () =>
            _controller.goTo(LimousineCustomerQuoteStep.providerOffer),
        onNext: () {
          _syncDraft();
          _controller.goTo(LimousineCustomerQuoteStep.reviewRequest);
        },
      ),
    ];
  }

  List<Widget> _reviewStep() {
    final errors = _controller.draftErrors;
    return [
      Text('${_controller.draft.from} → ${_controller.draft.to}'),
      Text(_controller.selectedProvider?.provider.companyName ?? ''),
      Text(_controller.selectedOffer?.offerId ?? ''),
      if (errors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _errorText(errors.first),
            style: TextStyle(color: _palette.danger),
          ),
        ),
      _navRow(
        onBack: () =>
            _controller.goTo(LimousineCustomerQuoteStep.detailsExtras),
        nextLabel: _t(kLimousineCustomerSubmit),
        nextKey: kLimousineCustomerSubmitKey,
        nextBusy: _controller.submitting,
        onNext: () async {
          _syncDraft();
          final locale = switch (_lang) {
            AppLanguage.fr => 'fr',
            AppLanguage.es => 'es',
            AppLanguage.en => 'en',
            _ => 'nl',
          };
          _controller.updateDraft(_controller.draft.copyWith(locale: locale));
          final ok = await _controller.submitRequest();
          if (ok) _controller.startPolling();
        },
      ),
    ];
  }

  String _errorText(LimousineCustomerDraftError error) {
    switch (error) {
      case LimousineCustomerDraftError.unsupportedJourney:
        return _t(kLimousineCustomerUnsupportedJourney);
      case LimousineCustomerDraftError.capacityExceeded:
        return _t(kLimousineCustomerCapacity);
      case LimousineCustomerDraftError.invalidSchedule:
        return _t(kLimousineCustomerScheduleInvalid);
      case LimousineCustomerDraftError.invalidDuration:
        return _t(kLimousineCustomerDurationInvalid);
      default:
        return _t(kLimousineCustomerValidation);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: _palette.surface,
        ),
      ),
    );
  }

  Widget _stepper(String label, int value, ValueChanged<int> onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value <= 0 ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value'),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _navRow({
    VoidCallback? onBack,
    VoidCallback? onNext,
    String? nextLabel,
    Key? nextKey,
    bool nextBusy = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (onBack != null)
            TextButton(
              onPressed: onBack,
              child: Text(_t(kLimousineCustomerBack)),
            ),
          const Spacer(),
          if (onNext != null)
            FilledButton(
              key: nextKey,
              onPressed: nextBusy ? null : onNext,
              child: Text(nextLabel ?? _t(kLimousineCustomerContinue)),
            ),
        ],
      ),
    );
  }

  void _syncDraft() {
    _controller.updateDraft(
      _controller.draft.copyWith(
        from: _from.text,
        to: _to.text,
        customerNote: _note.text,
        stops: _stops
            .map((controller) => controller.text.trim())
            .where((text) => text.isNotEmpty)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _pickSchedule({required bool returnTrip}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );
    if (time == null) return;
    final iso = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc().toIso8601String();
    _controller.updateDraft(
      returnTrip
          ? _controller.draft.copyWith(returnPickupIso: iso)
          : _controller.draft.copyWith(scheduledPickupIso: iso),
    );
  }
}

void openLimousineCustomerQuoteFlow(
  BuildContext context, {
  String? publicPartnerId,
  LimousinePublishedOffer? offer,
  String companyName = '',
  bool? entryEnabled,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LimousineCustomerQuotePage(
        entryEnabled: entryEnabled,
        initialPublicPartnerId: publicPartnerId,
        initialOffer: offer,
        initialCompanyName: companyName,
      ),
    ),
  );
}
